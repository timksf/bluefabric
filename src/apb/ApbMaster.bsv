package ApbMaster;

import Clocks :: *;
import Connectable :: *;
import FIFOF :: *;
import GetPut :: *;
import SpecialFIFOs :: *;

import Apb :: *;
import ApbSlave :: *;

(* always_ready, always_enabled *)
interface ApbMasterFabric_ifc#(
    numeric type addr_w,
    numeric type data_w,
    numeric type user_w
);
    method Bit#(addr_w) paddr;
    method Bool psel;
    method Bool penable;
    method Bool pwrite;
    method Bit#(data_w) pwdata;
    method Bit#(TDiv#(data_w, 8)) pstrb;
    method Bit#(3) pprot;
    method Bit#(user_w) pauser;
    method Bit#(user_w) pwuser;

    (* prefix = "" *)
    method Action ppready((* port = "pready" *) Bool value);
    (* prefix = "" *)
    method Action pprdata((* port = "prdata" *) Bit#(data_w) value);
    (* prefix = "" *)
    method Action ppslverr((* port = "pslverr" *) Bool value);
    (* prefix = "" *)
    method Action ppruser((* port = "pruser" *) Bit#(user_w) value);
    (* prefix = "" *)
    method Action ppbuser((* port = "pbuser" *) Bit#(user_w) value);
endinterface

interface ApbMaster_ifc#(
    numeric type addr_w,
    numeric type data_w,
    numeric type user_w
);
    (* prefix = "" *)
    interface ApbMasterFabric_ifc#(addr_w, data_w, user_w) fabric;

    interface Put#(ApbRequest_t#(addr_w, data_w, user_w)) request;
    interface Get#(ApbResponse_t#(data_w, user_w)) response;
endinterface

/*
 * PSEL is derived directly from the request queue. Clearing the access-phase
 * register after a completed transfer makes the following cycle the setup
 * phase of the next queued request, with no intervening idle cycle.
 */
module mkApbMaster#(Integer buffer_depth)(ApbMaster_ifc#(addr_w, data_w, user_w));

    let reset_asserted <- isResetAsserted();

    FIFOF#(ApbRequest_t#(addr_w, data_w, user_w))   f_request = ?;
    FIFOF#(ApbResponse_t#(data_w, user_w))          f_response = ?;

    if(buffer_depth == 0) begin
        f_request  <- mkBypassFIFOF;
        f_response <- mkBypassFIFOF;
    end else if(buffer_depth == 1) begin
        f_request  <- mkPipelineFIFOF;
        f_response <- mkPipelineFIFOF;
    end else if(buffer_depth == 2) begin
        f_request  <- mkFIFOF;
        f_response <- mkFIFOF;
    end else begin
        f_request  <- mkSizedFIFOF(buffer_depth);
        f_response <- mkSizedFIFOF(buffer_depth);
    end

    Reg#(Bool) rg_access <- mkReg(False);

    Wire#(Bool)         w_pready  <- mkBypassWire;
    Wire#(Bit#(data_w)) w_prdata  <- mkBypassWire;
    Wire#(Bool)         w_pslverr <- mkBypassWire;
    Wire#(Bit#(user_w)) w_pruser  <- mkBypassWire;
    Wire#(Bit#(user_w)) w_pbuser  <- mkBypassWire;

    Wire#(Bit#(addr_w))           w_paddr   <- mkDWire(0);
    Wire#(Bool)                   w_pwrite  <- mkDWire(False);
    Wire#(Bit#(data_w))           w_pwdata  <- mkDWire(0);
    Wire#(Bit#(TDiv#(data_w, 8))) w_pstrb   <- mkDWire(0);
    Wire#(Bit#(3))                w_pprot   <- mkDWire(0);
    Wire#(Bit#(user_w))           w_pauser  <- mkDWire(0);
    Wire#(Bit#(user_w))           w_pwuser  <- mkDWire(0);

    rule r_forward_request;
        w_paddr  <= f_request.first.address;
        w_pwrite <= f_request.first.write;
        w_pwdata <= f_request.first.write_data;
        w_pstrb  <= f_request.first.write_strobe;
        w_pprot  <= f_request.first.protection;
        w_pauser <= f_request.first.address_user;
        w_pwuser <= f_request.first.write_user;
    endrule

    rule r_begin_access if(!reset_asserted && !rg_access && f_request.notEmpty && f_response.notFull);
        rg_access <= True;
    endrule

    rule r_complete_access if(!reset_asserted && rg_access && f_request.notEmpty && f_response.notFull && w_pready);
        f_request.deq;
        f_response.enq(ApbResponse_t {
            read_data     : w_prdata,
            slave_error   : w_pslverr,
            read_user     : w_pruser,
            response_user : w_pbuser
        });
        rg_access <= False;
    endrule

    interface request  = toPut(f_request);
    interface response = toGet(f_response);

    interface ApbMasterFabric_ifc fabric;
        method paddr   = w_paddr;
        method psel    = !reset_asserted && f_request.notEmpty && f_response.notFull;
        method penable = !reset_asserted && rg_access && f_request.notEmpty && f_response.notFull;
        method pwrite  = w_pwrite;
        method pwdata  = w_pwdata;
        method pstrb = w_pwrite ? w_pstrb : 0; //strobe has to be 0 for reads
        method pprot   = w_pprot;
        method pauser  = w_pauser;
        method pwuser  = w_pwuser;

        method ppready  = w_pready._write;
        method pprdata  = w_prdata._write;
        method ppslverr = w_pslverr._write;
        method ppruser  = w_pruser._write;
        method ppbuser  = w_pbuser._write;
    endinterface

endmodule

instance Connectable#(
    ApbMasterFabric_ifc#(addr_w, data_w, user_w),
    ApbSlaveFabric_ifc#(addr_w, data_w, user_w)
);
    module mkConnection#(
        ApbMasterFabric_ifc#(addr_w, data_w, user_w) master,
        ApbSlaveFabric_ifc#(addr_w, data_w, user_w) slave
    )(Empty);

        rule r_connect_request;
            slave.ppaddr(master.paddr);
            slave.ppsel(master.psel);
            slave.ppenable(master.penable);
            slave.ppwrite(master.pwrite);
            slave.ppwdata(master.pwdata);
            slave.ppstrb(master.pstrb);
            slave.ppprot(master.pprot);
            slave.ppauser(master.pauser);
            slave.ppwuser(master.pwuser);
        endrule

        rule r_connect_ready;
            master.ppready(slave.pready);
        endrule

        rule r_connect_read_data;
            master.pprdata(slave.prdata);
        endrule

        rule r_connect_response;
            master.ppslverr(slave.pslverr);
        endrule

        rule r_connect_read_user;
            master.ppruser(slave.pruser);
        endrule

        rule r_connect_response_user;
            master.ppbuser(slave.pbuser);
        endrule

    endmodule
endinstance

instance Connectable#(
    ApbSlaveFabric_ifc#(addr_w, data_w, user_w),
    ApbMasterFabric_ifc#(addr_w, data_w, user_w)
);
    module mkConnection#(
        ApbSlaveFabric_ifc#(addr_w, data_w, user_w) slave,
        ApbMasterFabric_ifc#(addr_w, data_w, user_w) master
    )(Empty);
        mkConnection(master, slave);
    endmodule
endinstance

endpackage
