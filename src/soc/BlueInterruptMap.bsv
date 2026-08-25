package BlueInterruptMap;

import List :: *;
import ModuleCollect :: *;
import Vector :: *;

typedef struct {
    String name;
} IRQMapDef_t;

typedef struct {
    Bit#(n) type_anchor;
    Integer base;
    Integer width;
    String name;
    Bit#(n) lines;
} IRQMapSourceDef_t#(numeric type n);

typedef union tagged {
    IRQMapDef_t            IRQMapDef;
    IRQMapSourceDef_t#(n)  IRQMapSourceDef;
} IRQMapEntry_t#(numeric type n);

// An IRQ map places ordinary combinational vectors at channel bases and ORs
// intentional overlaps. Software, timer, and external CPU interrupts remain
// explicit SoC-level connections.
typedef ModuleCollect#(IRQMapEntry_t#(n), ifc)
    IRQMapCtx_t#(numeric type n, type ifc);

interface IRQMap_ifc#(numeric type n, type ifc);
    (* always_ready *)
    method Vector#(n, Bool) irqs;
    interface ifc internal;
endinterface

typedef struct {
    Bool valid;
    String errors;
    String map_name;
} IRQMapValidation_t;

typedef struct {
    String text;
} IRQMapDoc_t;

function List#(IRQMapDef_t) get_irq_map_def(
        IRQMapEntry_t#(n) entry
    ) = entry matches tagged IRQMapDef .x ? Cons(x, Nil) : Nil;

function List#(IRQMapSourceDef_t#(n)) get_irq_map_source_def(
        IRQMapEntry_t#(n) entry
    ) = entry matches tagged IRQMapSourceDef .x ? Cons(x, Nil) : Nil;

function String irq_map_append_newline(String acc, String msg);
    if(acc == "") return msg;
    else return acc + "\n" + msg;
endfunction

function IRQMapValidation_t validate_irq_map(
        List#(IRQMapEntry_t#(n)) entries
    );
    let map_defs = List::concat(List::map(get_irq_map_def, entries));
    let sources = List::concat(List::map(get_irq_map_source_def, entries));

    String errors = "";
    String map_name = "BlueIRQMap";

    if(List::length(map_defs) == 0) begin
        errors = irq_map_append_newline(errors, "BlueIRQMap validation failed: exactly one irq_map_def is required, found none.");
    end
    else if(List::length(map_defs) > 1) begin
        errors = irq_map_append_newline(errors, "BlueIRQMap validation failed: exactly one irq_map_def is required, found " + integerToString(List::length(map_defs)) + ".");
    end
    else begin
        map_name = map_defs[0].name;
    end

    for (Integer i = 0; i < List::length(sources); i = i + 1) begin
        let source = sources[i];

        if(source.base < 0 || source.width <= 0 || source.base + source.width > valueOf(n)) begin
            errors = irq_map_append_newline(errors, "BlueIRQMap validation failed: source " + source.name + " lies outside the interrupt vector.");
        end

        for (Integer j = i + 1; j < List::length(sources); j = j + 1) begin
            let other = sources[j];
            if(source.name == other.name) begin
                errors = irq_map_append_newline(errors, "BlueIRQMap validation failed: source name " + source.name + " is defined multiple times.");
            end
        end
    end

    return IRQMapValidation_t {
        valid: errors == "",
        errors: errors,
        map_name: map_name
    };
endfunction

module [IRQMapCtx_t#(n)] irq_map_def#(String name)();
    IRQMapEntry_t#(n) entry = tagged IRQMapDef IRQMapDef_t {
        name: name
    };
    addToCollection(entry);
endmodule

module [IRQMapCtx_t#(n)] irq_map_source#(Integer base, String name, Vector#(m, Bool) source)()
    provisos(Add#(m, pad, n));
    Bit#(n) lines = zeroExtend(pack(source)) << base;
    IRQMapEntry_t#(n) entry = tagged IRQMapSourceDef IRQMapSourceDef_t {
        type_anchor: 0,
        base: base,
        width: valueOf(m),
        name: name,
        lines: lines
    };
    addToCollection(entry);
endmodule

module [Module] create_irq_map#(IRQMapCtx_t#(n, ifc) ctx)(IRQMap_ifc#(n, ifc));
    let {map_device, entries} <- getCollection(ctx);
    let sources = List::concat(List::map(get_irq_map_source_def, entries));
    let validation = validate_irq_map(entries);

    if(!validation.valid) errorM(validation.errors);

    method Vector#(n, Bool) irqs;
        Bit#(n) result = 0;
        for (Integer i = 0; i < List::length(sources); i = i + 1) begin
            result = result | sources[i].lines;
        end
        return unpack(result);
    endmethod

    interface internal = map_device;
endmodule

module [Module] doc_irq_map#(IRQMapCtx_t#(n, ifc) ctx)(IRQMapDoc_t);
    let {_, entries} <- getCollection(ctx);
    let sources = List::concat(List::map(get_irq_map_source_def, entries));
    let validation = validate_irq_map(entries);

    if(!validation.valid) errorM(validation.errors);

    String text = validation.map_name;
    for (Integer i = 0; i < List::length(sources); i = i + 1) begin
        let source = sources[i];
        Integer last = source.base + source.width - 1;
        text = irq_map_append_newline(
            text,
            integerToString(source.base)
                + " - " + integerToString(last)
                + "  " + source.name
        );
    end

    return IRQMapDoc_t { text: text };
endmodule

endpackage
