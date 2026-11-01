"""mkApbMaster through mkTestApbMaster, which issues eight transfers and checks their responses itself.

Transfer i goes to 0x100 + 4i, writes when i is odd, carries PWDATA 0xA5000000 | i, PSTRB 0xF on writes, PPROT i & 7, PAUSER i and PWUSER i + 1.
The test target inserts i % 3 wait states and answers PRDATA 0x55000000 | i, PSLVERR for transfer 3, PRUSER i + 1 and
PBUSER i + 2, which the DUT counts in errors when they arrive wrong.
"""

import cocotb
from cocotb.triggers import FallingEdge

from tb import Port, reset, start_clock


def expected_request(i):
    return 0x100 + i * 4, i & 1, 0xA5000000 | i, 0xF if i & 1 else 0, i & 7, i, i + 1


@cocotb.test()
async def issues_transfers_and_waits_for_pready(dut):
    start_clock(dut)
    apb = Port(dut, "M_APB")
    apb.drive(pready=0, prdata=0, pslverr=0, pruser=0, pbuser=0)
    await reset(dut)

    transfer = 0
    waits = 0
    completing = False
    while not dut.done.value:
        await FallingEdge(dut.CLK)
        if completing:
            transfer += 1
            waits = transfer % 3
            completing = False

        apb.pready = 0
        if apb.psel and apb.penable:
            assert apb.read("paddr", "pwrite", "pwdata", "pstrb", "pprot", "pauser", "pwuser") == expected_request(transfer)
            if waits:
                waits -= 1
            else:
                apb.drive(prdata=0x55000000 | transfer, pslverr=int(transfer == 3), pruser=transfer + 1, pbuser=transfer + 2, pready=1)
                completing = True

    assert int(dut.errors.value) == 0
    assert transfer == 8
