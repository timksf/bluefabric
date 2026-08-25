import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


@cocotb.test()
async def test_round_robin(dut):
    cocotb.start_soon(Clock(dut.CLK, 10, "ns").start())
    dut.RST_N.value = 0
    dut.request.value = 0
    dut.advance.value = 0
    await RisingEdge(dut.CLK)
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1

    dut.request.value = 0b1111
    expected = [1, 2, 4, 8, 1, 2, 4, 8]
    for grant in expected:
        await Timer(1, "ns")
        assert int(dut.grant.value) == grant
        dut.advance.value = 1
        await RisingEdge(dut.CLK)
        dut.advance.value = 0

    dut.request.value = 0b1010
    await Timer(1, "ns")
    assert int(dut.grant.value) == 0b0010
    dut.advance.value = 1
    await RisingEdge(dut.CLK)
    dut.advance.value = 0
    await Timer(1, "ns")
    assert int(dut.grant.value) == 0b1000


@cocotb.test()
async def test_grant_is_locked_until_advance(dut):
    cocotb.start_soon(Clock(dut.CLK, 10, "ns").start())
    dut.RST_N.value = 0
    dut.request.value = 0
    dut.advance.value = 0
    await RisingEdge(dut.CLK)
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1

    await Timer(1, "ns")
    assert int(dut.grant.value) == 0

    dut.request.value = 0b0100
    await Timer(1, "ns")
    assert int(dut.grant.value) == 0b0100
    await RisingEdge(dut.CLK)
    await Timer(1, "ps")

    dut.request.value = 0b0101
    await Timer(1, "ns")
    assert int(dut.grant.value) == 0b0100

    dut.advance.value = 1
    await RisingEdge(dut.CLK)
    dut.advance.value = 0
    await Timer(1, "ns")
    assert int(dut.grant.value) == 0b0001


@cocotb.test()
async def test_single_request_reacquires_after_advance(dut):
    cocotb.start_soon(Clock(dut.CLK, 10, "ns").start())
    dut.RST_N.value = 0
    dut.request.value = 0
    dut.advance.value = 0
    await RisingEdge(dut.CLK)
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1

    dut.request.value = 0b0010
    await Timer(1, "ns")
    assert int(dut.grant.value) == 0b0010

    dut.advance.value = 1
    await RisingEdge(dut.CLK)
    dut.advance.value = 0
    await Timer(1, "ns")
    assert int(dut.grant.value) == 0b0010
