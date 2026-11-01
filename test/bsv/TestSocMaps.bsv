package TestSocMaps;

import Connectable :: *;
import GetPut :: *;
import Vector :: *;
import BuildVector :: *;

import AhbMaster :: *;
import AhbSlave :: *;
import AhbSlaveMux :: *;
import ApbMaster :: *;
import ApbSlave :: *;
import ApbSlaveMux :: *;
import Axi4Lite :: *;
import Axi4LiteAddrMap :: *;
import Axi4LiteRegSlice :: *;
import AXI4_Lite_Master :: *;
import AXI4_Lite_Slave :: *;
import AXI4_Lite_Types :: *;
import AddrMapDecoder :: *;
import AhbAddrMap :: *;
import ApbAddrMap :: *;
import BlueAddrMap :: *;
import BlueInterruptMap :: *;

module [AddrMapCtx_t#(16, Bit#(8))] test_addr_map();
    addr_map_def("TestSoC");
    addr_map_target(4096, 256, "uart", 8'd0);
    addr_map_target(8192, 4096, "peripherals", 8'd1);
endmodule

//default target: takes every address outside uart
module [AddrMapCtx_t#(16, Bit#(8))] test_default_map();
    addr_map_def("TestDefault");
    addr_map_target(4096, 256, "uart", 8'd0);
    addr_map_default("rest", 8'd1);
endmodule

// One declaration for any protocol: the endpoint type selects the fabric.
module [AddrMapCtx_t#(16, endpoint)] test_bus_addr_map#(Vector#(2, endpoint) targets)(Empty);
    addr_map_def("TestSoC bus");
    addr_map_target('h1000, 'h100,  "uart",        targets[0]);
    addr_map_target('h2000, 'h1000, "peripherals", targets[1]);
endmodule

module [IRQMapCtx_t#(8)] test_irq_map();
    Vector#(2, Bool) timer_irqs = unpack(2'b01);
    Vector#(3, Bool) peripheral_irqs = unpack(3'b101);

    irq_map_def("TestIRQs");
    irq_map_source(1, "timer", timer_irqs);
    irq_map_source(4, "peripherals", peripheral_irqs);
endmodule

module mkTestSocMaps(Empty);

    AddrMap_t#(2) invalid_addr_map = vec(addr_region('h1000, 'h100), addr_region('h1080, 'h80));
    let invalid_addr_errors = validate_addr_map(invalid_addr_map, 16);

    IRQMapEntry_t#(8) invalid_irq_def    = tagged IRQMapDef IRQMapDef_t { name: "InvalidIRQMap" };
    IRQMapEntry_t#(8) invalid_irq_source = tagged IRQMapSourceDef IRQMapSourceDef_t { type_anchor: 0, base: 7, width: 2, name: "out_of_range", lines: 0 };
    List#(IRQMapEntry_t#(8)) invalid_irq_entries = Cons(invalid_irq_def, Cons(invalid_irq_source, Nil));
    let invalid_irq_validation = validate_irq_map(invalid_irq_entries);

    if(invalid_addr_errors == "")
        errorM("address map validation accepted overlapping targets");
    if(validate_addr_map(vec(addr_region_default, addr_region_default), 16) == "")
        errorM("address map validation accepted two default regions");
    if(invalid_irq_validation.valid)
        errorM("interrupt map validation accepted an out-of-range source");

    AddrMapCollected_t#(2, Bit#(8), Empty) addr_collected <- collect_addr_map(test_addr_map);
    let addr_doc      = doc_addr_map(addr_collected);
    let addr_markdown = doc_addr_map_markdown(addr_collected);
    let irq_doc <- doc_irq_map(test_irq_map);

    String expected_addr_doc = "TestSoC\n"
        + "0x1000 - 0x10ff  uart\n"
        + "0x2000 - 0x2fff  peripherals";
    String expected_addr_markdown = "| Base | End | Name |\n"
        + "| --- | --- | --- |\n"
        + "| 0x1000 | 0x10ff | uart |\n"
        + "| 0x2000 | 0x2fff | peripherals |";
    String expected_irq_doc = "TestIRQs\n"
        + "1 - 2  timer\n"
        + "4 - 6  peripherals";

    if(addr_doc.text != expected_addr_doc)
        errorM("plain-text address map generation did not match");
    if(addr_markdown.text != expected_addr_markdown)
        errorM("Markdown address map generation did not match");
    if(irq_doc.text != expected_irq_doc)
        errorM("interrupt map documentation generation did not match");

    AddrMapCollected_t#(2, Bit#(8), Empty) default_collected <- collect_addr_map(test_default_map);
    let default_doc = doc_addr_map(default_collected);
    if(default_doc.text != "TestDefault\n0x1000 - 0x10ff  uart\ndefault                  rest")
        errorM("address map documentation of a default target did not match");
    AddrMap_ifc#(2, 16, Empty) i_default_map <- create_addr_map(test_default_map);

    AddrMap_ifc#(2, 16, Empty) i_addr_map <- create_addr_map(test_addr_map);
    AddrMapWithTargets_ifc#(2, 16, Bit#(8), Empty) i_addr_map_with_targets <- create_addr_map_with_targets(test_addr_map);
    let i_irq_map  <- create_irq_map(test_irq_map);

    function Bit#(2) select_target(Bit#(16) address) = i_addr_map.decoder.select(address);

    ApbSlaveMux_ifc#(2, 16, 32, 1) i_apb_mux <- mkApbSlaveMux(select_target);
    ApbMaster_ifc#(16, 32, 1) i_apb_source <- mkApbMaster(2);
    ApbSlave_ifc#(16, 32, 1)  i_apb_uart   <- mkApbSlave(True);
    ApbSlave_ifc#(16, 32, 1)  i_apb_periph <- mkApbSlave(True);

    mkConnection(i_apb_source.fabric, i_apb_mux.slave);
    mkConnection(i_apb_mux.masters[0], i_apb_uart.fabric);
    mkConnection(i_apb_mux.masters[1], i_apb_periph.fabric);

    AhbSlaveMux_ifc#(2, 16, 32) i_ahb_mux <- mkAhbSlaveMux(select_target);
    AhbMaster_ifc#(16, 32) i_ahb_source <- mkAhbMaster(2);
    AhbSlave_ifc#(16, 32)  i_ahb_uart   <- mkAhbSlave(True);
    AhbSlave_ifc#(16, 32)  i_ahb_periph <- mkAhbSlave(True);

    mkConnection(i_ahb_source.fabric, i_ahb_mux.slave);
    mkConnection(i_ahb_mux.masters[0], i_ahb_uart.fabric);
    mkConnection(i_ahb_mux.masters[1], i_ahb_periph.fabric);

    AXI4_Lite_Master_Rd#(16, 32) i_axi_source_read <- mkAXI4_Lite_Master_Rd(2);
    AXI4_Lite_Master_Wr#(16, 32) i_axi_source_write <- mkAXI4_Lite_Master_Wr(2);
    Vector#(2, AXI4_Lite_Slave_Rd#(16, 32)) v_axi_target_read <- replicateM(mkAXI4_Lite_Slave_Rd(2));
    Vector#(2, AXI4_Lite_Slave_Wr#(16, 32)) v_axi_target_write <- replicateM(mkAXI4_Lite_Slave_Wr(2));

    function Axi4LiteSlaveFab_ifc#(16, 32) axi_target(Integer i) = axi4_lite_slave_fab(v_axi_target_read[i].fab, v_axi_target_write[i].fab);

    //request channels registered so the decoder sees a registered address, targets see local addresses
    Axi4LiteBusCfg_t axi_map_cfg = defaultValue;
    axi_map_cfg.upstream_cut = axi4_lite_slice_request;
    axi_map_cfg.local_addr   = True;
    AddrMapBus_ifc#(2, Axi4LiteSlaveFab_ifc#(16, 32), Empty) i_axi_map <- create_addr_map_bus_cfg(axi_map_cfg, test_bus_addr_map(genWith(axi_target)));

    mkConnection(i_axi_source_read.fab, i_axi_map.up.rd);
    mkConnection(i_axi_source_write.fab, i_axi_map.up.wr);

    // The default configuration elaborates as well (idle here).
    AXI4_Lite_Master_Rd#(16, 32) i_idle_read  <- mkAXI4_Lite_Master_Rd(2);
    AXI4_Lite_Master_Wr#(16, 32) i_idle_write <- mkAXI4_Lite_Master_Wr(2);
    Vector#(2, AXI4_Lite_Slave_Rd#(16, 32)) v_idle_read  <- replicateM(mkAXI4_Lite_Slave_Rd(2));
    Vector#(2, AXI4_Lite_Slave_Wr#(16, 32)) v_idle_write <- replicateM(mkAXI4_Lite_Slave_Wr(2));
    function Axi4LiteSlaveFab_ifc#(16, 32) idle_target(Integer i) = axi4_lite_slave_fab(v_idle_read[i].fab, v_idle_write[i].fab);
    AddrMapBus_ifc#(2, Axi4LiteSlaveFab_ifc#(16, 32), Empty) i_idle_axi_map <- create_addr_map_bus(test_bus_addr_map(genWith(idle_target)));
    mkConnection(axi4_lite_master_fab(i_idle_read.fab, i_idle_write.fab), i_idle_axi_map.up);

    // The APB and AHB generators elaborate from the same map declaration.
    ApbMaster_ifc#(16, 32, 1) i_map_apb_source <- mkApbMaster(2);
    Vector#(2, ApbSlave_ifc#(16, 32, 1)) v_map_apb_targets <- replicateM(mkApbSlave(True));
    function ApbSlaveFabric_ifc#(16, 32, 1) apb_target(Integer i) = v_map_apb_targets[i].fabric;
    ApbBusCfg_t apb_map_cfg = defaultValue;
    apb_map_cfg.local_addr = True;
    AddrMapBus_ifc#(2, ApbSlaveFabric_ifc#(16, 32, 1), Empty) i_apb_map <- create_addr_map_bus_cfg(apb_map_cfg, test_bus_addr_map(genWith(apb_target)));
    mkConnection(i_map_apb_source.fabric, i_apb_map.up);

    AhbMaster_ifc#(16, 32) i_map_ahb_source <- mkAhbMaster(2);
    Vector#(2, AhbSlave_ifc#(16, 32)) v_map_ahb_targets <- replicateM(mkAhbSlave(True));
    function AhbSlaveFabric_ifc#(16, 32) ahb_target(Integer i) = v_map_ahb_targets[i].fabric;
    AddrMapBus_ifc#(2, AhbSlaveFabric_ifc#(16, 32), Empty) i_ahb_map <- create_addr_map_bus(test_bus_addr_map(genWith(ahb_target)));
    mkConnection(i_map_ahb_source.fabric, i_ahb_map.up);

    Reg#(Bit#(3)) rg_read_sent <- mkReg(0);
    Reg#(Bit#(3)) rg_write_sent <- mkReg(0);
    Reg#(Bit#(3)) rg_read_received <- mkReg(0);
    Reg#(Bit#(3)) rg_write_received <- mkReg(0);
    Vector#(2, Reg#(Bit#(3))) rg_target_reads <- replicateM(mkReg(0));
    Vector#(2, Reg#(Bit#(3))) rg_target_writes <- replicateM(mkReg(0));
    Reg#(Bit#(8)) rg_cycles <- mkReg(0);

    function Bit#(16) axi_test_address(Bit#(3) index);
        return case(index)
            0: 16'h1010;
            1: 16'h2ffc;
            2: 16'h1100;
            default: 16'h3000;
        endcase;
    endfunction

    rule r_axi_send_read(rg_read_sent < 4);
        i_axi_source_read.request.put(AXI4_Lite_Read_Rq_Pkg {
            addr: axi_test_address(rg_read_sent), prot: unpack(3'd5)
        });
        rg_read_sent <= rg_read_sent + 1;
    endrule

    rule r_axi_send_write(rg_write_sent < 4);
        let address = axi_test_address(rg_write_sent);
        i_axi_source_write.request.put(AXI4_Lite_Write_Rq_Pkg {
            addr: address, prot: unpack(3'd6),
            data: 32'ha5a50000 | zeroExtend(address), strb: 4'hf
        });
        rg_write_sent <= rg_write_sent + 1;
    endrule

    for(Integer i = 0; i < 2; i = i + 1) begin
        rule r_axi_target_read;
            let request <- v_axi_target_read[i].request.get;
            if(request.addr != (i == 0 ? 16'h0010 : 16'h0ffc) || pack(request.prot) != 5)
                $fatal(1, "decoded AXI read reached the wrong target or got the wrong local address/protection");
            v_axi_target_read[i].response.put(AXI4_Lite_Read_Rs_Pkg {
                data: (i == 0 ? 32'h10000000 : 32'h20000000) | zeroExtend(request.addr),
                resp: i == 0 ? OKAY : SLVERR
            });
            rg_target_reads[i] <= rg_target_reads[i] + 1;
        endrule
        rule r_axi_target_write;
            let request <- v_axi_target_write[i].request.get;
            if(request.addr != (i == 0 ? 16'h0010 : 16'h0ffc) || pack(request.prot) != 6 || request.data != (i == 0 ? 32'ha5a51010 : 32'ha5a52ffc) || request.strb != '1)
                $fatal(1, "decoded AXI write reached the wrong target or got the wrong local address/payload");
            v_axi_target_write[i].response.put(AXI4_Lite_Write_Rs_Pkg { resp: i == 0 ? OKAY : SLVERR });
            rg_target_writes[i] <= rg_target_writes[i] + 1;
        endrule
    end

    rule r_axi_check_read(rg_read_received < 4);
        let response <- i_axi_source_read.response.get;
        Bit#(32) expected_data = rg_read_received == 0 ? 32'h10000010 :
            (rg_read_received == 1 ? 32'h20000ffc : 0);
        AXI4_Lite_Response expected_resp = rg_read_received == 0 ? OKAY :
            (rg_read_received == 1 ? SLVERR : DECERR);
        if(response.data != expected_data || response.resp != expected_resp)
            $fatal(1, "decoded AXI read returned the wrong response");
        rg_read_received <= rg_read_received + 1;
    endrule

    rule r_axi_check_write(rg_write_received < 4);
        let response <- i_axi_source_write.response.get;
        AXI4_Lite_Response expected_resp = rg_write_received == 0 ? OKAY :
            (rg_write_received == 1 ? SLVERR : DECERR);
        if(response.resp != expected_resp)
            $fatal(1, "decoded AXI write returned the wrong response");
        rg_write_received <= rg_write_received + 1;
    endrule

    rule r_watchdog;
        rg_cycles <= rg_cycles + 1;
        if(rg_cycles == 200) $fatal(1, "decoded AXI transactions timed out");
    endrule

    Reg#(Bool) rg_checked <- mkReg(False);

    rule r_check(!rg_checked);
        let uart = i_addr_map.decoder.route(16'h1010);
        let peripheral = i_addr_map.decoder.route(16'h2ffc);
        let unaligned = i_addr_map.decoder.route(16'h2fff);
        let miss = i_addr_map.decoder.route(16'h3000);

        if(uart.sel != 2'b01 || uart.offset != 16'h0010)
            $fatal(1, "address decoder returned an invalid UART route");

        if(peripheral.sel != 2'b10 || peripheral.offset != 16'h0ffc)
            $fatal(1, "address decoder returned an invalid peripheral route");

        // Matching is by address mask only, so the last byte of a region hits.
        if(unaligned.sel != 2'b10 || unaligned.offset != 16'h0fff)
            $fatal(1, "address decoder rejected the last byte of a region");

        if(i_addr_map.decoder.select(16'h1010) != 2'b01 || i_addr_map.decoder.select(16'h2ffc) != 2'b10 || i_addr_map.decoder.select(16'h1100) != 0 || i_addr_map.decoder.select(16'h3000) != 0)
            $fatal(1, "address decoder returned invalid select signals");

        if(addr_map_route_hit(miss) || miss.offset != 0)
            $fatal(1, "address decoder accepted an unmapped address");

        let fallback = i_default_map.decoder.route(16'h3004);
        if(i_default_map.decoder.select(16'h1010) != 2'b01 || fallback.sel != 2'b10 || fallback.offset != 16'h3004)
            $fatal(1, "address decoder did not fall back to the default region");

        if(i_addr_map_with_targets.targets[0] != 0 || i_addr_map_with_targets.targets[1] != 1)
            $fatal(1, "address map endpoints did not preserve declaration order");

        if(pack(i_irq_map.irqs) != 8'h52)
            $fatal(1, "interrupt map returned 0x%0h instead of 0x52",
                pack(i_irq_map.irqs));

        rg_checked <= True;
    endrule

    rule r_finish(rg_checked && rg_read_received == 4 && rg_write_received == 4);
        if(readVReg(rg_target_reads) != replicate(1) || readVReg(rg_target_writes) != replicate(1))
            $fatal(1, "decoded AXI misses generated downstream transactions");
        $display("SoC maps, mux composition, and decoded AXI transactions passed");
        $finish(0);
    endrule

endmodule

endpackage
