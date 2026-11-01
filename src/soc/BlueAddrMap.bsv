package BlueAddrMap;

import Connectable :: *;
import DefaultValue :: *;
import List :: *;
import ModuleCollect :: *;
import Vector :: *;

import AddrMapDecoder :: *;

typedef struct {
    String name;
} AddrMapDef_t;

typedef struct {
    Bit#(aw) type_anchor;    //unused, only ties the address width to the entry type
    Integer  base;
    Integer  size;
    Bool     is_default;     //takes every address no other target claims, base and size are unused
    String   name;
    endpoint target;
} AddrMapTargetDef_t#(numeric type aw, type endpoint);

typedef union tagged {
    AddrMapDef_t                      AddrMapDef;
    AddrMapTargetDef_t#(aw, endpoint) AddrMapTargetDef;
} AddrMapEntry_t#(numeric type aw, type endpoint);

//a context describes one physical fabric segment, its endpoint type is opaque here and chosen by the protocol generator
//submodules may add targets to the same context, a bridge consumes a separate downstream context, possibly of another protocol
typedef ModuleCollect#(AddrMapEntry_t#(aw, endpoint), ifc) AddrMapCtx_t#(numeric type aw, type endpoint, type ifc);

interface AddrMap_ifc#(numeric type n, numeric type aw, type ifc);
    interface AddrMapDecoder_ifc#(n, aw) decoder;
    interface ifc internal;
endinterface

interface AddrMapWithTargets_ifc#(numeric type n, numeric type aw, type endpoint, type ifc);
    interface AddrMapDecoder_ifc#(n, aw) decoder;
    interface Vector#(n, endpoint) targets;
    interface ifc internal;
endinterface

//everything a fabric generator needs from a context, collected once, in declaration order
typedef struct {
    String               name;
    AddrMap_t#(n)        regions;
    Vector#(n, String)   names;
    Vector#(n, endpoint) targets;
    ifc                  internal;
} AddrMapCollected_t#(numeric type n, type endpoint, type ifc);

typedef struct {
    Bool   valid;
    String errors;
    String map_name;
} AddrMapValidation_t;

typedef struct {
    String text;
} AddrMapDoc_t;

function List#(AddrMapDef_t)                        get_addr_map_def(AddrMapEntry_t#(aw, endpoint) entry)           = entry matches tagged AddrMapDef .x ? Cons(x, Nil) : Nil;
function List#(AddrMapTargetDef_t#(aw, endpoint))   get_addr_map_target_def(AddrMapEntry_t#(aw, endpoint) entry)    = entry matches tagged AddrMapTargetDef .x ? Cons(x, Nil) : Nil;
    
function String                                     get_addr_map_name(AddrMapTargetDef_t#(aw, endpoint) target)     = target.name;
function endpoint                                   get_addr_map_target(AddrMapTargetDef_t#(aw, endpoint) target)   = target.target;
function AddrMapRegion_t                            get_addr_map_region(AddrMapTargetDef_t#(aw, endpoint) target)   = target.is_default ? addr_region_default : addr_region(target.base, target.size);

function String addr_map_append_newline(String acc, String msg);
    if(acc == "") return msg;
    else return acc + "\n" + msg;
endfunction

function String addr_map_integer_to_hex_digit(Integer n) = charToString(integerToHexDigit(n));

function String addr_map_integer_to_hex(Integer n);
    if(n < 16) return addr_map_integer_to_hex_digit(n);
    else return strConcat(addr_map_integer_to_hex(n / 16), addr_map_integer_to_hex_digit(n % 16));
endfunction

function AddrMapValidation_t validate_addr_map_entries(List#(AddrMapEntry_t#(aw, endpoint)) entries);
    let map_defs = List::concat(List::map(get_addr_map_def, entries));
    let targets  = List::concat(List::map(get_addr_map_target_def, entries));

    function String target_label(AddrMapTargetDef_t#(aw, endpoint) target) = "target " + target.name;
    String errors   = addr_map_labeled_errors(List::map(target_label, targets), List::map(get_addr_map_region, targets), valueOf(aw));
    String map_name = "BlueAddrMap";

    if(List::length(map_defs) == 0)
        errors = addr_map_append_newline(errors, "BlueAddrMap validation failed: exactly one addr_map_def is required, found none.");
    else if(List::length(map_defs) > 1)
        errors = addr_map_append_newline(errors, "BlueAddrMap validation failed: exactly one addr_map_def is required, found " + integerToString(List::length(map_defs)) + ".");
    else
        map_name = map_defs[0].name;

    for(Integer i = 0; i < List::length(targets); i = i + 1)
        for(Integer j = i + 1; j < List::length(targets); j = j + 1)
            if(targets[i].name == targets[j].name)
                errors = addr_map_append_newline(errors, "BlueAddrMap validation failed: target name " + targets[i].name + " is defined multiple times.");

    return AddrMapValidation_t { valid: errors == "", errors: errors, map_name: map_name };
endfunction

module addr_map_check_target_count#(String map_name, Integer targets, Integer expected)(Empty);
    if(targets != expected)
        errorM("BlueAddrMap target count mismatch: map " + map_name + " defines " + integerToString(targets) + " targets, but its fabric expects " + integerToString(expected) + ".");
endmodule

module [AddrMapCtx_t#(aw, endpoint)] addr_map_def#(String name)();
    AddrMapEntry_t#(aw, endpoint) entry = tagged AddrMapDef AddrMapDef_t { name: name };
    addToCollection(entry);
endmodule

module [AddrMapCtx_t#(aw, endpoint)] addr_map_target#(Integer base, Integer size, String name, endpoint target)();
    let errors = addr_map_region_errors(Cons(addr_region(base, size), Nil), valueOf(aw));
    if(errors != "") errorM("BlueAddrMap target " + name + ": " + errors);

    AddrMapEntry_t#(aw, endpoint) entry = tagged AddrMapTargetDef AddrMapTargetDef_t { type_anchor: 0, base: base, size: size, is_default: False, name: name, target: target };
    addToCollection(entry);
endmodule

//receives every access that hits no other target, instead of an error response from the fabric
module [AddrMapCtx_t#(aw, endpoint)] addr_map_default#(String name, endpoint target)();
    AddrMapEntry_t#(aw, endpoint) entry = tagged AddrMapTargetDef AddrMapTargetDef_t { type_anchor: 0, base: 0, size: 0, is_default: True, name: name, target: target };
    addToCollection(entry);
endmodule

//elaborates and validates a context exactly once, so devices instantiated inside it exist only once
module [Module] collect_addr_map#(AddrMapCtx_t#(aw, endpoint, ifc) ctx)(AddrMapCollected_t#(n, endpoint, ifc));
    let {map_device, entries} <- getCollection(ctx);
    let target_defs = List::concat(List::map(get_addr_map_target_def, entries));
    let validation  = validate_addr_map_entries(entries);

    if(!validation.valid) errorM(validation.errors);
    addr_map_check_target_count(validation.map_name, List::length(target_defs), valueOf(n));

    return AddrMapCollected_t {
        name:     validation.map_name,
        regions:  toVector(List::map(get_addr_map_region, target_defs)),
        names:    toVector(List::map(get_addr_map_name, target_defs)),
        targets:  toVector(List::map(get_addr_map_target, target_defs)),
        internal: map_device
    };
endmodule

module [Module] create_addr_map#(AddrMapCtx_t#(aw, endpoint, ifc) ctx)(AddrMap_ifc#(n, aw, ifc));
    AddrMapCollected_t#(n, endpoint, ifc) addr_map <- collect_addr_map(ctx);
    AddrMapDecoder_ifc#(n, aw) i_decoder <- mkAddrMapDecoder(addr_map.regions);

    interface decoder  = i_decoder;
    interface internal = addr_map.internal;
endmodule

module [Module] create_addr_map_with_targets#(AddrMapCtx_t#(aw, endpoint, ifc) ctx)(AddrMapWithTargets_ifc#(n, aw, endpoint, ifc));
    AddrMapCollected_t#(n, endpoint, ifc) addr_map <- collect_addr_map(ctx);
    AddrMapDecoder_ifc#(n, aw) i_decoder <- mkAddrMapDecoder(addr_map.regions);

    interface decoder  = i_decoder;
    interface targets  = addr_map.targets;
    interface internal = addr_map.internal;
endmodule

/* bus generation */

//one upstream port, one downstream port per target, and the request addresses that need a select
interface AddrMapRouter_ifc#(numeric type n, numeric type r, numeric type aw, type endpoint, type port);
    interface endpoint up;
    interface Vector#(n, port) down;
    method Vector#(r, Bit#(aw)) route_addr;              //address of every independently routed request channel (AXI: AR, AW)
    method Action route_sel(Vector#(r, Bit#(n)) sel);    //zero or one-hot select for each of those addresses
endinterface

//register stage, every routed request channel carries an arbitrary sideband
//the implementation keeps each sideband in lockstep with its request, through the registers or straight through
interface AddrMapCut_ifc#(numeric type r, numeric type aw, type side, type endpoint, type port);
    interface endpoint up;
    interface port down;
    method Vector#(r, Bit#(aw)) up_addr;              //address of every routed request channel offered upstream
    method Action up_side(Vector#(r, side) sides);    //sideband entering with those requests, don't care when not called
    method Vector#(r, side) down_side;                //sideband of the requests offered downstream
endinterface

//a protocol supplies its router, its cut and a local address view of a target, everything else is generic
//port is the downstream side of router and cut, it connects to an endpoint
typeclass AddrMapFabric#(type endpoint, type port, numeric type r, numeric type aw, type router_cfg, type cut_cfg)
        dependencies(endpoint determines (port, r, aw, router_cfg, cut_cfg));
    module mkAddrMapRouter#(router_cfg cfg)(AddrMapRouter_ifc#(n, r, aw, endpoint, port));
    module mkAddrMapCut#(cut_cfg cfg)(AddrMapCut_ifc#(r, aw, side, endpoint, port))
        provisos(
            Bits#(side, side_w)
        );
    function endpoint addr_map_local(Integer size, endpoint target);
endtypeclass

//cut configurations know when they are a plain connection
typeclass AddrMapCutCfg#(type cut_cfg);
    cut_cfg addr_map_cut_none;
    function Bool addr_map_cut_enabled(cut_cfg cfg);
endtypeclass

//cut configuration for protocols with a single kind of cut
typedef enum { AddrMapCutNone, AddrMapCutFull } AddrMapCut_t deriving(Bits, Eq, FShow);

instance AddrMapCutCfg#(AddrMapCut_t);
    addr_map_cut_none = AddrMapCutNone;
    function Bool addr_map_cut_enabled(AddrMapCut_t cfg) = cfg != AddrMapCutNone;
endinstance

//router configuration for protocols without router settings
typedef enum { AddrMapNoCfg } AddrMapNoCfg_t deriving(Bits, Eq, FShow);

instance DefaultValue#(AddrMapNoCfg_t);
    defaultValue = AddrMapNoCfg;
endinstance

typedef struct {
    router_cfg router;               //protocol specific router settings
    cut_cfg    upstream_cut;         //between the upstream port and the router
    cut_cfg    target_cut;           //between the router and every target, addr_map_target_cut adds one to a single target
    Bool       registered_decode;    //decode at the upstream cut input, the select travels through the cut as sideband
    Bool       local_addr;           //targets see the offset inside their region instead of the global address
} AddrMapBusCfg_t#(type router_cfg, type cut_cfg);

instance DefaultValue#(AddrMapBusCfg_t#(router_cfg, cut_cfg))
    provisos(
        DefaultValue#(router_cfg),
        AddrMapCutCfg#(cut_cfg)
    );
    defaultValue = AddrMapBusCfg_t {
        router:            defaultValue,
        upstream_cut:      addr_map_cut_none,
        target_cut:        addr_map_cut_none,
        registered_decode: False,
        local_addr:        False
    };
endinstance

interface AddrMapBus_ifc#(numeric type n, type endpoint, type ifc);
    interface endpoint up;
    interface ifc internal;
endinterface

//builds the bus of a collected map for any protocol with an AddrMapFabric instance, the endpoint type selects the protocol
module [Module] mkAddrMapBus#(AddrMapBusCfg_t#(router_cfg, cut_cfg) cfg, AddrMapCollected_t#(n, endpoint, ifc) addr_map)(AddrMapBus_ifc#(n, endpoint, ifc))
    provisos(
        AddrMapFabric#(endpoint, port, r, aw, router_cfg, cut_cfg),
        AddrMapCutCfg#(cut_cfg),
        Connectable#(port, endpoint)
    );

    AddrMapDecoder_ifc#(n, aw)                   i_decoder <- mkAddrMapDecoder(addr_map.regions);
    AddrMapRouter_ifc#(n, r, aw, endpoint, port) i_router  <- mkAddrMapRouter(cfg.router);

    /* downstream */

    for(Integer i = 0; i < valueOf(n); i = i + 1) begin
        let region = addr_map.regions[i];
        endpoint target = cfg.local_addr && !region.is_default ? addr_map_local(region.size, addr_map.targets[i]) : addr_map.targets[i];    //the default target always sees the full address
        if(addr_map_cut_enabled(cfg.target_cut)) begin
            AddrMapCut_ifc#(r, aw, Bit#(0), endpoint, port) i_target_cut <- mkAddrMapCut(cfg.target_cut);
            mkConnection(i_target_cut.down, target);
            target = i_target_cut.up;
        end
        mkConnection(i_router.down[i], target);
    end

    /* upstream */

    endpoint upstream   = i_router.up;
    Bool     registered = cfg.registered_decode && addr_map_cut_enabled(cfg.upstream_cut);    //without a cut there is nothing to register the select in

    if(addr_map_cut_enabled(cfg.upstream_cut)) begin
        AddrMapCut_ifc#(r, aw, Bit#(n), endpoint, port) i_upstream_cut <- mkAddrMapCut(cfg.upstream_cut);
        mkConnection(i_upstream_cut.down, i_router.up);
        upstream = i_upstream_cut.up;

        //decoder in front of the cut, its select is registered alongside the request
        if(registered) begin
            (* fire_when_enabled *)
            rule r_decode_registered;
                i_upstream_cut.up_side(Vector::map(i_decoder.select, i_upstream_cut.up_addr));
            endrule

            rule r_route_registered;
                i_router.route_sel(i_upstream_cut.down_side);
            endrule
        end
    end

    //decoder behind the cut, directly at the router
    if(!registered)
        rule r_route;
            i_router.route_sel(Vector::map(i_decoder.select, i_router.route_addr));
        endrule

    interface up       = upstream;
    interface internal = addr_map.internal;
endmodule

module [Module] create_addr_map_bus_cfg#(AddrMapBusCfg_t#(router_cfg, cut_cfg) cfg, AddrMapCtx_t#(aw, endpoint, ifc) ctx)(AddrMapBus_ifc#(n, endpoint, ifc))
    provisos(
        AddrMapFabric#(endpoint, port, r, aw, router_cfg, cut_cfg),
        AddrMapCutCfg#(cut_cfg),
        Connectable#(port, endpoint)
    );
    AddrMapCollected_t#(n, endpoint, ifc) addr_map <- collect_addr_map(ctx);
    AddrMapBus_ifc#(n, endpoint, ifc)     i_bus    <- mkAddrMapBus(cfg, addr_map);
    return i_bus;
endmodule

module [Module] create_addr_map_bus#(AddrMapCtx_t#(aw, endpoint, ifc) ctx)(AddrMapBus_ifc#(n, endpoint, ifc))
    provisos(
        AddrMapFabric#(endpoint, port, r, aw, router_cfg, cut_cfg),
        AddrMapCutCfg#(cut_cfg),
        Connectable#(port, endpoint),
        DefaultValue#(router_cfg)
    );
    AddrMapBus_ifc#(n, endpoint, ifc) i_bus <- create_addr_map_bus_cfg(defaultValue, ctx);
    return i_bus;
endmodule

/* declaration helpers */

//a target behind its own cut, cut is the protocol's cut configuration
module [AddrMapCtx_t#(aw, endpoint)] addr_map_target_cut#(Integer base, Integer size, String name, cut_cfg cut, endpoint target)()
    provisos(
        AddrMapFabric#(endpoint, port, r, aw, router_cfg, cut_cfg),
        Connectable#(port, endpoint)
    );
    AddrMapCut_ifc#(r, aw, Bit#(0), endpoint, port) i_cut <- liftModule(mkAddrMapCut(cut));
    Empty i_connect <- liftModule(mkConnection(i_cut.down, target));
    addr_map_target(base, size, name, i_cut.up);
endmodule

interface AddrMapSubBus_ifc#(numeric type n, type ifc);
    interface ifc internal;
endinterface

//a whole bus of the same protocol as one target, its map uses the addresses the parent forwards
module [AddrMapCtx_t#(aw, endpoint)] addr_map_bus#(Integer base, Integer size, String name, AddrMapBusCfg_t#(router_cfg, cut_cfg) cfg, AddrMapCtx_t#(aw, endpoint, ifc) sub)(AddrMapSubBus_ifc#(n, ifc))
    provisos(
        AddrMapFabric#(endpoint, port, r, aw, router_cfg, cut_cfg),
        AddrMapCutCfg#(cut_cfg),
        Connectable#(port, endpoint)
    );
    AddrMapBus_ifc#(n, endpoint, ifc) i_bus <- liftModule(create_addr_map_bus_cfg(cfg, sub));
    addr_map_target(base, size, name, i_bus.up);
    interface internal = i_bus.internal;
endmodule

//converts an upstream protocol into a downstream one, e.g. AHB to APB
typeclass AddrMapBridge#(type up_endpoint, type down_endpoint);
    module mkAddrMapBridge#(down_endpoint down)(up_endpoint);
endtypeclass

//a whole bus of another protocol behind a bridge as one target
module [AddrMapCtx_t#(aw, endpoint)] addr_map_bridge#(Integer base, Integer size, String name, AddrMapBusCfg_t#(router_cfg, cut_cfg) cfg, AddrMapCtx_t#(sub_aw, sub_endpoint, ifc) sub)(AddrMapSubBus_ifc#(n, ifc))
    provisos(
        AddrMapFabric#(sub_endpoint, port, r, sub_aw, router_cfg, cut_cfg),
        AddrMapCutCfg#(cut_cfg),
        Connectable#(port, sub_endpoint),
        AddrMapBridge#(endpoint, sub_endpoint)
    );
    AddrMapBus_ifc#(n, sub_endpoint, ifc) i_bus    <- liftModule(create_addr_map_bus_cfg(cfg, sub));
    endpoint                              i_bridge <- liftModule(mkAddrMapBridge(i_bus.up));
    addr_map_target(base, size, name, i_bridge);
    interface internal = i_bus.internal;
endmodule

/* devices */

//devices are instantiated inside the map that addresses them, so the map and its devices are declared together
//port selects the endpoint of the device, id for a device that is an endpoint itself

//instantiates a device that serves several targets, add them with addr_map_target
module [AddrMapCtx_t#(aw, endpoint)] addr_map_inst#(Module#(device) mk_device)(device);
    device i_device <- liftModule(mk_device);
    return i_device;
endmodule

module [AddrMapCtx_t#(aw, endpoint)] addr_map_device#(Integer base, Integer size, String name, Module#(device) mk_device, function endpoint port(device d))(device);
    device i_device <- liftModule(mk_device);
    addr_map_target(base, size, name, port(i_device));
    return i_device;
endmodule

module [AddrMapCtx_t#(aw, endpoint)] addr_map_device_cut#(Integer base, Integer size, String name, cut_cfg cut, Module#(device) mk_device, function endpoint port(device d))(device)
    provisos(
        AddrMapFabric#(endpoint, port_t, r, aw, router_cfg, cut_cfg),
        Connectable#(port_t, endpoint)
    );
    device i_device <- liftModule(mk_device);
    addr_map_target_cut(base, size, name, cut, port(i_device));
    return i_device;
endmodule

module [AddrMapCtx_t#(aw, endpoint)] addr_map_device_default#(String name, Module#(device) mk_device, function endpoint port(device d))(device);
    device i_device <- liftModule(mk_device);
    addr_map_default(name, port(i_device));
    return i_device;
endmodule

/* documentation */

//works on a collected map, so the devices of the map are not instantiated a second time
function AddrMapDoc_t doc_addr_map(AddrMapCollected_t#(n, endpoint, ifc) addr_map);
    String text = addr_map.name;
    for(Integer i = 0; i < valueOf(n); i = i + 1) begin
        let region = addr_map.regions[i];
        if(region.is_default)
            text = addr_map_append_newline(text, "default                  " + addr_map.names[i]);
        else
            text = addr_map_append_newline(text, "0x" + addr_map_integer_to_hex(region.base) + " - 0x" + addr_map_integer_to_hex(region.base + region.size - 1) + "  " + addr_map.names[i]);
    end
    return AddrMapDoc_t { text: text };
endfunction

function AddrMapDoc_t doc_addr_map_markdown(AddrMapCollected_t#(n, endpoint, ifc) addr_map);
    String text = "| Base | End | Name |\n| --- | --- | --- |";
    for(Integer i = 0; i < valueOf(n); i = i + 1) begin
        let region = addr_map.regions[i];
        if(region.is_default)
            text = addr_map_append_newline(text, "| default | | " + addr_map.names[i] + " |");
        else
            text = addr_map_append_newline(text, "| 0x" + addr_map_integer_to_hex(region.base) + " | 0x" + addr_map_integer_to_hex(region.base + region.size - 1) + " | " + addr_map.names[i] + " |");
    end
    return AddrMapDoc_t { text: text };
endfunction

endpackage
