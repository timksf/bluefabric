package AhbSlaveMux;

import Vector :: *;

import AddrMapDecoder :: *;
import Ahb :: *;
import AhbMaster :: *;
import AhbSlave :: *;

interface AhbSlaveMux_ifc#(
    numeric type slave_count,
    numeric type addr_w,
    numeric type data_w
);
    interface AhbSlaveFabric_ifc#(addr_w, data_w) slave;
    interface Vector#(
        slave_count,
        AhbMasterFabricShared_ifc#(addr_w, data_w)
    ) masters;
endinterface

module mkAhbSlaveMux#(
    function Bit#(slave_count) select_target(Bit#(addr_w) address)
)(AhbSlaveMux_ifc#(slave_count, addr_w, data_w));

    Wire#(Bit#(addr_w)) w_haddr     <- mkBypassWire;
    Wire#(Bool)         w_hsel      <- mkBypassWire;
    Wire#(AhbTransfer_t) w_htrans   <- mkBypassWire;
    Wire#(Bool)         w_hwrite    <- mkBypassWire;
    Wire#(AhbSize_t)    w_hsize     <- mkBypassWire;
    Wire#(AhbBurst_t)   w_hburst    <- mkBypassWire;
    Wire#(AhbProtection_t) w_hprot  <- mkBypassWire;
    Wire#(Bool)         w_hmastlock <- mkBypassWire;
    Wire#(Bit#(data_w)) w_hwdata    <- mkBypassWire;
    Wire#(Bool)         w_hreadyin  <- mkBypassWire;

    Vector#(slave_count, Wire#(Bool))         vw_hready <- replicateM(mkBypassWire);
    Vector#(slave_count, Wire#(Bit#(data_w))) vw_hrdata <- replicateM(mkBypassWire);
    Vector#(slave_count, Wire#(Bool))         vw_hresp  <- replicateM(mkBypassWire);

    //zero or one-hot, targets get the unchanged address
    Bit#(slave_count) sel = select_target(w_haddr);
    Bool transfer_valid = w_hsel &&
        (w_htrans == AHB_NONSEQ || w_htrans == AHB_SEQ);
    Bool route_valid = sel != 0 &&
        pack(w_hsize) <= fromInteger(valueOf(TLog#(TDiv#(data_w, 8))));

    Reg#(Bool)         rg_target_valid <- mkReg(False);
    Reg#(Bit#(slave_count)) rg_target  <- mkReg(0);
    Reg#(Bool)         rg_miss         <- mkReg(False);
    Reg#(Bool)         rg_miss_first   <- mkReg(False);

    Wire#(Bool)         w_hreadyout <- mkDWire(True);
    Wire#(Bit#(data_w)) w_hrdata    <- mkDWire(0);
    Wire#(Bool)         w_hresp     <- mkDWire(False);

    rule r_select_ready(rg_miss || rg_target_valid);
        w_hreadyout <= rg_miss ? rg_miss_first : onehot_select(rg_target, readVReg(vw_hready));
    endrule

    rule r_select_read_data(rg_target_valid);
        w_hrdata <= onehot_select(rg_target, readVReg(vw_hrdata));
    endrule

    rule r_select_response(rg_miss || rg_target_valid);
        w_hresp <= rg_miss || onehot_select(rg_target, readVReg(vw_hresp));
    endrule

    rule r_update_data_phase;
        if(w_hreadyin) begin
            rg_target_valid <= transfer_valid && route_valid;
            rg_target       <= sel;
            rg_miss         <= transfer_valid && !route_valid;
            rg_miss_first   <= False;
        end else if(rg_miss && !rg_miss_first) begin
            rg_miss_first <= True;
        end
    endrule

    Vector#(slave_count, AhbMasterFabricShared_ifc#(addr_w, data_w))
        v_masters = newVector;

    for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
        v_masters[n] = interface AhbMasterFabricShared_ifc;
            method haddr     = w_haddr;
            method hsel      = transfer_valid && route_valid && sel[n] == 1;
            method htrans    = w_htrans;
            method hwrite    = w_hwrite;
            method hsize     = w_hsize;
            method hburst    = w_hburst;
            method hprot     = w_hprot;
            method hmastlock = w_hmastlock;
            method hwdata    = w_hwdata;
            method hreadyin  = w_hreadyin;

            method pphready = vw_hready[n]._write;
            method pphrdata = vw_hrdata[n]._write;
            method pphresp  = vw_hresp[n]._write;
        endinterface;
    end

    interface AhbSlaveFabric_ifc slave;
        method pphaddr     = w_haddr._write;
        method pphsel      = w_hsel._write;
        method pphtrans    = w_htrans._write;
        method pphwrite    = w_hwrite._write;
        method pphsize     = w_hsize._write;
        method pphburst    = w_hburst._write;
        method pphprot     = w_hprot._write;
        method pphmastlock = w_hmastlock._write;
        method pphwdata    = w_hwdata._write;
        method pphreadyin  = w_hreadyin._write;

        method hreadyout = w_hreadyout;
        method hrdata    = w_hrdata;
        method hresp     = w_hresp;
    endinterface

    interface masters = v_masters;

endmodule

endpackage
