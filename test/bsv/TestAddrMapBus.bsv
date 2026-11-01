package TestAddrMapBus;

import BuildVector :: *;
import Connectable :: *;
import DefaultValue :: *;
import GetPut :: *;
import Vector :: *;

import AXI4_Lite_Master :: *;
import AXI4_Lite_Slave :: *;
import AXI4_Lite_Types :: *;
import Ahb :: *;
import AhbMaster :: *;
import AhbSlave :: *;
import Apb :: *;
import ApbSlave :: *;
import Axi4Lite :: *;
import Axi4LiteRegSlice :: *;
import Axi4LiteAddrMap :: *;
import AhbAddrMap :: *;
import ApbAddrMap :: *;
import BlueAddrMap :: *;

typedef Axi4LiteSlaveFab_ifc#(16, 32)  AxiPort_t;
typedef AhbSlaveFabric_ifc#(16, 32)    AhbPort_t;
typedef ApbSlaveFabric_ifc#(16, 32, 1) ApbPort_t;

/* AXI4-Lite targets */

interface TestCounts_ifc;
    method UInt#(8) reads;
    method UInt#(8) writes;
endinterface

interface TestAxiTarget_ifc;
    interface AxiPort_t port;
    interface TestCounts_ifc counts;
endinterface

//answers with its id and the local address it saw, stalls in a per target pattern
module mkTestAxiTarget#(Bit#(8) id, Bit#(16) mask, AXI4_Lite_Response resp)(TestAxiTarget_ifc);
    AXI4_Lite_Slave_Rd#(16, 32) i_rd <- mkAXI4_Lite_Slave_Rd(2);
    AXI4_Lite_Slave_Wr#(16, 32) i_wr <- mkAXI4_Lite_Slave_Wr(2);

    Reg#(UInt#(8)) rg_cycle  <- mkReg(0);
    Reg#(UInt#(8)) rg_reads  <- mkReg(0);
    Reg#(UInt#(8)) rg_writes <- mkReg(0);

    UInt#(8) phase = rg_cycle + unpack(id);

    rule r_cycle;
        rg_cycle <= rg_cycle + 1;
    endrule

    rule r_read(phase % 3 != 0);
        let rq <- i_rd.request.get;
        if((rq.addr & ~mask) != 0)
            $fatal(1, "target %0d got the non-local read address %h", id, rq.addr);
        i_rd.response.put(AXI4_Lite_Read_Rs_Pkg { data: {id, 8'h00, rq.addr}, resp: resp });
        rg_reads <= rg_reads + 1;
    endrule

    rule r_write(phase % 4 != 1);
        let rq <- i_wr.request.get;
        if((rq.addr & ~mask) != 0 || (rq.data[15:0] & mask) != rq.addr || rq.data[31:16] != 16'ha5a5 || rq.strb != '1)
            $fatal(1, "target %0d got a wrong write: address %h data %h", id, rq.addr, rq.data);
        i_wr.response.put(AXI4_Lite_Write_Rs_Pkg { resp: resp });
        rg_writes <= rg_writes + 1;
    endrule

    interface port = axi4_lite_slave_fab(i_rd.fab, i_wr.fab);
    interface TestCounts_ifc counts;
        method reads  = rg_reads;
        method writes = rg_writes;
    endinterface
endmodule

/* AXI4-Lite maps, devices live inside the maps */

function AxiPort_t axi_port(TestAxiTarget_ifc t) = t.port;

//regions are local to the parent's periph region
module [AddrMapCtx_t#(16, AxiPort_t)] axi_sub_map(Vector#(2, TestCounts_ifc));
    addr_map_def("sub");
    TestAxiTarget_ifc timer <- addr_map_device('h0000, 'h0100, "timer", mkTestAxiTarget(2, 'h00ff, OKAY),   axi_port);
    TestAxiTarget_ifc gpio  <- addr_map_device('h1000, 'h1000, "gpio",  mkTestAxiTarget(3, 'h0fff, SLVERR), axi_port);

    return vec(timer.counts, gpio.counts);
endmodule

module [AddrMapCtx_t#(16, AxiPort_t)] axi_top_map(Vector#(5, TestCounts_ifc));
    Axi4LiteBusCfg_t sub_cfg = defaultValue;
    sub_cfg.local_addr = True;

    addr_map_def("top");
    TestAxiTarget_ifc                                 uart   <- addr_map_device_cut('h1000, 'h0100, "uart", axi4_lite_slice_all, mkTestAxiTarget(0, 'h00ff, OKAY), axi_port);
    TestAxiTarget_ifc                                 ram    <- addr_map_device('h2000, 'h1000, "ram", mkTestAxiTarget(1, 'h0fff, SLVERR), axi_port);
    AddrMapSubBus_ifc#(2, Vector#(2, TestCounts_ifc)) periph <- addr_map_bus('h4000, 'h4000, "periph", sub_cfg, axi_sub_map);
    TestAxiTarget_ifc                                 err    <- addr_map_device_default("err", mkTestAxiTarget(4, 'hffff, OKAY), axi_port);

    return vec(uart.counts, ram.counts, periph.internal[0], periph.internal[1], err.counts);
endmodule

//what a global address should reach: target id and local address, or a DECERR from the sub bus
typedef struct {
    Bool               hit;
    Bit#(8)            id;
    Bit#(16)           local_addr;
    AXI4_Lite_Response resp;
} Expect_t deriving(Bits, Eq);

function Expect_t expect_axi(Bit#(16) a);
    if(a >= 'h1000 && a < 'h1100)      return Expect_t { hit: True,  id: 0, local_addr: a & 'h00ff, resp: OKAY };
    else if(a >= 'h2000 && a < 'h3000) return Expect_t { hit: True,  id: 1, local_addr: a & 'h0fff, resp: SLVERR };
    else if(a >= 'h4000 && a < 'h4100) return Expect_t { hit: True,  id: 2, local_addr: a & 'h00ff, resp: OKAY };
    else if(a >= 'h5000 && a < 'h6000) return Expect_t { hit: True,  id: 3, local_addr: a & 'h0fff, resp: SLVERR };
    else if(a >= 'h4000 && a < 'h8000) return Expect_t { hit: False, id: 0, local_addr: 0,          resp: DECERR };
    else                               return Expect_t { hit: True,  id: 4, local_addr: a,          resp: OKAY };
endfunction

typedef 48 AxiTransfers;

function Bit#(16) axi_test_addr(UInt#(8) k);
    Vector#(12, Bit#(16)) bases = vec('h1000, 'h2000, 'h2f80, 'h4000, 'h5000, 'h5fc0, 'h4100, 'h6000, 'h0000, 'h3000, 'h8000, 'hff00);
    Bit#(16) offset = zeroExtend(pack(k)) << 2;
    return bases[k % 12] + (offset & 'h3c);
endfunction

interface TestDone_ifc;
    method Bool done;
endinterface

//issues reads and writes over the whole map and checks every response, in order
module [Module] mkAxiBusTest#(String name, Axi4LiteBusCfg_t cfg)(TestDone_ifc);
    AXI4_Lite_Master_Rd#(16, 32) i_rd <- mkAXI4_Lite_Master_Rd(4);
    AXI4_Lite_Master_Wr#(16, 32) i_wr <- mkAXI4_Lite_Master_Wr(4);

    AddrMapBus_ifc#(4, AxiPort_t, Vector#(5, TestCounts_ifc)) i_bus <- create_addr_map_bus_cfg(cfg, axi_top_map);
    mkConnection(axi4_lite_master_fab(i_rd.fab, i_wr.fab), i_bus.up);

    Integer n = valueOf(AxiTransfers);
    Reg#(UInt#(8)) rg_rd_sent <- mkReg(0);
    Reg#(UInt#(8)) rg_wr_sent <- mkReg(0);
    Reg#(UInt#(8)) rg_rd_recv <- mkReg(0);
    Reg#(UInt#(8)) rg_wr_recv <- mkReg(0);
    Vector#(5, Reg#(UInt#(8))) rg_expect_reads  <- replicateM(mkReg(0));
    Vector#(5, Reg#(UInt#(8))) rg_expect_writes <- replicateM(mkReg(0));
    Reg#(Bool) rg_done <- mkReg(False);

    rule r_send_read(rg_rd_sent < fromInteger(n));
        i_rd.request.put(AXI4_Lite_Read_Rq_Pkg { addr: axi_test_addr(rg_rd_sent), prot: unpack(0) });
        rg_rd_sent <= rg_rd_sent + 1;
    endrule

    rule r_send_write(rg_wr_sent < fromInteger(n));
        let a = axi_test_addr(rg_wr_sent + 5);    //different order than the reads
        i_wr.request.put(AXI4_Lite_Write_Rq_Pkg { addr: a, data: {16'ha5a5, a}, strb: '1, prot: unpack(0) });
        rg_wr_sent <= rg_wr_sent + 1;
    endrule

    rule r_check_read(rg_rd_recv < fromInteger(n));
        let rs <- i_rd.response.get;
        let e = expect_axi(axi_test_addr(rg_rd_recv));
        Bit#(32) data = e.hit ? {e.id, 8'h00, e.local_addr} : 0;
        if(rs.resp != e.resp || rs.data != data)
            $fatal(1, "%s: read %0d from %h returned %h/%0d instead of %h/%0d", name, rg_rd_recv, axi_test_addr(rg_rd_recv), rs.data, pack(rs.resp), data, pack(e.resp));
        if(e.hit) rg_expect_reads[e.id] <= rg_expect_reads[e.id] + 1;
        rg_rd_recv <= rg_rd_recv + 1;
    endrule

    rule r_check_write(rg_wr_recv < fromInteger(n));
        let rs <- i_wr.response.get;
        let e = expect_axi(axi_test_addr(rg_wr_recv + 5));
        if(rs.resp != e.resp)
            $fatal(1, "%s: write %0d to %h returned %0d instead of %0d", name, rg_wr_recv, axi_test_addr(rg_wr_recv + 5), pack(rs.resp), pack(e.resp));
        if(e.hit) rg_expect_writes[e.id] <= rg_expect_writes[e.id] + 1;
        rg_wr_recv <= rg_wr_recv + 1;
    endrule

    rule r_finish(!rg_done && rg_rd_recv == fromInteger(n) && rg_wr_recv == fromInteger(n));
        for(Integer i = 0; i < 5; i = i + 1)
            if(i_bus.internal[i].reads != rg_expect_reads[i] || i_bus.internal[i].writes != rg_expect_writes[i])
                $fatal(1, "%s: target %0d saw %0d reads, %0d writes instead of %0d, %0d", name, i, i_bus.internal[i].reads, i_bus.internal[i].writes, rg_expect_reads[i], rg_expect_writes[i]);
        $display("%s passed", name);
        rg_done <= True;
    endrule

    method done = rg_done;
endmodule

/* AHB with an APB bus behind a bridge */

interface TestAhbTarget_ifc;
    interface AhbPort_t port;
endinterface

module mkTestAhbTarget#(Bit#(8) id)(TestAhbTarget_ifc);
    AhbSlave_ifc#(16, 32) i_slave <- mkAhbSlave(True);

    rule r_respond;
        let rq <- i_slave.request.get;
        i_slave.response.put(AhbResponse_t { read_data: {id, 8'h00, rq.address}, slave_error: False });
    endrule

    interface port = i_slave.fabric;
endmodule

interface TestApbTarget_ifc;
    interface ApbPort_t port;
endinterface

module mkTestApbTarget#(Bit#(8) id)(TestApbTarget_ifc);
    ApbSlave_ifc#(16, 32, 1) i_slave <- mkApbSlave(True);

    rule r_respond;
        let rq <- i_slave.request.get;
        i_slave.response.put(ApbResponse_t { read_data: {id, 8'h00, rq.address}, slave_error: False, read_user: 0, response_user: 0 });
    endrule

    interface port = i_slave.fabric;
endmodule

function ApbPort_t apb_port(TestApbTarget_ifc t) = t.port;
function AhbPort_t ahb_port(TestAhbTarget_ifc t) = t.port;

module [AddrMapCtx_t#(16, ApbPort_t)] apb_map(Empty);
    addr_map_def("apb");
    TestApbTarget_ifc apb0 <- addr_map_device('h8000, 'h1000, "apb0", mkTestApbTarget(1), apb_port);
    TestApbTarget_ifc apb1 <- addr_map_device('h9000, 'h1000, "apb1", mkTestApbTarget(2), apb_port);
endmodule

module [AddrMapCtx_t#(16, AhbPort_t)] ahb_map(Empty);
    addr_map_def("ahb");
    TestAhbTarget_ifc            sram <- addr_map_device('h0000, 'h1000, "sram", mkTestAhbTarget(0), ahb_port);
    AddrMapSubBus_ifc#(2, Empty) apb  <- addr_map_bridge('h8000, 'h8000, "apb", ApbBusCfg_t'(defaultValue), apb_map);
endmodule

module [Module] mkAhbBusTest(TestDone_ifc);
    AhbMaster_ifc#(16, 32) i_master <- mkAhbMaster(2);
    AddrMapBus_ifc#(2, AhbPort_t, Empty) i_bus <- create_addr_map_bus(ahb_map);
    mkConnection(i_master.fabric, i_bus.up);

    //address, write, expected read data, expected error
    Vector#(6, Tuple4#(Bit#(16), Bool, Bit#(32), Bool)) transfers = vec(
        tuple4('h0010, False, 'h0000_0010, False),    //AHB target
        tuple4('h8004, False, 'h0100_8004, False),    //APB behind the bridge
        tuple4('h9008, False, 'h0200_9008, False),
        tuple4('h8010, True,  0,           False),
        tuple4('h4000, False, 0,           True),     //miss on the AHB bus
        tuple4('ha000, False, 0,           True)      //miss on the APB bus, PSLVERR through the bridge
    );

    Reg#(UInt#(4)) rg_sent <- mkReg(0);
    Reg#(UInt#(4)) rg_recv <- mkReg(0);
    Reg#(Bool)     rg_done <- mkReg(False);

    rule r_send(rg_sent < 6);
        match {.a, .w, .*, .*} = transfers[rg_sent];
        let protection = ahb_protection(AHB_DATA_ACCESS, AHB_PRIVILEGED_ACCESS, AHB_NON_BUFFERABLE, AHB_NON_CACHEABLE);
        i_master.request.put(ahb_single_request(AhbRequest_t { address: a, write: w, write_data: 'h1234, size: AHB_WORD, protection: protection, lock: False }));
        rg_sent <= rg_sent + 1;
    endrule

    rule r_check(rg_recv < 6);
        let rs <- i_master.response.get;
        match {.a, .w, .data, .error} = transfers[rg_recv];
        if(rs.slave_error != error || (!w && !error && rs.read_data != data))
            $fatal(1, "AHB transfer %0d to %h returned %h/%b instead of %h/%b", rg_recv, a, rs.read_data, rs.slave_error, data, error);
        rg_recv <= rg_recv + 1;
    endrule

    rule r_finish(!rg_done && rg_recv == 6);
        $display("AHB bus with bridged APB bus passed");
        rg_done <= True;
    endrule

    method done = rg_done;
endmodule

/* top */

(* synthesize *)
module mkTestAddrMapBus(Empty);
    //registered decode, cuts upstream, at every target and an extra one at uart
    Axi4LiteBusCfg_t cfg_cut = defaultValue;
    cfg_cut.upstream_cut      = axi4_lite_slice_request;
    cfg_cut.target_cut        = axi4_lite_slice_request;
    cfg_cut.registered_decode = True;
    cfg_cut.local_addr        = True;

    //registered decode with every channel cut and same cycle responses
    Axi4LiteBusCfg_t cfg_all = defaultValue;
    cfg_all.upstream_cut          = axi4_lite_slice_all;
    cfg_all.registered_decode     = True;
    cfg_all.local_addr            = True;
    cfg_all.router.fall_through   = True;
    cfg_all.router.max_outstanding = 3;

    //no cuts, combinational decode, same cycle responses
    Axi4LiteBusCfg_t cfg_plain = defaultValue;
    cfg_plain.local_addr          = True;
    cfg_plain.router.fall_through = True;

    TestDone_ifc t_cut   <- mkAxiBusTest("AXI4-Lite registered decode with cuts", cfg_cut);
    TestDone_ifc t_all   <- mkAxiBusTest("AXI4-Lite registered decode, fall through", cfg_all);
    TestDone_ifc t_plain <- mkAxiBusTest("AXI4-Lite combinational decode, fall through", cfg_plain);
    TestDone_ifc t_ahb   <- mkAhbBusTest;

    Reg#(UInt#(16)) rg_cycles <- mkReg(0);

    rule r_watchdog;
        rg_cycles <= rg_cycles + 1;
        if(rg_cycles == 5000) $fatal(1, "address map bus test timed out");
    endrule

    rule r_finish(t_cut.done && t_all.done && t_plain.done && t_ahb.done);
        $display("address map bus tests passed");
        $finish(0);
    endrule
endmodule

endpackage
