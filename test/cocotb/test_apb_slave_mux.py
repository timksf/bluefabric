"""mkApbSlaveMux through mkTestApbSlaveMux: the upstream port S_APB is decoded onto M_APB0 (0x0000) and M_APB1 (0x1000), 4 KiB each.

Target t always answers PREADY with PRDATA 0x11000000 | t and PSLVERR t. A miss is answered by the mux with PSLVERR.
"""

import cocotb
from cocotb.triggers import RisingEdge

from tb import Port, reset, settle, start_clock

# request signals other than the address, forwarded unchanged to the selected target
REQUEST = dict(pwrite=1, pwdata=0xA5A51234, pstrb=0xD, pprot=5, pauser=6, pwuser=7)


def target_of(address):
    return address // 0x1000 if address < 0x2000 else None


async def transfer(dut, address):
    """One transfer, checked in its access phase."""
    upstream = Port(dut, "S_APB")
    targets = [Port(dut, "M_APB0"), Port(dut, "M_APB1")]

    upstream.drive(paddr=address, psel=1, penable=0)
    await RisingEdge(dut.CLK)
    upstream.penable = 1
    await settle()

    target = target_of(address)
    if target is None:
        assert upstream.read("pready", "pslverr") == (1, 1)
        assert all(port.psel == 0 for port in targets)
    else:
        selected, other = targets[target], targets[1 - target]
        assert selected.read("psel", "penable", "paddr") == (1, 1, address)
        assert selected.read(*REQUEST) == tuple(REQUEST.values())
        assert other.psel == 0
        assert upstream.read("pready", "prdata", "pslverr") == (1, 0x11000000 | target, target)

    await RisingEdge(dut.CLK)
    upstream.drive(psel=0, penable=0)


@cocotb.test()
async def routes_by_address(dut):
    start_clock(dut)
    Port(dut, "S_APB").drive(psel=0, penable=0, **REQUEST)
    for target in range(2):
        Port(dut, f"M_APB{target}").drive(pready=1, prdata=0x11000000 | target, pslverr=target, pruser=target + 2, pbuser=target + 4)
    await reset(dut)

    for address in (0x0040, 0x1044, 0x3000):
        await transfer(dut, address)
