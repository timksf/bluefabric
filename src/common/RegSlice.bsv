package RegSlice;

import Clocks :: *;
import FIFOF :: *;

//protocol independent VALID/READY channel
//enabled:  a two entry FIFO (skid buffer) registers VALID, payload and READY
//          cuts every combinational path through the channel, keeps one transfer per cycle and adds one cycle of latency
//disabled: plain wires, no registers and no latency
(* always_enabled *)
interface RegSliceChannel_ifc#(type t);
    //upstream
    method Action   source(Bool valid, t payload);
    method Bool     source_ready;

    //downstream
    method Bool     sink_valid;
    method t        sink_payload;
    method Action   sink(Bool ready);
endinterface

module mkRegSliceChannel#(Bool enable)(RegSliceChannel_ifc#(t)) provisos(Bits#(t, t_width));
    //a missing source/sink call reads as VALID/READY low instead of blocking the rules
    Wire#(Bool) w_valid   <- mkDWire(False);
    Wire#(t)    w_payload <- mkDWire(?);
    Wire#(Bool) w_ready   <- mkDWire(False);

    RegSliceChannel_ifc#(t) ifc = ?;

    if(enable) begin
        let reset_asserted <- isResetAsserted;
        //unguarded so the outputs come straight from the FIFO registers, the rules state enq/deq conditions explicitly
        FIFOF#(t) f_slice <- mkUGFIFOF;

        rule r_enq(!reset_asserted && w_valid && f_slice.notFull);
            f_slice.enq(w_payload);
        endrule

        rule r_deq(!reset_asserted && w_ready && f_slice.notEmpty);
            f_slice.deq;
        endrule

        ifc = interface RegSliceChannel_ifc;
            method Action source(Bool valid, t payload);
                w_valid   <= valid;
                w_payload <= payload;
            endmethod
            method source_ready = !reset_asserted && f_slice.notFull;
            method sink_valid   = !reset_asserted && f_slice.notEmpty;
            method sink_payload = f_slice.first;
            method sink         = w_ready._write;
        endinterface;
    end else begin
        ifc = interface RegSliceChannel_ifc;
            method Action source(Bool valid, t payload);
                w_valid   <= valid;
                w_payload <= payload;
            endmethod
            method source_ready = w_ready;
            method sink_valid   = w_valid;
            method sink_payload = w_payload;
            method sink         = w_ready._write;
        endinterface;
    end

    return ifc;
endmodule

endpackage
