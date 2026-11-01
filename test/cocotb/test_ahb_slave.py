"""mkAhbSlave (pipelined and bypass request) through mkTestAhbSlave(Bypass).

The test slave answers HRDATA = address ^ write data and an ERROR response for addresses with bit 4 set. The DUT is the
only slave on its bus, so HREADY in follows its own HREADYOUT.
"""

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge
from cocotbext.ahb import AHBLiteMaster, AHBMonitor

from tb import IDLE, NONSEQ, WORD, Port, ahb_bus, next_mid_cycle, reset, start_clock


async def follow_ready(dut):
    while True:
        await FallingEdge(dut.CLK)
        dut.S_AHB_hreadyin.value = dut.S_AHB_hreadyout.value


async def check_two_cycle_error(dut):
    """An ERROR response takes two cycles: HRESP high with HREADYOUT low, then HRESP high with HREADYOUT high."""
    ahb = Port(dut, "S_AHB")
    await FallingEdge(dut.CLK)
    ahb.drive(hsel=1, htrans=NONSEQ, haddr=0x10, hwrite=0, hsize=WORD)

    for _ in range(10):
        await next_mid_cycle(dut)
        if ahb.hresp:
            assert ahb.hreadyout == 0
            break
    else:
        raise AssertionError("the slave did not begin its error response")

    ahb.drive(hsel=0, htrans=IDLE)
    await next_mid_cycle(dut)
    assert ahb.hreadyout == 1
    assert ahb.hresp == 1


@cocotb.test()
async def errors_and_pipelined_transfers(dut):
    start_clock(dut)
    dut.S_AHB_hreadyin.value = 0
    await reset(dut)
    cocotb.start_soon(follow_ready(dut))
    await check_two_cycle_error(dut)
    await reset(dut)

    bus = ahb_bus(dut, "S_AHB", hready="hreadyout")
    AHBMonitor(bus, dut.CLK, dut.RST_N)
    master = AHBLiteMaster(bus, dut.CLK, dut.RST_N)

    addresses = [0x00, 0x04, 0x08, 0x0C, 0x20, 0x24, 0x28, 0x2C]
    values = [0xA5A50000 | i for i in range(len(addresses))]
    writes = [i & 1 for i in range(len(addresses))]
    responses = await master.custom(addresses, values, writes, size=[4] * len(addresses), pip=True, sync=True)

    assert len(responses) == len(addresses)
    for address, value, response in zip(addresses, values, responses):
        assert response["resp"].value == 0
        assert int(response["data"], 16) == address ^ value
