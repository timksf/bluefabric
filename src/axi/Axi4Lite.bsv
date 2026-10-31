package Axi4Lite;

import Connectable :: *;

import BlueAXI :: *;

//complete AXI4-Lite port with both directions, e.g. the target type of an AXI4-Lite address map
interface Axi4LiteSlaveFab_ifc#(numeric type aw, numeric type dw);
    interface AXI4_Lite_Slave_Rd_Fab#(aw, dw) rd;
    interface AXI4_Lite_Slave_Wr_Fab#(aw, dw) wr;
endinterface

interface Axi4LiteMasterFab_ifc#(numeric type aw, numeric type dw);
    interface AXI4_Lite_Master_Rd_Fab#(aw, dw) rd;
    interface AXI4_Lite_Master_Wr_Fab#(aw, dw) wr;
endinterface

function Axi4LiteSlaveFab_ifc#(aw, dw) axi4_lite_slave_fab(
        AXI4_Lite_Slave_Rd_Fab#(aw, dw) rd_fab,
        AXI4_Lite_Slave_Wr_Fab#(aw, dw) wr_fab
    );
    return interface Axi4LiteSlaveFab_ifc;
        interface rd = rd_fab;
        interface wr = wr_fab;
    endinterface;
endfunction

function Axi4LiteMasterFab_ifc#(aw, dw) axi4_lite_master_fab(
        AXI4_Lite_Master_Rd_Fab#(aw, dw) rd_fab,
        AXI4_Lite_Master_Wr_Fab#(aw, dw) wr_fab
    );
    return interface Axi4LiteMasterFab_ifc;
        interface rd = rd_fab;
        interface wr = wr_fab;
    endinterface;
endfunction

//passes everything through but cuts AR/AW addresses down to the offset inside an aligned power of two region
function Axi4LiteSlaveFab_ifc#(aw, dw) axi4_lite_local(Integer size, Axi4LiteSlaveFab_ifc#(aw, dw) s);
    Bit#(aw) mask = fromInteger(size - 1);
    return interface Axi4LiteSlaveFab_ifc;
        interface AXI4_Lite_Slave_Rd_Fab rd;
            method arready                          = s.rd.arready;
            method Action parvalid(Bool v)          = s.rd.parvalid(v);
            method Action paraddr(Bit#(aw) a)       = s.rd.paraddr(a & mask);
            method Action parprot(AXI4_Lite_Prot p) = s.rd.parprot(p);
            method rvalid                           = s.rd.rvalid;
            method Action prready(Bool r)           = s.rd.prready(r);
            method rdata                            = s.rd.rdata;
            method rresp                            = s.rd.rresp;
        endinterface
        interface AXI4_Lite_Slave_Wr_Fab wr;
            method awready                             = s.wr.awready;
            method Action pawvalid(Bool v)             = s.wr.pawvalid(v);
            method Action pawaddr(Bit#(aw) a)          = s.wr.pawaddr(a & mask);
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

instance Connectable#(Axi4LiteMasterFab_ifc#(aw, dw), Axi4LiteSlaveFab_ifc#(aw, dw));
    module mkConnection#(Axi4LiteMasterFab_ifc#(aw, dw) master, Axi4LiteSlaveFab_ifc#(aw, dw) slave)(Empty);
        mkConnection(master.rd, slave.rd);
        mkConnection(master.wr, slave.wr);
    endmodule
endinstance

instance Connectable#(Axi4LiteSlaveFab_ifc#(aw, dw), Axi4LiteMasterFab_ifc#(aw, dw));
    module mkConnection#(Axi4LiteSlaveFab_ifc#(aw, dw) slave, Axi4LiteMasterFab_ifc#(aw, dw) master)(Empty);
        mkConnection(master, slave);
    endmodule
endinstance

endpackage
