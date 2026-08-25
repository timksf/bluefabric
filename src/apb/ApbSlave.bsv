package ApbSlave;

import Clocks :: *;
import FIFOF :: *;
import GetPut :: *;
import SpecialFIFOs :: *;

import Apb :: *;

(* always_ready, always_enabled *)
interface ApbSlaveFabric_ifc#(
    numeric type addr_w,
    numeric type data_w,
    numeric type user_w
);
    (* prefix = "" *)
    method Action ppaddr((* port = "paddr" *) Bit#(addr_w) value);
    (* prefix = "" *)
    method Action ppsel((* port = "psel" *) Bool value);
    (* prefix = "" *)
    method Action ppenable((* port = "penable" *) Bool value);
    (* prefix = "" *)
    method Action ppwrite((* port = "pwrite" *) Bool value);
    (* prefix = "" *)
    method Action ppwdata((* port = "pwdata" *) Bit#(data_w) value);
    (* prefix = "" *)
    method Action ppstrb((* port = "pstrb" *) Bit#(TDiv#(data_w, 8)) value);
    (* prefix = "" *)
    method Action ppprot((* port = "pprot" *) Bit#(3) value);
    (* prefix = "" *)
    method Action ppauser((* port = "pauser" *) Bit#(user_w) value);
    (* prefix = "" *)
    method Action ppwuser((* port = "pwuser" *) Bit#(user_w) value);

    method Bool pready;
    method Bit#(data_w) prdata;
    method Bool pslverr;
    method Bit#(user_w) pruser;
    method Bit#(user_w) pbuser;
endinterface

interface ApbSlave_ifc#(
    numeric type addr_w,
    numeric type data_w,
    numeric type user_w
);
    (* prefix = "" *)
    interface ApbSlaveFabric_ifc#(addr_w, data_w, user_w) fabric;

    interface Get#(ApbRequest_t#(addr_w, data_w, user_w)) request;
    method ApbRequest_t#(addr_w, data_w, user_w) first;
    interface Put#(ApbResponse_t#(data_w, user_w)) response;
endinterface

/*
 * The request path can optionally register the setup phase. The response path
 * is fall-through so a handler can complete the first access cycle without
 * inserting a wait state.
 */
module mkApbSlave#(Bool pipeline_req)(ApbSlave_ifc#(addr_w, data_w, user_w));

    let reset_asserted <- isResetAsserted();

    FIFOF#(ApbRequest_t#(addr_w, data_w, user_w)) f_request = ?;

    //default to a bypass fifo to allow a cycle of backpressure from the downstream handler
    if(pipeline_req) begin
        f_request <- mkPipelineFIFOF;
    end else begin
        f_request <- mkBypassFIFOF;
    end

    FIFOF#(ApbResponse_t#(data_w, user_w)) f_response <- mkBypassFIFOF;

    Wire#(Bit#(addr_w))           w_paddr   <- mkBypassWire;
    Wire#(Bool)                   w_psel    <- mkBypassWire;
    Wire#(Bool)                   w_penable <- mkBypassWire;
    Wire#(Bool)                   w_pwrite  <- mkBypassWire;
    Wire#(Bit#(data_w))           w_pwdata  <- mkBypassWire;
    Wire#(Bit#(TDiv#(data_w, 8))) w_pstrb   <- mkBypassWire;
    Wire#(Bit#(3))                w_pprot   <- mkBypassWire;
    Wire#(Bit#(user_w))           w_pauser  <- mkBypassWire;
    Wire#(Bit#(user_w))           w_pwuser  <- mkBypassWire;

    Wire#(Bit#(data_w)) w_prdata  <- mkDWire(0);
    Wire#(Bool)         w_pslverr <- mkDWire(False);
    Wire#(Bit#(user_w)) w_pruser  <- mkDWire(0);
    Wire#(Bit#(user_w)) w_pbuser  <- mkDWire(0);

    rule r_capture_setup if (!reset_asserted && w_psel && !w_penable && f_request.notFull);
        f_request.enq(ApbRequest_t {
            address       : w_paddr,
            write         : w_pwrite,
            write_data    : w_pwdata,
            write_strobe  : w_pstrb,
            protection    : w_pprot,
            address_user  : w_pauser,
            write_user    : w_pwuser
        });
    endrule

    rule r_complete_access if (!reset_asserted && w_psel && w_penable && f_response.notEmpty);
        f_response.deq;
    endrule

    rule r_forward_response;
        w_prdata  <= f_response.first.read_data;
        w_pslverr <= f_response.first.slave_error;
        w_pruser  <= f_response.first.read_user;
        w_pbuser  <= f_response.first.response_user;
    endrule

    method first = f_request.first;

    interface request  = toGet(f_request);
    interface response = toPut(f_response);

    interface ApbSlaveFabric_ifc fabric;
        method ppaddr   = w_paddr._write;
        method ppsel    = w_psel._write;
        method ppenable = w_penable._write;
        method ppwrite  = w_pwrite._write;
        method ppwdata  = w_pwdata._write;
        method ppstrb   = w_pstrb._write;
        method ppprot   = w_pprot._write;
        method ppauser  = w_pauser._write;
        method ppwuser  = w_pwuser._write;

        method pready = !reset_asserted && w_psel && w_penable && f_response.notEmpty;
        method prdata  = w_prdata;
        method pslverr = w_pslverr;
        method pruser  = w_pruser;
        method pbuser  = w_pbuser;
    endinterface

endmodule

endpackage
