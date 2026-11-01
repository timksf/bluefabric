"""mkAhbMasterMux through mkTestAhbMasterMux: three upstream managers (S_AHB0..2) share the downstream port M_AHB.

Manager i writes when i is odd and drives HPROT 8 + i, so the forwarded request shows who owns the downstream port. The
downstream target answers HRDATA 0x66001234 with an ERROR response, which only the owner of the data phase may see.
Switching managers costs one idle address phase (the handover bubble).
"""

import cocotb
from cocotb.triggers import RisingEdge

from tb import IDLE, INCR4, NONSEQ, SEQ, SINGLE, WORD, Port, mid_cycle, reset, start_clock

MANAGERS = 3


def drive(dut, i, address=0, htrans=IDLE, hwdata=0, hburst=SINGLE, hmastlock=0):
    Port(dut, f"S_AHB{i}").drive(haddr=address, hsel=int(htrans != IDLE), htrans=htrans, hwrite=i & 1, hsize=WORD, hburst=hburst, hprot=8 + i, hmastlock=hmastlock, hwdata=hwdata, hreadyin=1)


def check_forwarded(dut, owner, address, htrans, hwdata):
    """The address phase of manager owner and the write data of the previous data phase are on the downstream port."""
    downstream = Port(dut, "M_AHB")
    assert downstream.read("hsel", "htrans", "haddr") == (int(htrans != IDLE), htrans, address)
    assert downstream.read("hwrite", "hsize", "hprot", "hwdata") == (owner & 1, WORD, 8 + owner, hwdata)


def check_idle(dut, hwdata):
    """An idle address phase, with the write data of the previous data phase."""
    downstream = Port(dut, "M_AHB")
    assert downstream.read("hsel", "htrans", "hwdata") == (0, IDLE, hwdata)


def check_ready(dut, *managers):
    """Exactly these managers see HREADYOUT, so only they may advance."""
    for i in range(MANAGERS):
        assert Port(dut, f"S_AHB{i}").hreadyout == int(i in managers)


def check_response_owner(dut, owner):
    """Only the owner of the data phase sees the downstream response."""
    for i in range(MANAGERS):
        expected = (0x66001234, 1) if i == owner else (0, 0)
        assert Port(dut, f"S_AHB{i}").read("hrdata", "hresp") == expected


async def setup(dut):
    start_clock(dut)
    for i in range(MANAGERS):
        drive(dut, i)
    Port(dut, "M_AHB").drive(hready=1, hrdata=0x66001234, hresp=1)
    await reset(dut)


@cocotb.test()
async def lone_manager_keeps_pipelining(dut):
    await setup(dut)

    drive(dut, 0, 0x100, NONSEQ)
    await mid_cycle(dut)
    check_forwarded(dut, 0, 0x100, NONSEQ, 0)
    check_ready(dut, 0)
    check_response_owner(dut, None)

    # the next address phase overlaps the data phase without a bubble
    await RisingEdge(dut.CLK)
    drive(dut, 0, 0x104, NONSEQ, 0xA0000100)
    await mid_cycle(dut)
    check_forwarded(dut, 0, 0x104, NONSEQ, 0xA0000100)
    check_ready(dut, 0)
    check_response_owner(dut, 0)


@cocotb.test()
async def rotates_at_single_boundaries(dut):
    await setup(dut)

    drive(dut, 0, 0x100, NONSEQ)
    drive(dut, 1, 0x200, NONSEQ)
    drive(dut, 2, 0x300, NONSEQ)
    await mid_cycle(dut)
    check_forwarded(dut, 0, 0x100, NONSEQ, 0)
    check_ready(dut, 0)

    # a downstream wait state holds the selected address phase
    Port(dut, "M_AHB").hready = 0
    await RisingEdge(dut.CLK)
    await mid_cycle(dut)
    check_forwarded(dut, 0, 0x100, NONSEQ, 0)
    check_ready(dut)

    Port(dut, "M_AHB").hready = 1
    await RisingEdge(dut.CLK)
    drive(dut, 0, 0x104, NONSEQ, 0xA0000100)
    await mid_cycle(dut)
    check_idle(dut, 0xA0000100)
    check_ready(dut, 0)
    check_response_owner(dut, 0)

    # the handover bubble holds across downstream wait states as well
    Port(dut, "M_AHB").hready = 0
    await RisingEdge(dut.CLK)
    await mid_cycle(dut)
    check_idle(dut, 0xA0000100)
    check_ready(dut)
    check_response_owner(dut, 0)

    Port(dut, "M_AHB").hready = 1
    await RisingEdge(dut.CLK)
    drive(dut, 0, 0x108, NONSEQ, 0xA0000104)
    await mid_cycle(dut)
    check_forwarded(dut, 1, 0x200, NONSEQ, 0)
    check_ready(dut, 1)
    check_response_owner(dut, None)

    await RisingEdge(dut.CLK)
    drive(dut, 1, 0x204, NONSEQ, 0xB0000200)
    await mid_cycle(dut)
    check_idle(dut, 0xB0000200)
    check_ready(dut, 1)
    check_response_owner(dut, 1)

    await RisingEdge(dut.CLK)
    drive(dut, 1, 0x208, NONSEQ, 0xB0000204)
    await mid_cycle(dut)
    check_forwarded(dut, 2, 0x300, NONSEQ, 0)
    check_ready(dut, 2)
    check_response_owner(dut, None)

    await RisingEdge(dut.CLK)
    drive(dut, 2, 0x304, NONSEQ, 0xC0000300)
    await mid_cycle(dut)
    check_idle(dut, 0xC0000300)
    check_ready(dut, 2)
    check_response_owner(dut, 2)

    # back to manager 0, whose request was held since its last turn
    await RisingEdge(dut.CLK)
    drive(dut, 2, 0x308, NONSEQ, 0xC0000304)
    await mid_cycle(dut)
    check_forwarded(dut, 0, 0x104, NONSEQ, 0)
    check_ready(dut)
    check_response_owner(dut, None)

    await RisingEdge(dut.CLK)
    await mid_cycle(dut)
    check_idle(dut, 0xA0000104)
    check_ready(dut, 0)
    check_response_owner(dut, 0)


@cocotb.test()
async def keeps_fixed_length_bursts_together(dut):
    await setup(dut)

    drive(dut, 0, 0x400, NONSEQ, hburst=INCR4)
    drive(dut, 1, 0x500, NONSEQ)
    for beat in range(4):
        await mid_cycle(dut)
        check_forwarded(dut, 0, 0x400 + 4 * beat, NONSEQ if beat == 0 else SEQ, 0 if beat == 0 else 0xD0000000 | (0x400 + 4 * (beat - 1)))
        check_ready(dut, 0)
        assert Port(dut, "M_AHB").hburst == INCR4

        # after the last beat manager 0 asks for a new SINGLE, which must wait for manager 1
        await RisingEdge(dut.CLK)
        last = beat == 3
        drive(dut, 0, 0x404 + 4 * beat, NONSEQ if last else SEQ, 0xD0000000 | (0x400 + 4 * beat), hburst=SINGLE if last else INCR4)

    await mid_cycle(dut)
    check_idle(dut, 0xD000040C)
    check_ready(dut, 0)

    await RisingEdge(dut.CLK)
    await mid_cycle(dut)
    check_forwarded(dut, 1, 0x500, NONSEQ, 0)


@cocotb.test()
async def keeps_locked_sequences_together(dut):
    await setup(dut)

    # manager 0 locks its first two transfers, the third one is unlocked
    drive(dut, 0, 0x600, NONSEQ, hmastlock=1)
    drive(dut, 1, 0x700, NONSEQ)
    for beat in range(3):
        await mid_cycle(dut)
        check_forwarded(dut, 0, 0x600 + 4 * beat, NONSEQ, 0 if beat == 0 else 0xE0000000 | (0x600 + 4 * (beat - 1)))
        assert Port(dut, "M_AHB").hmastlock == int(beat < 2)
        check_ready(dut, 0)

        await RisingEdge(dut.CLK)
        drive(dut, 0, 0x604 + 4 * beat, NONSEQ, 0xE0000000 | (0x600 + 4 * beat), hmastlock=int(beat == 0))

    await mid_cycle(dut)
    check_idle(dut, 0xE0000608)
    check_ready(dut, 0)

    await RisingEdge(dut.CLK)
    await mid_cycle(dut)
    check_forwarded(dut, 1, 0x700, NONSEQ, 0)
