"""Cycle-level checks of mkAxi4LiteSlaveMux through its raw fabric ports, with no BlueAXI transactors in the DUT.

mkTestAxi4LiteFabric exposes the upstream port (s_rd_*, s_wr_*), one downstream port per target (m_rd_<i>_*, m_wr_<i>_*)
and the select inputs sel_rd/sel_wr. The test drives the clock itself, so every cycle has fixed phases:

    0 ns  CLK low, upstream inputs and the registered outputs of the target models are driven
    2 ns  targets that couple READY to VALID react (write_ready_mode)
    3 ns  targets that answer in the same cycle drive R/B (combinational)
    5 ns  every port is sampled and checked against the reference model
    5 ns  CLK high, the sampled handshakes take effect in the model

The reference model (Fabric) tracks outstanding reads and writes in order, which target owes each response, and what
every target model holds. The configuration comes from the environment: AXI_MUX_TEST_DEPTH (max_outstanding),
AXI_MUX_TEST_FALL_THROUGH and AXI_MUX_TEST_ONEHOT0.
"""

import os
import random
from collections import deque
from dataclasses import dataclass

import cocotb
from cocotb.triggers import Timer

from tb import DECERR

# upstream signals per direction, driven by the test (request) or by the mux (response)
READ_REQUEST = ("arvalid", "araddr", "arprot", "rready")
READ_RESPONSE = ("arready", "rvalid", "rdata", "rresp")
WRITE_REQUEST = ("awvalid", "awaddr", "awprot", "wvalid", "wdata", "wstrb", "bready")
WRITE_RESPONSE = ("awready", "wready", "bvalid", "bresp")
PAYLOAD = {
    "ar": ("araddr", "arprot"),
    "r": ("rdata", "rresp"),
    "aw": ("awaddr", "awprot"),
    "w": ("wdata", "wstrb"),
    "b": ("bresp",),
}


def selected_port(mask):
    """The target of a one-hot select, None for zero or several bits (a DECERR)."""
    return mask.bit_length() - 1 if mask and not mask & (mask - 1) else None


# responses of the target models, they encode port, address and protection so a misrouted response shows up
def read_result(port, address, protection):
    return 0x80000000 | port << 24 | protection << 20 | address, (0, 2, 3)[port % 3]


def write_result(port, address, protection):
    return (0, 2, 3)[(port + (address >> 2) + protection) % 3]


@dataclass
class Read:
    owner: int | None    # target that owes the response, None for a DECERR
    data: int
    resp: int


@dataclass
class Write:
    owner: int | None
    address: int
    protection: int
    data_done: bool      # W was accepted


class Target:
    """What one target model holds."""

    def __init__(self):
        self.reads = deque()       # (cycle the response is ready, rdata, rresp)
        self.addresses = deque()   # (awaddr, awprot) waiting for W
        self.data = deque()        # (wdata, wstrb) waiting for AW
        self.responses = deque()   # (cycle the response is ready, bresp)

    def idle(self):
        return not (self.reads or self.addresses or self.data or self.responses)


def port_signals(dut, side, index=None):
    """Signals of the upstream port (side "s", s_rd_<name>) or of downstream port index (side "m", m_rd_<index>_<name>)."""
    port = "" if index is None else f"_{index}"
    return {name: getattr(dut, f"{side}_{direction}{port}_{name}") for direction, names in (("rd", READ_REQUEST + READ_RESPONSE), ("wr", WRITE_REQUEST + WRITE_RESPONSE)) for name in names}


class Fabric:
    def __init__(self, dut):
        self.dut = dut
        self.ports = len(dut.sel_rd)
        self.depth = int(os.environ["AXI_MUX_TEST_DEPTH"])
        self.fall_through = bool(int(os.environ.get("AXI_MUX_TEST_FALL_THROUGH", "1")))
        self.onehot0 = bool(int(os.environ.get("AXI_MUX_TEST_ONEHOT0", "0")))    # the caller guarantees at most one select bit
        self.multi_hot = self.ports > 1 and not self.onehot0                         # several select bits are a legal input
        self.upstream = port_signals(dut, "s")
        self.downstream = [port_signals(dut, "m", i) for i in range(self.ports)]
        self.inputs = dict.fromkeys(READ_REQUEST + WRITE_REQUEST, 0)
        self.inputs.update(sel_rd=0, sel_wr=0)
        self.cycle = 0

        # target model behaviour, tests replace these
        self.ready = lambda channel, port, cycle: True      # AR/AW/W READY
        self.latency = lambda channel, port, cycle: 0       # cycles until R/B
        self.write_ready_mode = "independent"               # "together": AWREADY = WVALID and WREADY = AWVALID, "data_first": AWREADY once W arrived
        self.combinational = False                          # True or a predicate on the port: answer in the handshake cycle
        self.clear()

    def clear(self):
        self.reads = deque()        # outstanding reads in order, Read
        self.writes = deque()       # outstanding writes in order, Write
        self.data_owners = deque()  # writes whose W is still due, in order
        self.targets = [Target() for _ in range(self.ports)]
        self.stalled = {}           # payload of every channel stalled with VALID and without READY
        self.read_cycles = []       # cycles of the AR handshakes
        self.write_cycles = []      # cycles of the AW handshakes
        self.read_done = 0
        self.write_done = 0
        self.peak_reads = 0
        self.peak_writes = 0
        self.concurrent = 0         # cycles with an AR and an AW handshake
        self.early_data = False     # W was accepted for the offered AW before its handshake
        self.early_handshakes = 0
        self.younger_reads = 0      # cycles a younger R was held back
        self.younger_writes = 0     # cycles a younger B was held back

    async def reset(self):
        self.dut.RST_N.value = 0
        self.inputs = dict.fromkeys(self.inputs, 0)
        self.clear()
        for _ in range(3):
            await self.tick(check=False)
        for name in ("arready", "rvalid", "awready", "wready", "bvalid"):
            assert not int(self.upstream[name].value), f"{name} asserted during reset"
        for port in self.downstream:
            for name in ("arvalid", "rready", "awvalid", "wvalid", "bready"):
                assert not int(port[name].value), f"{name} asserted during reset"
        self.dut.RST_N.value = 1
        await self.tick()

    async def tick(self, check=True):
        """One clock cycle, returns the sampled (upstream, downstream) values when checking."""
        self.dut.CLK.value = 0
        self.drive_inputs()
        self.drive_registered_targets()
        await Timer(2, "ns")
        self.drive_coupled_ready()
        await Timer(1, "ns")
        self.drive_same_cycle_responses()
        await Timer(2, "ns")

        sample = None
        if check:
            upstream = {name: int(signal.value) for name, signal in self.upstream.items()}
            downstream = [{name: int(signal.value) for name, signal in port.items()} for port in self.downstream]
            self.check(upstream, downstream)
            sample = upstream, downstream

        self.dut.CLK.value = 1
        await Timer(5, "ns")
        if check:
            self.update_targets(downstream)
        self.cycle += 1
        return sample

    def drive_inputs(self):
        for name, value in self.inputs.items():
            handle = getattr(self.dut, name) if name.startswith("sel_") else self.upstream[name]
            handle.value = value

    def drive_registered_targets(self):
        for i, port in enumerate(self.downstream):
            target = self.targets[i]
            rvalid = bool(target.reads and target.reads[0][0] <= self.cycle)
            bvalid = bool(target.responses and target.responses[0][0] <= self.cycle)
            values = {
                "arready": int(self.ready("ar", i, self.cycle)),
                "awready": int(self.ready("aw", i, self.cycle)),
                "wready": int(self.ready("w", i, self.cycle)),
                "rvalid": int(rvalid),
                "rdata": target.reads[0][1] if rvalid else 0,
                "rresp": target.reads[0][2] if rvalid else 0,
                "bvalid": int(bvalid),
                "bresp": target.responses[0][1] if bvalid else 0,
            }
            for name, value in values.items():
                port[name].value = value

    def drive_coupled_ready(self):
        for i, port in enumerate(self.downstream):
            if self.write_ready_mode == "together":
                port["awready"].value = int(port["wvalid"].value)
                port["wready"].value = int(port["awvalid"].value)
            elif self.write_ready_mode == "data_first":
                port["awready"].value = int(bool(self.targets[i].data))

    def drive_same_cycle_responses(self):
        if not self.combinational:
            return
        for i, port in enumerate(self.downstream):
            if callable(self.combinational) and not self.combinational(i):
                continue
            target = self.targets[i]
            ar = int(port["arvalid"].value) and int(port["arready"].value)
            aw = int(port["awvalid"].value) and int(port["awready"].value)
            w = int(port["wvalid"].value) and int(port["wready"].value)
            if not target.reads and ar:
                data, resp = read_result(i, int(port["araddr"].value), int(port["arprot"].value))
                port["rvalid"].value = 1
                port["rdata"].value = data
                port["rresp"].value = resp
            if target.addresses:
                address = target.addresses[0]
            elif aw:
                address = int(port["awaddr"].value), int(port["awprot"].value)
            else:
                address = None
            if not target.responses and address is not None and (target.data or w):
                port["bvalid"].value = 1
                port["bresp"].value = write_result(i, *address)

    def update_targets(self, downstream):
        """Applies the handshakes sampled before the clock edge to the target models."""
        for i, port in enumerate(downstream):
            target = self.targets[i]
            if port["arvalid"] and port["arready"]:
                data, resp = read_result(i, port["araddr"], port["arprot"])
                target.reads.append((self.cycle + self.latency("r", i, self.cycle), data, resp))
            if port["awvalid"] and port["awready"]:
                target.addresses.append((port["awaddr"], port["awprot"]))
            if port["wvalid"] and port["wready"]:
                target.data.append((port["wdata"], port["wstrb"]))
            if target.addresses and target.data:
                address, protection = target.addresses.popleft()
                target.data.popleft()
                target.responses.append((self.cycle + self.latency("b", i, self.cycle), write_result(i, address, protection)))
            if port["rvalid"] and port["rready"]:
                target.reads.popleft()
            if port["bvalid"] and port["bready"]:
                target.responses.popleft()

    # checks against the reference model, in the order the mux sees the cycle

    def check(self, upstream, downstream):
        self.check_stable("upstream", upstream)
        for i, port in enumerate(downstream):
            if port["rvalid"] and self.reads and self.reads[0].owner != i:
                assert not port["rready"], "younger read response accepted out of order"
                self.younger_reads += 1
            if port["bvalid"] and self.writes and self.writes[0].owner != i:
                assert not port["bready"], "younger write response accepted out of order"
                self.younger_writes += 1
            self.check_stable(i, port)
        if len(self.reads) == self.depth:
            assert not upstream["arready"], "read limit exceeded, or ready feeds through a full FIFO"
        if len(self.writes) == self.depth:
            assert not upstream["awready"], "write slot released before B, or ready feeds through a full FIFO"

        self.check_requests(upstream, downstream)
        self.check_write_data(upstream, downstream)
        self.check_response_ready(upstream, downstream)
        self.check_responses(upstream)

        self.peak_reads = max(self.peak_reads, len(self.reads))
        self.peak_writes = max(self.peak_writes, len(self.writes))
        assert len(self.reads) <= self.depth and len(self.writes) <= self.depth
        self.concurrent += int(upstream["arvalid"] and upstream["arready"] and upstream["awvalid"] and upstream["awready"])

    def check_stable(self, name, signals):
        """A stalled channel keeps VALID and its payload until READY."""
        for channel in PAYLOAD:
            valid = signals[f"{channel}valid"]
            ready = signals[f"{channel}ready"]
            payload = tuple(signals[field] for field in PAYLOAD[channel])
            key = (name, channel)
            if key in self.stalled:
                assert valid and payload == self.stalled[key], f"{key} changed while stalled"
            if valid and not ready:
                self.stalled[key] = payload
            else:
                self.stalled.pop(key, None)

    def check_requests(self, upstream, downstream):
        """AR and AW reach only the selected target, unbuffered, and every accepted one becomes outstanding."""
        for channel, select in (("ar", "sel_rd"), ("aw", "sel_wr")):
            selected = selected_port(self.inputs[select])
            accepted = upstream[f"{channel}valid"] and upstream[f"{channel}ready"]
            forwarded = []
            for i, port in enumerate(downstream):
                if port[f"{channel}valid"]:
                    assert upstream[f"{channel}valid"] and selected == i
                    for field in PAYLOAD[channel]:
                        assert port[field] == upstream[field], f"{field} was buffered or translated"
                    if port[f"{channel}ready"]:
                        forwarded.append(i)
            assert forwarded == ([selected] if accepted and selected is not None else [])
            if not accepted:
                continue

            if channel == "ar":
                data, resp = (0, DECERR) if selected is None else read_result(selected, upstream["araddr"], upstream["arprot"])
                self.reads.append(Read(selected, data, resp))
                self.read_cycles.append(self.cycle)
            else:
                write = Write(selected, upstream["awaddr"], upstream["awprot"], data_done=self.early_data)
                self.writes.append(write)
                if not self.early_data:
                    self.data_owners.append(write)
                self.early_data = False
                self.write_cycles.append(self.cycle)

    def check_write_data(self, upstream, downstream):
        """W goes to the oldest write still waiting for data, or to the offered AW before its handshake (unbuffered)."""
        owner = self.data_owners[0].owner if self.data_owners else selected_port(self.inputs["sel_wr"])
        forwarded = []
        for i, port in enumerate(downstream):
            if port["wvalid"]:
                assert upstream["wvalid"] and owner == i
                assert (port["wdata"], port["wstrb"]) == (upstream["wdata"], upstream["wstrb"])
                if port["wready"]:
                    forwarded.append(i)

        if not (upstream["wvalid"] and upstream["wready"]):
            assert not forwarded
            return
        assert forwarded == ([] if owner is None else [owner])
        if self.data_owners:
            self.data_owners.popleft().data_done = True
        else:
            assert upstream["awvalid"], "W accepted without an offered AW"
            assert not self.early_data, "multiple W beats accepted for a stalled AW"
            self.early_data = True
            self.early_handshakes += 1

    def check_response_ready(self, upstream, downstream):
        """RREADY/BREADY only reach the target that owes the oldest response.

        In fall-through mode they may lead it: towards the offered request when nothing is outstanding, or towards the
        oldest write before its W. AXI allows READY before VALID, and no other response can be pending.
        """
        for i, port in enumerate(downstream):
            if port["rready"]:
                assert upstream["rready"]
                if self.reads:
                    assert self.reads[0].owner == i, "RREADY to a target that owes no response"
                else:
                    assert self.fall_through and upstream["arvalid"] and selected_port(self.inputs["sel_rd"]) == i, "RREADY with no outstanding or offered read"
            if port["bready"]:
                assert upstream["bready"]
                if self.writes:
                    assert self.writes[0].owner == i, "BREADY to a target that owes no response"
                    assert self.writes[0].data_done or self.fall_through, "BREADY before W"
                else:
                    assert self.fall_through and upstream["awvalid"] and selected_port(self.inputs["sel_wr"]) == i, "BREADY with no outstanding or offered write"

    def check_responses(self, upstream):
        """R and B arrive in request order with the response of the right target, or DECERR."""
        if upstream["rvalid"]:
            assert self.reads, "response with no read owner"
            oldest = self.reads[0]
            assert (upstream["rdata"], upstream["rresp"]) == (oldest.data, oldest.resp), "read response reordered or corrupted"
            if upstream["rready"]:
                self.reads.popleft()
                self.read_done += 1
        if upstream["bvalid"]:
            assert self.writes and self.writes[0].data_done, "B before W or without an owner"
            oldest = self.writes[0]
            expected = DECERR if oldest.owner is None else write_result(oldest.owner, oldest.address, oldest.protection)
            assert upstream["bresp"] == expected, "write response reordered or corrupted"
            if upstream["bready"]:
                self.writes.popleft()
                self.write_done += 1

    def targets_idle(self):
        return all(target.idle() for target in self.targets)

    async def drain(self):
        """Stops new requests and accepts every outstanding response."""
        self.inputs.update(arvalid=0, awvalid=0, wvalid=0, rready=1, bready=1)
        for _ in range(2000):
            await self.tick()
            if not self.reads and not self.writes:
                for _ in range(3):
                    await self.tick()
                assert self.targets_idle()
                assert not self.early_data
                return
        raise AssertionError("draining outstanding responses timed out")


# traffic

def transactions(fabric, count, rng, invalid=True):
    """Random reads and writes, with zero and multi-hot selects (DECERR) mixed in when invalid."""
    def select(i):
        if invalid and i % 13 == 4:
            return 0
        if invalid and i % 13 == 9 and fabric.multi_hot:
            return 3 | (1 << (fabric.ports - 1))
        return 1 << rng.randrange(fabric.ports)

    reads = [(select(i), rng.randrange(0x10000), rng.randrange(8)) for i in range(count)]
    writes = [(select(i), rng.randrange(0x10000), rng.randrange(8), rng.getrandbits(32), rng.randrange(16)) for i in range(count)]
    return reads, writes


async def stream(fabric, reads, writes, rng, gaps=True):
    """Offers AR, AW and W independently, with random gaps and response backpressure, until everything completed."""
    sequences = dict(ar=reads, aw=writes, w=writes)
    index = dict(ar=0, aw=0, w=0)
    offered = dict(ar=False, aw=False, w=False)
    for _ in range(30000):
        for channel, sequence in sequences.items():
            if not offered[channel] and index[channel] < len(sequence) and (not gaps or rng.random() < 0.7):
                offered[channel] = True
            fabric.inputs[f"{channel}valid"] = int(offered[channel])
            if not offered[channel]:
                continue
            transaction = sequence[index[channel]]
            if channel == "ar":
                fabric.inputs.update(sel_rd=transaction[0], araddr=transaction[1], arprot=transaction[2])
            elif channel == "aw":
                fabric.inputs.update(sel_wr=transaction[0], awaddr=transaction[1], awprot=transaction[2])
            else:
                fabric.inputs.update(wdata=transaction[3], wstrb=transaction[4])
        fabric.inputs.update(rready=int(not gaps or rng.random() < 0.65), bready=int(not gaps or rng.random() < 0.6))

        upstream, _ = await fabric.tick()
        for channel in index:
            if upstream[f"{channel}valid"] and upstream[f"{channel}ready"]:
                index[channel] += 1
                offered[channel] = False

        if all(index[channel] == len(sequences[channel]) for channel in index) and not fabric.reads and not fabric.writes:
            fabric.inputs.update(arvalid=0, awvalid=0, wvalid=0)
            for _ in range(3):
                await fabric.tick()
            assert fabric.read_done == len(reads) and fabric.write_done == len(writes)
            assert fabric.targets_idle()
            assert not fabric.early_data
            return
    raise AssertionError(f"stream timed out: {index}, R={len(fabric.reads)}, B={len(fabric.writes)}")


# tests, each starts from reset

@cocotb.test()
async def response_timing(dut):
    """Fall-through answers in the handshake cycle, registered mode adds exactly one cycle."""
    fabric = Fabric(dut)
    fabric.combinational = True
    await fabric.reset()

    if not fabric.fall_through:
        fabric.inputs.update(arvalid=1, awvalid=1, wvalid=1, sel_rd=1, sel_wr=1, araddr=0x1234, awaddr=0x5678, wdata=0xABCDEF01, wstrb=0xF, rready=1, bready=1)
        upstream, _ = await fabric.tick()
        assert upstream["arready"] and upstream["awready"] and upstream["wready"]
        assert not upstream["rvalid"] and not upstream["bvalid"], "registered mode bypassed its owner queues"
        fabric.inputs.update(arvalid=0, awvalid=0, wvalid=0, sel_rd=0, sel_wr=0)
        upstream, _ = await fabric.tick()
        assert upstream["rvalid"] and upstream["bvalid"], "registered mode added more than one response cycle"
        assert fabric.read_done == fabric.write_done == 1
        await fabric.drain()
        return

    # empty owner queues must be bypassed, also at depth one, without leaking slots
    fabric.inputs.update(arvalid=1, awvalid=1, wvalid=1, rready=1, bready=1)
    for i in range(40):
        fabric.inputs.update(sel_rd=1 << (i % fabric.ports), sel_wr=1 << ((i + 1) % fabric.ports), araddr=i * 4, arprot=i % 8, awaddr=0x8000 + i * 4, awprot=(i + 2) % 8, wdata=0x12340000 + i, wstrb=i % 16)
        upstream, _ = await fabric.tick()
        assert all(upstream[name] for name in ("arready", "rvalid", "awready", "wready", "bvalid")), "an empty owner FIFO added a response cycle"
        assert not fabric.reads and not fabric.writes
    assert fabric.read_done == fabric.write_done == 40

    # a bypassed owner is kept when the same-cycle response stalls
    fabric.inputs.update(rready=0, bready=0, araddr=0x2468, awaddr=0x1357)
    upstream, _ = await fabric.tick()
    assert upstream["arready"] and upstream["awready"] and upstream["wready"]
    assert upstream["rvalid"] and upstream["bvalid"]
    fabric.inputs.update(arvalid=0, awvalid=0, wvalid=0, sel_rd=0, sel_wr=0, araddr=0, awaddr=0)
    for _ in range(5):
        upstream, _ = await fabric.tick()
        assert upstream["rvalid"] and upstream["bvalid"]
    await fabric.drain()
    assert fabric.read_done == fabric.write_done == 41

    # a DECERR comes from the mux itself and never takes the bypass, it follows its request's handshake by one cycle
    for mask in (0, 3) if fabric.multi_hot else (0,):
        fabric.inputs.update(arvalid=1, awvalid=1, wvalid=1, sel_rd=mask, sel_wr=mask)
        upstream, _ = await fabric.tick()
        assert upstream["arready"] and upstream["awready"] and upstream["wready"]
        assert not upstream["rvalid"] and not upstream["bvalid"], "DECERR in the request's handshake cycle"
        fabric.inputs.update(arvalid=0, awvalid=0, wvalid=0)
        upstream, _ = await fabric.tick()
        assert upstream["rvalid"] and upstream["rresp"] == DECERR
        assert upstream["bvalid"] and upstream["bresp"] == DECERR
    await fabric.drain()


@cocotb.test()
async def mixed_response_latency(dut):
    """Immediate and delayed targets mixed, with younger responses waiting and independent stalls."""
    fabric = Fabric(dut)
    await fabric.reset()
    rng = random.Random(0xB1A55)
    fabric.combinational = lambda port: port % 2 == 0
    fabric.ready = lambda channel, port, cycle: rng.random() < 0.7
    fabric.latency = lambda channel, port, cycle: 0 if port % 2 == 0 else 11
    reads, writes = transactions(fabric, 250, rng)
    await stream(fabric, reads, writes, rng)


@cocotb.test()
async def forwards_without_buffering(dut):
    """Requests wait at the targets, not in the mux: AR/AW/W stay offered downstream until the target takes them."""
    fabric = Fabric(dut)
    await fabric.reset()
    fabric.ready = lambda channel, port, cycle: False
    fabric.inputs.update(arvalid=1, araddr=0xFFFE, arprot=7, sel_rd=1, awvalid=1, awaddr=0x1357, awprot=5, sel_wr=1 << (fabric.ports - 1), wvalid=1, wdata=0x12345678, wstrb=5)
    for _ in range(6):
        upstream, downstream = await fabric.tick()
        assert not upstream["arready"] and not upstream["awready"] and not upstream["wready"]
        assert downstream[0]["arvalid"] and downstream[-1]["awvalid"] and downstream[-1]["wvalid"]

    fabric.ready = lambda channel, port, cycle: channel != "w"
    upstream, _ = await fabric.tick()
    assert upstream["arready"] and upstream["awready"]
    fabric.inputs.update(arvalid=0, awvalid=0, araddr=0, awaddr=0, sel_rd=0, sel_wr=0)
    for _ in range(6):
        upstream, downstream = await fabric.tick()
        assert not upstream["wready"] and downstream[-1]["wvalid"]
        assert not upstream["bvalid"]

    fabric.ready = lambda channel, port, cycle: True
    upstream, _ = await fabric.tick()
    assert upstream["wready"]
    fabric.inputs["wvalid"] = 0
    for _ in range(6):
        await fabric.tick()
    await fabric.drain()
    assert fabric.read_done == fabric.write_done == 1


@cocotb.test()
async def outstanding_limits(dut):
    """Exactly max_outstanding reads and writes, and a write slot is only released by its B."""
    fabric = Fabric(dut)
    await fabric.reset()

    # fill both queues while withholding W and both response handshakes
    for i in range(fabric.depth):
        fabric.inputs.update(arvalid=1, araddr=0x100 + i * 4, arprot=i % 8, awvalid=1, awaddr=0x200 + i * 4, awprot=(i + 3) % 8, sel_rd=1 << (i % fabric.ports), sel_wr=1 << ((i + 1) % fabric.ports))
        upstream, _ = await fabric.tick()
        assert upstream["arready"] and upstream["awready"]
    for _ in range(5):
        upstream, _ = await fabric.tick()
        assert not upstream["arready"] and not upstream["awready"]

    # W does not release capacity, it is reserved until B
    fabric.inputs.update(wvalid=1, wdata=0xFEDCBA98, wstrb=0xA)
    for _ in range(fabric.depth):
        upstream, _ = await fabric.tick()
        assert upstream["wready"] and not upstream["awready"]
    fabric.inputs["wvalid"] = 0
    for _ in range(5):
        upstream, _ = await fabric.tick()
        assert not upstream["awready"]
    assert fabric.peak_reads == fabric.depth and fabric.peak_writes == fabric.depth

    # responses free the slots, the stalled extra requests complete before VALID is withdrawn
    fabric.inputs.update(rready=1, bready=1)
    for _ in range(20):
        upstream, _ = await fabric.tick()
        for channel in ("ar", "aw"):
            if upstream[f"{channel}valid"] and upstream[f"{channel}ready"]:
                fabric.inputs[f"{channel}valid"] = 0
        if not fabric.inputs["arvalid"] and not fabric.inputs["awvalid"]:
            break
    else:
        raise AssertionError("capacity did not recover after response handshakes")

    fabric.inputs["wvalid"] = 1
    for _ in range(20):
        upstream, _ = await fabric.tick()
        if upstream["wready"]:
            fabric.inputs["wvalid"] = 0
            break
    else:
        raise AssertionError("extra write data did not complete")
    await fabric.drain()
    assert fabric.read_done == fabric.depth + 1 and fabric.write_done == fabric.depth + 1


@cocotb.test()
async def ignores_unowed_responses(dut):
    """Responses of targets that owe nothing are neither forwarded nor accepted."""
    fabric = Fabric(dut)
    await fabric.reset()
    for target in fabric.targets:
        target.reads.append((0, 0xDEADBEEF, 2))
        target.responses.append((0, 2))
    fabric.inputs.update(rready=1, bready=1)
    for _ in range(3):
        upstream, downstream = await fabric.tick()
        assert not upstream["rvalid"] and not upstream["bvalid"]
        assert not any(port["rready"] or port["bready"] for port in downstream)


@cocotb.test()
async def write_ready_coupling(dut):
    """Targets that couple AWREADY and WREADY, or take W before AW, which exercises W before the AW handshake."""
    fabric = Fabric(dut)
    for mode in ("together", "data_first"):
        await fabric.reset()
        fabric.write_ready_mode = mode
        rng = random.Random(0xA420)
        reads, writes = transactions(fabric, 80, rng)
        await stream(fabric, reads, writes, rng)
        if mode == "data_first":
            assert fabric.early_handshakes > 0, "the W before AW handshake path was not exercised"


@cocotb.test()
async def ordering_under_latency(dut):
    """A long-latency oldest response blocks READY to younger responses of other targets."""
    fabric = Fabric(dut)
    concurrent = {}
    for latency in (0, 3, 17):
        rng = random.Random(0xA410 + latency)
        await fabric.reset()
        fabric.ready = lambda channel, port, cycle: rng.random() < 0.65
        fabric.latency = lambda channel, port, cycle: latency * (fabric.ports - port) + rng.randrange(5)
        reads, writes = transactions(fabric, 250, rng)
        await stream(fabric, reads, writes, rng)
        concurrent[latency] = fabric.concurrent
        if latency == 17 and fabric.ports > 1 and fabric.depth > 1:
            assert fabric.younger_reads > 0 and fabric.younger_writes > 0

    # read and write are independent, with long latencies both are mostly idle, so only the dense stream must overlap
    dut._log.info("same-cycle AR+AW acceptances per latency: %s", concurrent)
    assert concurrent[0] > 0, "read and write address acceptance was unnecessarily serialized"


@cocotb.test()
async def sustained_throughput(dut):
    """With two or more slots and immediate targets, one request per cycle on AR and AW."""
    fabric = Fabric(dut)
    await fabric.reset()
    rng = random.Random(0xFAB)
    reads, writes = transactions(fabric, 80, rng, invalid=False)
    await stream(fabric, reads, writes, rng, gaps=False)
    if fabric.depth >= 2:
        assert all(b - a == 1 for a, b in zip(fabric.read_cycles, fabric.read_cycles[1:]))
        assert all(b - a == 1 for a, b in zip(fabric.write_cycles, fabric.write_cycles[1:]))


@cocotb.test()
async def reset_with_pending_traffic(dut):
    """Reset clears outstanding owners, addresses waiting for W, and W accepted before a stalled AW."""
    fabric = Fabric(dut)
    rng = random.Random(0x5E7)

    await fabric.reset()
    for i in range(fabric.depth):
        fabric.inputs.update(arvalid=1, awvalid=1, sel_rd=1, sel_wr=1, araddr=i * 4, awaddr=i * 4)
        await fabric.tick()
    fabric.inputs.update(arvalid=0, awvalid=0, wvalid=1, wdata=0xFFFF0000, wstrb=0xF)
    await fabric.tick()
    await fabric.reset()
    reads, writes = transactions(fabric, 30, rng)
    await stream(fabric, reads, writes, rng)

    await fabric.reset()
    fabric.ready = lambda channel, port, cycle: channel != "aw"
    fabric.inputs.update(awvalid=1, sel_wr=1, wvalid=1, wdata=0xAAAAAAAA, wstrb=3)
    upstream, _ = await fabric.tick()
    assert upstream["wready"] and not upstream["awready"]
    fabric.inputs["wvalid"] = 0
    await fabric.tick()
    await fabric.reset()
    fabric.ready = lambda channel, port, cycle: True
    reads, writes = transactions(fabric, 20, rng)
    await stream(fabric, reads, writes, rng)
