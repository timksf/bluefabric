package AhbApbBridge;

import Clocks :: *;

import Ahb :: *;
import AhbSlave :: *;
import ApbMaster :: *;

typedef enum {
    BridgeIdle,
    BridgeSetup,
    BridgeAccess,
    BridgeErrorFirst,
    BridgeErrorLast
} AhbApbBridgeState_t deriving(Bits, Eq, FShow);

interface AhbApbBridge_ifc#(
    numeric type addr_w,
    numeric type data_w,
    numeric type user_w
);
    interface AhbSlaveFabric_ifc#(addr_w, data_w) ahb;
    interface ApbMasterFabric_ifc#(addr_w, data_w, user_w) apb;
endinterface

function Bool ahb_apb_transfer_supported(
    Bit#(addr_w) address,
    AhbSize_t size,
    Integer bus_bytes
);
    Bit#(TAdd#(addr_w, 1)) transfer_bytes = 1 << pack(size);
    Bit#(TAdd#(addr_w, 1)) extended_address = zeroExtend(address);
    return transfer_bytes != 0 &&
        transfer_bytes <= fromInteger(bus_bytes) &&
        (extended_address & (transfer_bytes - 1)) == 0;
endfunction

function Bit#(strobe_w) ahb_apb_write_strobe(
    Bit#(addr_w) address,
    AhbSize_t size
);
    Integer bus_bytes = valueOf(strobe_w);
    Bit#(addr_w) transfer_bytes = 1 << pack(size);
    Bit#(addr_w) first_lane = address % fromInteger(bus_bytes);
    Bit#(strobe_w) result = 0;

    for(Integer n = 0; n < bus_bytes; n = n + 1) begin
        if(fromInteger(n) >= first_lane &&
                fromInteger(n) < first_lane + transfer_bytes)
            result[n] = 1;
    end

    return result;
endfunction

module mkAhbApbBridge(AhbApbBridge_ifc#(addr_w, data_w, user_w));

    let reset_asserted <- isResetAsserted();

    Wire#(Bit#(addr_w))  w_haddr     <- mkBypassWire;
    Wire#(Bool)          w_hsel      <- mkBypassWire;
    Wire#(AhbTransfer_t) w_htrans    <- mkBypassWire;
    Wire#(Bool)          w_hwrite    <- mkBypassWire;
    Wire#(AhbSize_t)     w_hsize     <- mkBypassWire;
    Wire#(AhbProtection_t) w_hprot   <- mkBypassWire;
    Wire#(Bit#(data_w))  w_hwdata    <- mkBypassWire;
    Wire#(Bool)          w_hreadyin  <- mkBypassWire;

    Wire#(Bool)         w_pready  <- mkBypassWire;
    Wire#(Bit#(data_w)) w_prdata  <- mkBypassWire;
    Wire#(Bool)         w_pslverr <- mkBypassWire;
    Wire#(Bit#(user_w)) w_pruser  <- mkBypassWire;
    Wire#(Bit#(user_w)) w_pbuser  <- mkBypassWire;

    Reg#(AhbApbBridgeState_t) rg_state  <- mkReg(BridgeIdle);
    Reg#(Bit#(addr_w))        rg_haddr  <- mkReg(0);
    Reg#(Bool)                rg_hwrite <- mkReg(False);
    Reg#(AhbSize_t)           rg_hsize  <- mkReg(AHB_BYTE);
    Reg#(AhbProtection_t)     rg_hprot  <- mkReg(ahb_protection(
        AHB_OPCODE_FETCH, AHB_USER_ACCESS, AHB_NON_BUFFERABLE, AHB_NON_CACHEABLE
    ));

    Bool transfer_valid = w_hsel &&
        (w_htrans == AHB_NONSEQ || w_htrans == AHB_SEQ);
    Bool transfer_supported = ahb_apb_transfer_supported(
        w_haddr,
        w_hsize,
        valueOf(TDiv#(data_w, 8))
    );
    Bool apb_error = rg_state == BridgeAccess &&
        w_pready && w_pslverr;

    function Action capture_address();
        action
            rg_haddr  <= w_haddr;
            rg_hwrite <= w_hwrite;
            rg_hsize  <= w_hsize;
            rg_hprot  <= w_hprot;
        endaction
    endfunction

    rule r_update_state if(!reset_asserted);
        case(rg_state)
            BridgeIdle: begin
                if(w_hreadyin && transfer_valid) begin
                    capture_address();
                    rg_state <= transfer_supported ?
                        BridgeSetup : BridgeErrorFirst;
                end
            end

            BridgeSetup: begin
                rg_state <= BridgeAccess;
            end

            BridgeAccess: begin
                if(w_pready) begin
                    if(w_pslverr) begin
                        rg_state <= BridgeErrorLast;
                    end else if(w_hreadyin && transfer_valid) begin
                        capture_address();
                        rg_state <= transfer_supported ?
                            BridgeSetup : BridgeErrorFirst;
                    end else begin
                        rg_state <= BridgeIdle;
                    end
                end
            end

            BridgeErrorFirst: begin
                rg_state <= BridgeErrorLast;
            end

            BridgeErrorLast: begin
                if(w_hreadyin && transfer_valid) begin
                    capture_address();
                    rg_state <= transfer_supported ?
                        BridgeSetup : BridgeErrorFirst;
                end else begin
                    rg_state <= BridgeIdle;
                end
            end
        endcase
    endrule

    Bool hreadyout = rg_state == BridgeIdle ||
        (rg_state == BridgeAccess && w_pready && !w_pslverr) ||
        rg_state == BridgeErrorLast;

    Bool hresp = apb_error ||
        rg_state == BridgeErrorFirst ||
        rg_state == BridgeErrorLast;
    Bool psel = rg_state == BridgeSetup ||
        rg_state == BridgeAccess;

    interface AhbSlaveFabric_ifc ahb;
        method pphaddr     = w_haddr._write;
        method pphsel      = w_hsel._write;
        method pphtrans    = w_htrans._write;
        method pphwrite    = w_hwrite._write;
        method pphsize     = w_hsize._write;
        method Action pphburst(AhbBurst_t value);
            noAction;
        endmethod
        method pphprot     = w_hprot._write;
        method Action pphmastlock(Bool value);
            noAction;
        endmethod
        method pphwdata    = w_hwdata._write;
        method pphreadyin  = w_hreadyin._write;

        method hreadyout = !reset_asserted && hreadyout;
        method hrdata    = w_prdata;
        method hresp     = !reset_asserted && hresp;
    endinterface

    interface ApbMasterFabric_ifc apb;
        method paddr   = rg_haddr;
        method psel    = !reset_asserted && psel;
        method penable = !reset_asserted &&
            rg_state == BridgeAccess;
        method pwrite  = rg_hwrite;
        method pwdata  = w_hwdata;
        method pstrb   = rg_hwrite ?
            ahb_apb_write_strobe(rg_haddr, rg_hsize) : 0;
        method pprot = {
            ~pack(rg_hprot)[0],
            1'b0,
            pack(rg_hprot)[1]
        };
        method pauser = 0;
        method pwuser = 0;

        method ppready  = w_pready._write;
        method pprdata  = w_prdata._write;
        method ppslverr = w_pslverr._write;
        method ppruser  = w_pruser._write;
        method ppbuser  = w_pbuser._write;
    endinterface

endmodule

endpackage
