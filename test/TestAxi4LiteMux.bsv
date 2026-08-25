package TestAxi4LiteMux;

import Connectable :: *;
import GetPut :: *;

import AddrMapDecoder :: *;
import Axi4LiteSlaveMux :: *;
import AXI4_Lite_Slave :: *;
import AXI4_Lite_Types :: *;

module mkTestAxi4LiteDecoder(AddrMapDecoder_ifc#(16));
    method AddrMapHit_t#(16) lookup(Bit#(16) address, Bit#(16) bytes);
        AddrMapHit_t#(16) result = AddrMapHit_t {
            hit          : False,
            target_index : 0,
            global_addr  : address,
            offset       : 0
        };

        if(bytes != 0 && address < 16'h1000 &&
                zeroExtend(address) + zeroExtend(bytes) <= 17'h01000) begin
            result.hit = True;
            result.target_index = 0;
            result.offset = address;
        end else if(bytes != 0 && address >= 16'h1000 &&
                zeroExtend(address) + zeroExtend(bytes) <= 17'h02000) begin
            result.hit = True;
            result.target_index = 1;
            result.offset = address - 16'h1000;
        end

        return result;
    endmethod
endmodule

interface TestAxi4LiteMux_ifc;
    (* prefix = "S_AXI" *)
    interface AXI4_Lite_Slave_Rd_Fab#(16, 32) s_axi_read;
    (* prefix = "S_AXI" *)
    interface AXI4_Lite_Slave_Wr_Fab#(16, 32) s_axi_write;

    (* always_ready *) method Bit#(8) write_count;
    (* always_ready *) method Bit#(1) last_write_target;
    (* always_ready *) method Bit#(16) last_write_address;
    (* always_ready *) method Bit#(32) last_write_data;
    (* always_ready *) method Bit#(4) last_write_strobe;
    (* always_ready *) method Bit#(3) last_write_protection;
endinterface

(* synthesize *)
module mkTestAxi4LiteMux(TestAxi4LiteMux_ifc);
    let i_decoder <- mkTestAxi4LiteDecoder;
    Axi4LiteSlaveMux_ifc#(2, 16, 32) i_mux <-
        mkAxi4LiteSlaveMux(i_decoder.lookup);

    AXI4_Lite_Slave_Rd#(16, 32) i_read0 <-
        mkAXI4_Lite_Slave_Rd(0);
    AXI4_Lite_Slave_Rd#(16, 32) i_read1 <-
        mkAXI4_Lite_Slave_Rd(0);
    AXI4_Lite_Slave_Wr#(16, 32) i_write0 <-
        mkAXI4_Lite_Slave_Wr(0);
    AXI4_Lite_Slave_Wr#(16, 32) i_write1 <-
        mkAXI4_Lite_Slave_Wr(0);

    mkConnection(i_mux.masters_read[0], i_read0.fab);
    mkConnection(i_mux.masters_read[1], i_read1.fab);
    mkConnection(i_mux.masters_write[0], i_write0.fab);
    mkConnection(i_mux.masters_write[1], i_write1.fab);

    Reg#(Bit#(8))  rg_write_count   <- mkReg(0);
    Reg#(Bit#(1))  rg_write_target  <- mkReg(0);
    Reg#(Bit#(16)) rg_write_address <- mkReg(0);
    Reg#(Bit#(32)) rg_write_data    <- mkReg(0);
    Reg#(Bit#(4))  rg_write_strobe  <- mkReg(0);
    Reg#(Bit#(3))  rg_write_prot    <- mkReg(0);

    rule r_read0;
        let request <- i_read0.request.get;
        i_read0.response.put(AXI4_Lite_Read_Rs_Pkg {
            data : 32'h10000000 |
                (zeroExtend(pack(request.prot)) << 20) |
                zeroExtend(request.addr),
            resp : OKAY
        });
    endrule

    rule r_read1;
        let request <- i_read1.request.get;
        i_read1.response.put(AXI4_Lite_Read_Rs_Pkg {
            data : 32'h20000000 |
                (zeroExtend(pack(request.prot)) << 20) |
                zeroExtend(request.addr),
            resp : SLVERR
        });
    endrule

    (* mutually_exclusive = "r_write0, r_write1" *)
    rule r_write0;
        let request <- i_write0.request.get;
        i_write0.response.put(AXI4_Lite_Write_Rs_Pkg {
            resp : OKAY
        });

        rg_write_count   <= rg_write_count + 1;
        rg_write_target  <= 0;
        rg_write_address <= request.addr;
        rg_write_data    <= request.data;
        rg_write_strobe  <= request.strb;
        rg_write_prot    <= pack(request.prot);
    endrule

    rule r_write1;
        let request <- i_write1.request.get;
        i_write1.response.put(AXI4_Lite_Write_Rs_Pkg {
            resp : SLVERR
        });

        rg_write_count   <= rg_write_count + 1;
        rg_write_target  <= 1;
        rg_write_address <= request.addr;
        rg_write_data    <= request.data;
        rg_write_strobe  <= request.strb;
        rg_write_prot    <= pack(request.prot);
    endrule

    method write_count           = rg_write_count;
    method last_write_target     = rg_write_target;
    method last_write_address    = rg_write_address;
    method last_write_data       = rg_write_data;
    method last_write_strobe     = rg_write_strobe;
    method last_write_protection = rg_write_prot;

    interface s_axi_read  = i_mux.slave_read;
    interface s_axi_write = i_mux.slave_write;
endmodule

endpackage
