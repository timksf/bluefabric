package TestAxi4Full2Lite;

import GetPut :: *;
import StmtFSM :: *;
import Connectable :: *;
import FIFO :: *;
import FIFOF :: *;
import BlueAXI :: *;
import Axi4Full2Lite :: *;

module mkTestAxi4Full2Lite();

    Axi4Full2Lite_ifc#(32, 32, 4, 4) dut <- mkAxi4Full2Lite();
    AXI4_Master_Rd#(32, 32, 4, 4) m_rd <- mkAXI4_Master_Rd(2, 2, False);
    AXI4_Master_Wr#(32, 32, 4, 4) m_wr <- mkAXI4_Master_Wr(2, 2, 0, False);
    AXI4_Lite_Slave_Rd#(32, 32) s_rd <- mkAXI4_Lite_Slave_Rd(2);
    AXI4_Lite_Slave_Wr#(32, 32) s_wr <- mkAXI4_Lite_Slave_Wr(2);

    FIFOF#(Tuple2#(AXI4_Lite_Write_Rq_Pkg#(32, 32), AXI4_Lite_Response)) f_expected_wr <- mkSizedFIFOF(256);
    FIFO#(AXI4_Lite_Write_Rs_Pkg)   f_pending_rsp <- mkSizedFIFO(256);
    FIFOF#(AXI4_Write_Rs#(4, 4))    f_expected_rsp <- mkSizedFIFOF(16);

    Reg#(UInt#(9))  rg_count            <- mkReg(0);
    Reg#(UInt#(16)) rg_writes           <- mkReg(0);
    Reg#(UInt#(16)) rg_responses        <- mkReg(0);
    Reg#(UInt#(8))  rg_reads            <- mkReg(0);
    Reg#(Bool)      rg_lite_rsp_enable  <- mkReg(True);
    Reg#(Bool)      rg_axi_rsp_enable   <- mkReg(True);
    Reg#(Bool)      rg_wait_data        <- mkReg(False);
    Reg#(UInt#(16)) rg_cycles           <- mkReg(0);

    mkConnection(m_rd.fab, dut.s_axi_rd);
    mkConnection(m_wr.fab, dut.s_axi_wr);
    mkConnection(dut.m_axil_rd, s_rd.fab);
    mkConnection(dut.m_axil_wr, s_wr.fab);

    rule r_timeout;
        rg_cycles <= rg_cycles + 1;
        if(rg_cycles == 5000) begin
            $display("FAIL: timeout, writes=%0d responses=%0d", rg_writes, rg_responses);
            $finish(1);
        end
    endrule

    rule r_respond_rd;
        let req <- s_rd.request.get;
        s_rd.response.put(AXI4_Lite_Read_Rs_Pkg {
            data: req.addr < 'h1000 ? 'h1000 - req.addr : 'hDEADBEEF + req.addr,
            resp: OKAY
        });
    endrule

    rule r_check_rd;
        let rsp <- m_rd.response.get;
        Bit#(32) expected = rg_reads < 8 ? 'h1000 - (zeroExtend(pack(rg_reads)) << 2) : 'hDEADCEEF;
        if(rsp.data != expected || rsp.resp != OKAY || rsp.last != (rg_reads == 7 || rg_reads == 8)) begin
            $display("FAIL: read response ", fshow(rsp));
            $finish(1);
        end
        rg_reads <= rg_reads + 1;
    endrule

    rule r_check_wr;
        let req <- s_wr.request.get;
        if(!f_expected_wr.notEmpty) begin
            $display("FAIL: unexpected Lite write ", fshow(req));
            $finish(1);
        end else begin
            match {.expected, .resp} = f_expected_wr.first;
            f_expected_wr.deq;
            if(req != expected) begin
                $display("FAIL: Lite write ", fshow(req), " expected ", fshow(expected));
                $finish(1);
            end
            f_pending_rsp.enq(AXI4_Lite_Write_Rs_Pkg { resp: resp });
        end
        rg_writes <= rg_writes + 1;
    endrule

    rule r_respond_wr if(rg_lite_rsp_enable);
        s_wr.response.put(f_pending_rsp.first);
        f_pending_rsp.deq;
    endrule

    rule r_check_rsp if(rg_axi_rsp_enable);
        let rsp <- m_wr.response.get;
        if(!f_expected_rsp.notEmpty) begin
            $display("FAIL: unexpected AXI response ", fshow(rsp));
            $finish(1);
        end else begin
            let expected = f_expected_rsp.first;
            f_expected_rsp.deq;
            if(rg_wait_data || rsp != expected) begin
                $display("FAIL: AXI response ", fshow(rsp), " expected ", fshow(expected));
                $finish(1);
            end
        end
        rg_responses <= rg_responses + 1;
    endrule

    rule r_no_early_rsp if(rg_wait_data && dut.s_axi_wr.bvalid);
        $display("FAIL: response before rejected write data");
        $finish(1);
    endrule

    function Action send_addr(Bit#(32) addr, UInt#(8) len, AXI4_BurstType burst, AXI4_Response resp);
        action
            m_wr.request_addr.put(AXI4_Write_Rq_Addr {
                id: 5, addr: addr, burst_length: len, burst_size: bitsToBurstSize(32),
                burst_type: burst, lock: NORMAL, cache: NORMAL_NON_CACHEABLE_NON_BUFFERABLE,
                prot: PRIV_SECURE_DATA, qos: 0, region: 0, user: 9
            });
            f_expected_rsp.enq(AXI4_Write_Rs { id: 5, resp: resp, user: 9 });
        endaction
    endfunction

    function Action send_data(Bit#(32) addr, Bool last, Bool rejected, AXI4_Lite_Response resp);
        action
            axi4_write_data(m_wr, addr ^ 'h12345678, 'h5, last);
            if(!rejected) begin
                f_expected_wr.enq(tuple2(AXI4_Lite_Write_Rq_Pkg {
                    addr: addr, data: addr ^ 'h12345678, strb: 'h5, prot: PRIV_SECURE_DATA
                }, resp));
            end
        endaction
    endfunction

    function Stmt error_burst(Bit#(32) addr, UInt#(9) error_beat, AXI4_Lite_Response error_resp);
        return seq
            send_addr(addr, 2, INCR, unpack(pack(error_resp)));
            rg_count <= 0;
            while(rg_count < 3) action
                send_data(addr + (zeroExtend(pack(rg_count)) << 2), rg_count == 2, False, rg_count == error_beat ? error_resp : OKAY);
                rg_count <= rg_count + 1;
            endaction
        endseq;
    endfunction

    Stmt s = seq
        $display("Start mkAxi4Full2Lite test");
        axi4_read_data(m_rd, 'h0, 7);
        axi4_read_data(m_rd, 'h1000, 0);

        //delayed Lite responses and consecutive bursts, with W ahead of AW acceptance.
        rg_lite_rsp_enable <= False;
        send_addr('h0, 1, INCR, OKAY);
        send_data('h0, False, False, OKAY);
        send_data('h4, True, False, OKAY);
        send_addr('h100, 0, INCR, OKAY);
        send_data('h100, True, False, OKAY);
        delay(12);
        action
            if(rg_writes != 2 || rg_responses != 0) begin
                $display("FAIL: forwarded beyond WLAST or responded before Lite");
                $finish(1);
            end
            rg_lite_rsp_enable <= True;
        endaction
        await(rg_responses == 2);

        //errors on the first, middle, final, and only beat.
        error_burst('h200, 0, SLVERR);
        await(rg_responses == 3);
        error_burst('h300, 1, DECERR);
        await(rg_responses == 4);
        error_burst('h400, 2, SLVERR);
        await(rg_responses == 5);
        send_addr('h500, 0, INCR, DECERR);
        send_data('h500, True, False, DECERR);
        await(rg_responses == 6);

        //preserve the first error if a later beat reports a different error.
        send_addr('h600, 1, INCR, DECERR);
        send_data('h600, False, False, DECERR);
        send_data('h604, True, False, SLVERR);
        await(rg_responses == 7);

        //rejected single beat with delayed W, then rejected FIXED and WRAP bursts.
        rg_wait_data <= True;
        send_addr('h701, 0, INCR, SLVERR);
        delay(12);
        rg_wait_data <= False;
        send_data('h701, True, True, OKAY);
        await(rg_responses == 8);
        send_addr('h800, 1, FIXED, SLVERR);
        send_data('h800, False, True, OKAY);
        delay(8);
        action
            if(rg_responses != 8) begin
                $display("FAIL: rejected burst responded before final data");
                $finish(1);
            end
        endaction
        send_data('h800, True, True, OKAY);
        await(rg_responses == 9);
        send_addr('h900, 1, WRAP, SLVERR);
        send_data('h900, False, True, OKAY);
        send_data('h904, True, True, OKAY);
        await(rg_responses == 10);

        //early and missing WLAST: AWLEN remains the consumption boundary.
        send_addr('ha00, 1, INCR, SLVERR);
        send_data('ha00, True, False, OKAY);
        send_data('ha04, True, False, OKAY);
        await(rg_responses == 11);
        send_addr('hb00, 0, INCR, SLVERR);
        send_data('hb00, False, False, OKAY);
        await(rg_responses == 12);

        //fill the upstream response buffer, then hold the next B response.
        rg_axi_rsp_enable <= False;
        send_addr('hc00, 0, INCR, OKAY);
        send_data('hc00, True, False, OKAY);
        send_addr('hd00, 0, INCR, OKAY);
        send_data('hd00, True, False, OKAY);
        delay(20);
        action
            if(!dut.s_axi_wr.bvalid || dut.s_axi_wr.bresp != OKAY || dut.s_axi_wr.bid != 5) begin
                $display("FAIL: B response not held under backpressure");
                $finish(1);
            end
        endaction
        delay(8);
        rg_axi_rsp_enable <= True;
        await(rg_responses == 14);

        //maximum AWLEN exercises the full eight-bit countdown.
        send_addr('h1000, 255, INCR, OKAY);
        rg_count <= 0;
        while(rg_count < 256) action
            send_data('h1000 + (zeroExtend(pack(rg_count)) << 2), rg_count == 255, False, OKAY);
            rg_count <= rg_count + 1;
        endaction
        await(rg_responses == 15 && rg_reads == 9);
        delay(12);
        action
            if(rg_writes != 276 || f_expected_wr.notEmpty || f_expected_rsp.notEmpty || dut.m_axil_wr.awvalid || dut.m_axil_wr.wvalid || dut.s_axi_wr.bvalid) begin
                $display("FAIL: incorrect write count or trailing traffic, writes=%0d", rg_writes);
                $finish(1);
            end
            $display("PASS: AXI4 Full-to-Lite write cases");
        endaction
    endseq;

    mkAutoFSM(s);

endmodule

endpackage
