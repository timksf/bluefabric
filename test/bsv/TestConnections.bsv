package TestConnections;

import Connectable :: *;

import AddrMapDecoder :: *;
import AhbApbBridge :: *;
import AhbMaster :: *;
import AhbMasterMux :: *;
import AhbSlave :: *;
import AhbSlaveMux :: *;
import ApbMaster :: *;
import ApbMasterMux :: *;
import ApbSlave :: *;
import ApbSlaveMux :: *;

// Two 4 KiB targets at 0x0000 and 0x1000, for any mux width.
function Bit#(n) decode_ahb_address(Bit#(32) address);
    Bit#(n) sel = 0;
    for(Integer i = 0; i < valueOf(n) && i < 2; i = i + 1)
        sel[i] = pack(address >> 12 == fromInteger(i));
    return sel;
endfunction

(* synthesize *)
module mkTestConnections(Empty);

    ApbMaster_ifc#(32, 32, 1) i_apb_master <- mkApbMaster(2);
    ApbSlave_ifc#(32, 32, 1)  i_apb_slave  <- mkApbSlave(True);

    mkConnection(i_apb_master.fabric, i_apb_slave.fabric);

    AhbMaster_ifc#(32, 32) i_ahb_master <- mkAhbMaster(2);
    AhbSlave_ifc#(32, 32)  i_ahb_slave  <- mkAhbSlave(True);

    mkConnection(i_ahb_master.fabric, i_ahb_slave.fabric);

    AhbMaster_ifc#(32, 32) i_ahb_master0 <- mkAhbMaster(2);
    AhbMaster_ifc#(32, 32) i_ahb_master1 <- mkAhbMaster(2);
    AhbMasterMux_ifc#(2, 32, 32) i_ahb_master_mux <- mkAhbMasterMux;
    AhbSlaveMux_ifc#(2, 32, 32) i_ahb_slave_mux <- mkAhbSlaveMux(decode_ahb_address);
    AhbSlave_ifc#(32, 32) i_ahb_slave0 <- mkAhbSlave(True);
    AhbSlave_ifc#(32, 32) i_ahb_slave1 <- mkAhbSlave(True);

    mkConnection(i_ahb_master0.fabric, i_ahb_master_mux.up[0]);
    mkConnection(i_ahb_master1.fabric, i_ahb_master_mux.up[1]);
    mkConnection(i_ahb_master_mux.down, i_ahb_slave_mux.slave);
    mkConnection(i_ahb_slave_mux.masters[0], i_ahb_slave0.fabric);
    mkConnection(i_ahb_slave_mux.masters[1], i_ahb_slave1.fabric);

    AhbMaster_ifc#(32, 32) i_bridge_master0 <- mkAhbMaster(2);
    AhbMaster_ifc#(32, 32) i_bridge_master1 <- mkAhbMaster(2);
    AhbMasterMux_ifc#(2, 32, 32) i_bridge_ahb_master_mux <- mkAhbMasterMux;
    AhbSlaveMux_ifc#(1, 32, 32) i_bridge_ahb_mux <- mkAhbSlaveMux(decode_ahb_address);
    AhbApbBridge_ifc#(32, 32, 1) i_bridge <- mkAhbApbBridge;
    ApbMaster_ifc#(32, 32, 1) i_bridge_apb_master <- mkApbMaster(2);
    ApbMasterMux_ifc#(2, 32, 32, 1) i_bridge_apb_master_mux <- mkApbMasterMux;
    ApbSlaveMux_ifc#(2, 32, 32, 1) i_bridge_apb_mux <- mkApbSlaveMux(decode_ahb_address);
    ApbSlave_ifc#(32, 32, 1) i_bridge_apb_slave0 <- mkApbSlave(True);
    ApbSlave_ifc#(32, 32, 1) i_bridge_apb_slave1 <- mkApbSlave(True);

    mkConnection(i_bridge_master0.fabric, i_bridge_ahb_master_mux.up[0]);
    mkConnection(i_bridge_master1.fabric, i_bridge_ahb_master_mux.up[1]);
    mkConnection(i_bridge_ahb_master_mux.down, i_bridge_ahb_mux.slave);
    mkConnection(i_bridge_ahb_mux.masters[0], i_bridge.ahb);
    mkConnection(i_bridge.apb, i_bridge_apb_master_mux.slaves[0]);
    mkConnection(i_bridge_apb_master.fabric, i_bridge_apb_master_mux.slaves[1]);
    mkConnection(i_bridge_apb_master_mux.master, i_bridge_apb_mux.slave);
    mkConnection(i_bridge_apb_mux.masters[0], i_bridge_apb_slave0.fabric);
    mkConnection(i_bridge_apb_mux.masters[1], i_bridge_apb_slave1.fabric);

endmodule

endpackage
