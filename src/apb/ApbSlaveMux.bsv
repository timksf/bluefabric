package ApbSlaveMux;

import Vector :: *;

import AddrMapDecoder :: *;
import ApbMaster :: *;
import ApbSlave :: *;

interface ApbSlaveMux_ifc#(
    numeric type slave_count,
    numeric type addr_w,
    numeric type data_w,
    numeric type user_w
);
    interface ApbSlaveFabric_ifc#(addr_w, data_w, user_w) slave;
    interface Vector#(
        slave_count,
        ApbMasterFabric_ifc#(addr_w, data_w, user_w)
    ) masters;
endinterface

module mkApbSlaveMux#(
    function Bit#(slave_count) select_target(Bit#(addr_w) address)
)(ApbSlaveMux_ifc#(slave_count, addr_w, data_w, user_w));

    Wire#(Bit#(addr_w))           w_paddr   <- mkBypassWire;
    Wire#(Bool)                   w_psel    <- mkBypassWire;
    Wire#(Bool)                   w_penable <- mkBypassWire;
    Wire#(Bool)                   w_pwrite  <- mkBypassWire;
    Wire#(Bit#(data_w))           w_pwdata  <- mkBypassWire;
    Wire#(Bit#(TDiv#(data_w, 8))) w_pstrb   <- mkBypassWire;
    Wire#(Bit#(3))                w_pprot   <- mkBypassWire;
    Wire#(Bit#(user_w))           w_pauser  <- mkBypassWire;
    Wire#(Bit#(user_w))           w_pwuser  <- mkBypassWire;

    Vector#(slave_count, Wire#(Bool))         vw_pready  <- replicateM(mkBypassWire);
    Vector#(slave_count, Wire#(Bit#(data_w))) vw_prdata  <- replicateM(mkBypassWire);
    Vector#(slave_count, Wire#(Bool))         vw_pslverr <- replicateM(mkBypassWire);
    Vector#(slave_count, Wire#(Bit#(user_w))) vw_pruser  <- replicateM(mkBypassWire);
    Vector#(slave_count, Wire#(Bit#(user_w))) vw_pbuser  <- replicateM(mkBypassWire);

    //zero or one-hot, targets get the unchanged address
    Bit#(slave_count) sel = select_target(w_paddr);

    Wire#(Bool)         w_pready  <- mkDWire(True);
    Wire#(Bit#(data_w)) w_prdata  <- mkDWire(0);
    Wire#(Bool)         w_pslverr <- mkDWire(True);
    Wire#(Bit#(user_w)) w_pruser  <- mkDWire(0);
    Wire#(Bit#(user_w)) w_pbuser  <- mkDWire(0);

    // Unmapped transfers complete at once with PSLVERR (wire defaults).
    rule r_select_response(sel != 0);
        w_pready  <= onehot_select(sel, readVReg(vw_pready));
        w_prdata  <= onehot_select(sel, readVReg(vw_prdata));
        w_pslverr <= onehot_select(sel, readVReg(vw_pslverr));
        w_pruser  <= onehot_select(sel, readVReg(vw_pruser));
        w_pbuser  <= onehot_select(sel, readVReg(vw_pbuser));
    endrule

    Vector#(slave_count, ApbMasterFabric_ifc#(addr_w, data_w, user_w))
        v_masters = newVector;

    for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
        v_masters[n] = interface ApbMasterFabric_ifc;
            method paddr   = w_paddr;
            method psel    = w_psel && sel[n] == 1;
            method penable = w_penable;
            method pwrite  = w_pwrite;
            method pwdata  = w_pwdata;
            method pstrb   = w_pstrb;
            method pprot   = w_pprot;
            method pauser  = w_pauser;
            method pwuser  = w_pwuser;

            method ppready  = vw_pready[n]._write;
            method pprdata  = vw_prdata[n]._write;
            method ppslverr = vw_pslverr[n]._write;
            method ppruser  = vw_pruser[n]._write;
            method ppbuser  = vw_pbuser[n]._write;
        endinterface;
    end

    interface ApbSlaveFabric_ifc slave;
        method ppaddr   = w_paddr._write;
        method ppsel    = w_psel._write;
        method ppenable = w_penable._write;
        method ppwrite  = w_pwrite._write;
        method ppwdata  = w_pwdata._write;
        method ppstrb   = w_pstrb._write;
        method ppprot   = w_pprot._write;
        method ppauser  = w_pauser._write;
        method ppwuser  = w_pwuser._write;

        method pready  = w_pready;
        method prdata  = w_prdata;
        method pslverr = w_pslverr;
        method pruser  = w_pruser;
        method pbuser  = w_pbuser;
    endinterface

    interface masters = v_masters;

endmodule

endpackage
