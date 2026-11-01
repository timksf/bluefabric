package TestRouting;

import GenericArbiter :: *;

// Fixed configurations used only to generate RTL for cocotb tests.

(* synthesize *)
module mkTestGenericArbiter(GenericArbiter_ifc#(4));
    let i_dut <- mkGenericArbiter;
    return i_dut;
endmodule

endpackage
