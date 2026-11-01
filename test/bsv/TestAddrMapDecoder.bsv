package TestAddrMapDecoder;

import Vector :: *;
import BuildVector :: *;
import AddrMapDecoder :: *;

function AddrMap_t#(4) test_address_map();
    return vec(addr_region('ha0, 'h10), addr_region('h00, 'h10),
               addr_region('hff, 1), addr_region('h40, 'h20));
endfunction

(* always_ready, always_enabled *)
interface TestAddrMapDecoder_ifc;
    (* prefix = "" *)
    method Action decode((* port = "address" *) Bit#(8) address);
    method Bit#(4) sel;
    method Bit#(4) fab_sel;
    method Bit#(1) full_sel;
    method Bit#(2) adjacent_sel;
    method Bit#(4) route_sel;
    method Bool hit;
    method Bit#(8) offset;
endinterface

(* synthesize *)
module mkTestAddrMapDecoder(TestAddrMapDecoder_ifc);
    AddrMapDecoder_ifc#(4, 8) i_decoder <- mkAddrMapDecoder(test_address_map);
    AddrMapDecoderFab_ifc#(4, 8) i_fab <- mkAddrMapDecoderFab(test_address_map);
    AddrMapDecoder_ifc#(1, 8) i_full <- mkAddrMapDecoder(vec(addr_region(0, 256)));
    AddrMapDecoder_ifc#(2, 8) i_adjacent <- mkAddrMapDecoder(vec(addr_region(0, 128), addr_region(128, 128)));
    Wire#(Bit#(8)) w_address <- mkBypassWire;
    let route = i_decoder.route(w_address);

    method Action decode(Bit#(8) address);
        w_address <= address;
        i_fab.decode(address);
    endmethod
    method sel = i_decoder.select(w_address);
    method fab_sel = i_fab.sel;
    method full_sel = i_full.select(w_address);
    method adjacent_sel = i_adjacent.select(w_address);
    method route_sel = route.sel;
    method hit = addr_map_route_hit(route);
    method offset = route.offset;
endmodule

(* synthesize *)
module mkTestAddrMapSelect(AddrMapDecoderFab_ifc#(4, 8));
    let i_decoder <- mkAddrMapDecoderFab(test_address_map);
    return i_decoder;
endmodule

`ifndef ADDR_MAP_INVALID_CASE
`define ADDR_MAP_INVALID_CASE 0
`endif

module mkTestInvalidAddrMap(AddrMapDecoderFab_ifc#(2, 8));
    AddrMapRegion_t bad_region = case (`ADDR_MAP_INVALID_CASE)
        0: addr_region(8, 8);      // overlaps the first region
        1: addr_region(33, 16);    // misaligned
        2: addr_region(32, 3);     // not a power of two
        3: addr_region(32, 0);     // zero size
        4: addr_region(-16, 16);   // negative base
        5: addr_region(256, 16);   // outside an 8-bit address space
        6: addr_region(0, 512);    // larger than the address space
        default: addr_region(32, -16);
    endcase;
    let i_decoder <- mkAddrMapDecoderFab(vec(addr_region(0, 16), bad_region));
    return i_decoder;
endmodule

endpackage
