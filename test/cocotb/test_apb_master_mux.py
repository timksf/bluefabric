"""mkApbMasterMux through mkTestApbMasterMux: two upstream managers (S_APB0, S_APB1) share the downstream port M_APB.

Every signal manager i drives is derived from i, so the forwarded request shows who owns the downstream port. The
downstream target answers a fixed response, which only the owner may see together with PREADY.
"""

import cocotb
from cocotb.triggers import RisingEdge

from tb import Port, mid_cycle, reset, start_clock

RESPONSE = dict(prdata=0x55001234, pslverr=1, pruser=9, pbuser=10)


def request(i):
    return dict(paddr=0x100 + i * 0x40, pwrite=i, pwdata=0xA5000000 | i, pstrb=0xF - i, pprot=2 + i, pauser=4 + i, pwuser=6 + i)


def drive(dut, i, psel, penable=0):
    Port(dut, f"S_APB{i}").drive(psel=psel, penable=penable, **request(i))


def check_owner(dut, i, penable, pready=1):
    """Manager i owns the downstream port: its request is forwarded, it sees the response and the other one waits."""
    downstream = Port(dut, "M_APB")
    assert downstream.read("psel", "penable") == (1, penable)
    assert downstream.read(*request(i)) == tuple(request(i).values())
    assert Port(dut, f"S_APB{i}").read("pready", *RESPONSE) == (pready, *RESPONSE.values())
    assert Port(dut, f"S_APB{1 - i}").pready == 0


@cocotb.test()
async def arbitrates_between_managers(dut):
    start_clock(dut)
    for i in range(2):
        drive(dut, i, psel=0)
    downstream = Port(dut, "M_APB")
    downstream.drive(pready=1, **RESPONSE)
    await reset(dut)

    # manager 1 keeps the port through its access phase although manager 0 asks, also while the target waits
    downstream.pready = 0
    drive(dut, 1, psel=1)
    await RisingEdge(dut.CLK)
    drive(dut, 0, psel=1)
    drive(dut, 1, psel=1, penable=1)
    await mid_cycle(dut)
    check_owner(dut, 1, penable=1, pready=0)

    # once manager 1 completes, manager 0 gets the port with its setup phase
    downstream.pready = 1
    await RisingEdge(dut.CLK)
    drive(dut, 1, psel=0)
    await mid_cycle(dut)
    check_owner(dut, 0, penable=0)

    # simultaneous requests: manager 0 first, then manager 1, then manager 0 again
    drive(dut, 0, psel=0)
    await reset(dut)
    drive(dut, 0, psel=1)
    drive(dut, 1, psel=1)
    await mid_cycle(dut)
    check_owner(dut, 0, penable=0)

    await RisingEdge(dut.CLK)
    drive(dut, 0, psel=1, penable=1)
    await mid_cycle(dut)
    check_owner(dut, 0, penable=1)

    await RisingEdge(dut.CLK)
    drive(dut, 0, psel=0)
    await mid_cycle(dut)
    check_owner(dut, 1, penable=0)

    await RisingEdge(dut.CLK)
    drive(dut, 1, psel=1, penable=1)
    await mid_cycle(dut)
    check_owner(dut, 1, penable=1)

    await RisingEdge(dut.CLK)
    drive(dut, 0, psel=1)
    drive(dut, 1, psel=1)
    await mid_cycle(dut)
    check_owner(dut, 0, penable=0)
