package Axi4SlaveMux;

import BlueAXI :: *;
import AddrMapDecoder :: *;
import Vector :: *;
import GetPut :: *;

interface Axi4SlaveMux_ifc#(numeric type slave_count, numeric type aw, numeric type dw, numeric type iw, numeric type uw);
    interface AXI4_Slave_Rd_Fab#(aw, dw, iw, uw) slave_read;
    interface AXI4_Slave_Wr_Fab#(aw, dw, iw, uw) slave_write;

    interface Vector#(slave_count, AXI4_Master_Rd_Fab#(aw, dw, iw, uw)) masters_read;
    interface Vector#(slave_count, AXI4_Master_Wr_Fab#(aw, dw, iw, uw)) masters_write;
endinterface

// One outstanding burst per direction. Decode the whole span before forwarding;
// rejected reads return all beats, rejected writes drain all beats.
module mkAxi4SlaveMux#(
    function AddrMapHit_t#(aw) decode_address(Bit#(aw) address, Bit#(aw) bytes),
    function Bool target_accepts(Bit#(aw) target, AXI4_BurstSize size)
)(Axi4SlaveMux_ifc#(slave_count, aw, dw, iw, uw));

    AXI4_Slave_Rd#(aw, dw, iw, uw)                        i_rd  <- mkAXI4_Slave_Rd(2, 2);
    AXI4_Slave_Wr#(aw, dw, iw, uw)                        i_wr  <- mkAXI4_Slave_Wr(2, 2, 2);
    Vector#(slave_count, AXI4_Master_Rd#(aw, dw, iw, uw)) i_mrd <- replicateM(mkAXI4_Master_Rd(2, 2, False));
    Vector#(slave_count, AXI4_Master_Wr#(aw, dw, iw, uw)) i_mwr <- replicateM(mkAXI4_Master_Wr(2, 2, 2, False));

    function AddrMapHit_t#(aw) route_request(Bit#(aw) addr, UInt#(8) len, AXI4_BurstSize size, AXI4_BurstType burst);
        // Widen before calculating the span, including for small address buses.
        UInt#(TAdd#(aw, 16)) bytes = (zeroExtend(len) + 1) << pack(size);
        UInt#(TAdd#(aw, 16)) start = zeroExtend(unpack(addr));
        let hit = decode_address(addr, truncate(pack(bytes)));

        if(burst != INCR || pack(size) > fromInteger(valueOf(TLog#(TDiv#(dw, 8)))) ||
                (addr & ((1 << pack(size)) - 1)) != 0 ||
                (start & 4095) + bytes > 4096 ||
                start + bytes > (1 << valueOf(aw)) ||
                hit.target_index >= fromInteger(valueOf(slave_count)) ||
                !target_accepts(hit.target_index, size)) begin
            hit.hit = False;
        end
        return hit;
    endfunction

    Reg#(Bool)     rg_rd_busy   <- mkReg(False);
    Reg#(Bool)     rg_rd_miss   <- mkReg(False);
    Reg#(Bit#(aw)) rg_rd_target <- mkReg(0);
    Reg#(UInt#(8)) rg_rd_left   <- mkReg(0);
    Reg#(Bit#(iw)) rg_rd_id     <- mkReg(0);
    Reg#(Bit#(uw)) rg_rd_user   <- mkReg(0);

    rule r_read_route(!rg_rd_busy);
        let rq <- i_rd.request.get;
        let hit = route_request(rq.addr, rq.burst_length, rq.burst_size, rq.burst_type);
        if(hit.hit) begin
            rq.addr = hit.offset;
            i_mrd[hit.target_index].request.put(rq);
        end
        rg_rd_busy   <= True;
        rg_rd_miss   <= !hit.hit;
        rg_rd_target <= hit.target_index;
        rg_rd_left   <= rq.burst_length;
        rg_rd_id     <= rq.id;
        rg_rd_user   <= rq.user;
    endrule

    rule r_read_error(rg_rd_busy && rg_rd_miss);
        i_rd.response.put(AXI4_Read_Rs { id: rg_rd_id, data: 0, resp: DECERR, last: rg_rd_left == 0, user: rg_rd_user });
        rg_rd_left <= rg_rd_left - 1;
        if(rg_rd_left == 0) rg_rd_busy <= False;
    endrule

    for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
        rule r_read_response(rg_rd_busy && !rg_rd_miss && rg_rd_target == fromInteger(n));
            let rs <- i_mrd[n].response.get;
            i_rd.response.put(rs);
            if(rs.last) rg_rd_busy <= False;
        endrule
    end

    Reg#(Bool)     rg_wr_busy     <- mkReg(False);
    Reg#(Bool)     rg_wr_miss     <- mkReg(False);
    Reg#(Bool)     rg_wr_done     <- mkReg(False);
    Reg#(Bool)     rg_wr_bad_last <- mkReg(False);
    Reg#(Bit#(aw)) rg_wr_target   <- mkReg(0);
    Reg#(UInt#(8)) rg_wr_left     <- mkReg(0);
    Reg#(Bit#(iw)) rg_wr_id       <- mkReg(0);
    Reg#(Bit#(uw)) rg_wr_user     <- mkReg(0);

    rule r_write_route(!rg_wr_busy);
        let rq <- i_wr.request_addr.get;
        let hit = route_request(rq.addr, rq.burst_length, rq.burst_size, rq.burst_type);
        if(hit.hit) begin
            rq.addr = hit.offset;
            i_mwr[hit.target_index].request_addr.put(rq);
        end
        rg_wr_busy     <= True;
        rg_wr_miss     <= !hit.hit;
        rg_wr_done     <= False;
        rg_wr_bad_last <= False;
        rg_wr_target   <= hit.target_index;
        rg_wr_left     <= rq.burst_length;
        rg_wr_id       <= rq.id;
        rg_wr_user     <= rq.user;
    endrule

    rule r_write_data(rg_wr_busy && !rg_wr_done);
        let beat <- i_wr.request_data.get;
        if(!rg_wr_miss) i_mwr[rg_wr_target].request_data.put(beat);
        rg_wr_bad_last <= rg_wr_bad_last || (beat.last != (rg_wr_left == 0));
        rg_wr_left     <= rg_wr_left - 1;
        if(rg_wr_left == 0) rg_wr_done <= True;
    endrule

    rule r_write_error(rg_wr_busy && rg_wr_done && rg_wr_miss);
        i_wr.response.put(AXI4_Write_Rs { id: rg_wr_id, resp: DECERR, user: rg_wr_user });
        rg_wr_busy <= False;
    endrule

    for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
        rule r_write_response(rg_wr_busy && rg_wr_done && !rg_wr_miss && rg_wr_target == fromInteger(n));
            let rs <- i_mwr[n].response.get;
            if(rg_wr_bad_last) rs.resp = SLVERR;
            i_wr.response.put(rs);
            rg_wr_busy <= False;
        endrule
    end

    function AXI4_Master_Rd_Fab#(aw, dw, iw, uw) read_fab(AXI4_Master_Rd#(aw, dw, iw, uw) x) = x.fab;
    function AXI4_Master_Wr_Fab#(aw, dw, iw, uw) write_fab(AXI4_Master_Wr#(aw, dw, iw, uw) x) = x.fab;

    interface slave_read    = i_rd.fab;
    interface slave_write   = i_wr.fab;
    interface masters_read  = map(read_fab, i_mrd);
    interface masters_write = map(write_fab, i_mwr);
endmodule

endpackage
