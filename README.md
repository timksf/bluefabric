# BlueFabric

BlueFabric provides generic Bluespec interconnect blocks. Public bus interfaces
are `always_ready` and `always_enabled`, so generated Verilog exposes ordinary,
unguarded protocol signals.

## Source layout

| Path | Contents |
| --- | --- |
| `src/axi/` | AXI memory-mapped components and the BlueAXI source link |
| `src/axis/` | AXI Stream interfaces and components |
| `src/apb/` | APB interfaces, adapters, masters, slaves, and muxes |
| `src/ahb/` | AHB-Lite interfaces, transactors, muxes, and the AHB-to-APB bridge |
| `src/common/` | Protocol-independent arbiters and address decoding |
| `src/soc/` | Address-map and interrupt-map construction, validation, decoding, and documentation |
| `src/BlueFabric.bsv` | Aggregate package exporting all public BlueFabric interfaces and modules |

Import `BlueFabric :: *` to use the complete public API without importing each
source package separately.

## AXI4-Lite

| Source file | Module | Latency and behavior |
| --- | --- | --- |
| `axi/Axi4LiteSlaveMux.bsv` | `mkAxi4LiteSlaveMux(max_outstanding, fall_through)`, `mkAxi4LiteSlaveMuxCfg(cfg)` | Direct fabric routing with bounded outstanding reads and writes |
| `axi/Axi4LiteRegSlice.bsv` | `mkAxi4LiteRegSlice(cfg)` | Optional full-throughput register slice, selectable per channel |
| `axi/Axi4Lite.bsv` | `Axi4LiteSlaveFab_ifc`, `Axi4LiteMasterFab_ifc` | Both directions of an AXI4-Lite port as one interface |

`mkAxi4LiteSlaveMux(max_outstanding, fall_through)` takes independent one-hot `Bit#(n)`
masks through `sel_rd` and `sel_wr`; bit `i` selects master port `i`.
Drive both masks every cycle and hold each selection stable while its address
channel is stalled. Addresses, protection, data, and strobes pass through
unchanged. The mux stores only ownership metadata, with no transaction or
payload buffering. Decoding and address translation belong outside the mux.

The positive elaboration-time `max_outstanding` parameter independently bounds
reads from `AR` through `R` and writes from `AW` through `B`. A completed `W`
does not release a write slot. Responses are returned in acceptance order,
including across different targets; younger targets are backpressured until
the oldest response completes. Read and write channels operate independently.

Write data follows address order. Once `AWVALID` supplies its route, `W` may
complete before, with, or after the `AW` handshake; no address or data buffer
is needed. This also supports targets that wait for `WVALID` before asserting
`AWREADY`. A single flag records a `W` that completed before its `AW`; until
that `AW` is accepted, further `W` is backpressured so the next write's data
cannot reach the wrong target. Without an offered address or queued owner, `W`
is backpressured. Zero masks are not forwarded and return `DECERR`; an invalid
write consumes its data before responding.

`mkAxi4LiteSlaveMuxCfg(Axi4LiteSlaveMuxCfg_t)` exposes one more option.
`sel_onehot0 = True` declares that the select never has more than one bit set,
as is guaranteed for an `AddrMapDecoder` output, and removes the multi-hot
detection from the address paths. Without it, multi-hot masks also return
`DECERR`. `defaultValue` is depth 2, registered responses, and checked selects.

The elaboration-time `fall_through` Boolean selects the response latency:

- `True`: with nothing outstanding, a target's response may complete in the
  cycle its request is accepted. A stalled response retains its owner normally.
  The mux's own `DECERR` responses never take this bypass: they always follow
  the request's handshake by one cycle, so the mux itself never answers early.
- `False`: ownership is registered, adding one response cycle and shortening the
  request-to-response path. Addresses and data still pass directly through; no
  payload registers are inserted.

In both modes no downstream `VALID` depends on any `READY`, and no `READY`
depends on another `READY` beyond the unavoidable pass-through
(`ARREADY`/`AWREADY`/`WREADY` upstream from the selected target, `RREADY`/`BREADY`
downstream from the master). Connecting targets whose `ARREADY` depends on
`RREADY` (e.g. `arready = !rvalid_q || rready`) therefore cannot form a
combinational loop. To achieve this in fall-through mode, the mux picks the
response owner from the offered request's select instead of from its handshake,
and may assert `RREADY`/`BREADY` towards that target before it responds; AXI
permits `READY` before `VALID`. A compliant target cannot respond before the
cycle it accepts the request, so no other response can be taken. Fall-through
still has combinational paths from `ARVALID`/`AWVALID`/`WVALID` to
`RVALID`/`BVALID`, which is inherent to same-cycle responses.

Full FIFOs retain registered space flags in both modes: response readiness does
not feed back into address acceptance, and a full slot is reusable the following
cycle. With ready targets, true same-cycle responses, and AW/W offered together,
`fall_through=True` sustains one read and one write per cycle even at depth one.

```bsv
Axi4LiteSlaveMux_ifc#(3, 16, 32) i_mux <- mkAxi4LiteSlaveMux(4, False);
```

`mkAxi4LiteRegSlice(Axi4LiteRegSliceCfg_t)` registers any subset of the five
channels. A registered channel is a two-entry FIFO (skid buffer): `VALID`,
payload, and `READY` all come from registers, throughput stays at one transfer
per cycle, and latency grows by one cycle. Unselected channels are wires. The
presets are `axi4_lite_slice_all` (the `defaultValue`), `axi4_lite_slice_request`
(AR, AW, W), and `axi4_lite_slice_none`. Each channel is a generic
`mkRegSliceChannel` from `common/RegSlice.bsv`, usable for any VALID/READY channel.

In front of an address map, the slice mainly removes paths that run straight
through the fabric (e.g. upstream `AWADDR` through the decoder to `WREADY`),
which would otherwise add to the master's and the targets' own logic. Slicing
all channels removes every input-to-output path. It does not shorten the
decoder and mux logic between the slice and the owner queues. Use it with
`fall_through = False`: in fall-through mode the decoded select drives
`RVALID`/`BVALID` directly, so a request-only slice moves the decoder onto the
response output and makes timing worse.

## APB

| Source file | Module | Latency and behavior |
| --- | --- | --- |
| `apb/Apb.bsv` | Fabric types and interfaces | Parameterized APB4 signals with APB5 user sidebands |
| `apb/ApbMaster.bsv` | `mkApbMaster` | Converts queued requests and responses to APB transfers |
| `apb/ApbSlave.bsv` | `mkApbSlave` | Converts APB transfers to queued requests and responses |
| `apb/ApbSlaveMux.bsv` | `mkApbSlaveMux` | Routes one upstream APB port to multiple downstream slaves |
| `apb/ApbMasterMux.bsv` | `mkApbMasterMux` | Round-robin arbitration from multiple upstream masters to one downstream port |

`mkApbMaster` supports back-to-back setup phases and holds the access phase
through wait states.

`mkApbSlave` optionally pipelines requests through its `pipeline_req`
constructor argument. Its fall-through response path permits completion in
the first access cycle.

`mkApbSlaveMux` forwards the unchanged address and completes decode misses
with `PREADY` and `PSLVERR`. Its pure select function returns a zero or one-hot
`Bit#(n)` and can be `AddrMapDecoder_ifc.select`.

`mkApbMasterMux` retains its round-robin grant through the complete setup and
access transfer, including wait states, and returns the response only to the
selected master.

## AHB-Lite

| Source file | Module | Latency and behavior |
| --- | --- | --- |
| `ahb/Ahb.bsv` | Fabric types and helpers | Parameterized AHB-Lite payloads, protection encoding, burst addressing, and single-request construction |
| `ahb/AhbMaster.bsv` | `mkAhbMaster` | Converts queued requests and responses to pipelined AHB-Lite transfers |
| `ahb/AhbSlave.bsv` | `mkAhbSlave` | Converts pipelined AHB-Lite transfers to queued requests and responses |
| `ahb/AhbSlaveMux.bsv` | `mkAhbSlaveMux` | Routes one upstream AHB-Lite port to multiple downstream slaves |
| `ahb/AhbMasterMux.bsv` | `mkAhbMasterMux` | Round-robin arbitration from multiple upstream masters to one downstream port |
| `ahb/AhbApbBridge.bsv` | `mkAhbApbBridge` | Unbuffered, single-transfer AHB-to-APB bridge |

`mkAhbMaster` accepts `AhbMasterRequest_t` beats carrying `HBURST` and a `last`
marker, and generates `NONSEQ`, `SEQ`, and `BUSY` transfers. `last` must mark
the final beat, including the protocol-defined final beat of a fixed-length
burst. The master reserves response-buffer capacity before accepting an
address phase.

`mkAhbSlave` correlates each accepted address phase with its write-data phase,
optionally pipelines requests through `pipeline_req`, holds wait states, and
generates the required two-cycle `ERROR` response. Its `transfer_request`
interface preserves observed `HTRANS` and `HBURST` metadata for burst-aware
targets.

`mkAhbSlaveMux` decodes the current address phase combinationally with a select
function like `mkApbSlaveMux`, forwards the unchanged address, and records
the selected target for the corresponding data phase. Decode misses and
transfers wider than the data bus receive a two-cycle AHB error response. The
shared `HREADY` is forwarded to every downstream slave.

`mkAhbMasterMux` tracks address and data ownership separately, preserving
full-rate overlapping phases for an uncontended master. Under contention it
changes ownership after a `SINGLE` transfer or fixed-length burst, inserting
one `IDLE` address phase. Fixed-length bursts, locked transfers, wait states,
and `BUSY` cycles are not interleaved; an undefined-length `INCR` retains
ownership until `IDLE`.

`mkAhbApbBridge` captures the AHB address and control phase, drives one APB
setup cycle, and holds the access phase through `PREADY`. Write data remains
cut-through. APB errors and unsupported or misaligned AHB sizes produce a
two-cycle AHB error response.

## Common components

| Source file | Module | Description |
| --- | --- | --- |
| `common/GenericArbiter.bsv` | `mkGenericArbiter` | Parameterized round-robin arbiter with explicit grant retention and release |
| `common/AddrMapDecoder.bsv` | `mkAddrMapDecoder`, `mkAddrMapDecoderFab` | Validates a region vector and produces parallel select bits |
| `common/RegSlice.bsv` | `mkRegSliceChannel` | Register slice (skid buffer) or pass-through for one VALID/READY channel |

A basic address map is a vector of byte regions. Vector entry `i` drives select
bit `i`; no explicit target index, map name, or module-collection context is needed:

```bsv
import AddrMapDecoder :: *;
import BuildVector :: *;

AddrMap_t#(2) cfg_map = vec(
    addr_region('h1000, 'h0100),
    addr_region('h2000, 'h1000)
);
AddrMapDecoder_ifc#(2, 16) i_decoder <- mkAddrMapDecoder(cfg_map);
```

Regions contain only elaboration-time `Integer base` and `Integer size` fields.
Sizes must be positive powers of two, bases naturally aligned, regions disjoint,
and every region inside the decoder's address width. Invalid maps fail during
elaboration. A full-address-space region is representable without truncating its
size, and entries may appear in any order.

Because regions are aligned powers of two, a region matches when the address
bits above its size equal its base: one masked compare per region, with no
adders or magnitude comparators on the address path. `select(address)` packs
these matches into a zero or one-hot `Bit#(n)`. `route(address)` returns
`AddrMapRoute_t` with the same `sel` and the region-local `offset`, for fabrics
that translate addresses themselves (`mkAxi4SlaveMux`). `onehot_select(sel, values)` is the
matching AND-OR multiplexer. Transfer sizes are not part of the decode; a
fabric that needs span checks (AXI4 bursts in `mkAxi4SlaveMux`) performs them
itself.

`mkAddrMapDecoderFab(cfg_map)` exposes the same decoder as
`AddrMapDecoderFab_ifc#(n, aw)`: the `decode(address)` input drives the `sel`
mask in the same cycle.

## SoC maps

| Source file | Module | Description |
| --- | --- | --- |
| `soc/BlueAddrMap.bsv` | `addr_map_def`, `addr_map_target`, `addr_map_default` | Declares a named address map, its targets and an optional default target |
| `soc/BlueAddrMap.bsv` | `addr_map_target_cut`, `addr_map_bus`, `addr_map_bridge` | Declares a target behind its own cut, a nested bus, or a bus of another protocol behind a bridge |
| `soc/BlueAddrMap.bsv` | `addr_map_device`, `addr_map_device_cut`, `addr_map_device_default`, `addr_map_inst` | Instantiates a device inside the map and declares its target |
| `soc/BlueAddrMap.bsv` | `create_addr_map_bus`, `create_addr_map_bus_cfg`, `mkAddrMapBus` | Builds the bus of a map, or of a collected map, for any protocol with an `AddrMapFabric` instance |
| `soc/BlueAddrMap.bsv` | `collect_addr_map`, `create_addr_map`, `create_addr_map_with_targets` | Collects and validates a map, optionally creating its decoder and retaining target interfaces |
| `soc/BlueAddrMap.bsv` | `doc_addr_map`, `doc_addr_map_markdown` | Generates plain-text or Markdown documentation of a collected map |
| `soc/BlueInterruptMap.bsv` | `irq_map_def`, `irq_map_source` | Declares a named interrupt map and its sources |
| `soc/BlueInterruptMap.bsv` | `create_irq_map` | Validates a map and creates the combined interrupt vector |
| `soc/BlueInterruptMap.bsv` | `doc_irq_map` | Generates interrupt-map documentation |
| `soc/Axi4LiteAddrMap.bsv` | `AddrMapFabric` instance, `Axi4LiteBusCfg_t` | AXI4-Lite router (`mkAxi4LiteSlaveMux`) and cuts (`mkAxi4LiteRegSliceSide`) |
| `soc/AhbAddrMap.bsv` | `AddrMapFabric` and AHB-to-APB `AddrMapBridge` instances, `AhbBusCfg_t` | AHB router (`mkAhbSlaveMux`), bridge (`mkAhbApbBridge`) |
| `soc/ApbAddrMap.bsv` | `AddrMapFabric` instance, `ApbBusCfg_t` | APB router (`mkApbSlaveMux`) |

A map is a module in an `AddrMapCtx_t` context whose endpoint type is the
protocol's slave port. The map instantiates the devices it addresses, so the
map and its devices are declared together; whatever else the map wants to
expose is its return interface (`internal`). Every protocol uses the same
declaration style and the same builder, the endpoint type selects the protocol:

```bsv
function Axi4LiteSlaveFab_ifc#(32, 32) uart_port(Uart_ifc u) = u.s_axi;

module [AddrMapCtx_t#(32, Axi4LiteSlaveFab_ifc#(32, 32))] soc_map(SocDevices_ifc);
    addr_map_def("SoC AXI4-Lite");
    Axi4LiteSlaveFab_ifc#(32, 32) rom    <- addr_map_device('h0000_0000, 'h0000_1000, "BOOT_ROM", mkRom, id);
    Uart_ifc                      uart   <- addr_map_device_cut('h4000_0000, 'h0001_0000, "UART", axi4_lite_slice_all, mkUart, uart_port);
    AddrMapSubBus_ifc#(2, Empty)  periph <- addr_map_bus('h5000_0000, 'h1000_0000, "PERIPH", defaultValue, periph_map);    //another map module
    Axi4LiteSlaveFab_ifc#(32, 32) err    <- addr_map_device_default("ERROR", mkErrorSlave, id);

    interface uart_irq = uart.irq;
endmodule

Axi4LiteBusCfg_t cfg = defaultValue;
cfg.upstream_cut      = axi4_lite_slice_request;
cfg.registered_decode = True;
AddrMapBus_ifc#(4, Axi4LiteSlaveFab_ifc#(32, 32), SocDevices_ifc) i_bus <- create_addr_map_bus_cfg(cfg, soc_map);
mkConnection(cpu.m_axi, i_bus.up);
```

`addr_map_device(base, size, name, mk_device, port)` instantiates `mk_device`,
declares `port(device)` as the target and returns the device; `port` is `id`
for a device that is an endpoint itself. `addr_map_device_cut` and
`addr_map_device_default` do the same for a target behind its own cut and for
the default target. A device that serves several targets is instantiated with
`addr_map_inst(mk_device)` and its targets are declared with `addr_map_target`.
Targets can also be passed into the map as arguments and declared with
`addr_map_target`, e.g. when a testbench swaps devices.

`AddrMapBusCfg_t#(router_cfg, cut_cfg)` holds the generic options; each
protocol names its instance, e.g. `Axi4LiteBusCfg_t`:

- `router`: protocol router settings (AXI4-Lite: `max_outstanding`,
  `fall_through`; APB and AHB have none).
- `upstream_cut`: register stage between the upstream port and the router.
  For AXI4-Lite a register slice configuration, e.g. `axi4_lite_slice_request`.
- `target_cut`: register stage in front of every target.
  `addr_map_target_cut(base, size, name, cut, target)` adds one to a single target.
- `registered_decode`: decode in front of the upstream cut, so the select
  travels through the cut as sideband, registered together with the request,
  and the router starts from registers. Without a cut, decoding stays
  combinational.
- `local_addr`: targets see only the offset inside their region. The
  `axi4_lite_local`, `apb_local` and `ahb_local` helpers AND the address with
  the constant `size - 1`, so they cost no logic, and they can also wrap
  individual targets of a hand-built fabric.

`defaultValue` is depth 2, registered responses, no cuts, combinational
decode and global addresses. APB and AHB cuts are not implemented yet and fail
during elaboration when configured.

`addr_map_default(name, target)` receives every access no other target claims,
instead of the fabric's error response. It always sees the full address.
`addr_map_bus` nests a bus of the same protocol as one target; its own map uses
the addresses the parent forwards, i.e. local offsets when the parent has
`local_addr`. `addr_map_bridge` does the same for another protocol through an
`AddrMapBridge` instance (AHB to APB is provided). Both return the nested map's
`internal` interface; their `n` is the nested map's target count.

**Protocol interface.** A protocol only supplies primitives through
`AddrMapFabric#(endpoint, port, r, aw, router_cfg, cut_cfg)`:

- `mkAddrMapRouter(cfg)`: upstream endpoint, `n` downstream ports, the address
  of each of its `r` independently routed request channels (`route_addr`;
  AXI4-Lite: AR and AW) and a select input per channel (`route_sel`).
- `mkAddrMapCut(cfg)`: register stage between an endpoint and a port. Each
  routed request channel carries an arbitrary sideband: `up_addr` is the
  address offered upstream, `up_side` the sideband entering with it and
  `down_side` the sideband of the request offered downstream. The
  implementation keeps the sideband in lockstep with its request.
- `addr_map_local(size, target)`: the local-address view of a target.

`AddrMapCutCfg` says whether a cut configuration is a plain connection.
`mkAddrMapBus` does everything else for every protocol: it builds the shared
decoder, places the cuts, connects the decoder to the router (directly, or in
front of the upstream cut with the select as sideband) and connects the
targets. `create_addr_map_bus_cfg` collects a map and calls it.

Validation errors name the offending targets. The explicit `n` in the bus type
checks that the map contains one target per select bit, in declaration order.
`collect_addr_map(ctx)` elaborates a context exactly once and returns the plain
struct `AddrMapCollected_t` with the map `name`, its `regions`, `targets`, and
`internal` interface; the builders use it so devices declared inside a map
exist only once. To document a map, collect it once and pass the result to
both the documentation and the bus:

```bsv
AddrMapCollected_t#(4, Axi4LiteSlaveFab_ifc#(32, 32), SocDevices_ifc) addr_map <- collect_addr_map(soc_map);
messageM(doc_addr_map(addr_map).text);
AddrMapBus_ifc#(4, Axi4LiteSlaveFab_ifc#(32, 32), SocDevices_ifc) i_bus <- mkAddrMapBus(cfg, addr_map);
```

`create_addr_map` and
`create_addr_map_with_targets` only create the decoder, for hand-built fabrics.

`create_irq_map` validates interrupt-source placement before combining the
source vectors.

## Testing

Tests generate Verilog with `bsc` and run cocotb with cocotbext-axi,
cocotbext-ahb, and Icarus Verilog. SoC map validation runs directly in
Bluesim. First initialize the BlueAXI submodule:

```sh
git submodule update --init --recursive
```

The included Nix flake provides the complete test environment. From the
BlueFabric repository root:

```sh
nix develop ./nix
make test
```

Without Nix, install Bluespec and Icarus Verilog, then install the Python test
dependencies and run the same target:

```sh
python -m pip install -r test/cocotb/requirements.txt
make test
```

Individual `Makefile` targets such as `test-apb-master`, `test-ahb-mux`, and
`test-ahb-apb-bridge` run one component at a time.

The tests are split by kind:

- `test/bsv/`: Bluespec harnesses. They wrap a component for cocotb, or are
  Bluesim tests themselves (`TestSocMaps`, `TestAddrMapBus`).
- `test/cocotb/`: one cocotb module per harness, sharing the helpers in
  `tb.py` (port accessor, reset, protocol constants).
- `test/scripts/`: the elaboration check for invalid address maps.

`make test-axi-lite-mux` runs the BlueAXI compatibility test and a direct-fabric
matrix with 1, 3, and 8 master ports, depths 1, 2, 3, and 8, and both
`fall_through` modes (24 configurations), plus 8 configurations with
`sel_onehot0`. The fabric tests check same-cycle
responses and exactly one added cycle in registered mode, independent channel
stalls, varying per-target response latency,
response ordering, exact outstanding limits, early write data, invalid masks,
reset with pending traffic, and sustained throughput. To run a smaller matrix:

```sh
make test-axi-lite-mux-fabric AXI_MUX_TEST_PORTS=3 AXI_MUX_TEST_DEPTHS="1 3" AXI_MUX_TEST_FALL_THROUGH="0 1"
```

`make test-axi-lite-reg-slice` drives all five channels of the register slice
with random VALID/READY in the all, request-only, and pass-through
configurations. It checks ordering, stability under stall, latency, sustained
throughput, and that registered outputs do not depend combinationally on any input.

`make test-addr-map-decoder` exhaustively checks an 8-bit decoder over all 256
addresses and rejects eight invalid maps during elaboration. `make test-soc-maps`
also exercises an AXI4-Lite address map built with `create_addr_map_bus_cfg`
(request slice, decoder, mux, and `local_addr`) with decoded AXI reads, writes,
and unmapped errors, and checks default targets in the decoder and the
documentation. `make test-addr-map-bus` runs 48 reads and 48 writes through
three AXI4-Lite buses (registered decode with request cuts upstream and at every
target, registered decode with fully cut upstream and fall-through, plain
combinational decode with fall-through). Each map has devices declared inside
it, a per-target cut, a nested bus, and a default target, and every target
stalls in its own pattern. It also runs AHB transfers into an APB bus behind
the AHB-to-APB bridge, including misses on both buses.
