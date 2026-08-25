package TestSocMaps;

import Connectable :: *;
import Vector :: *;

import AhbMaster :: *;
import AhbSlave :: *;
import AhbSlaveMux :: *;
import ApbMaster :: *;
import ApbSlave :: *;
import ApbSlaveMux :: *;
import Axi4LiteSlaveMux :: *;
import AXI4_Lite_Master :: *;
import AXI4_Lite_Slave :: *;
import AddrMapDecoder :: *;
import BlueAddrMap :: *;
import BlueInterruptMap :: *;

module [AddrMapCtx_t#(16, Bit#(8))] test_addr_map();
    addr_map_def("TestSoC");
    addr_map_target(4096, 256, "uart", 8'd0);
    addr_map_target(8192, 4096, "peripherals", 8'd1);
endmodule

module [IRQMapCtx_t#(8)] test_irq_map();
    Vector#(2, Bool) timer_irqs = unpack(2'b01);
    Vector#(3, Bool) peripheral_irqs = unpack(3'b101);

    irq_map_def("TestIRQs");
    irq_map_source(1, "timer", timer_irqs);
    irq_map_source(4, "peripherals", peripheral_irqs);
endmodule

module mkTestSocMaps(Empty);

    AddrMapEntry_t#(16, Bit#(8)) invalid_addr_def =
        tagged AddrMapDef AddrMapDef_t {
            name: "InvalidAddressMap"
        };
    AddrMapEntry_t#(16, Bit#(8)) invalid_addr_target_a =
        tagged AddrMapTargetDef AddrMapTargetDef_t {
            type_anchor: 0,
            base: 4096,
            size: 256,
            name: "target_a",
            target: 0
        };
    AddrMapEntry_t#(16, Bit#(8)) invalid_addr_target_b =
        tagged AddrMapTargetDef AddrMapTargetDef_t {
            type_anchor: 0,
            base: 4224,
            size: 128,
            name: "target_b",
            target: 1
        };
    List#(AddrMapEntry_t#(16, Bit#(8))) invalid_addr_entries =
        Cons(
            invalid_addr_def,
            Cons(
                invalid_addr_target_a,
                Cons(invalid_addr_target_b, Nil)
            )
        );
    let invalid_addr_validation =
        validate_addr_map_entries(invalid_addr_entries);

    IRQMapEntry_t#(8) invalid_irq_def =
        tagged IRQMapDef IRQMapDef_t {
            name: "InvalidIRQMap"
        };
    IRQMapEntry_t#(8) invalid_irq_source =
        tagged IRQMapSourceDef IRQMapSourceDef_t {
            type_anchor: 0,
            base: 7,
            width: 2,
            name: "out_of_range",
            lines: 0
        };
    List#(IRQMapEntry_t#(8)) invalid_irq_entries =
        Cons(invalid_irq_def, Cons(invalid_irq_source, Nil));
    let invalid_irq_validation = validate_irq_map(invalid_irq_entries);

    if(invalid_addr_validation.valid)
        errorM("address map validation accepted overlapping targets");
    if(invalid_irq_validation.valid)
        errorM("interrupt map validation accepted an out-of-range source");

    let addr_doc <- doc_addr_map(test_addr_map);
    let addr_markdown <- doc_addr_map_markdown(test_addr_map);
    let irq_doc <- doc_irq_map(test_irq_map);

    String expected_addr_doc =
        "TestSoC\n"
        + "0x1000 - 0x10ff  uart\n"
        + "0x2000 - 0x2fff  peripherals";
    String expected_addr_markdown =
        "| Base | End | Name |\n"
        + "| --- | --- | --- |\n"
        + "| 0x1000 | 0x10ff | uart |\n"
        + "| 0x2000 | 0x2fff | peripherals |";
    String expected_irq_doc =
        "TestIRQs\n"
        + "1 - 2  timer\n"
        + "4 - 6  peripherals";

    if(addr_doc.text != expected_addr_doc)
        errorM("plain-text address map generation did not match");
    if(addr_markdown.text != expected_addr_markdown)
        errorM("Markdown address map generation did not match");
    if(irq_doc.text != expected_irq_doc)
        errorM("interrupt map documentation generation did not match");

    let i_addr_map <- create_addr_map(test_addr_map);
    AddrMapWithTargets_ifc#(2, 16, Bit#(8), Empty) i_addr_map_with_targets <-
        create_addr_map_with_targets(test_addr_map);
    let i_irq_map  <- create_irq_map(test_irq_map);

    function AddrMapHit_t#(16) decode_address(
        Bit#(16) address,
        Bit#(16) bytes
    );
        return i_addr_map.decoder.lookup(address, bytes);
    endfunction

    ApbSlaveMux_ifc#(2, 16, 32, 1) i_apb_mux <-
        mkApbSlaveMux(decode_address);
    ApbMaster_ifc#(16, 32, 1) i_apb_source <- mkApbMaster(2);
    ApbSlave_ifc#(16, 32, 1)  i_apb_uart   <- mkApbSlave(True);
    ApbSlave_ifc#(16, 32, 1)  i_apb_periph <- mkApbSlave(True);

    mkConnection(i_apb_source.fabric, i_apb_mux.slave);
    mkConnection(i_apb_mux.masters[0], i_apb_uart.fabric);
    mkConnection(i_apb_mux.masters[1], i_apb_periph.fabric);

    AhbSlaveMux_ifc#(2, 16, 32) i_ahb_mux <-
        mkAhbSlaveMux(decode_address);
    AhbMaster_ifc#(16, 32) i_ahb_source <- mkAhbMaster(2);
    AhbSlave_ifc#(16, 32)  i_ahb_uart   <- mkAhbSlave(True);
    AhbSlave_ifc#(16, 32)  i_ahb_periph <- mkAhbSlave(True);

    mkConnection(i_ahb_source.fabric, i_ahb_mux.slave);
    mkConnection(i_ahb_mux.masters[0], i_ahb_uart.fabric);
    mkConnection(i_ahb_mux.masters[1], i_ahb_periph.fabric);

    Axi4LiteSlaveMux_ifc#(2, 16, 32) i_axi_mux <-
        mkAxi4LiteSlaveMux(decode_address);
    AXI4_Lite_Master_Rd#(16, 32) i_axi_source_read <-
        mkAXI4_Lite_Master_Rd(2);
    AXI4_Lite_Master_Wr#(16, 32) i_axi_source_write <-
        mkAXI4_Lite_Master_Wr(2);
    Vector#(2, AXI4_Lite_Slave_Rd#(16, 32)) v_axi_target_read <-
        replicateM(mkAXI4_Lite_Slave_Rd(2));
    Vector#(2, AXI4_Lite_Slave_Wr#(16, 32)) v_axi_target_write <-
        replicateM(mkAXI4_Lite_Slave_Wr(2));

    mkConnection(i_axi_source_read.fab, i_axi_mux.slave_read);
    mkConnection(i_axi_source_write.fab, i_axi_mux.slave_write);

    for(Integer n = 0; n < 2; n = n + 1) begin
        mkConnection(i_axi_mux.masters_read[n], v_axi_target_read[n].fab);
        mkConnection(i_axi_mux.masters_write[n], v_axi_target_write[n].fab);
    end

    Reg#(Bool) rg_checked <- mkReg(False);

    rule r_check(!rg_checked);
        let uart = i_addr_map.decoder.lookup(16'h1010, 16'd4);
        let peripheral = i_addr_map.decoder.lookup(16'h2ffc, 16'd4);
        let crossing = i_addr_map.decoder.lookup(16'h2ffe, 16'd4);
        let miss = i_addr_map.decoder.lookup(16'h3000, 16'd4);

        if(!uart.hit || uart.target_index != 0 ||
                uart.global_addr != 16'h1010 || uart.offset != 16'h0010)
            $fatal(1, "address decoder returned an invalid UART route");

        if(!peripheral.hit || peripheral.target_index != 1 ||
                peripheral.global_addr != 16'h2ffc ||
                peripheral.offset != 16'h0ffc)
            $fatal(1, "address decoder returned an invalid peripheral route");

        if(crossing.hit)
            $fatal(1, "address decoder accepted a transfer crossing a target boundary");

        if(miss.hit)
            $fatal(1, "address decoder accepted an unmapped transfer");

        if(i_addr_map_with_targets.targets[0] != 0 ||
                i_addr_map_with_targets.targets[1] != 1)
            $fatal(1, "address map endpoints did not preserve declaration order");

        if(pack(i_irq_map.irqs) != 8'h52)
            $fatal(1, "interrupt map returned 0x%0h instead of 0x52",
                pack(i_irq_map.irqs));

        rg_checked <= True;
    endrule

    rule r_finish(rg_checked);
        $display("SoC map generation and mux composition passed");
        $finish(0);
    endrule

endmodule

endpackage
