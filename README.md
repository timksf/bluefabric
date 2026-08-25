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
| `axi/Axi4LiteSlaveMux.bsv` | `mkAxi4LiteSlaveMux` | Routes one BlueAXI slave port to multiple master ports, with one outstanding read and write |

`mkAxi4LiteSlaveMux` routes reads and writes independently and holds each
selected response source through its `R` or `B` handshake. It captures the
write address before routing `W`, accepts `WVALID` before `AWVALID`, and
returns `DECERR` after consuming a complete decode-miss transaction. Its pure
decode function can wrap `AddrMapDecoder_ifc.lookup`.

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

`mkApbSlaveMux` passes the decoder-provided offset downstream and completes
decode misses with `PREADY` and `PSLVERR`. Its pure decode function can wrap
`AddrMapDecoder_ifc.lookup`.

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

`mkAhbSlaveMux` decodes the current address phase combinationally and records
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
| `common/AddrMapDecoder.bsv` | `mkAddrMapDecoderFab` | Fabric wrapper for a pure address-map lookup function |

## SoC maps

| Source file | Module | Description |
| --- | --- | --- |
| `soc/BlueAddrMap.bsv` | `addr_map_def`, `addr_map_target` | Declares a named address map and its targets |
| `soc/BlueAddrMap.bsv` | `create_addr_map`, `create_addr_map_with_targets` | Validates a map and creates its decoder, optionally retaining target interfaces |
| `soc/BlueAddrMap.bsv` | `doc_addr_map`, `doc_addr_map_markdown` | Generates plain-text or Markdown address-map documentation |
| `soc/BlueInterruptMap.bsv` | `irq_map_def`, `irq_map_source` | Declares a named interrupt map and its sources |
| `soc/BlueInterruptMap.bsv` | `create_irq_map` | Validates a map and creates the combined interrupt vector |
| `soc/BlueInterruptMap.bsv` | `doc_irq_map` | Generates interrupt-map documentation |
| `soc/AhbAddrMap.bsv` | `create_ahb_addr_map` | Connects an address map to an AHB slave mux |
| `soc/ApbAddrMap.bsv` | `create_apb_addr_map` | Connects an address map to an APB slave mux |

`create_addr_map` validates target sizes, alignment, address-space bounds,
names, and overlap. Slave muxes accept the same pure `decode(address, bytes)`
signature, so an SoC can wrap the resulting `decoder.lookup` method in a local
function. Targets remain explicitly connected in declaration order.

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
python -m pip install -r test/requirements.txt
make test
```

Individual `Makefile` targets such as `test-register`, `test-crossbar`,
`test-apb-master`, and `test-ahb-apb-bridge` run one component at a time.
