"""Shared helpers for the BlueFabric cocotb tests."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

# AXI xRESP
OKAY, EXOKAY, SLVERR, DECERR = 0, 1, 2, 3

# AHB HTRANS
IDLE, BUSY, NONSEQ, SEQ = 0, 1, 2, 3

# AHB HBURST
SINGLE, INCR, WRAP4, INCR4 = 0, 1, 2, 3

# AHB HSIZE
BYTE, HALFWORD, WORD = 0, 1, 2


class Port:
    """The signals of one DUT port, named <prefix>_<signal>.

    Reading an attribute returns the signal as int, assigning drives it:
        apb = Port(dut, "S_APB")
        apb.psel = 1
        assert apb.pready == 1
    """

    def __init__(self, dut, prefix):
        object.__setattr__(self, "_dut", dut)
        object.__setattr__(self, "_prefix", prefix)

    def signal(self, name):
        return getattr(self._dut, f"{self._prefix}_{name}")

    def __getattr__(self, name):
        return int(self.signal(name).value)

    def __setattr__(self, name, value):
        self.signal(name).value = value

    def drive(self, **values):
        for name, value in values.items():
            setattr(self, name, value)

    def read(self, *names):
        return tuple(getattr(self, name) for name in names)


def start_clock(dut, period_ns=10):
    cocotb.start_soon(Clock(dut.CLK, period_ns, "ns").start())


async def reset(dut, cycles=2):
    """Active low reset for some cycles, returns one cycle after the release."""
    dut.RST_N.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.CLK)
    dut.RST_N.value = 1
    await RisingEdge(dut.CLK)


async def settle():
    """Lets combinational outputs follow inputs that were just driven."""
    await Timer(1, "ps")


async def mid_cycle(dut):
    """Waits for the next falling edge, the sample point of the tests that drive inputs on the rising edge."""
    await FallingEdge(dut.CLK)
    await settle()


async def next_mid_cycle(dut):
    """Waits for the falling edge after the next rising edge."""
    await RisingEdge(dut.CLK)
    await mid_cycle(dut)


def to_int(value):
    """Integer of a cocotbext result value, a LogicArray in cocotb 2 and a BinaryValue before."""
    return value.to_unsigned() if hasattr(value, "to_unsigned") else int(value)


def ahb_bus(dut, prefix, hready="hready"):
    """cocotbext-ahb bus of an AHB port, hready names the signal the master samples."""
    from cocotbext.ahb import AHBBus

    signals = {name: name for name in ("haddr", "hsize", "htrans", "hwdata", "hrdata", "hwrite", "hresp")}
    signals["hready"] = hready
    optional = {name: name for name in ("hburst", "hmastlock", "hprot", "hsel")}
    return AHBBus.from_prefix(dut, prefix, signals=signals, optional_signals=optional)
