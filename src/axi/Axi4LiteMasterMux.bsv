package Axi4LiteMasterMux;

import Vector :: *;
import GetPut :: *;
import BlueAXI :: *;

interface Axi4LiteMasterMux_ifc#(numeric type aw, numeric type dw);
    interface Vector#(2, AXI4_Lite_Slave_Rd_Fab#(aw, dw)) s_rd;
    interface Vector#(2, AXI4_Lite_Slave_Wr_Fab#(aw, dw)) s_wr;
    interface AXI4_Lite_Master_Rd_Fab#(aw, dw) m_rd;
    interface AXI4_Lite_Master_Wr_Fab#(aw, dw) m_wr;
endinterface

(* descending_urgency = "r_read_request, r_read_request_1, r_rd_turn" *)
(* descending_urgency = "r_write_request, r_write_request_1, r_wr_turn" *)
module mkAxi4LiteMasterMux(Axi4LiteMasterMux_ifc#(aw, dw));

    Vector#(2, AXI4_Lite_Slave_Rd#(aw, dw)) i_rd   <- replicateM(mkAXI4_Lite_Slave_Rd(2));
    Vector#(2, AXI4_Lite_Slave_Wr#(aw, dw)) i_wr   <- replicateM(mkAXI4_Lite_Slave_Wr(2));
    AXI4_Lite_Master_Rd#(aw, dw)            i_m_rd <- mkAXI4_Lite_Master_Rd(2);
    AXI4_Lite_Master_Wr#(aw, dw)            i_m_wr <- mkAXI4_Lite_Master_Wr(2);

    Reg#(Bool)    rg_rd_busy  <- mkReg(False);
    Reg#(Bool)    rg_wr_busy  <- mkReg(False);
    Reg#(Bit#(1)) rg_rd_turn  <- mkReg(0);
    Reg#(Bit#(1)) rg_wr_turn  <- mkReg(0);
    Reg#(Bit#(1)) rg_rd_owner <- mkReg(0);
    Reg#(Bit#(1)) rg_wr_owner <- mkReg(0);

    // Poll alternating ports while idle; ownership lasts through the response.
    rule r_rd_turn(!rg_rd_busy);
        rg_rd_turn <= rg_rd_turn + 1;
    endrule

    rule r_wr_turn(!rg_wr_busy);
        rg_wr_turn <= rg_wr_turn + 1;
    endrule

    for(Integer n = 0; n < 2; n = n + 1) begin
        rule r_read_request(!rg_rd_busy && rg_rd_turn == fromInteger(n));
            let rq <- i_rd[n].request.get;
            i_m_rd.request.put(rq);
            rg_rd_owner <= fromInteger(n);
            rg_rd_busy  <= True;
        endrule

        rule r_read_response(rg_rd_busy && rg_rd_owner == fromInteger(n));
            let rs <- i_m_rd.response.get;
            i_rd[n].response.put(rs);
            rg_rd_busy <= False;
            rg_rd_turn <= fromInteger(1 - n);
        endrule

        rule r_write_request(!rg_wr_busy && rg_wr_turn == fromInteger(n));
            let rq <- i_wr[n].request.get;
            i_m_wr.request.put(rq);
            rg_wr_owner <= fromInteger(n);
            rg_wr_busy  <= True;
        endrule

        rule r_write_response(rg_wr_busy && rg_wr_owner == fromInteger(n));
            let rs <- i_m_wr.response.get;
            i_wr[n].response.put(rs);
            rg_wr_busy <= False;
            rg_wr_turn <= fromInteger(1 - n);
        endrule
    end

    function AXI4_Lite_Slave_Rd_Fab#(aw, dw) read_fab(AXI4_Lite_Slave_Rd#(aw, dw) x) = x.fab;
    function AXI4_Lite_Slave_Wr_Fab#(aw, dw) write_fab(AXI4_Lite_Slave_Wr#(aw, dw) x) = x.fab;

    interface s_rd = map(read_fab, i_rd);
    interface s_wr = map(write_fab, i_wr);
    interface m_rd = i_m_rd.fab;
    interface m_wr = i_m_wr.fab;
endmodule

endpackage
