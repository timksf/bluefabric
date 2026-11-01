package ApbAddrMap;

import BuildVector :: *;
import Vector :: *;

import ApbMaster :: *;
import ApbSlave :: *;
import ApbSlaveMux :: *;
import BlueAddrMap :: *;

//APB has no router settings, cuts are not implemented yet
typedef AddrMapBusCfg_t#(AddrMapNoCfg_t, AddrMapCut_t) ApbBusCfg_t;

//passes everything through and reports PADDR
function ApbSlaveFabric_ifc#(aw, dw, uw) apb_tap_addr(Wire#(Bit#(aw)) w_paddr, ApbSlaveFabric_ifc#(aw, dw, uw) s);
    return interface ApbSlaveFabric_ifc;
        method Action ppaddr(Bit#(aw) a);
            w_paddr <= a;
            s.ppaddr(a);
        endmethod
        method ppsel    = s.ppsel;
        method ppenable = s.ppenable;
        method ppwrite  = s.ppwrite;
        method ppwdata  = s.ppwdata;
        method ppstrb   = s.ppstrb;
        method ppprot   = s.ppprot;
        method ppauser  = s.ppauser;
        method ppwuser  = s.ppwuser;

        method pready  = s.pready;
        method prdata  = s.prdata;
        method pslverr = s.pslverr;
        method pruser  = s.pruser;
        method pbuser  = s.pbuser;
    endinterface;
endfunction

instance AddrMapFabric#(ApbSlaveFabric_ifc#(aw, dw, uw), ApbMasterFabric_ifc#(aw, dw, uw), 1, aw, AddrMapNoCfg_t, AddrMapCut_t);

    module mkAddrMapRouter#(AddrMapNoCfg_t cfg)(AddrMapRouter_ifc#(n, 1, aw, ApbSlaveFabric_ifc#(aw, dw, uw), ApbMasterFabric_ifc#(aw, dw, uw)));
        Wire#(Bit#(aw)) w_paddr <- mkDWire(0);
        Wire#(Bit#(n))  w_sel   <- mkDWire(0);

        //the mux asks for the select of its current address, which route_sel supplies
        function Bit#(n) routed_select(Bit#(aw) address) = w_sel;
        ApbSlaveMux_ifc#(n, aw, dw, uw) i_mux <- mkApbSlaveMux(routed_select);

        interface up   = apb_tap_addr(w_paddr, i_mux.slave);
        interface down = i_mux.masters;

        method route_addr = vec(w_paddr);
        method Action route_sel(Vector#(1, Bit#(n)) sel) = w_sel._write(sel[0]);
    endmodule

    module mkAddrMapCut#(AddrMapCut_t cfg)(AddrMapCut_ifc#(1, aw, side, ApbSlaveFabric_ifc#(aw, dw, uw), ApbMasterFabric_ifc#(aw, dw, uw)))
        provisos(
            Bits#(side, side_w)
        );
        errorM("APB cuts are not implemented yet");
        return ?;
    endmodule

    function addr_map_local = apb_local;

endinstance

endpackage
