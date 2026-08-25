package AhbMasterMux;

import Clocks :: *;
import Vector :: *;

import GenericArbiter :: *;
import Ahb :: *;
import AhbMaster :: *;
import AhbSlave :: *;

interface AhbMasterMux_ifc#(numeric type n, numeric type aw, numeric type dw);
    interface Vector#(n, AhbSlaveFabric_ifc#(aw, dw)) up;
    interface AhbMasterFabric_ifc#(aw, dw) down;
endinterface

typedef struct {
    Bit#(aw)        address;
    AhbTransfer_t   transfer;
    Bool            write;
    AhbSize_t       size;
    AhbBurst_t      burst;
    AhbProtection_t protection;
    Bool            lock;
} AhbMuxAddress_t#(numeric type aw) deriving(Bits, Eq, FShow);

/*
 * Address ownership changes only at SINGLE or fixed-length burst boundaries.
 * A one-cycle IDLE address phase separates owners. During that cycle the
 * outgoing owner completes its data phase and its overlapping next address is
 * retained in a per-port holding register. HWDATA is not buffered: it follows
 * the registered data-phase owner, as required by AHB's pipelined timing.
 */
module mkAhbMasterMux(AhbMasterMux_ifc#(n, aw, dw))
    provisos(
        Add#(1, nmninone_, n)
    );

    let reset_asserted <- isResetAsserted();

    GenericArbiter_ifc#(n) i_arbiter <- mkGenericArbiter;

    Vector#(n, Reg#(Maybe#(AhbMuxAddress_t#(aw)))) vrg_pending <-
        replicateM(mkReg(tagged Invalid));

    Reg#(Bool)     rg_handover         <- mkReg(False);
    Reg#(Bool)     rg_data_valid       <- mkReg(False);
    Reg#(Bit#(n))  rg_data_owner       <- mkReg(0);
    Reg#(UInt#(5)) rg_burst_beats_left <- mkReg(0);

    Vector#(n, Wire#(Bit#(aw)))        vw_haddr     <- replicateM(mkBypassWire);
    Vector#(n, Wire#(Bool))            vw_hsel      <- replicateM(mkBypassWire);
    Vector#(n, Wire#(AhbTransfer_t))   vw_htrans    <- replicateM(mkBypassWire);
    Vector#(n, Wire#(Bool))            vw_hwrite    <- replicateM(mkBypassWire);
    Vector#(n, Wire#(AhbSize_t))       vw_hsize     <- replicateM(mkBypassWire);
    Vector#(n, Wire#(AhbBurst_t))      vw_hburst    <- replicateM(mkBypassWire);
    Vector#(n, Wire#(AhbProtection_t)) vw_hprot     <- replicateM(mkBypassWire);
    Vector#(n, Wire#(Bool))            vw_hmastlock <- replicateM(mkBypassWire);
    Vector#(n, Wire#(Bit#(dw)))        vw_hwdata    <- replicateM(mkBypassWire);

    Wire#(Bool)     w_hready <- mkBypassWire;
    Wire#(Bit#(dw)) w_hrdata <- mkBypassWire;
    Wire#(Bool)     w_hresp  <- mkBypassWire;

    Wire#(Bit#(aw))        w_haddr     <- mkDWire(0);
    Wire#(Bool)            w_hsel      <- mkDWire(False);
    Wire#(AhbTransfer_t)   w_htrans    <- mkDWire(AHB_IDLE);
    Wire#(Bool)            w_hwrite    <- mkDWire(False);
    Wire#(AhbSize_t)       w_hsize     <- mkDWire(AHB_BYTE);
    Wire#(AhbBurst_t)      w_hburst    <- mkDWire(AHB_SINGLE);
    Wire#(AhbProtection_t) w_hprot     <- mkDWire(ahb_protection(
        AHB_OPCODE_FETCH, AHB_USER_ACCESS, AHB_NON_BUFFERABLE, AHB_NON_CACHEABLE
    ));
    Wire#(Bool)     w_hmastlock <- mkDWire(False);
    Wire#(Bit#(dw)) w_hwdata    <- mkDWire(0);

    function Bool live_valid(Integer i);
        return vw_hsel[i] &&
            (vw_htrans[i] == AHB_NONSEQ || vw_htrans[i] == AHB_SEQ);
    endfunction

    function Bool live_active(Integer i);
        return vw_hsel[i] && vw_htrans[i] != AHB_IDLE;
    endfunction

    function AhbMuxAddress_t#(aw) live_address(Integer i);
        return AhbMuxAddress_t {
            address    : vw_haddr[i],
            transfer   : vw_htrans[i],
            write      : vw_hwrite[i],
            size       : vw_hsize[i],
            burst      : vw_hburst[i],
            protection : vw_hprot[i],
            lock       : vw_hmastlock[i]
        };
    endfunction

    function Bit#(n) request_bits();
        Bit#(n) result = 0;
        for(Integer i = 0; i < valueOf(n); i = i + 1)
            result[i] = pack(isValid(vrg_pending[i]) || live_valid(i));
        return result;
    endfunction

    function UInt#(5) fixed_burst_tail(AhbBurst_t burst);
        case(burst)
            AHB_WRAP4, AHB_INCR4:   return 3;
            AHB_WRAP8, AHB_INCR8:   return 7;
            AHB_WRAP16, AHB_INCR16: return 15;
            default:                 return 0;
        endcase
    endfunction

    function Maybe#(AhbMuxAddress_t#(aw)) granted_pending(Bit#(n) one_hot);
        Maybe#(AhbMuxAddress_t#(aw)) result = tagged Invalid;
        for(Integer i = 0; i < valueOf(n); i = i + 1) begin
            if(one_hot[i] == 1)
                result = vrg_pending[i];
        end
        return result;
    endfunction

    function AhbMuxAddress_t#(aw) granted_live_address(Bit#(n) one_hot);
        AhbMuxAddress_t#(aw) result = live_address(0);
        for(Integer i = 0; i < valueOf(n); i = i + 1) begin
            if(one_hot[i] == 1)
                result = live_address(i);
        end
        return result;
    endfunction

    function Bool granted_live_active(Bit#(n) one_hot);
        Bool result = False;
        for(Integer i = 0; i < valueOf(n); i = i + 1) begin
            if(one_hot[i] == 1)
                result = live_active(i);
        end
        return result;
    endfunction

    function Bool granted_live_valid(Bit#(n) one_hot);
        Bool result = False;
        for(Integer i = 0; i < valueOf(n); i = i + 1) begin
            if(one_hot[i] == 1)
                result = live_valid(i);
        end
        return result;
    endfunction

    function Bit#(dw) granted_write_data(Bit#(n) one_hot);
        Bit#(dw) result = 0;
        for(Integer i = 0; i < valueOf(n); i = i + 1) begin
            if(one_hot[i] == 1)
                result = vw_hwdata[i];
        end
        return result;
    endfunction

    Bit#(n) request = request_bits();
    Bit#(n) grant   = i_arbiter.grant;

    Bool grant_present = grant != 0;
    Maybe#(AhbMuxAddress_t#(aw)) pending_address = granted_pending(grant);
    Bool grant_buffered = grant_present && isValid(pending_address);

    AhbMuxAddress_t#(aw) selected_address =
        grant_buffered ?
            fromMaybe(?, pending_address) :
            granted_live_address(grant);

    Bool selected_active =
        grant_present && (grant_buffered || granted_live_active(grant));
    Bool selected_valid =
        grant_present && (grant_buffered || granted_live_valid(grant));

    Bool output_active = !rg_handover && selected_active;
    Bool output_valid  = !rg_handover && selected_valid;

    Bool address_accepted = w_hready && output_valid;
    Bool other_request = (request & ~grant) != 0;

    Bool single_boundary =
        address_accepted && selected_address.burst == AHB_SINGLE;
    Bool fixed_boundary =
        address_accepted && selected_address.transfer == AHB_SEQ &&
        rg_burst_beats_left == 1;
    Bool arbitration_boundary =
        !selected_address.lock && (single_boundary || fixed_boundary);

    Bool start_handover = arbitration_boundary && other_request;
    Bool release_inactive =
        !rg_handover && w_hready && grant_present && !selected_active;
    Bool advance_arbiter = start_handover || release_inactive;

    rule r_arbitrate;
        i_arbiter.prequest(reset_asserted ? 0 : request);
    endrule

    rule r_advance_arbiter;
        i_arbiter.padvance(!reset_asserted && advance_arbiter);
    endrule

    rule r_drive_address;
        if(!reset_asserted && output_active) begin
            w_haddr     <= selected_address.address;
            w_hsel      <= True;
            w_htrans    <= selected_address.transfer;
            w_hwrite    <= selected_address.write;
            w_hsize     <= selected_address.size;
            w_hburst    <= selected_address.burst;
            w_hprot     <= selected_address.protection;
            w_hmastlock <= selected_address.lock;
        end
    endrule

    rule r_drive_write_data;
        if(!reset_asserted && rg_data_valid)
            w_hwdata <= granted_write_data(rg_data_owner);
    endrule

    rule r_update_state;
        if(reset_asserted) begin
            rg_handover   <= False;
            rg_data_valid <= False;
            rg_data_owner <= 0;
            rg_burst_beats_left <= 0;
            for(Integer i = 0; i < valueOf(n); i = i + 1)
                vrg_pending[i] <= tagged Invalid;
        end else if(w_hready) begin
            if(rg_handover)
                rg_handover <= False;
            else if(start_handover)
                rg_handover <= True;

            rg_data_valid <= output_valid;
            rg_data_owner <= output_valid ? grant : 0;

            if(release_inactive) begin
                rg_burst_beats_left <= 0;
            end else if(address_accepted) begin
                if(selected_address.transfer == AHB_NONSEQ)
                    rg_burst_beats_left <= fixed_burst_tail(
                        selected_address.burst
                    );
                else if(selected_address.transfer == AHB_SEQ &&
                        rg_burst_beats_left != 0)
                    rg_burst_beats_left <= rg_burst_beats_left - 1;
            end

            for(Integer i = 0; i < valueOf(n); i = i + 1) begin
                Bool direct_address =
                    !rg_handover && !grant_buffered &&
                    grant[i] == 1 && selected_valid;
                Bool capture_address =
                    rg_data_valid && rg_data_owner[i] == 1 &&
                    live_valid(i) && !direct_address;
                Bool consume_address =
                    address_accepted && grant_buffered && grant[i] == 1;

                if(capture_address)
                    vrg_pending[i] <= tagged Valid live_address(i);
                else if(consume_address)
                    vrg_pending[i] <= tagged Invalid;
            end
        end
    endrule

    Vector#(n, AhbSlaveFabric_ifc#(aw, dw)) v_up = newVector;

    for(Integer i = 0; i < valueOf(n); i = i + 1) begin
        v_up[i] = interface AhbSlaveFabric_ifc;
            method pphaddr     = vw_haddr[i]._write;
            method pphsel      = vw_hsel[i]._write;
            method pphtrans    = vw_htrans[i]._write;
            method pphwrite    = vw_hwrite[i]._write;
            method pphsize     = vw_hsize[i]._write;
            method pphburst    = vw_hburst[i]._write;
            method pphprot     = vw_hprot[i]._write;
            method pphmastlock = vw_hmastlock[i]._write;
            method pphwdata    = vw_hwdata[i]._write;
            method Action pphreadyin(Bool value);
                noAction;
            endmethod

            method hreadyout =
                !reset_asserted && w_hready &&
                ((rg_data_valid && rg_data_owner[i] == 1) ||
                    (!rg_handover && !grant_buffered &&
                        grant[i] == 1 && selected_active));
            method hrdata =
                rg_data_valid && rg_data_owner[i] == 1 ? w_hrdata : 0;
            method hresp =
                rg_data_valid && rg_data_owner[i] == 1 ? w_hresp : False;
        endinterface;
    end

    interface AhbMasterFabric_ifc down;
        method haddr     = w_haddr;
        method hsel      = w_hsel;
        method htrans    = w_htrans;
        method hwrite    = w_hwrite;
        method hsize     = w_hsize;
        method hburst    = w_hburst;
        method hprot     = w_hprot;
        method hmastlock = w_hmastlock;
        method hwdata    = w_hwdata;

        method pphready = w_hready._write;
        method pphrdata = w_hrdata._write;
        method pphresp  = w_hresp._write;
    endinterface

    interface up = v_up;

endmodule

endpackage
