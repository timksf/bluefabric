package Axi4LiteSlaveMux;

import Clocks :: *;
import Vector :: *;

import AddrMapDecoder :: *;
import AXI4_Lite_Master :: *;
import AXI4_Lite_Slave :: *;
import AXI4_Lite_Types :: *;

interface Axi4LiteSlaveMux_ifc#(
    numeric type slave_count,
    numeric type addr_w,
    numeric type data_w
);
    interface AXI4_Lite_Slave_Rd_Fab#(addr_w, data_w) slave_read;
    interface AXI4_Lite_Slave_Wr_Fab#(addr_w, data_w) slave_write;
    interface Vector#(
        slave_count,
        AXI4_Lite_Master_Rd_Fab#(addr_w, data_w)
    ) masters_read;
    interface Vector#(
        slave_count,
        AXI4_Lite_Master_Wr_Fab#(addr_w, data_w)
    ) masters_write;
endinterface

module mkAxi4LiteSlaveMux#(
    function AddrMapHit_t#(addr_w) decode_address(
        Bit#(addr_w) address,
        Bit#(addr_w) bytes
    )
)(Axi4LiteSlaveMux_ifc#(slave_count, addr_w, data_w));

    let reset_asserted <- isResetAsserted();

    Wire#(Bool)           w_arvalid <- mkBypassWire;
    Wire#(Bit#(addr_w))   w_araddr  <- mkBypassWire;
    Wire#(AXI4_Lite_Prot) w_arprot  <- mkBypassWire;
    Wire#(Bool)           w_rready  <- mkBypassWire;

    Wire#(Bool)               w_arready <- mkDWire(False);
    Wire#(Bool)               w_rvalid  <- mkDWire(False);
    Wire#(Bit#(data_w))       w_rdata   <- mkDWire(0);
    Wire#(AXI4_Lite_Response) w_rresp   <- mkDWire(OKAY);

    Vector#(slave_count, Wire#(Bool))               vw_arready  <- replicateM(mkBypassWire);
    Vector#(slave_count, Wire#(Bool))               vw_rvalid   <- replicateM(mkBypassWire);
    Vector#(slave_count, Wire#(Bit#(data_w)))       vw_rdata    <- replicateM(mkBypassWire);
    Vector#(slave_count, Wire#(AXI4_Lite_Response)) vw_rresp    <- replicateM(mkBypassWire);

    Bit#(addr_w) transfer_bytes = fromInteger(valueOf(TDiv#(data_w, 8)));
    AddrMapHit_t#(addr_w) read_route = decode_address(w_araddr, transfer_bytes);
    Bool read_route_valid = read_route.hit && read_route.target_index < fromInteger(valueOf(slave_count));

    Reg#(Bool)         rg_read_valid  <- mkReg(False);
    Reg#(Bool)         rg_read_miss   <- mkReg(False);
    Reg#(Bit#(addr_w)) rg_read_target <- mkReg(0);

    rule r_select_read;
        if(!reset_asserted && !rg_read_valid) begin
            if(read_route_valid) begin
                for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
                    if(read_route.target_index == fromInteger(n))
                        w_arready <= vw_arready[n];
                end
            end else begin
                w_arready <= True;
            end
        end else if(!reset_asserted && rg_read_miss) begin
            w_rvalid <= True;
            w_rresp  <= DECERR;
        end else if(!reset_asserted) begin
            for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
                if(rg_read_target == fromInteger(n)) begin
                    w_rvalid <= vw_rvalid[n];
                    w_rdata  <= vw_rdata[n];
                    w_rresp  <= vw_rresp[n];
                end
            end
        end
    endrule

    rule r_update_read;
        if(w_rvalid && w_rready) begin
            rg_read_valid <= False;
            rg_read_miss  <= False;
        end else if(w_arvalid && w_arready) begin
            rg_read_valid  <= True;
            rg_read_miss   <= !read_route_valid;
            rg_read_target <= read_route.target_index;
        end
    endrule

    Wire#(Bool)                      w_awvalid <- mkBypassWire;
    Wire#(Bit#(addr_w))              w_awaddr  <- mkBypassWire;
    Wire#(AXI4_Lite_Prot)            w_awprot  <- mkBypassWire;
    Wire#(Bool)                      w_wvalid  <- mkBypassWire;
    Wire#(Bit#(data_w))              w_wdata   <- mkBypassWire;
    Wire#(Bit#(TDiv#(data_w, 8)))    w_wstrb   <- mkBypassWire;
    Wire#(Bool)                      w_bready  <- mkBypassWire;

    Wire#(Bool)               w_awready <- mkDWire(False);
    Wire#(Bool)               w_wready  <- mkDWire(False);
    Wire#(Bool)               w_bvalid  <- mkDWire(False);
    Wire#(AXI4_Lite_Response) w_bresp   <- mkDWire(OKAY);

    Vector#(slave_count, Wire#(Bool))               vw_awready  <- replicateM(mkBypassWire);
    Vector#(slave_count, Wire#(Bool))               vw_wready   <- replicateM(mkBypassWire);
    Vector#(slave_count, Wire#(Bool))               vw_bvalid   <- replicateM(mkBypassWire);
    Vector#(slave_count, Wire#(AXI4_Lite_Response)) vw_bresp    <- replicateM(mkBypassWire);

    AddrMapHit_t#(addr_w) write_route = decode_address(w_awaddr, transfer_bytes);
    Bool write_route_valid = write_route.hit && write_route.target_index < fromInteger(valueOf(slave_count));

    Reg#(Bool)           rg_write_valid     <- mkReg(False);
    Reg#(Bool)           rg_write_miss      <- mkReg(False);
    Reg#(Bool)           rg_write_addr_done <- mkReg(False);
    Reg#(Bool)           rg_write_data_done <- mkReg(False);
    Reg#(Bit#(addr_w))   rg_write_target    <- mkReg(0);
    Reg#(Bit#(addr_w))   rg_write_address   <- mkReg(0);
    Reg#(AXI4_Lite_Prot) rg_write_prot      <- mkReg(UNPRIV_SECURE_DATA);

    rule r_select_write;
        if(!reset_asserted && !rg_write_valid) begin
            w_awready <= True;
        end else if(!reset_asserted) begin
            if(!rg_write_data_done) begin
                if(rg_write_miss) begin
                    w_wready <= True;
                end else begin
                    for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
                        if(rg_write_target == fromInteger(n))
                            w_wready <= vw_wready[n];
                    end
                end
            end

            if(rg_write_addr_done && rg_write_data_done &&
                    rg_write_miss) begin
                w_bvalid <= True;
                w_bresp  <= DECERR;
            end else if(rg_write_addr_done && rg_write_data_done) begin
                for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
                    if(rg_write_target == fromInteger(n)) begin
                        w_bvalid <= vw_bvalid[n];
                        w_bresp  <= vw_bresp[n];
                    end
                end
            end
        end
    endrule

    rule r_update_write;
        if(w_bvalid && w_bready) begin
            rg_write_valid     <= False;
            rg_write_miss      <= False;
            rg_write_addr_done <= False;
            rg_write_data_done <= False;
        end else if(w_awvalid && w_awready) begin
            rg_write_valid     <= True;
            rg_write_miss      <= !write_route_valid;
            rg_write_addr_done <= !write_route_valid;
            rg_write_data_done <= False;
            rg_write_target    <= write_route.target_index;
            rg_write_address   <= write_route.offset;
            rg_write_prot      <= w_awprot;
        end else begin
            if(rg_write_valid && !rg_write_miss &&
                    !rg_write_addr_done) begin
                for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
                    if(rg_write_target == fromInteger(n) && vw_awready[n])
                        rg_write_addr_done <= True;
                end
            end

            if(w_wvalid && w_wready)
                rg_write_data_done <= True;
        end
    endrule

    Vector#(slave_count, AXI4_Lite_Master_Rd_Fab#(addr_w, data_w)) v_masters_read = newVector;
    Vector#(slave_count, AXI4_Lite_Master_Wr_Fab#(addr_w, data_w)) v_masters_write = newVector;

    for(Integer n = 0; n < valueOf(slave_count); n = n + 1) begin
        v_masters_read[n] = interface AXI4_Lite_Master_Rd_Fab;
            method arvalid = !reset_asserted && !rg_read_valid &&
                w_arvalid && read_route_valid &&
                read_route.target_index == fromInteger(n);
            method araddr = read_route.offset;
            method arprot = w_arprot;
            method rready = !reset_asserted && rg_read_valid &&
                !rg_read_miss && rg_read_target == fromInteger(n) &&
                w_rready;

            method parready = vw_arready[n]._write;
            method prvalid  = vw_rvalid[n]._write;
            method prdata   = vw_rdata[n]._write;
            method prresp   = vw_rresp[n]._write;
        endinterface;

        v_masters_write[n] = interface AXI4_Lite_Master_Wr_Fab;
            method awvalid = !reset_asserted && rg_write_valid &&
                !rg_write_miss && !rg_write_addr_done &&
                rg_write_target == fromInteger(n);
            method awaddr  = rg_write_address;
            method awprot  = rg_write_prot;
            method wvalid = !reset_asserted && rg_write_valid &&
                !rg_write_miss && !rg_write_data_done &&
                rg_write_target == fromInteger(n) && w_wvalid;
            method wdata   = w_wdata;
            method wstrb   = w_wstrb;
            method bready = !reset_asserted && rg_write_valid &&
                !rg_write_miss && rg_write_addr_done &&
                rg_write_data_done &&
                rg_write_target == fromInteger(n) && w_bready;

            method pawready = vw_awready[n]._write;
            method pwready  = vw_wready[n]._write;
            method pbvalid  = vw_bvalid[n]._write;
            method pbresp   = vw_bresp[n]._write;
        endinterface;
    end

    interface AXI4_Lite_Slave_Rd_Fab slave_read;
        method parvalid = w_arvalid._write;
        method paraddr  = w_araddr._write;
        method parprot  = w_arprot._write;
        method prready  = w_rready._write;

        method arready = w_arready;
        method rvalid  = w_rvalid;
        method rdata   = w_rdata;
        method rresp   = w_rresp;
    endinterface

    interface AXI4_Lite_Slave_Wr_Fab slave_write;
        method pawvalid = w_awvalid._write;
        method pawaddr  = w_awaddr._write;
        method pawprot  = w_awprot._write;
        method pwvalid  = w_wvalid._write;
        method pwdata   = w_wdata._write;
        method pwstrb   = w_wstrb._write;
        method pbready  = w_bready._write;

        method awready = w_awready;
        method wready  = w_wready;
        method bvalid  = w_bvalid;
        method bresp   = w_bresp;
    endinterface

    interface masters_read  = v_masters_read;
    interface masters_write = v_masters_write;

endmodule

endpackage
