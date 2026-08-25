package ApbMasterMux;

import Clocks :: *;
import Vector :: *;

import GenericArbiter :: *;
import ApbMaster :: *;
import ApbSlave :: *;

interface ApbMasterMux_ifc#(
    numeric type master_count,
    numeric type addr_w,
    numeric type data_w,
    numeric type user_w
);
    interface Vector#(
        master_count,
        ApbSlaveFabric_ifc#(addr_w, data_w, user_w)
    ) slaves;
    interface ApbMasterFabric_ifc#(addr_w, data_w, user_w) master;
endinterface

module mkApbMasterMux(
    ApbMasterMux_ifc#(master_count, addr_w, data_w, user_w)
) provisos(
    Add#(1, masters_minus_one__, master_count)
);

    let reset_asserted <- isResetAsserted();

    GenericArbiter_ifc#(master_count) i_arbiter <- mkGenericArbiter;

    Vector#(master_count, Wire#(Bit#(addr_w)))           vw_paddr   <- replicateM(mkBypassWire);
    Vector#(master_count, Wire#(Bool))                   vw_psel    <- replicateM(mkBypassWire);
    Vector#(master_count, Wire#(Bool))                   vw_penable <- replicateM(mkBypassWire);
    Vector#(master_count, Wire#(Bool))                   vw_pwrite  <- replicateM(mkBypassWire);
    Vector#(master_count, Wire#(Bit#(data_w)))           vw_pwdata  <- replicateM(mkBypassWire);
    Vector#(master_count, Wire#(Bit#(TDiv#(data_w, 8)))) vw_pstrb   <- replicateM(mkBypassWire);
    Vector#(master_count, Wire#(Bit#(3)))                vw_pprot   <- replicateM(mkBypassWire);
    Vector#(master_count, Wire#(Bit#(user_w)))           vw_pauser  <- replicateM(mkBypassWire);
    Vector#(master_count, Wire#(Bit#(user_w)))           vw_pwuser  <- replicateM(mkBypassWire);

    Wire#(Bool)         w_pready  <- mkBypassWire;
    Wire#(Bit#(data_w)) w_prdata  <- mkBypassWire;
    Wire#(Bool)         w_pslverr <- mkBypassWire;
    Wire#(Bit#(user_w)) w_pruser  <- mkBypassWire;
    Wire#(Bit#(user_w)) w_pbuser  <- mkBypassWire;

    Wire#(Bit#(addr_w))           w_paddr   <- mkDWire(0);
    Wire#(Bool)                   w_psel    <- mkDWire(False);
    Wire#(Bool)                   w_penable <- mkDWire(False);
    Wire#(Bool)                   w_pwrite  <- mkDWire(False);
    Wire#(Bit#(data_w))           w_pwdata  <- mkDWire(0);
    Wire#(Bit#(TDiv#(data_w, 8))) w_pstrb   <- mkDWire(0);
    Wire#(Bit#(3))                w_pprot   <- mkDWire(0);
    Wire#(Bit#(user_w))           w_pauser  <- mkDWire(0);
    Wire#(Bit#(user_w))           w_pwuser  <- mkDWire(0);

    function Bit#(TLog#(master_count)) one_hot_index(
        Bit#(master_count) one_hot
    );
        Bit#(TLog#(master_count)) result = 0;
        for(Integer n = 0; n < valueOf(master_count); n = n + 1) begin
            if(one_hot[n] == 1)
                result = fromInteger(n);
        end
        return result;
    endfunction

    Bit#(master_count) grant = i_arbiter.grant;
    Bit#(TLog#(master_count)) granted_master =
        one_hot_index(grant);
    Bool transfer_complete = grant != 0 &&
        vw_psel[granted_master] &&
        vw_penable[granted_master] &&
        w_pready;

    rule r_arbitrate;
        Bit#(master_count) request = 0;
        for(Integer n = 0; n < valueOf(master_count); n = n + 1)
            request[n] = pack(vw_psel[n]);

        i_arbiter.prequest(reset_asserted ? 0 : request);
    endrule

    rule r_advance_arbiter;
        i_arbiter.padvance(!reset_asserted && transfer_complete);
    endrule

    rule r_select_master;
        if(!reset_asserted && grant != 0) begin
            w_paddr   <= vw_paddr[granted_master];
            w_psel    <= vw_psel[granted_master];
            w_penable <= vw_penable[granted_master];
            w_pwrite  <= vw_pwrite[granted_master];
            w_pwdata  <= vw_pwdata[granted_master];
            w_pstrb   <= vw_pstrb[granted_master];
            w_pprot   <= vw_pprot[granted_master];
            w_pauser  <= vw_pauser[granted_master];
            w_pwuser  <= vw_pwuser[granted_master];
        end
    endrule

    Vector#(
        master_count,
        ApbSlaveFabric_ifc#(addr_w, data_w, user_w)
    ) v_slaves = newVector;

    for(Integer n = 0; n < valueOf(master_count); n = n + 1) begin
        v_slaves[n] = interface ApbSlaveFabric_ifc;
            method ppaddr   = vw_paddr[n]._write;
            method ppsel    = vw_psel[n]._write;
            method ppenable = vw_penable[n]._write;
            method ppwrite  = vw_pwrite[n]._write;
            method ppwdata  = vw_pwdata[n]._write;
            method ppstrb   = vw_pstrb[n]._write;
            method ppprot   = vw_pprot[n]._write;
            method ppauser  = vw_pauser[n]._write;
            method ppwuser  = vw_pwuser[n]._write;

            method pready = !reset_asserted && grant[n] == 1 &&
                w_pready;
            method prdata = grant[n] == 1 ? w_prdata : 0;
            method pslverr = grant[n] == 1 ?
                w_pslverr : False;
            method pruser = grant[n] == 1 ? w_pruser : 0;
            method pbuser = grant[n] == 1 ? w_pbuser : 0;
        endinterface;
    end

    interface ApbMasterFabric_ifc master;
        method paddr   = w_paddr;
        method psel    = w_psel;
        method penable = w_penable;
        method pwrite  = w_pwrite;
        method pwdata  = w_pwdata;
        method pstrb   = w_pstrb;
        method pprot   = w_pprot;
        method pauser  = w_pauser;
        method pwuser  = w_pwuser;

        method ppready  = w_pready._write;
        method pprdata  = w_prdata._write;
        method ppslverr = w_pslverr._write;
        method ppruser  = w_pruser._write;
        method ppbuser  = w_pbuser._write;
    endinterface

    interface slaves = v_slaves;

endmodule

endpackage
