package Axi4LiteRegSlice;

import DefaultValue :: *;

import AXI4_Lite_Master :: *;
import AXI4_Lite_Slave :: *;
import AXI4_Lite_Types :: *;

import RegSlice :: *;

//channels to register, each registered channel costs one cycle of latency and cuts its VALID/payload and READY paths
typedef struct {
    Bool ar;
    Bool r;
    Bool aw;
    Bool w;
    Bool b;
} Axi4LiteRegSliceCfg_t deriving(Bits, Eq, FShow);

Axi4LiteRegSliceCfg_t axi4_lite_slice_none = Axi4LiteRegSliceCfg_t {
    ar: False, r: False, aw: False, w: False, b: False
};

//request channels only, registers the address that feeds an address decoder
Axi4LiteRegSliceCfg_t axi4_lite_slice_request = Axi4LiteRegSliceCfg_t {
    ar: True, r: False, aw: True, w: True, b: False
};

Axi4LiteRegSliceCfg_t axi4_lite_slice_all = Axi4LiteRegSliceCfg_t {
    ar: True, r: True, aw: True, w: True, b: True
};

instance DefaultValue#(Axi4LiteRegSliceCfg_t);
    defaultValue = axi4_lite_slice_all;
endinstance

interface Axi4LiteRegSlice_ifc#(numeric type aw, numeric type dw);
    interface AXI4_Lite_Slave_Rd_Fab#(aw, dw)  s_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(aw, dw)  s_wr;
    interface AXI4_Lite_Master_Rd_Fab#(aw, dw) m_rd;
    interface AXI4_Lite_Master_Wr_Fab#(aw, dw) m_wr;
endinterface

//every channel is an independent RegSliceChannel, so channels can be registered selectively
module mkAxi4LiteRegSlice#(Axi4LiteRegSliceCfg_t cfg)(Axi4LiteRegSlice_ifc#(aw, dw));
    RegSliceChannel_ifc#(Tuple2#(Bit#(aw), AXI4_Lite_Prot))           i_ar <- mkRegSliceChannel(cfg.ar);
    RegSliceChannel_ifc#(Tuple2#(Bit#(dw), AXI4_Lite_Response))       i_r  <- mkRegSliceChannel(cfg.r);
    RegSliceChannel_ifc#(Tuple2#(Bit#(aw), AXI4_Lite_Prot))           i_aw <- mkRegSliceChannel(cfg.aw);
    RegSliceChannel_ifc#(Tuple2#(Bit#(dw), Bit#(TDiv#(dw, 8))))       i_w  <- mkRegSliceChannel(cfg.w);
    RegSliceChannel_ifc#(AXI4_Lite_Response)                          i_b  <- mkRegSliceChannel(cfg.b);

    //the fabric interfaces split each channel into one method per signal
    Wire#(Bool)               w_arvalid <- mkBypassWire;
    Wire#(Bit#(aw))           w_araddr  <- mkBypassWire;
    Wire#(AXI4_Lite_Prot)     w_arprot  <- mkBypassWire;
    Wire#(Bool)               w_rvalid  <- mkBypassWire;
    Wire#(Bit#(dw))           w_rdata   <- mkBypassWire;
    Wire#(AXI4_Lite_Response) w_rresp   <- mkBypassWire;
    Wire#(Bool)               w_awvalid <- mkBypassWire;
    Wire#(Bit#(aw))           w_awaddr  <- mkBypassWire;
    Wire#(AXI4_Lite_Prot)     w_awprot  <- mkBypassWire;
    Wire#(Bool)               w_wvalid  <- mkBypassWire;
    Wire#(Bit#(dw))           w_wdata   <- mkBypassWire;
    Wire#(Bit#(TDiv#(dw, 8))) w_wstrb   <- mkBypassWire;
    Wire#(Bool)               w_bvalid  <- mkBypassWire;
    Wire#(AXI4_Lite_Response) w_bresp   <- mkBypassWire;

    //one rule per channel, in pass through mode the channels must not depend on each other's wires
    //e.g. AR feeds an address decoder whose select steers R
    rule r_ar_source; i_ar.source(w_arvalid, tuple2(w_araddr, w_arprot)); endrule
    rule r_r_source;  i_r.source (w_rvalid,  tuple2(w_rdata,  w_rresp));  endrule
    rule r_aw_source; i_aw.source(w_awvalid, tuple2(w_awaddr, w_awprot)); endrule
    rule r_w_source;  i_w.source (w_wvalid,  tuple2(w_wdata,  w_wstrb));  endrule
    rule r_b_source;  i_b.source (w_bvalid,  w_bresp);                    endrule

    interface AXI4_Lite_Slave_Rd_Fab s_rd;
        method parvalid = w_arvalid._write;
        method paraddr  = w_araddr._write;
        method parprot  = w_arprot._write;
        method arready  = i_ar.source_ready;

        method rvalid   = i_r.sink_valid;
        method rdata    = tpl_1(i_r.sink_payload);
        method rresp    = tpl_2(i_r.sink_payload);
        method prready  = i_r.sink;
    endinterface

    interface AXI4_Lite_Slave_Wr_Fab s_wr;
        method pawvalid = w_awvalid._write;
        method pawaddr  = w_awaddr._write;
        method pawprot  = w_awprot._write;
        method awready  = i_aw.source_ready;

        method pwvalid  = w_wvalid._write;
        method pwdata   = w_wdata._write;
        method pwstrb   = w_wstrb._write;
        method wready   = i_w.source_ready;

        method bvalid   = i_b.sink_valid;
        method bresp    = i_b.sink_payload;
        method pbready  = i_b.sink;
    endinterface

    interface AXI4_Lite_Master_Rd_Fab m_rd;
        method arvalid  = i_ar.sink_valid;
        method araddr   = tpl_1(i_ar.sink_payload);
        method arprot   = tpl_2(i_ar.sink_payload);
        method parready = i_ar.sink;

        method prvalid  = w_rvalid._write;
        method prdata   = w_rdata._write;
        method prresp   = w_rresp._write;
        method rready   = i_r.source_ready;
    endinterface

    interface AXI4_Lite_Master_Wr_Fab m_wr;
        method awvalid  = i_aw.sink_valid;
        method awaddr   = tpl_1(i_aw.sink_payload);
        method awprot   = tpl_2(i_aw.sink_payload);
        method pawready = i_aw.sink;

        method wvalid   = i_w.sink_valid;
        method wdata    = tpl_1(i_w.sink_payload);
        method wstrb    = tpl_2(i_w.sink_payload);
        method pwready  = i_w.sink;

        method pbvalid  = w_bvalid._write;
        method pbresp   = w_bresp._write;
        method bready   = i_b.source_ready;
    endinterface
endmodule

endpackage
