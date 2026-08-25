package BlueAddrMap;

import List :: *;
import ModuleCollect :: *;
import Vector :: *;

import AddrMapDecoder :: *;

typedef struct {
    String name;
} AddrMapDef_t;

typedef struct {
    Bit#(aw) type_anchor;
    Integer base;
    Integer size;
    String name;
    endpoint target;
} AddrMapTargetDef_t#(numeric type aw, type endpoint);

typedef union tagged {
    AddrMapDef_t                       AddrMapDef;
    AddrMapTargetDef_t#(aw, endpoint)  AddrMapTargetDef;
} AddrMapEntry_t#(numeric type aw, type endpoint);

// A context describes one physical fabric segment. The endpoint type is opaque
// to this package and is chosen by its protocol generator. Submodules may add
// targets to the same context, and a bridge consumes a separate downstream
// context whose endpoint type can use a different protocol.
typedef ModuleCollect#(AddrMapEntry_t#(aw, endpoint), ifc)
    AddrMapCtx_t#(numeric type aw, type endpoint, type ifc);

interface AddrMap_ifc#(numeric type aw, type ifc);
    interface AddrMapDecoder_ifc#(aw) decoder;
    interface ifc internal;
endinterface

interface AddrMapWithTargets_ifc#(
    numeric type n,
    numeric type aw,
    type endpoint,
    type ifc
);
    interface AddrMapDecoder_ifc#(aw) decoder;
    interface Vector#(n, endpoint) targets;
    interface ifc internal;
endinterface

typedef struct {
    Bool valid;
    String errors;
    String map_name;
} AddrMapValidation_t;

typedef struct {
    String text;
} AddrMapDoc_t;

function List#(AddrMapDef_t) get_addr_map_def(
        AddrMapEntry_t#(aw, endpoint) entry
    ) = entry matches tagged AddrMapDef .x ? Cons(x, Nil) : Nil;

function List#(AddrMapTargetDef_t#(aw, endpoint)) get_addr_map_target_def(
        AddrMapEntry_t#(aw, endpoint) entry
    ) = entry matches tagged AddrMapTargetDef .x ? Cons(x, Nil) : Nil;

function endpoint get_addr_map_target(
        AddrMapTargetDef_t#(aw, endpoint) target
    ) = target.target;

function Bool addr_map_is_power_of_two(Integer value);
    if(value == 1) return True;
    else if(value <= 0 || (value % 2) != 0) return False;
    else return addr_map_is_power_of_two(value / 2);
endfunction

function Bool addr_map_size_is_valid(Integer size);
    return addr_map_is_power_of_two(size);
endfunction

function Integer addr_map_target_length(
        AddrMapTargetDef_t#(aw, endpoint) target
    ) = target.size;

function Bool addr_map_target_match(
        AddrMapTargetDef_t#(aw, endpoint) target,
        Bit#(aw) address
    );
    Bit#(aw) base = fromInteger(target.base);
    Bit#(aw) range_mask = fromInteger(target.size - 1);
    return ((address ~^ base) | range_mask) == '1;
endfunction

function Bool addr_map_targets_overlap(
        AddrMapTargetDef_t#(aw, endpoint) a,
        AddrMapTargetDef_t#(aw, endpoint) b
    );
    Integer a_end = a.base + addr_map_target_length(a);
    Integer b_end = b.base + addr_map_target_length(b);
    return (a.base < b_end) && (b.base < a_end);
endfunction

function AddrMapHit_t#(aw) decode_addr_map_targets(
        List#(AddrMapTargetDef_t#(aw, endpoint)) targets,
        Bit#(aw) address,
        Bit#(aw) bytes
    );
    AddrMapHit_t#(aw) result = AddrMapHit_t {
        hit: False,
        target_index: 0,
        global_addr: address,
        offset: 0
    };

    for (Integer i = 0; i < List::length(targets); i = i + 1) begin
        let target = targets[i];
        Bit#(TAdd#(aw, 1)) span_base = zeroExtend(address);
        Bit#(TAdd#(aw, 1)) span_end = span_base + zeroExtend(bytes);
        Bit#(TAdd#(aw, 1)) target_base = fromInteger(target.base);
        Bit#(TAdd#(aw, 1)) target_end = fromInteger(
            target.base + addr_map_target_length(target)
        );
        Bool start_matches = addr_map_target_match(target, address);
        Bool in_target = bytes != 0 && start_matches && span_end <= target_end;

        if(in_target && !result.hit) begin
            result = AddrMapHit_t {
                hit: True,
                target_index: fromInteger(i),
                global_addr: address,
                offset: address - truncate(target_base)
            };
        end
    end
    return result;
endfunction

function String addr_map_append_newline(String acc, String msg);
    if(acc == "") return msg;
    else return acc + "\n" + msg;
endfunction

function String addr_map_integer_to_hex_digit(Integer n) = charToString(integerToHexDigit(n));

function String addr_map_integer_to_hex(Integer n);
    if(n < 16) return addr_map_integer_to_hex_digit(n);
    else return strConcat(addr_map_integer_to_hex(n / 16), addr_map_integer_to_hex_digit(n % 16));
endfunction

function AddrMapValidation_t validate_addr_map_entries(
        List#(AddrMapEntry_t#(aw, endpoint)) entries
    );
    let map_defs = List::concat(List::map(get_addr_map_def, entries));
    let targets = List::concat(List::map(get_addr_map_target_def, entries));

    Integer address_space = 2 ** valueOf(aw);
    String errors = "";
    String map_name = "BlueAddrMap";

    if(List::length(map_defs) == 0) begin
        errors = addr_map_append_newline(errors, "BlueAddrMap validation failed: exactly one addr_map_def is required, found none.");
    end
    else if(List::length(map_defs) > 1) begin
        errors = addr_map_append_newline(errors, "BlueAddrMap validation failed: exactly one addr_map_def is required, found " + integerToString(List::length(map_defs)) + ".");
    end
    else begin
        map_name = map_defs[0].name;
    end

    for (Integer i = 0; i < List::length(targets); i = i + 1) begin
        let target = targets[i];
        Integer size = addr_map_target_length(target);

        if(!addr_map_size_is_valid(size)) begin
            errors = addr_map_append_newline(errors, "BlueAddrMap validation failed: target " + target.name + " size is not a power of two.");
        end
        else if((target.base % size) != 0) begin
            errors = addr_map_append_newline(errors, "BlueAddrMap validation failed: target " + target.name + " base is not aligned to its size.");
        end
        if(target.base < 0 || (target.base + size) > address_space) begin
            errors = addr_map_append_newline(errors, "BlueAddrMap validation failed: target " + target.name + " lies outside the address space.");
        end

        for (Integer j = i + 1; j < List::length(targets); j = j + 1) begin
            let other = targets[j];
            if(target.name == other.name) begin
                errors = addr_map_append_newline(errors, "BlueAddrMap validation failed: target name " + target.name + " is defined multiple times.");
            end
            if(addr_map_targets_overlap(target, other)) begin
                errors = addr_map_append_newline(errors, "BlueAddrMap validation failed: targets " + target.name + " and " + other.name + " overlap.");
            end
        end
    end

    return AddrMapValidation_t {
        valid: errors == "",
        errors: errors,
        map_name: map_name
    };
endfunction

module [AddrMapCtx_t#(aw, endpoint)] addr_map_def#(String name)();
    AddrMapEntry_t#(aw, endpoint) entry = tagged AddrMapDef AddrMapDef_t {
        name: name
    };
    addToCollection(entry);
endmodule

module [AddrMapCtx_t#(aw, endpoint)] addr_map_target#(Integer base, Integer size, String name, endpoint target)();
    if(!addr_map_size_is_valid(size)) begin
        errorM("BlueAddrMap target " + name + " size is not a power of two.");
    end
    else if((base % size) != 0) begin
        errorM("BlueAddrMap target " + name + " base is not aligned to its size.");
    end

    AddrMapEntry_t#(aw, endpoint) entry = tagged AddrMapTargetDef AddrMapTargetDef_t {
        type_anchor: 0,
        base: base,
        size: size,
        name: name,
        target: target
    };
    addToCollection(entry);
endmodule

module [Module] create_addr_map#(AddrMapCtx_t#(aw, endpoint, ifc) ctx)(AddrMap_ifc#(aw, ifc));
    let {map_device, entries} <- getCollection(ctx);
    let targets = List::concat(List::map(get_addr_map_target_def, entries));
    let validation = validate_addr_map_entries(entries);

    if(!validation.valid) errorM(validation.errors);

    interface AddrMapDecoder_ifc decoder;
        method AddrMapHit_t#(aw) lookup(Bit#(aw) address, Bit#(aw) bytes) =
            decode_addr_map_targets(targets, address, bytes);
    endinterface

    interface internal = map_device;
endmodule

module [Module] create_addr_map_with_targets#(
    AddrMapCtx_t#(aw, endpoint, ifc) ctx
)(AddrMapWithTargets_ifc#(n, aw, endpoint, ifc));
    let {map_device, entries} <- getCollection(ctx);
    let target_defs = List::concat(List::map(get_addr_map_target_def, entries));
    let validation = validate_addr_map_entries(entries);

    if(!validation.valid) errorM(validation.errors);
    if(List::length(target_defs) != valueOf(n)) begin
        errorM(
            "BlueAddrMap target count mismatch: map "
                + validation.map_name
                + " defines "
                + integerToString(List::length(target_defs))
                + " targets, but its fabric expects "
                + integerToString(valueOf(n))
                + "."
        );
    end

    Vector#(n, endpoint) v_targets =
        toVector(List::map(get_addr_map_target, target_defs));

    interface AddrMapDecoder_ifc decoder;
        method AddrMapHit_t#(aw) lookup(Bit#(aw) address, Bit#(aw) bytes) =
            decode_addr_map_targets(target_defs, address, bytes);
    endinterface

    interface targets  = v_targets;
    interface internal = map_device;
endmodule

module [Module] doc_addr_map#(AddrMapCtx_t#(aw, endpoint, ifc) ctx)(AddrMapDoc_t);
    let {_, entries} <- getCollection(ctx);
    let targets = List::concat(List::map(get_addr_map_target_def, entries));
    let validation = validate_addr_map_entries(entries);

    if(!validation.valid) errorM(validation.errors);

    String text = validation.map_name;
    for (Integer i = 0; i < List::length(targets); i = i + 1) begin
        let target = targets[i];
        Integer target_end = target.base + addr_map_target_length(target) - 1;
        text = addr_map_append_newline(
            text,
            "0x" + addr_map_integer_to_hex(target.base)
                + " - 0x" + addr_map_integer_to_hex(target_end)
                + "  " + target.name
        );
    end

    return AddrMapDoc_t { text: text };
endmodule

module [Module] doc_addr_map_markdown#(AddrMapCtx_t#(aw, endpoint, ifc) ctx)(AddrMapDoc_t);
    let {_, entries} <- getCollection(ctx);
    let targets = List::concat(List::map(get_addr_map_target_def, entries));
    let validation = validate_addr_map_entries(entries);

    if(!validation.valid) errorM(validation.errors);

    String text = "| Base | End | Name |\n"
        + "| --- | --- | --- |";
    for (Integer i = 0; i < List::length(targets); i = i + 1) begin
        let target = targets[i];
        Integer target_end = target.base + addr_map_target_length(target) - 1;
        text = addr_map_append_newline(
            text,
            "| 0x" + addr_map_integer_to_hex(target.base)
                + " | 0x" + addr_map_integer_to_hex(target_end)
                + " | " + target.name
                + " |"
        );
    end

    return AddrMapDoc_t { text: text };
endmodule

endpackage
