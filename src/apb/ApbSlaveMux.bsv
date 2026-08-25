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
    function AddrMapHit_t#(addr_w) decode_address(
        Bit#(addr_w) address,
        Bit#(addr_w) bytes
    )
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

    AddrMapHit_t#(addr_w) route =
        decode_address(w_paddr, fromInteger(valueOf(TDiv#(data_w, 8))));
    Bool route_valid = route.hit &&
        route.target_index < fromInteger(valueOf(slave_count));

    Wire#(Bool)         w_pready  <- mkDWire(True);
    Wire#(Bit#(data_w)) w_prdata  <- mkDWire(0);
    Wire#(Bool)         w_pslverr <- mkDWire(True);
    Wire#(Bit#(user_w)) w_pruser  <- mkDWire(0);
    Wire#(Bit#(user_w)) w_pbuser  <- mkDWire(0);

    rule r_select_ready;
        for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
            if(route_valid && route.target_index == fromInteger(n))
                w_pready <= vw_pready[n];
        end
    endrule

    rule r_select_read_data;
        for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
            if(route_valid && route.target_index == fromInteger(n))
                w_prdata <= vw_prdata[n];
        end
    endrule

    rule r_select_response;
        for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
            if(route_valid && route.target_index == fromInteger(n))
                w_pslverr <= vw_pslverr[n];
        end
    endrule

    rule r_select_read_user;
        for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
            if(route_valid && route.target_index == fromInteger(n))
                w_pruser <= vw_pruser[n];
        end
    endrule

    rule r_select_response_user;
        for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
            if(route_valid && route.target_index == fromInteger(n))
                w_pbuser <= vw_pbuser[n];
        end
    endrule

    Vector#(slave_count, ApbMasterFabric_ifc#(addr_w, data_w, user_w))
        v_masters = newVector;

    for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
        v_masters[n] = interface ApbMasterFabric_ifc;
            method paddr   = route.offset;
            method psel    = w_psel && route_valid &&
                route.target_index == fromInteger(n);
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
