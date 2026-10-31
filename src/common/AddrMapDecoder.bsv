package AddrMapDecoder;

import List :: *;
import Vector :: *;

//elaboration time region, its position in the map is its select bit
//power of two sized and aligned to its size, so a hit is a single masked compare
typedef struct {
    Integer base;
    Integer size;
} AddrMapRegion_t;

typedef Vector#(n, AddrMapRegion_t) AddrMap_t#(numeric type n);

function AddrMapRegion_t addr_region(Integer base, Integer size);
    return AddrMapRegion_t { base: base, size: size };
endfunction

function Bool addr_map_size_is_valid(Integer size);
    if(size == 1) return True;
    else if(size <= 0 || (size % 2) != 0) return False;
    else return addr_map_size_is_valid(size / 2);
endfunction

function Bool addr_map_regions_overlap(AddrMapRegion_t a, AddrMapRegion_t b);
    return a.base < b.base + b.size && b.base < a.base + a.size;
endfunction

//reports every problem in a list of regions, each named by its label (e.g. "region 3" or "target uart")
function String addr_map_labeled_errors(
        List#(String) labels,
        List#(AddrMapRegion_t) regions,
        Integer address_width
    );
    String errors = "";
    Integer address_space = 2 ** address_width;
    for(Integer i = 0; i < List::length(regions); i = i + 1) begin
        let region = regions[i];
        String prefix = "Address map " + labels[i] + ": ";
        if(!addr_map_size_is_valid(region.size))
            errors = errors + prefix + "size must be a positive power of two.\n";
        else if(region.base % region.size != 0)
            errors = errors + prefix + "base must be aligned to size.\n";
        if(region.base < 0 || region.base + region.size > address_space)
            errors = errors + prefix + "region lies outside the address space.\n";
        for(Integer j = i + 1; j < List::length(regions); j = j + 1) begin
            if(addr_map_regions_overlap(region, regions[j]))
                errors = errors + prefix + "overlaps " + labels[j] + ".\n";
        end
    end
    return errors;
endfunction

function String addr_map_region_errors(List#(AddrMapRegion_t) regions, Integer address_width);
    function String label(Integer i) = "region " + integerToString(i);
    let labels = List::map(label, List::upto(0, List::length(regions) - 1));
    return addr_map_labeled_errors(labels, regions, address_width);
endfunction

function String validate_addr_map(AddrMap_t#(n) address_map, Integer address_width);
    return addr_map_region_errors(Vector::toList(address_map), address_width);
endfunction

//compares only the address bits above the region offset, no adder or magnitude compare
function Bool addr_region_hit(Bit#(aw) address, AddrMapRegion_t region);
    Bit#(aw) offset_mask = fromInteger(region.size - 1);
    return (address & ~offset_mask) == fromInteger(region.base);
endfunction

//one-hot or zero, as validated regions never overlap
function Bit#(n) addr_map_select(AddrMap_t#(n) address_map, Bit#(aw) address);
    return pack(Vector::map(addr_region_hit(address), address_map));
endfunction

//address bits inside the selected region, zero when nothing is selected
function Bit#(aw) addr_map_offset(AddrMap_t#(n) address_map, Bit#(n) sel, Bit#(aw) address);
    Bit#(aw) offset_mask = 0;
    for(Integer i = 0; i < valueOf(n); i = i + 1)
        if(sel[i] == 1) offset_mask = offset_mask | fromInteger(address_map[i].size - 1);
    return address & offset_mask;
endfunction

//AND-OR selection by a zero or one-hot mask, zero when nothing is selected
function t onehot_select(Bit#(n) sel, Vector#(n, t) values) provisos(Bits#(t, t_width));
    Bit#(t_width) result = 0;
    for(Integer i = 0; i < valueOf(n); i = i + 1)
        result = result | (sel[i] == 1 ? pack(values[i]) : 0);
    return unpack(result);
endfunction

//for fabrics that translate addresses themselves: zero or one-hot select plus region local offset
typedef struct {
    Bit#(n)  sel;
    Bit#(aw) offset;
} AddrMapRoute_t#(numeric type n, numeric type aw) deriving(Bits, Eq, FShow);

function Bool addr_map_route_hit(AddrMapRoute_t#(n, aw) route) = route.sel != 0;

function AddrMapRoute_t#(n, aw) addr_map_route(AddrMap_t#(n) address_map, Bit#(aw) address);
    let sel = addr_map_select(address_map, address);
    return AddrMapRoute_t { sel: sel, offset: addr_map_offset(address_map, sel, address) };
endfunction

(* always_ready *)
interface AddrMapDecoder_ifc#(numeric type n, numeric type aw);
    method Bit#(n) select(Bit#(aw) address);
    method AddrMapRoute_t#(n, aw) route(Bit#(aw) address);
endinterface

module mkAddrMapDecoder#(AddrMap_t#(n) address_map)(AddrMapDecoder_ifc#(n, aw));
    let errors = validate_addr_map(address_map, valueOf(aw));
    if(errors != "") errorM(errors);

    method select(address) = addr_map_select(address_map, address);
    method route(address)  = addr_map_route(address_map, address);
endmodule

(* always_ready, always_enabled *)
interface AddrMapDecoderFab_ifc#(numeric type n, numeric type aw);
    (* prefix = "" *)
    method Action decode((* port = "address" *) Bit#(aw) address);
    method Bit#(n) sel;
endinterface

module mkAddrMapDecoderFab#(AddrMap_t#(n) address_map)(AddrMapDecoderFab_ifc#(n, aw));
    AddrMapDecoder_ifc#(n, aw) i_decoder <- mkAddrMapDecoder(address_map);
    Wire#(Bit#(n)) w_select <- mkDWire(0);

    method Action decode(Bit#(aw) address);
        w_select <= i_decoder.select(address);
    endmethod
    method sel = w_select;
endmodule

endpackage
