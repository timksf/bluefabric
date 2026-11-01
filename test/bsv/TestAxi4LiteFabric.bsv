package TestAxi4LiteFabric;

import Axi4LiteSlaveMux :: *;

`ifndef AXI_MUX_PORTS
`define AXI_MUX_PORTS 3
`endif
`ifndef AXI_MUX_DEPTH
`define AXI_MUX_DEPTH 3
`endif

`ifndef AXI_MUX_FALL_THROUGH
`define AXI_MUX_FALL_THROUGH 1
`endif

`ifndef AXI_MUX_ONEHOT0
`define AXI_MUX_ONEHOT0 0
`endif

(* synthesize *)
module mkTestAxi4LiteFabric(Axi4LiteSlaveMux_ifc#(`AXI_MUX_PORTS, 16, 32));
    let i_mux <- mkAxi4LiteSlaveMuxCfg(Axi4LiteSlaveMuxCfg_t {
        max_outstanding: `AXI_MUX_DEPTH,
        fall_through:    `AXI_MUX_FALL_THROUGH == 1,
        sel_onehot0:     `AXI_MUX_ONEHOT0 == 1
    });
    return i_mux;
endmodule

endpackage
