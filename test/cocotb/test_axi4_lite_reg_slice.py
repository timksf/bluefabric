"""Cycle-level checks of mkAxi4LiteRegSlice, all five channels at once."""

import os
import random
from collections import deque

import cocotb
from cocotb.triggers import Timer


# channel: (source prefix, sink prefix, payload fields with widths)
CHANNELS = {
    "ar": ("s_rd_", "m_rd_", (("araddr", 16), ("arprot", 3))),
    "r":  ("m_rd_", "s_rd_", (("rdata", 32), ("rresp", 2))),
    "aw": ("s_wr_", "m_wr_", (("awaddr", 16), ("awprot", 3))),
    "w":  ("s_wr_", "m_wr_", (("wdata", 32), ("wstrb", 4))),
    "b":  ("m_wr_", "s_wr_", (("bresp", 2),)),
}
CONFIGS = {
    0: set(),
    1: {"ar", "aw", "w"},
    2: set(CHANNELS),
}


class Channel:
    def __init__(self, dut, name, registered, rng):
        source, sink, fields = CHANNELS[name]
        self.name = name
        self.registered = registered
        self.rng = rng
        self.fields = fields
        self.source_valid = getattr(dut, f"{source}{name}valid")
        self.source_ready = getattr(dut, f"{source}{name}ready")
        self.source_payload = [getattr(dut, f"{source}{field}") for field, _ in fields]
        self.sink_valid = getattr(dut, f"{sink}{name}valid")
        self.sink_ready = getattr(dut, f"{sink}{name}ready")
        self.sink_payload = [getattr(dut, f"{sink}{field}") for field, _ in fields]
        self.reset()

    def reset(self):
        self.valid = 0
        self.ready = 0
        self.payload = self.random_payload()
        self.sent = deque()
        self.received = 0
        self.stalled = None
        self.accept_cycles = []
        self.deliver_cycles = []

    def random_payload(self):
        return tuple(self.rng.getrandbits(width) for _, width in self.fields)

    def drive(self, valid_probability, ready_probability):
        # An AXI source keeps VALID and payload until its handshake.
        if not self.valid and self.rng.random() < valid_probability:
            self.valid = 1
            self.payload = self.random_payload()
        self.ready = int(self.rng.random() < ready_probability)

    def apply(self, flip=False):
        valid, ready, payload = self.valid, self.ready, self.payload
        if flip:
            valid, ready = 1 - valid, 1 - ready
            payload = tuple(value ^ ((1 << width) - 1) for value, (_, width) in zip(payload, self.fields))
        self.source_valid.value = valid
        self.sink_ready.value = ready
        for handle, value in zip(self.source_payload, payload):
            handle.value = value

    def outputs(self):
        return (
            int(self.source_ready.value),
            int(self.sink_valid.value),
            tuple(int(handle.value) for handle in self.sink_payload),
        )

    def check(self, cycle, outputs):
        source_ready, sink_valid, sink_payload = outputs
        if self.stalled is not None:
            assert sink_valid and sink_payload == self.stalled, f"{self.name}: sink payload changed while stalled"
        self.stalled = sink_payload if sink_valid and not self.ready else None
        if not self.registered:
            assert source_ready == self.ready, f"{self.name}: pass-through READY differs"
            assert sink_valid == self.valid, f"{self.name}: pass-through VALID differs"
            if sink_valid:
                assert sink_payload == self.payload, f"{self.name}: pass-through payload differs"
        # Accept first: a pass-through channel delivers in the same cycle.
        if self.valid and source_ready:
            self.sent.append((cycle, self.payload))
            self.accept_cycles.append(cycle)
            self.valid = 0
        if sink_valid and self.ready:
            assert self.sent, f"{self.name}: delivered a transfer that was never sent"
            sent_cycle, payload = self.sent.popleft()
            assert sink_payload == payload, f"{self.name}: transfer reordered or corrupted"
            assert cycle - sent_cycle >= int(self.registered), f"{self.name}: registered channel has no latency"
            self.received += 1
            self.deliver_cycles.append(cycle)


class Slice:
    def __init__(self, dut, seed):
        self.dut = dut
        config = int(os.environ.get("REG_SLICE_TEST_CFG", "2"))
        rng = random.Random(seed)
        self.channels = [Channel(dut, name, name in CONFIGS[config], rng) for name in CHANNELS]
        self.cycle = 0

    async def tick(self):
        self.dut.CLK.value = 0
        registered = [channel for channel in self.channels if channel.registered]
        if registered:
            # Registered outputs must not react to any input in the same cycle.
            for channel in self.channels:
                channel.apply(flip=True)
            await Timer(2, "ns")
            flipped = [channel.outputs() for channel in registered]
        for channel in self.channels:
            channel.apply()
        await Timer(2, "ns")
        outputs = [channel.outputs() for channel in self.channels]
        if registered:
            stable = [output for channel, output in zip(self.channels, outputs) if channel.registered]
            assert stable == flipped, "a registered channel output depends combinationally on an input"
        for channel, output in zip(self.channels, outputs):
            channel.check(self.cycle, output)
        self.dut.CLK.value = 1
        await Timer(5, "ns")
        self.cycle += 1

    async def reset(self):
        self.dut.RST_N.value = 0
        for channel in self.channels:
            channel.reset()
            channel.apply()
        for _ in range(3):
            self.dut.CLK.value = 0
            await Timer(5, "ns")
            self.dut.CLK.value = 1
            await Timer(5, "ns")
        self.dut.RST_N.value = 1

    async def run(self, cycles, valid_probability, ready_probability):
        for _ in range(cycles):
            for channel in self.channels:
                channel.drive(valid_probability, ready_probability)
            await self.tick()

    async def drain(self):
        # Offered transfers keep VALID until accepted; nothing new is offered.
        for _ in range(10):
            for channel in self.channels:
                channel.ready = 1
            await self.tick()
        for channel in self.channels:
            assert not channel.sent, f"{channel.name}: transfers lost in the slice"


@cocotb.test()
async def reg_slice_order_stability_and_throughput(dut):
    test = Slice(dut, 0x5115E)
    await test.reset()

    # Random backpressure and gaps on every channel independently.
    for valid_probability, ready_probability in ((0.7, 0.6), (0.9, 0.2), (0.3, 0.95), (1.0, 1.0)):
        await test.run(400, valid_probability, ready_probability)
    await test.drain()
    assert all(channel.received > 100 for channel in test.channels)

    # Sustained traffic: one transfer per cycle on every channel.
    for channel in test.channels:
        channel.accept_cycles.clear()
        channel.deliver_cycles.clear()
    await test.run(64, 1.0, 1.0)
    for channel in test.channels:
        accepted = channel.accept_cycles[2:]
        assert all(b - a == 1 for a, b in zip(accepted, accepted[1:])), f"{channel.name}: throughput below 1/cycle"
    await test.drain()

    # A full slice keeps its data and accepts again after one free cycle.
    await test.reset()
    for channel in test.channels:
        channel.ready = 0
    for _ in range(4):
        for channel in test.channels:
            if not channel.valid:
                channel.valid = 1
                channel.payload = channel.random_payload()
        await test.tick()
    for channel in test.channels:
        expected = 2 if channel.registered else 0
        assert len(channel.sent) == expected, f"{channel.name}: holds {len(channel.sent)} transfers, expected {expected}"
    await test.drain()

    dut._log.warning(
        "Register slice passed: registered channels %s",
        sorted(channel.name for channel in test.channels if channel.registered),
    )
