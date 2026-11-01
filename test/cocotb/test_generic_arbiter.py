"""mkGenericArbiter with four requesters: round-robin order, grant held until advance, re-grant of a lone requester."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tb import reset, start_clock


async def setup(dut):
    start_clock(dut)
    dut.request.value = 0
    dut.advance.value = 0
    await reset(dut)


async def grant(dut):
    """The grant after the request inputs settled, it is combinational from the requests."""
    await Timer(1, "ns")
    return int(dut.grant.value)


async def advance(dut):
    """Releases the current grant at the next clock edge."""
    dut.advance.value = 1
    await RisingEdge(dut.CLK)
    dut.advance.value = 0


@cocotb.test()
async def rotates_round_robin(dut):
    await setup(dut)

    dut.request.value = 0b1111
    for expected in (0b0001, 0b0010, 0b0100, 0b1000) * 2:
        assert await grant(dut) == expected
        await advance(dut)

    # the requester after the last granted one wins, skipping idle ones
    dut.request.value = 0b1010
    assert await grant(dut) == 0b0010
    await advance(dut)
    assert await grant(dut) == 0b1000


@cocotb.test()
async def holds_grant_until_advance(dut):
    await setup(dut)
    assert await grant(dut) == 0

    dut.request.value = 0b0100
    assert await grant(dut) == 0b0100
    await RisingEdge(dut.CLK)
    await Timer(1, "ps")

    # a new request with higher priority does not take over a held grant
    dut.request.value = 0b0101
    assert await grant(dut) == 0b0100
    await advance(dut)
    assert await grant(dut) == 0b0001


@cocotb.test()
async def regrants_lone_requester(dut):
    await setup(dut)

    dut.request.value = 0b0010
    assert await grant(dut) == 0b0010
    await advance(dut)
    assert await grant(dut) == 0b0010
