package Axi4LiteSlaveMux;

import Clocks :: *;
import DefaultValue :: *;
import FIFOF :: *;
import Vector :: *;

import AXI4_Lite_Master :: *;
import AXI4_Lite_Slave :: *;
import AXI4_Lite_Types :: *;

import AddrMapDecoder :: *;

(* always_enabled *)
interface Axi4LiteSlaveMux_ifc#(numeric type n, numeric type aw, numeric type dw);
    (* prefix="" *)
    method Action sel_rd((*port = "sel_rd"*) Bit#(n) select);
    (* prefix="" *)
    method Action sel_wr((*port="sel_wr"*) Bit#(n) select);

    interface AXI4_Lite_Slave_Rd_Fab#(aw, dw) s_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(aw, dw) s_wr;
    interface Vector#(n, AXI4_Lite_Master_Rd_Fab#(aw, dw)) m_rd;
    interface Vector#(n, AXI4_Lite_Master_Wr_Fab#(aw, dw)) m_wr;
endinterface

typedef struct {
    //outstanding transactions for each channel-pair (AR to R) and (AW to B)
    Integer max_outstanding;
    //responses may complete in the cycle their request is accepted
    Bool    fall_through;
    //removes multi-hot detection hardware, behaviour for multi-hot undefined
    Bool    sel_onehot0;
} Axi4LiteSlaveMuxCfg_t;

instance DefaultValue#(Axi4LiteSlaveMuxCfg_t);
    defaultValue = Axi4LiteSlaveMuxCfg_t {
        max_outstanding: 2,
        fall_through:    False,
        sel_onehot0:     False
    };
endinstance

module mkAxi4LiteSlaveMux#(Integer max_outstanding, Bool fall_through)(Axi4LiteSlaveMux_ifc#(n, aw, dw));
    Axi4LiteSlaveMuxCfg_t cfg = defaultValue;
    cfg.max_outstanding = max_outstanding;
    cfg.fall_through    = fall_through;

    let ifc <- mkAxi4LiteSlaveMuxCfg(cfg);
    return ifc;
endmodule

module mkAxi4LiteSlaveMuxCfg#(Axi4LiteSlaveMuxCfg_t cfg)(Axi4LiteSlaveMux_ifc#(n, aw, dw));

    if(cfg.max_outstanding < 1)
        errorM("mkAxi4LiteSlaveMux requires max_outstanding >= 1");

    let reset_asserted <- isResetAsserted();

    //Unguarded, owners feed always-ready outputs, and the tracking rules below state every enq/deq condition explicitly.
    FIFOF#(Bit#(n)) f_read_owner   <- mkUGSizedFIFOF(cfg.max_outstanding);  //owner of every accepted read, oldest first
    FIFOF#(Bit#(0)) f_write_credit <- mkUGSizedFIFOF(cfg.max_outstanding);  //one entry per write from AW until B (bounds outstanding writes)
    FIFOF#(Bit#(n)) f_write_owner  <- mkUGSizedFIFOF(cfg.max_outstanding);  //owner of every accepted AW still waiting for its W
    FIFOF#(Bit#(n)) f_write_resp   <- mkUGSizedFIFOF(cfg.max_outstanding);  //owner of every write with AW and W done, waiting for B
    Reg#(Bool)      rg_early_w     <- mkReg(False);                         //W of the offered, not yet accepted AW has already completed

    //upstream inputs
    Wire#(Bit#(n))            w_sel_rd  <- mkBypassWire;
    Wire#(Bit#(n))            w_sel_wr  <- mkBypassWire;
    Wire#(Bool)               w_arvalid <- mkBypassWire;
    Wire#(Bit#(aw))           w_araddr  <- mkBypassWire;
    Wire#(AXI4_Lite_Prot)     w_arprot  <- mkBypassWire;
    Wire#(Bool)               w_rready  <- mkBypassWire;
    Wire#(Bool)               w_awvalid <- mkBypassWire;
    Wire#(Bit#(aw))           w_awaddr  <- mkBypassWire;
    Wire#(AXI4_Lite_Prot)     w_awprot  <- mkBypassWire;
    Wire#(Bool)               w_wvalid  <- mkBypassWire;
    Wire#(Bit#(dw))           w_wdata   <- mkBypassWire;
    Wire#(Bit#(TDiv#(dw, 8))) w_wstrb   <- mkBypassWire;
    Wire#(Bool)               w_bready  <- mkBypassWire;

    //downstream inputs
    Vector#(n, Wire#(Bool))               vw_arready <- replicateM(mkBypassWire);
    Vector#(n, Wire#(Bool))               vw_rvalid  <- replicateM(mkBypassWire);
    Vector#(n, Wire#(Bit#(dw)))           vw_rdata   <- replicateM(mkBypassWire);
    Vector#(n, Wire#(AXI4_Lite_Response)) vw_rresp   <- replicateM(mkBypassWire);
    Vector#(n, Wire#(Bool))               vw_awready <- replicateM(mkBypassWire);
    Vector#(n, Wire#(Bool))               vw_wready  <- replicateM(mkBypassWire);
    Vector#(n, Wire#(Bool))               vw_bvalid  <- replicateM(mkBypassWire);
    Vector#(n, Wire#(AXI4_Lite_Response)) vw_bresp   <- replicateM(mkBypassWire);

    //check if one-hot or trust config
    function Bit#(n) route(Bit#(n) select);
        if(cfg.sel_onehot0)
            return select;
        else 
            return (select & (select - 1)) == 0 ? select : 0;
    endfunction

    //check if the selected route is ready, if no route is selected, complete immediately (DECERR)
    function Bool routed_ready(Bit#(n) owner, Vector#(n, Wire#(Bool)) readies);
        return owner == 0 || (owner & pack(readVReg(readies))) != 0;
    endfunction

    //DECERR for owner zero
    function AXI4_Lite_Response select_response(Bit#(n) owner, Vector#(n, Wire#(AXI4_Lite_Response)) responses);
        return unpack((owner == 0 ? pack(DECERR) : 0) | pack(onehot_select(owner, readVReg(responses))));
    endfunction


    /* read channel */

    //the read channel tracks read owner by the select signal present at a valid AR transaction
    Bit#(n) ar_route = route(w_sel_rd);                                   //zero for no or multi-hot select
    Bool    ar_space = !reset_asserted && f_read_owner.notFull;           //read queue still has room
    Bool    ar_ready = ar_space && routed_ready(ar_route, vw_arready);    //routes are accepted either for a zero owner(DECERR) or when the path is ready
    Bool    ar_fire  = w_arvalid && ar_ready;

    //a read is allowed when an AR transaction happened earlier or happens currently in fall through mode
    //fall through only forwards target responses, DECERR is always queued and answered one cycle after its AR
    Bool    r_head_valid    = !reset_asserted && (f_read_owner.notEmpty || (cfg.fall_through && w_arvalid && ar_route != 0));    //a queued owner, or in fall through the offered AR to a real target
    Bit#(n) r_head          = (cfg.fall_through && !f_read_owner.notEmpty) ? ar_route : f_read_owner.first;                      //offered AR when fall through with empty queue, otherwise oldest queued owner
    Bool    r_valid         = r_head_valid && (r_head == 0 || (r_head & pack(readVReg(vw_rvalid))) != 0);                        //owner zero is DECERR from the mux, otherwise the owner's RVALID
    Bool    r_fire          = r_valid && w_rready;

    rule r_track_reads;
        //in fall through mode, the fifo still has priority to maintain correct ordering
        Bool fall_through = r_fire && !f_read_owner.notEmpty;    //response completed together with its AR
        if(ar_fire && !fall_through)                             //every accepted AR is queued unless fall through is on
            f_read_owner.enq(ar_route);
        if(r_fire && f_read_owner.notEmpty)                      //when R completes, make space again
            f_read_owner.deq;
    endrule


    /* write channel */

    Bit#(n) aw_route = route(w_sel_wr);                                   //same as AR
    Bool    aw_space = !reset_asserted && f_write_credit.notFull;         //free credit, then owner and resp queues cannot be full either
    Bool    aw_ready = aw_space && routed_ready(aw_route, vw_awready);    //same as AR
    Bool    aw_fire  = w_awvalid && aw_ready;

    //W uses AW order
    Bool    w_queued       = f_write_owner.notEmpty;                                                     //an accepted AW is still waiting for its W
    Bool    w_owner_valid  = !reset_asserted && !rg_early_w && (w_queued || (w_awvalid && aw_space));    //oldest queued AW, or live to the offered AW unless its W already went through (rg_early_w)
    Bit#(n) w_owner        = w_queued ? f_write_owner.first : aw_route;                                  //oldest queued AW first, otherwise the offered AW
    Bool    w_ready        = w_owner_valid && routed_ready(w_owner, vw_wready);                          //route zero consumes W without a target
    Bool    w_fire         = w_wvalid && w_ready;
    Bool    w_before_aw    = w_fire && !w_queued && !aw_fire;                                            //W may arrive earlier than AW

    //a write completes when both its AW and W are complete
    Bool    done_queued = w_fire && w_queued;                                  //AW already fired and W fires
    Bool    done_live   = aw_fire && (rg_early_w || (w_fire && !w_queued));    //AW fires and we either have a W stored or are doing W live
    Bit#(n) done_owner  = w_queued ? f_write_owner.first : aw_route;           //used to track who the response channel belongs to next

    //select the correct response
    Bool    b_next_valid    = w_queued ? w_wvalid : (w_awvalid && aw_space && (rg_early_w || w_wvalid));                              //the write completing next is offered: done_queued || done_live with all READYs high
    Bool    b_head_valid    = !reset_asserted && (f_write_resp.notEmpty || (cfg.fall_through && b_next_valid && done_owner != 0));    //DECERR is never bypassed, it is answered one cycle after the write completes
    Bit#(n) b_head          = (cfg.fall_through && !f_write_resp.notEmpty) ? done_owner : f_write_resp.first;                         //fall through permits live response, otherwise allowed only after the W completes
    Bool    b_valid         = b_head_valid && (b_head == 0 || (b_head & pack(readVReg(vw_bvalid))) != 0);                             //owner zero is DECERR from the mux, otherwise the owner's BVALID
    Bool    b_fire          = b_valid && w_bready;

    rule r_track_writes;
        Bool fall_through = b_fire && !f_write_resp.notEmpty;

        //credits: +1 per accepted AW, -1 per B, both at the same time cancel out
        if(aw_fire && !b_fire)
            f_write_credit.enq(?);
        if(b_fire && !aw_fire)
            f_write_credit.deq;

        if(aw_fire && !rg_early_w && !(w_fire && !w_queued))    //AW still needs its W: not sent early and not live now
            f_write_owner.enq(aw_route);
        if(done_queued)                                         //the oldest queued AW got its W
            f_write_owner.deq;

        if(w_before_aw)     //remember that the offered AW's W already went through
            rg_early_w <= True;
        else if(aw_fire)    //that AW is accepted now
            rg_early_w <= False;

        if((done_queued || done_live) && !fall_through)    //every completed write waits for B unless already answered
            f_write_resp.enq(done_owner);
        if(b_fire && f_write_resp.notEmpty)                //a bypassed B has nothing to dequeue
            f_write_resp.deq;
    endrule


    Vector#(n, AXI4_Lite_Master_Rd_Fab#(aw, dw)) v_m_rd = newVector;
    Vector#(n, AXI4_Lite_Master_Wr_Fab#(aw, dw)) v_m_wr = newVector;

    for(Integer i = 0; i < valueOf(n); i = i + 1) begin
        v_m_rd[i] = interface AXI4_Lite_Master_Rd_Fab;
            method arvalid = ar_space && w_arvalid && ar_route[i] == 1;
            method araddr  = w_araddr;
            method arprot  = w_arprot;
            method rready  = r_head_valid && r_head[i] == 1 && w_rready;

            method parready = vw_arready[i]._write;
            method prvalid  = vw_rvalid[i]._write;
            method prdata   = vw_rdata[i]._write;
            method prresp   = vw_rresp[i]._write;
        endinterface;

        v_m_wr[i] = interface AXI4_Lite_Master_Wr_Fab;
            method awvalid = aw_space && w_awvalid && aw_route[i] == 1;
            method awaddr  = w_awaddr;
            method awprot  = w_awprot;
            method wvalid  = w_owner_valid && w_owner[i] == 1 && w_wvalid;
            method wdata   = w_wdata;
            method wstrb   = w_wstrb;
            method bready  = b_head_valid && b_head[i] == 1 && w_bready;

            method pawready = vw_awready[i]._write;
            method pwready  = vw_wready[i]._write;
            method pbvalid  = vw_bvalid[i]._write;
            method pbresp   = vw_bresp[i]._write;
        endinterface;
    end

    method sel_rd = w_sel_rd._write;
    method sel_wr = w_sel_wr._write;

    interface AXI4_Lite_Slave_Rd_Fab s_rd;
        method parvalid = w_arvalid._write;
        method paraddr  = w_araddr._write;
        method parprot  = w_arprot._write;
        method prready  = w_rready._write;

        method arready = ar_ready;
        method rvalid  = r_valid;
        method rdata   = onehot_select(r_head, readVReg(vw_rdata));
        method rresp   = select_response(r_head, vw_rresp);
    endinterface

    interface AXI4_Lite_Slave_Wr_Fab s_wr;
        method pawvalid = w_awvalid._write;
        method pawaddr  = w_awaddr._write;
        method pawprot  = w_awprot._write;
        method pwvalid  = w_wvalid._write;
        method pwdata   = w_wdata._write;
        method pwstrb   = w_wstrb._write;
        method pbready  = w_bready._write;

        method awready = aw_ready;
        method wready  = w_ready;
        method bvalid  = b_valid;
        method bresp   = select_response(b_head, vw_bresp);
    endinterface

    interface m_rd = v_m_rd;
    interface m_wr = v_m_wr;

endmodule

endpackage
