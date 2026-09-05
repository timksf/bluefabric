package Axi4Full2Lite;

import GetPut :: *;

import BlueAXI :: *;

interface Axi4Full2Lite_ifc#(numeric type aw, numeric type dw, numeric type iw, numeric type uw);

    /* AXI4 Slave */
    interface AXI4_Slave_Rd_Fab#(aw, dw, iw, uw) s_axi_rd;
    interface AXI4_Slave_Wr_Fab#(aw, dw, iw, uw) s_axi_wr;

    /* AXI4L Master */
    interface AXI4_Lite_Master_Rd_Fab#(aw, dw) m_axil_rd;
    interface AXI4_Lite_Master_Wr_Fab#(aw, dw) m_axil_wr;

endinterface

module mkAxi4Full2Lite(Axi4Full2Lite_ifc#(aw, dw, iw, uw));

    AXI4_Slave_Rd#(aw, dw, iw, uw)  i_s_rd <- mkAXI4_Slave_Rd(0, 0);
    AXI4_Slave_Wr#(aw, dw, iw, uw)  i_s_wr <- mkAXI4_Slave_Wr(0, 0, 0);

    AXI4_Lite_Master_Rd#(aw, dw)    i_m_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(aw, dw)    i_m_wr <- mkAXI4_Lite_Master_Wr(1);

    /* read channel */
    Reg#(Bool)     rg_rd_busy   <- mkReg(False);
    Reg#(Bool)     rg_rd_err    <- mkReg(False);
    Reg#(UInt#(8)) rg_burst_cnt <- mkReg(0);
    //channel state that has to be kept track of until the last response
    Reg#(AXI4_Prot) rg_rd_prot   <- mkRegU;
    Reg#(Bit#(aw))  rg_rd_addr   <- mkRegU;
    Reg#(Bit#(uw))  rg_rd_usr    <- mkRegU;
    Reg#(Bit#(iw))  rg_rd_id     <- mkRegU;
    Reg#(Bit#(3))   rg_lg2incr   <- mkRegU;
    
    rule raccept_rd_rq if(!rg_rd_busy);
        let req <- i_s_rd.request.get;

        Bool aligned    = (req.addr & ((1 << pack(req.burst_size)) - 1)) == 0;
        Bool error      = !aligned || req.burst_type == WRAP || req.burst_type == FIXED;

        rg_rd_err       <= error;
        rg_burst_cnt    <= req.burst_length;
        rg_rd_busy      <= True;
        rg_rd_addr      <= req.addr;
        rg_rd_prot      <= req.prot;
        rg_rd_usr       <= req.user;
        rg_rd_id        <= req.id;
        rg_lg2incr      <= pack(req.burst_size);

        if(!error) begin
            i_m_rd.request.put(
                AXI4_Lite_Read_Rq_Pkg { addr: req.addr, prot: unpack(pack(req.prot)) }
            );
        end

    endrule

    rule rprocess_rd if(rg_rd_busy && !rg_rd_err);

        let rs <- i_m_rd.response.get;

        Bool last           = rg_burst_cnt == 0;
        AXI4_Response resp  = unpack(pack(rs.resp));

        if(rg_burst_cnt > 0) begin
            let next_addr = rg_rd_addr + (1 << rg_lg2incr);
            i_m_rd.request.put(
                AXI4_Lite_Read_Rq_Pkg { addr: next_addr, prot: unpack(pack(rg_rd_prot)) }
            );
            rg_burst_cnt    <= rg_burst_cnt - 1;
            rg_rd_addr      <= next_addr;
        end

        if(last) begin
            rg_rd_busy  <= False;
        end

        i_s_rd.response.put(
            AXI4_Read_Rs {
                id:     rg_rd_id,
                data:   rs.data,
                resp:   resp,
                last:   last,
                user:   rg_rd_usr
            }
        );

    endrule

    rule rrd_err if(rg_rd_busy && rg_rd_err);

        Bool last = rg_burst_cnt == 0;

        i_s_rd.response.put(
            AXI4_Read_Rs {
                id:     rg_rd_id,
                data:   ?,
                resp:   SLVERR,
                last:   rg_burst_cnt == 0,
                user:   rg_rd_usr
            }
        );

        if(last) begin
            rg_rd_busy      <= False;
            rg_rd_err       <= False;
        end else begin
            rg_burst_cnt    <= rg_burst_cnt - 1;
        end

    endrule


    interface s_axi_rd = i_s_rd.fab;
    interface s_axi_wr = i_s_wr.fab;

    interface m_axil_rd = i_m_rd.fab;
    interface m_axil_wr = i_m_wr.fab;

endmodule

endpackage