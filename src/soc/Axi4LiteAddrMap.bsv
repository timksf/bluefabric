package Axi4LiteAddrMap;

import BuildVector :: *;
import DefaultValue :: *;
import Vector :: *;

import AXI4_Lite_Master :: *;
import AXI4_Lite_Slave :: *;
import AXI4_Lite_Types :: *;

import Axi4Lite :: *;
import Axi4LiteRegSlice :: *;
import Axi4LiteSlaveMux :: *;
import BlueAddrMap :: *;

typedef struct {
    Integer max_outstanding;    //outstanding reads and, independently, writes
    Bool    fall_through;       //same cycle responses, see mkAxi4LiteSlaveMux
} Axi4LiteRouterCfg_t;

instance DefaultValue#(Axi4LiteRouterCfg_t);
    defaultValue = Axi4LiteRouterCfg_t { max_outstanding: 2, fall_through: False };
endinstance

//cuts are register slices, configured per channel
typedef AddrMapBusCfg_t#(Axi4LiteRouterCfg_t, Axi4LiteRegSliceCfg_t) Axi4LiteBusCfg_t;

instance AddrMapCutCfg#(Axi4LiteRegSliceCfg_t);
    addr_map_cut_none = axi4_lite_slice_none;
    function Bool addr_map_cut_enabled(Axi4LiteRegSliceCfg_t cfg) = cfg != axi4_lite_slice_none;
endinstance

//passes everything through and reports the AR and AW addresses
function Axi4LiteSlaveFab_ifc#(aw, dw) axi4_lite_tap_addr(Wire#(Bit#(aw)) w_araddr, Wire#(Bit#(aw)) w_awaddr, Axi4LiteSlaveFab_ifc#(aw, dw) s);
    return interface Axi4LiteSlaveFab_ifc;
        interface AXI4_Lite_Slave_Rd_Fab rd;
            method arready                          = s.rd.arready;
            method Action parvalid(Bool v)          = s.rd.parvalid(v);
            method Action paraddr(Bit#(aw) a);
                w_araddr <= a;
                s.rd.paraddr(a);
            endmethod
            method Action parprot(AXI4_Lite_Prot p) = s.rd.parprot(p);
            method rvalid                           = s.rd.rvalid;
            method Action prready(Bool r)           = s.rd.prready(r);
            method rdata                            = s.rd.rdata;
            method rresp                            = s.rd.rresp;
        endinterface
        interface AXI4_Lite_Slave_Wr_Fab wr;
            method awready                             = s.wr.awready;
            method Action pawvalid(Bool v)             = s.wr.pawvalid(v);
            method Action pawaddr(Bit#(aw) a);
                w_awaddr <= a;
                s.wr.pawaddr(a);
            endmethod
            method Action pawprot(AXI4_Lite_Prot p)    = s.wr.pawprot(p);
            method wready                              = s.wr.wready;
            method Action pwvalid(Bool v)              = s.wr.pwvalid(v);
            method Action pwdata(Bit#(dw) d)           = s.wr.pwdata(d);
            method Action pwstrb(Bit#(TDiv#(dw, 8)) b) = s.wr.pwstrb(b);
            method bvalid                              = s.wr.bvalid;
            method Action pbready(Bool b)              = s.wr.pbready(b);
            method bresp                               = s.wr.bresp;
        endinterface
    endinterface;
endfunction

//AR and AW are routed independently
instance AddrMapFabric#(Axi4LiteSlaveFab_ifc#(aw, dw), Axi4LiteMasterFab_ifc#(aw, dw), 2, aw, Axi4LiteRouterCfg_t, Axi4LiteRegSliceCfg_t);

    module mkAddrMapRouter#(Axi4LiteRouterCfg_t cfg)(AddrMapRouter_ifc#(n, 2, aw, Axi4LiteSlaveFab_ifc#(aw, dw), Axi4LiteMasterFab_ifc#(aw, dw)));
        //validated regions never overlap, so the decoded select is zero or one-hot
        Axi4LiteSlaveMux_ifc#(n, aw, dw) i_mux <- mkAxi4LiteSlaveMuxCfg(Axi4LiteSlaveMuxCfg_t {
            max_outstanding: cfg.max_outstanding,
            fall_through:    cfg.fall_through,
            sel_onehot0:     True
        });

        Wire#(Bit#(aw)) w_araddr <- mkDWire(0);
        Wire#(Bit#(aw)) w_awaddr <- mkDWire(0);

        function Axi4LiteMasterFab_ifc#(aw, dw) down_port(Integer i) = axi4_lite_master_fab(i_mux.m_rd[i], i_mux.m_wr[i]);

        interface up   = axi4_lite_tap_addr(w_araddr, w_awaddr, axi4_lite_slave_fab(i_mux.s_rd, i_mux.s_wr));
        interface down = genWith(down_port);

        method route_addr = vec(w_araddr, w_awaddr);
        method Action route_sel(Vector#(2, Bit#(n)) sel);
            i_mux.sel_rd(sel[0]);
            i_mux.sel_wr(sel[1]);
        endmethod
    endmodule

    module mkAddrMapCut#(Axi4LiteRegSliceCfg_t cfg)(AddrMapCut_ifc#(2, aw, side, Axi4LiteSlaveFab_ifc#(aw, dw), Axi4LiteMasterFab_ifc#(aw, dw)))
        provisos(
            Bits#(side, side_w)
        );
        Axi4LiteRegSliceSide_ifc#(aw, dw, side) i_slice <- mkAxi4LiteRegSliceSide(cfg);

        interface up   = axi4_lite_slave_fab(i_slice.slice.s_rd, i_slice.slice.s_wr);
        interface down = axi4_lite_master_fab(i_slice.slice.m_rd, i_slice.slice.m_wr);

        method up_addr = vec(i_slice.up_araddr, i_slice.up_awaddr);
        method Action up_side(Vector#(2, side) sides);
            i_slice.up_ar_side(sides[0]);
            i_slice.up_aw_side(sides[1]);
        endmethod
        method down_side = vec(i_slice.down_ar_side, i_slice.down_aw_side);
    endmodule

    function addr_map_local = axi4_lite_local;

endinstance

endpackage
