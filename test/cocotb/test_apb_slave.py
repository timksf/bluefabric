"""mkApbSlave (registered and bypass request) through mkTestApbSlave(Bypass).

The test slave answers PRDATA = address ^ write data, PSLVERR for addresses with bit 4 set, and echoes PAUSER as PRUSER
and PWUSER as PBUSER.
"""

import cocotb
from cocotb.triggers import RisingEdge

from tb import Port, reset, start_clock


async def transfer(dut, apb, **request):
    """One APB transfer: setup phase, then access phase until PREADY. Returns the response and the wait states."""
    apb.drive(psel=1, penable=0, **request)
    await RisingEdge(dut.CLK)

    apb.penable = 1
    waits = 0
    await RisingEdge(dut.CLK)
    while not apb.pready:
        waits += 1
        await RisingEdge(dut.CLK)
    response = apb.read("prdata", "pslverr", "pruser", "pbuser")

    apb.drive(psel=0, penable=0)
    await RisingEdge(dut.CLK)
    return response, waits


@cocotb.test()
async def answers_without_wait_states(dut):
    start_clock(dut)
    apb = Port(dut, "S_APB")
    apb.drive(psel=0, penable=0)
    await reset(dut)

    for i in range(16):
        address = i * 4
        data = 0xA5A50000 | i
        address_user = i & 0xF
        write_user = (i + 1) & 0xF
        response, waits = await transfer(dut, apb, paddr=address, pwrite=i & 1, pwdata=data, pstrb=0xF ^ (i & 3), pprot=i & 7, pauser=address_user, pwuser=write_user)

        assert waits == 0
        assert response == (address ^ data, int(bool(address & 0x10)), address_user, write_user)
