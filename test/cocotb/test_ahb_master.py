"""mkAhbMaster through mkTestAhbMaster, which issues eight transfers and checks their responses itself.

Transfers 0, 1, 6 and 7 are SINGLE, transfers 2 to 5 form an INCR4 burst with a pause before beat 3 (a BUSY cycle).
Transfer i goes to 0x100 + 4i. The test target answers 0x55000000 | i and an ERROR response for transfer 3, which the
DUT counts in errors when they arrive wrong.
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotbext.ahb import AHBLiteSlave, AHBMonitor

from tb import BUSY, INCR4, NONSEQ, SEQ, SINGLE, Port, ahb_bus, start_clock, to_int


class Target(AHBLiteSlave):
    def _index(self, address):
        return (to_int(address) - 0x100) // 4

    def _chk_rd(self, address, _size):
        return self._index(address) != 3

    def _chk_wr(self, address, _size):
        return self._index(address) != 3

    def _rd(self, address, _size):
        return 0x55000000 | self._index(address)

    def _wr(self, address, _size, _value):
        return 0x55000000 | self._index(address)


@cocotb.test()
async def issues_singles_and_a_paused_burst(dut):
    start_clock(dut)
    bus = ahb_bus(dut, "M_AHB")
    AHBMonitor(bus, dut.CLK, dut.RST_N)
    Target(bus, dut.CLK, dut.RST_N)
    ahb = Port(dut, "M_AHB")

    dut.RST_N.value = 0
    await RisingEdge(dut.CLK)
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1

    # address phases that completed: (HADDR, HTRANS, HBURST)
    transfers = []
    busy_seen = False
    for _ in range(100):
        await RisingEdge(dut.CLK)
        await Timer(1, "ps")
        busy_seen |= ahb.htrans == BUSY
        if ahb.hready and ahb.htrans in (NONSEQ, SEQ):
            transfers.append((to_int(ahb.signal("haddr").value), ahb.htrans, ahb.hburst))
        if dut.done.value:
            break
    else:
        raise AssertionError("the master did not receive all responses")

    assert int(dut.errors.value) == 0
    assert transfers == [
        (0x100, NONSEQ, SINGLE),
        (0x104, NONSEQ, SINGLE),
        (0x108, NONSEQ, INCR4),
        (0x10C, SEQ, INCR4),
        (0x110, SEQ, INCR4),
        (0x114, SEQ, INCR4),
        (0x118, NONSEQ, SINGLE),
        (0x11C, NONSEQ, SINGLE),
    ]
    assert busy_seen
