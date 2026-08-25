package AhbSlave;

import Clocks :: *;
import FIFOF :: *;
import GetPut :: *;
import SpecialFIFOs :: *;

import Ahb :: *;

(* always_ready, always_enabled *)
interface AhbSlaveFabric_ifc#(
    numeric type addr_w,
    numeric type data_w
);
    (* prefix = "" *)
    method Action pphaddr((* port = "haddr" *) Bit#(addr_w) value);
    (* prefix = "" *)
    method Action pphsel((* port = "hsel" *) Bool value);
    (* prefix = "" *)
    method Action pphtrans((* port = "htrans" *) AhbTransfer_t value);
    (* prefix = "" *)
    method Action pphwrite((* port = "hwrite" *) Bool value);
    (* prefix = "" *)
    method Action pphsize((* port = "hsize" *) AhbSize_t value);
    (* prefix = "" *)
    method Action pphburst((* port = "hburst" *) AhbBurst_t value);
    (* prefix = "" *)
    method Action pphprot((* port = "hprot" *) AhbProtection_t value);
    (* prefix = "" *)
    method Action pphmastlock((* port = "hmastlock" *) Bool value);
    (* prefix = "" *)
    method Action pphwdata((* port = "hwdata" *) Bit#(data_w) value);
    (* prefix = "" *)
    method Action pphreadyin((* port = "hreadyin" *) Bool value);

    method Bool hreadyout;
    method Bit#(data_w) hrdata;
    method Bool hresp;
endinterface

interface AhbSlave_ifc#(
    numeric type addr_w,
    numeric type data_w
);
    (* prefix = "" *)
    interface AhbSlaveFabric_ifc#(addr_w, data_w) fabric;

    interface Get#(AhbRequest_t#(addr_w, data_w)) request;
    method AhbRequest_t#(addr_w, data_w) first;
    interface Get#(AhbTransferRequest_t#(addr_w, data_w)) transfer_request;
    method AhbTransferRequest_t#(addr_w, data_w) first_transfer;
    interface Put#(AhbResponse_t#(data_w)) response;
endinterface

module mkAhbSlave#(Bool pipeline_req)(
    AhbSlave_ifc#(addr_w, data_w)
);

    let reset_asserted <- isResetAsserted();

    FIFOF#(AhbTransferRequest_t#(addr_w, data_w)) f_request = ?;
    if(pipeline_req) begin
        f_request <- mkPipelineFIFOF;
    end else begin
        f_request <- mkBypassFIFOF;
    end

    FIFOF#(AhbResponse_t#(data_w)) f_response <- mkBypassFIFOF;

    Reg#(Maybe#(AhbTransferRequest_t#(addr_w, data_w))) rg_data <-
        mkReg(tagged Invalid);
    Reg#(Bool) rg_request_sent <- mkReg(False);
    Reg#(Bool) rg_error_first  <- mkReg(False);
    PulseWire pw_request_sent  <- mkPulseWire;

    Wire#(Bit#(addr_w)) w_haddr     <- mkBypassWire;
    Wire#(Bool)         w_hsel      <- mkBypassWire;
    Wire#(AhbTransfer_t) w_htrans   <- mkBypassWire;
    Wire#(Bool)         w_hwrite    <- mkBypassWire;
    Wire#(AhbSize_t)    w_hsize     <- mkBypassWire;
    Wire#(AhbBurst_t)   w_hburst    <- mkBypassWire;
    Wire#(AhbProtection_t) w_hprot  <- mkBypassWire;
    Wire#(Bool)         w_hmastlock <- mkBypassWire;
    Wire#(Bit#(data_w)) w_hwdata    <- mkBypassWire;
    Wire#(Bool)         w_hreadyin  <- mkBypassWire;

    Wire#(Bit#(data_w)) w_hrdata         <- mkDWire(0);
    Wire#(Bool)         w_response_error <- mkDWire(False);

    Bool data_valid = isValid(rg_data);
    Bool response_valid = f_response.notEmpty;
    Bool data_ready = !data_valid ||
        (response_valid && (!w_response_error || rg_error_first));
    Bool address_valid = w_hsel &&
        (w_htrans == AHB_NONSEQ || w_htrans == AHB_SEQ);

    rule r_forward_response;
        w_hrdata         <= f_response.first.read_data;
        w_response_error <= f_response.first.slave_error;
    endrule

    rule r_update_data_phase if(!reset_asserted);
        if(w_hreadyin) begin
            if(address_valid) begin
                rg_data <= tagged Valid AhbTransferRequest_t {
                    request: AhbRequest_t {
                        address    : w_haddr,
                        write      : w_hwrite,
                        write_data : 0,
                        size       : w_hsize,
                        protection : w_hprot,
                        lock       : w_hmastlock
                    },
                    transfer : w_htrans,
                    burst    : w_hburst
                };
            end else begin
                rg_data <= tagged Invalid;
            end
            rg_request_sent <= False;
            rg_error_first  <= False;
        end else begin
            if(pw_request_sent)
                rg_request_sent <= True;
            if(data_valid && response_valid &&
                    w_response_error && !rg_error_first)
                rg_error_first <= True;
        end
    endrule

    rule r_complete_response if(!reset_asserted && w_hreadyin);
        f_response.deq;
    endrule

    rule r_send_request if(
        rg_data matches tagged Valid .request &&&
        !reset_asserted && !rg_request_sent && f_request.notFull
    );
        let value = request;
        value.request.write_data = w_hwdata;
        f_request.enq(value);
        pw_request_sent.send;
    endrule

    method first = f_request.first.request;
    method first_transfer = f_request.first;

    interface Get request;
        method ActionValue#(AhbRequest_t#(addr_w, data_w)) get;
            let value = f_request.first.request;
            f_request.deq;
            return value;
        endmethod
    endinterface

    interface transfer_request = toGet(f_request);
    interface response = toPut(f_response);

    interface AhbSlaveFabric_ifc fabric;
        method pphaddr     = w_haddr._write;
        method pphsel      = w_hsel._write;
        method pphtrans    = w_htrans._write;
        method pphwrite    = w_hwrite._write;
        method pphsize     = w_hsize._write;
        method pphburst    = w_hburst._write;
        method pphprot     = w_hprot._write;
        method pphmastlock = w_hmastlock._write;
        method pphwdata    = w_hwdata._write;
        method pphreadyin  = w_hreadyin._write;

        method hreadyout = !reset_asserted && data_ready;
        method hrdata = w_hrdata;
        method hresp = w_response_error;
    endinterface

endmodule

endpackage
