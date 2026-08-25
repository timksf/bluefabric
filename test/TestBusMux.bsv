package TestBusMux;

import Vector :: *;

import AddrMapDecoder :: *;
import ApbMaster :: *;
import ApbMasterMux :: *;
import ApbSlave :: *;
import ApbSlaveMux :: *;
import AhbMaster :: *;
import AhbMasterMux :: *;
import AhbSlave :: *;
import AhbSlaveMux :: *;

module mkTestAddrMapDecoder(AddrMapDecoder_ifc#(16));
    method AddrMapHit_t#(16) lookup(Bit#(16) address, Bit#(16) bytes);
        AddrMapHit_t#(16) result = AddrMapHit_t {
            hit          : False,
            target_index : 0,
            global_addr  : address,
            offset       : 0
        };

        if(bytes != 0 && address < 16'h1000 &&
                zeroExtend(address) + zeroExtend(bytes) <= 17'h01000) begin
            result.hit = True;
            result.target_index = 0;
            result.offset = address;
        end else if(bytes != 0 && address >= 16'h1000 &&
                zeroExtend(address) + zeroExtend(bytes) <= 17'h02000) begin
            result.hit = True;
            result.target_index = 1;
            result.offset = address - 16'h1000;
        end

        return result;
    endmethod
endmodule

interface TestApbSlaveMux_ifc;
    (* prefix = "S_APB" *)
    interface ApbSlaveFabric_ifc#(16, 32, 4) s_apb;
    (* prefix = "M_APB0" *)
    interface ApbMasterFabric_ifc#(16, 32, 4) m_apb0;
    (* prefix = "M_APB1" *)
    interface ApbMasterFabric_ifc#(16, 32, 4) m_apb1;
endinterface

(* synthesize *)
module mkTestApbSlaveMux(TestApbSlaveMux_ifc);
    let i_decoder <- mkTestAddrMapDecoder;
    ApbSlaveMux_ifc#(2, 16, 32, 4) i_mux <-
        mkApbSlaveMux(i_decoder.lookup);

    interface s_apb  = i_mux.slave;
    interface m_apb0 = i_mux.masters[0];
    interface m_apb1 = i_mux.masters[1];
endmodule

interface TestApbMasterMux_ifc;
    (* prefix = "S_APB0" *)
    interface ApbSlaveFabric_ifc#(16, 32, 4) s_apb0;
    (* prefix = "S_APB1" *)
    interface ApbSlaveFabric_ifc#(16, 32, 4) s_apb1;
    (* prefix = "M_APB" *)
    interface ApbMasterFabric_ifc#(16, 32, 4) m_apb;
endinterface

(* synthesize *)
module mkTestApbMasterMux(TestApbMasterMux_ifc);
    ApbMasterMux_ifc#(2, 16, 32, 4) i_mux <- mkApbMasterMux;

    interface s_apb0 = i_mux.slaves[0];
    interface s_apb1 = i_mux.slaves[1];
    interface m_apb  = i_mux.master;
endmodule

interface TestAhbSlaveMux_ifc;
    (* prefix = "S_AHB" *)
    interface AhbSlaveFabric_ifc#(16, 32) s_ahb;
    (* prefix = "M_AHB0" *)
    interface AhbMasterFabricShared_ifc#(16, 32) m_ahb0;
    (* prefix = "M_AHB1" *)
    interface AhbMasterFabricShared_ifc#(16, 32) m_ahb1;
endinterface

(* synthesize *)
module mkTestAhbSlaveMux(TestAhbSlaveMux_ifc);
    let i_decoder <- mkTestAddrMapDecoder;
    AhbSlaveMux_ifc#(2, 16, 32) i_mux <-
        mkAhbSlaveMux(i_decoder.lookup);

    interface s_ahb  = i_mux.slave;
    interface m_ahb0 = i_mux.masters[0];
    interface m_ahb1 = i_mux.masters[1];
endmodule

interface TestAhbMasterMux_ifc;
    (* prefix = "S_AHB0" *)
    interface AhbSlaveFabric_ifc#(16, 32) s_ahb0;
    (* prefix = "S_AHB1" *)
    interface AhbSlaveFabric_ifc#(16, 32) s_ahb1;
    (* prefix = "S_AHB2" *)
    interface AhbSlaveFabric_ifc#(16, 32) s_ahb2;
    (* prefix = "M_AHB" *)
    interface AhbMasterFabric_ifc#(16, 32) m_ahb;
endinterface

(* synthesize *)
module mkTestAhbMasterMux(TestAhbMasterMux_ifc);
    AhbMasterMux_ifc#(3, 16, 32) i_mux <- mkAhbMasterMux;

    interface s_ahb0 = i_mux.up[0];
    interface s_ahb1 = i_mux.up[1];
    interface s_ahb2 = i_mux.up[2];
    interface m_ahb  = i_mux.down;
endmodule

endpackage
