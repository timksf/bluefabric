package TestAxi4Full2Lite;

import GetPut :: *;
import StmtFSM :: *;
import Connectable :: *;
import ClientServer :: *;

import BlueAXI :: *;
import Axi4Full2Lite :: *;


module mkTestAxi4Full2Lite();

    Axi4Full2Lite_ifc#(32, 32, 0, 0) dut <- mkAxi4Full2Lite();

    AXI4_Master_Rd#(32, 32, 0, 0) m_rd <- mkAXI4_Master_Rd(2, 2, False);
    AXI4_Master_Wr#(32, 32, 0, 0) m_wr <- mkAXI4_Master_Wr(2, 2, 2, False);

    AXI4_Lite_Slave_Rd#(32, 32) s_rd <- mkAXI4_Lite_Slave_Rd(2);
    AXI4_Lite_Slave_Wr#(32, 32) s_wr <- mkAXI4_Lite_Slave_Wr(2);

    Reg#(UInt#(32)) rg_count <- mkReg(0);

    mkConnection(m_rd.fab,      dut.s_axi_rd);
    mkConnection(m_wr.fab,      dut.s_axi_wr);
    mkConnection(dut.m_axil_rd, s_rd.fab);
    mkConnection(dut.m_axil_wr, s_wr.fab);

    rule rrespond;
        let req <- s_rd.request.get;
        Bit#(32) rsp = 0;

        if(req.addr < 'h1000)
            rsp = 32'h1000 - req.addr;
        else 
            rsp = 32'hDEADBEEF + req.addr;

        s_rd.response.put(AXI4_Lite_Read_Rs_Pkg { data: rsp, resp: OKAY });
    endrule

    rule rdrain_rd_rsp;
        let rsp <- m_rd.response.get();
        $display("Read Response %0x", rsp.data);
    endrule

    Stmt s = seq
        $display("Start mkAxi4Full2Lite test...");

        axi4_read_data(m_rd, 'h0, 7);
        axi4_read_data(m_rd, 'h1000, 0);

        delay(100);

    endseq;

    mkAutoFSM(s);

endmodule

endpackage