package AhbAddrMap;

import BuildVector :: *;
import Connectable :: *;
import Vector :: *;

import Ahb :: *;
import AhbApbBridge :: *;
import AhbMaster :: *;
import AhbSlave :: *;
import AhbSlaveMux :: *;
import ApbMaster :: *;
import ApbSlave :: *;
import BlueAddrMap :: *;

//AHB has no router settings, cuts are not implemented yet
typedef AddrMapBusCfg_t#(AddrMapNoCfg_t, AddrMapCut_t) AhbBusCfg_t;

//passes everything through and reports HADDR
function AhbSlaveFabric_ifc#(aw, dw) ahb_tap_addr(Wire#(Bit#(aw)) w_haddr, AhbSlaveFabric_ifc#(aw, dw) s);
    return interface AhbSlaveFabric_ifc;
        method Action pphaddr(Bit#(aw) a);
            w_haddr <= a;
            s.pphaddr(a);
        endmethod
        method pphsel      = s.pphsel;
        method pphtrans    = s.pphtrans;
        method pphwrite    = s.pphwrite;
        method pphsize     = s.pphsize;
        method pphburst    = s.pphburst;
        method pphprot     = s.pphprot;
        method pphmastlock = s.pphmastlock;
        method pphwdata    = s.pphwdata;
        method pphreadyin  = s.pphreadyin;

        method hreadyout = s.hreadyout;
        method hrdata    = s.hrdata;
        method hresp     = s.hresp;
    endinterface;
endfunction

instance AddrMapFabric#(AhbSlaveFabric_ifc#(aw, dw), AhbMasterFabricShared_ifc#(aw, dw), 1, aw, AddrMapNoCfg_t, AddrMapCut_t);

    module mkAddrMapRouter#(AddrMapNoCfg_t cfg)(AddrMapRouter_ifc#(n, 1, aw, AhbSlaveFabric_ifc#(aw, dw), AhbMasterFabricShared_ifc#(aw, dw)));
        Wire#(Bit#(aw)) w_haddr <- mkDWire(0);
        Wire#(Bit#(n))  w_sel   <- mkDWire(0);

        //the mux asks for the select of its current address phase, which route_sel supplies
        function Bit#(n) routed_select(Bit#(aw) address) = w_sel;
        AhbSlaveMux_ifc#(n, aw, dw) i_mux <- mkAhbSlaveMux(routed_select);

        interface up   = ahb_tap_addr(w_haddr, i_mux.slave);
        interface down = i_mux.masters;

        method route_addr = vec(w_haddr);
        method Action route_sel(Vector#(1, Bit#(n)) sel) = w_sel._write(sel[0]);
    endmodule

    module mkAddrMapCut#(AddrMapCut_t cfg)(AddrMapCut_ifc#(1, aw, side, AhbSlaveFabric_ifc#(aw, dw), AhbMasterFabricShared_ifc#(aw, dw)))
        provisos(
            Bits#(side, side_w)
        );
        errorM("AHB cuts are not implemented yet");
        return ?;
    endmodule

    function addr_map_local = ahb_local;

endinstance

//an APB bus behind mkAhbApbBridge
instance AddrMapBridge#(AhbSlaveFabric_ifc#(aw, dw), ApbSlaveFabric_ifc#(aw, dw, uw));
    module mkAddrMapBridge#(ApbSlaveFabric_ifc#(aw, dw, uw) down)(AhbSlaveFabric_ifc#(aw, dw));
        AhbApbBridge_ifc#(aw, dw, uw) i_bridge <- mkAhbApbBridge;
        mkConnection(i_bridge.apb, down);
        return i_bridge.ahb;
    endmodule
endinstance

endpackage
