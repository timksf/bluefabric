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
    Reg#(Bool)      rg_rd_busy  <- mkReg(False);
    Reg#(Bool)      rg_rd_err   <- mkReg(False);
    Reg#(UInt#(8))  rg_rd_cnt   <- mkReg(0);
    //channel state that has to be kept track of until the last response
    Reg#(AXI4_Prot) rg_rd_prot  <- mkRegU;
    Reg#(Bit#(aw))  rg_rd_addr  <- mkRegU;
    Reg#(Bit#(uw))  rg_rd_usr   <- mkRegU;
    Reg#(Bit#(iw))  rg_rd_id    <- mkRegU;
    Reg#(Bit#(3))   rg_rd_incr  <- mkRegU;

    /* write channel */
    Reg#(Bool)      rg_wr_busy  <- mkReg(False);
    Reg#(Bool)      rg_wr_err   <- mkReg(False);
    Reg#(UInt#(8))  rg_wr_cnt   <- mkReg(0);
    Reg#(AXI4_Prot) rg_wr_prot  <- mkRegU;
    Reg#(Bit#(aw))  rg_wr_addr  <- mkRegU;
    Reg#(Bit#(uw))  rg_wr_usr   <- mkRegU;
    Reg#(Bit#(iw))  rg_wr_id    <- mkRegU;
    Reg#(Bit#(3))   rg_wr_incr  <- mkRegU;

    
    rule raccept_rd_rq if(!rg_rd_busy);
        let req <- i_s_rd.request.get;

        Bool aligned    = (req.addr & ((1 << pack(req.burst_size)) - 1)) == 0;
        Bool error      = !aligned || req.burst_type != INCR;

        rg_rd_err   <= error;
        rg_rd_cnt   <= req.burst_length;
        rg_rd_busy  <= True;
        rg_rd_addr  <= req.addr;
        rg_rd_prot  <= req.prot;
        rg_rd_usr   <= req.user;
        rg_rd_id    <= req.id;
        rg_rd_incr  <= pack(req.burst_size);

        if(!error) begin
            i_m_rd.request.put(
                AXI4_Lite_Read_Rq_Pkg { addr: req.addr, prot: unpack(pack(req.prot)) }
            );
        end
    endrule

    rule rprocess_rd if(rg_rd_busy && !rg_rd_err);
        let rs <- i_m_rd.response.get;

        Bool last           = rg_rd_cnt == 0;
        AXI4_Response resp  = unpack(pack(rs.resp));

        if(rg_rd_cnt > 0) begin
            let next_addr = rg_rd_addr + (1 << rg_rd_incr);
            i_m_rd.request.put(
                AXI4_Lite_Read_Rq_Pkg { addr: next_addr, prot: unpack(pack(rg_rd_prot)) }
            );
            rg_rd_cnt   <= rg_rd_cnt - 1;
            rg_rd_addr  <= next_addr;
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
        Bool last = rg_rd_cnt == 0;
        i_s_rd.response.put(
            AXI4_Read_Rs {
                id:     rg_rd_id,
                data:   ?,
                resp:   SLVERR,
                last:   rg_rd_cnt == 0,
                user:   rg_rd_usr
            }
        );
        if(last) begin
            rg_rd_busy  <= False;
            rg_rd_err   <= False;
        end else begin
            rg_rd_cnt   <= rg_rd_cnt - 1;
        end
    endrule


    /* write */

    rule raccept_wr_addr if(!rg_wr_busy);
        let req <- i_s_wr.request_addr.get;

        Bool aligned    = (req.addr & ((1 << pack(req.burst_size)) - 1)) == 0;
        Bool error      = !aligned || req.burst_type != INCR;
        //lock, cache, qos, region are ignored

        rg_wr_err   <= error;
        rg_wr_cnt   <= req.burst_length;
        rg_wr_busy  <= True;
        rg_wr_addr  <= req.addr;
        rg_wr_prot  <= req.prot;
        rg_wr_usr   <= req.user;
        rg_wr_id    <= req.id;
        rg_wr_incr  <= pack(req.burst_size);
    endrule

    rule rfwd_wr_data if(rg_wr_busy && !rg_wr_err);
        let req <- i_s_wr.request_data.get;
        i_m_wr.request.put(
            AXI4_Lite_Write_Rq_Pkg{ addr: rg_wr_addr, data: req.data, strb: req.strb, prot: unpack(pack(rg_wr_prot)) }
        );
        if(!req.last) begin
            rg_wr_addr <= rg_wr_addr + (1 << rg_wr_incr);
        end else begin
            //burst ends here
            
        end
    endrule

    rule rdisc_wr_data if(rg_wr_busy && rg_wr_err);
        let __unused <- i_s_wr.request_data.get;
    endrule

    rule rfwd_wr_rsp if(rg_wr_busy && !rg_wr_err);
        let rsp <- i_m_wr.response.get;
        if(rg_wr_cnt == 0) begin
            rg_wr_busy <= False;
            //there is only a single response expected for a burst
            i_s_wr.response.put(
                AXI4_Write_Rs { id: rg_wr_id, resp: unpack(pack(rsp.resp)), user: rg_wr_usr }
            );
        end else begin
            rg_wr_cnt <= rg_wr_cnt - 1;
        end
    endrule

    rule rwr_err if(rg_wr_busy && rg_wr_err);
        i_s_wr.response.put(
            AXI4_Write_Rs { id: rg_wr_id, resp: SLVERR, user: rg_wr_usr }
        );
        if(rg_wr_cnt == 0) begin
            rg_wr_busy  <= False;
            rg_wr_err   <= False;
        end else begin
            rg_wr_cnt   <= rg_wr_cnt - 1;
        end
    endrule


    interface s_axi_rd = i_s_rd.fab;
    interface s_axi_wr = i_s_wr.fab;

    interface m_axil_rd = i_m_rd.fab;
    interface m_axil_wr = i_m_wr.fab;

endmodule

endpackage