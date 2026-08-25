package TestRouting;

import AxiStreamCrossbar :: *;
import AxiStreamDemux :: *;
import AxiStreamMux :: *;
import GenericArbiter :: *;

// Fixed configurations used only to generate RTL for cocotb tests.

(* synthesize *)
module mkTestGenericArbiter(GenericArbiter_ifc#(4));
    let i_dut <- mkGenericArbiter;
    return i_dut;
endmodule

(* synthesize *)
module mkTestAxiStreamMux(AxiStreamMux_ifc#(32, 4, 4, 4));
    let i_dut <- mkAxiStreamMux;
    return i_dut;
endmodule

(* synthesize *)
module mkTestAxiStreamDemux(AxiStreamDemux_ifc#(32, 4, 4, 4));
    let i_dut <- mkAxiStreamDemux;
    return i_dut;
endmodule

(* synthesize *)
module mkTestAxiStreamCrossbar(
        AxiStreamCrossbar_ifc#(2, 2, 32, 4, 4, 4)
    );
    let i_dut <- mkAxiStreamCrossbar;
    return i_dut;
endmodule

endpackage
