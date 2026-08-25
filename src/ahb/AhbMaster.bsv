package AhbMaster;

import Clocks :: *;
import Connectable :: *;
import FIFOF :: *;
import GetPut :: *;
import SpecialFIFOs :: *;

import Ahb :: *;
import AhbSlave :: *;

(* always_ready, always_enabled *)
interface AhbMasterFabric_ifc#(numeric type aw, numeric type dw);
    method Bit#(aw) haddr;
    method Bool hsel;
    method AhbTransfer_t htrans;
    method Bool hwrite;
    method AhbSize_t hsize;
    method AhbBurst_t hburst;
    method AhbProtection_t hprot;
    method Bool hmastlock;
    method Bit#(dw) hwdata;

    (* prefix = "" *)
    method Action pphready((* port = "hready" *) Bool value);
    (* prefix = "" *)
    method Action pphrdata((* port = "hrdata" *) Bit#(dw) value);
    (* prefix = "" *)
    method Action pphresp((* port = "hresp" *) Bool value);
endinterface

/*
 * Interconnect-facing master port. Unlike an endpoint master, an interconnect
 * owns the shared HREADY signal and forwards it to downstream slaves.
 */
(* always_ready, always_enabled *)
interface AhbMasterFabricShared_ifc#(numeric type aw, numeric type dw);
    method Bit#(aw) haddr;
    method Bool hsel;
    method AhbTransfer_t htrans;
    method Bool hwrite;
    method AhbSize_t hsize;
    method AhbBurst_t hburst;
    method AhbProtection_t hprot;
    method Bool hmastlock;
    method Bit#(dw) hwdata;
    method Bool hreadyin;

    (* prefix = "" *)
    method Action pphready((* port = "hready" *) Bool value);
    (* prefix = "" *)
    method Action pphrdata((* port = "hrdata" *) Bit#(dw) value);
    (* prefix = "" *)
    method Action pphresp((* port = "hresp" *) Bool value);
endinterface

interface AhbMaster_ifc#(numeric type aw, numeric type dw);
    (* prefix = "" *)
    interface AhbMasterFabric_ifc#(aw, dw) fabric;

    interface Put#(AhbMasterRequest_t#(aw, dw)) request;
    interface Get#(AhbResponse_t#(dw)) response;
endinterface

module mkAhbMaster#(Integer buffer_depth)(AhbMaster_ifc#(aw, dw));

    let reset_asserted <- isResetAsserted();
    Integer response_depth = buffer_depth == 0 ? 1 :
        buffer_depth <= 65535 ? buffer_depth :
        error("mkAhbMaster buffer_depth exceeds the 16-bit reservation count");

    FIFOF#(AhbMasterRequest_t#(aw, dw)) f_request = ?;
    FIFOF#(AhbResponse_t#(dw))          f_response = ?;

    if(buffer_depth == 0) begin
        f_request <- mkBypassFIFOF;
    end else if(buffer_depth == 1) begin
        f_request <- mkPipelineFIFOF;
    end else if(buffer_depth == 2) begin
        f_request <- mkFIFOF;
    end else begin
        f_request <- mkSizedFIFOF(buffer_depth);
    end

    if(response_depth == 1) begin
        f_response <- mkPipelineFIFOF;
    end else if(response_depth == 2) begin
        f_response <- mkFIFOF;
    end else begin
        f_response <- mkSizedFIFOF(response_depth);
    end

    Reg#(Bool)            rg_data_valid      <- mkReg(False);
    Reg#(Bit#(dw))        rg_write_data      <- mkReg(0);
    Reg#(UInt#(16))       rg_reserved        <- mkReg(0);
    Reg#(Bool)            rg_burst_active    <- mkReg(False);
    Reg#(Bit#(aw))        rg_burst_address   <- mkReg(0);
    Reg#(Bool)            rg_burst_write     <- mkReg(False);
    Reg#(AhbSize_t)       rg_burst_size      <- mkReg(AHB_BYTE);
    Reg#(AhbBurst_t)      rg_burst           <- mkReg(AHB_SINGLE);
    Reg#(AhbProtection_t) rg_burst_prot      <- mkReg(ahb_protection(
        AHB_OPCODE_FETCH, AHB_USER_ACCESS, AHB_NON_BUFFERABLE, AHB_NON_CACHEABLE
    ));
    Reg#(Bool)            rg_burst_lock      <- mkReg(False);

    PulseWire pw_reserve <- mkPulseWire;
    PulseWire pw_release <- mkPulseWire;

    Wire#(Bool)         w_hready <- mkBypassWire;
    Wire#(Bit#(dw))     w_hrdata <- mkBypassWire;
    Wire#(Bool)         w_hresp  <- mkBypassWire;

    Wire#(Bit#(aw))       w_haddr      <- mkDWire(0);
    Wire#(Bool)           w_hwrite     <- mkDWire(False);
    Wire#(Bit#(dw))       w_write_data <- mkDWire(0);
    Wire#(AhbSize_t)      w_hsize      <- mkDWire(AHB_BYTE);
    Wire#(AhbBurst_t)     w_hburst     <- mkDWire(AHB_SINGLE);
    Wire#(AhbProtection_t) w_hprot     <- mkDWire(ahb_protection(
        AHB_OPCODE_FETCH, AHB_USER_ACCESS, AHB_NON_BUFFERABLE, AHB_NON_CACHEABLE
    ));
    Wire#(Bool)           w_hmastlock  <- mkDWire(False);

    Bool address_valid = !reset_asserted && f_request.notEmpty && (rg_reserved < fromInteger(response_depth) || pw_release);
    Bool burst_busy = !reset_asserted && rg_burst_active && !address_valid;

    rule r_forward_request;
        w_haddr      <= f_request.first.request.address;
        w_hwrite     <= f_request.first.request.write;
        w_write_data <= f_request.first.request.write_data;
        w_hsize      <= f_request.first.request.size;
        w_hburst     <= f_request.first.burst;
        w_hprot      <= f_request.first.request.protection;
        w_hmastlock  <= f_request.first.request.lock;
    endrule

    rule r_update_reserved;
        if(pw_reserve && !pw_release)
            rg_reserved <= rg_reserved + 1;
        else if(!pw_reserve && pw_release)
            rg_reserved <= rg_reserved - 1;
    endrule

    rule r_complete_data_phase if(!reset_asserted && w_hready && rg_data_valid);
        f_response.enq(AhbResponse_t {
            read_data   : w_hrdata,
            slave_error : w_hresp
        });
    endrule

    rule r_accept_address_phase if(!reset_asserted && w_hready && address_valid);
        let burst = rg_burst_active ? rg_burst : f_request.first.burst;
        rg_write_data    <= w_write_data;
        rg_burst_active  <= !f_request.first.last && burst != AHB_SINGLE;
        rg_burst_address <= ahb_next_burst_address(
            f_request.first.request.address,
            f_request.first.request.size,
            burst
        );
        rg_burst_write <= f_request.first.request.write;
        rg_burst_size  <= f_request.first.request.size;
        rg_burst       <= burst;
        rg_burst_prot  <= f_request.first.request.protection;
        rg_burst_lock  <= f_request.first.request.lock;
        f_request.deq;
        pw_reserve.send;
    endrule

    rule r_update_data_phase if(!reset_asserted && w_hready);
        rg_data_valid <= address_valid;
    endrule

    interface request = toPut(f_request);
    interface Get response;
        method ActionValue#(AhbResponse_t#(dw)) get if(f_response.notEmpty);
            let value = f_response.first;
            f_response.deq;
            pw_release.send;
            return value;
        endmethod
    endinterface

    interface AhbMasterFabric_ifc fabric;
        method haddr     = burst_busy ? rg_burst_address : w_haddr;
        method hsel      = address_valid || burst_busy;
        method htrans    = address_valid ?
            (rg_burst_active ? AHB_SEQ : AHB_NONSEQ) :
            (burst_busy ? AHB_BUSY : AHB_IDLE);
        method hwrite    = burst_busy ? rg_burst_write : w_hwrite;
        method hsize     = burst_busy ? rg_burst_size : w_hsize;
        method hburst    = rg_burst_active ?
            rg_burst : w_hburst;
        method hprot     = burst_busy ? rg_burst_prot : w_hprot;
        method hmastlock = burst_busy ? rg_burst_lock : w_hmastlock;
        method hwdata    = rg_write_data;

        method pphready = w_hready._write;
        method pphrdata = w_hrdata._write;
        method pphresp  = w_hresp._write;
    endinterface

endmodule

instance Connectable#(AhbMasterFabric_ifc#(aw, dw), AhbSlaveFabric_ifc#(aw, dw));
    module mkConnection#(AhbMasterFabric_ifc#(aw, dw) master, AhbSlaveFabric_ifc#(aw, dw) slave)(Empty);

        rule r_connect_request;
            slave.pphaddr(master.haddr);
            slave.pphsel(master.hsel);
            slave.pphtrans(master.htrans);
            slave.pphwrite(master.hwrite);
            slave.pphsize(master.hsize);
            slave.pphburst(master.hburst);
            slave.pphprot(master.hprot);
            slave.pphmastlock(master.hmastlock);
            slave.pphwdata(master.hwdata);
        endrule

        rule r_connect_ready;
            let hready = slave.hreadyout;
            slave.pphreadyin(hready);
            master.pphready(hready);
        endrule

        rule r_connect_read_data;
            master.pphrdata(slave.hrdata);
        endrule

        rule r_connect_response;
            master.pphresp(slave.hresp);
        endrule

    endmodule
endinstance

instance Connectable#(AhbSlaveFabric_ifc#(aw, dw), AhbMasterFabric_ifc#(aw, dw));
    module mkConnection#(AhbSlaveFabric_ifc#(aw, dw) slave, AhbMasterFabric_ifc#(aw, dw) master)(Empty);
        mkConnection(master, slave);
    endmodule
endinstance

instance Connectable#(AhbMasterFabricShared_ifc#(aw, dw), AhbSlaveFabric_ifc#(aw, dw));
    module mkConnection#(AhbMasterFabricShared_ifc#(aw, dw) master, AhbSlaveFabric_ifc#(aw, dw) slave)(Empty);

        rule r_connect_request;
            slave.pphaddr(master.haddr);
            slave.pphsel(master.hsel);
            slave.pphtrans(master.htrans);
            slave.pphwrite(master.hwrite);
            slave.pphsize(master.hsize);
            slave.pphburst(master.hburst);
            slave.pphprot(master.hprot);
            slave.pphmastlock(master.hmastlock);
            slave.pphwdata(master.hwdata);
        endrule

        rule r_connect_shared_ready;
            slave.pphreadyin(master.hreadyin);
        endrule

        rule r_connect_ready;
            master.pphready(slave.hreadyout);
        endrule

        rule r_connect_read_data;
            master.pphrdata(slave.hrdata);
        endrule

        rule r_connect_response;
            master.pphresp(slave.hresp);
        endrule

    endmodule
endinstance

instance Connectable#(AhbSlaveFabric_ifc#(aw, dw), AhbMasterFabricShared_ifc#(aw, dw));
    module mkConnection#(AhbSlaveFabric_ifc#(aw, dw) slave, AhbMasterFabricShared_ifc#(aw, dw) master)(Empty);
        mkConnection(master, slave);
    endmodule
endinstance

endpackage
