package TestAhbApbBridge;

import AhbApbBridge :: *;
import AhbSlave :: *;
import ApbMaster :: *;

interface TestAhbApbBridge_ifc;
    (* prefix = "S_AHB" *)
    interface AhbSlaveFabric_ifc#(16, 32) s_ahb;

    (* prefix = "M_APB" *)
    interface ApbMasterFabric_ifc#(16, 32, 1) m_apb;
endinterface

(* synthesize *)
module mkTestAhbApbBridge(TestAhbApbBridge_ifc);

    AhbApbBridge_ifc#(16, 32, 1) i_bridge <- mkAhbApbBridge;

    interface s_ahb = i_bridge.ahb;
    interface m_apb = i_bridge.apb;

endmodule

endpackage
