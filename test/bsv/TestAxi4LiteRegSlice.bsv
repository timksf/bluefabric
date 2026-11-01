package TestAxi4LiteRegSlice;

import Axi4LiteRegSlice :: *;

// 0: no channel registered, 1: request channels only, 2: every channel.
`ifndef REG_SLICE_CFG
`define REG_SLICE_CFG 2
`endif

(* synthesize *)
module mkTestAxi4LiteRegSlice(Axi4LiteRegSlice_ifc#(16, 32));
    Axi4LiteRegSliceCfg_t cfg = case(`REG_SLICE_CFG)
        0: axi4_lite_slice_none;
        1: axi4_lite_slice_request;
        default: axi4_lite_slice_all;
    endcase;
    let i_slice <- mkAxi4LiteRegSlice(cfg);
    return i_slice;
endmodule

endpackage
