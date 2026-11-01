"""mkAhbApbBridge through mkTestAhbApbBridge: AHB transfers on S_AHB become APB transfers on M_APB.

The APB target answers PRDATA 0xA5000000 | address, inserts one wait state at 0x1020 and answers PSLVERR at 0x10F0.
Narrow writes must arrive with the byte lanes and strobes AHB uses, an APB error must become a two-cycle AHB ERROR, and
a misaligned transfer must be rejected by the bridge without an APB transfer.
"""

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge
from cocotbext.ahb import AHBLiteMaster

from tb import HALFWORD, IDLE, NONSEQ, SINGLE, WORD, Port, ahb_bus, mid_cycle, next_mid_cycle, reset, settle, start_clock

WAIT_ADDRESS = 0x1020
ERROR_ADDRESS = 0x10F0


async def follow_ready(dut):
    """The bridge is the only slave on its AHB bus, so HREADY in follows its own HREADYOUT."""
    while True:
        await mid_cycle(dut)
        dut.S_AHB_hreadyin.value = dut.S_AHB_hreadyout.value


async def apb_target(dut, transfers):
    """Answers every APB transfer and records each completed one in transfers."""
    apb = Port(dut, "M_APB")
    current = None
    waits = 0
    completed = False

    while True:
        await FallingEdge(dut.CLK)
        apb.drive(pready=0, prdata=0, pslverr=0, pruser=0, pbuser=0)

        if not int(dut.RST_N.value):
            current, waits, completed = None, 0, False
            continue

        if apb.psel and not apb.penable:
            current = dict(address=apb.paddr, write=apb.pwrite, write_data=apb.pwdata, strobe=apb.pstrb, protection=apb.pprot)
            waits = int(current["address"] == WAIT_ADDRESS)
            completed = False

        if apb.psel and apb.penable and current is not None:
            apb.prdata = 0xA5000000 | current["address"]
            if waits:
                waits -= 1
            else:
                apb.drive(pready=1, pslverr=int(current["address"] == ERROR_ADDRESS))
                if not completed:
                    transfers.append(dict(current))
                    completed = True


async def expect_two_cycle_error(dut, address, size):
    """A single read that must end in a two-cycle ERROR: HRESP with HREADYOUT low, then with HREADYOUT high."""
    ahb = Port(dut, "S_AHB")
    while not ahb.hreadyout:
        await RisingEdge(dut.CLK)

    await FallingEdge(dut.CLK)
    ahb.drive(haddr=address, hsel=1, htrans=NONSEQ, hwrite=0, hsize=size, hburst=SINGLE, hprot=3, hmastlock=0, hwdata=0)
    await RisingEdge(dut.CLK)
    await FallingEdge(dut.CLK)
    ahb.drive(hsel=0, htrans=IDLE)

    for _ in range(12):
        await settle()
        if ahb.hresp:
            assert ahb.hreadyout == 0
            break
        await RisingEdge(dut.CLK)
        await FallingEdge(dut.CLK)
    else:
        raise AssertionError("the bridge did not begin the AHB error response")

    await next_mid_cycle(dut)
    assert ahb.read("hresp", "hreadyout") == (1, 1)

    await next_mid_cycle(dut)
    assert ahb.hresp == 0


@cocotb.test()
async def bridges_transfers_and_errors(dut):
    start_clock(dut)
    dut.S_AHB_hreadyin.value = 0
    Port(dut, "M_APB").drive(pready=0, prdata=0, pslverr=0, pruser=0, pbuser=0)
    await reset(dut)

    transfers = []
    cocotb.start_soon(follow_ready(dut))
    cocotb.start_soon(apb_target(dut, transfers))
    master = AHBLiteMaster(ahb_bus(dut, "S_AHB", hready="hreadyout"), dut.CLK, dut.RST_N, timeout=50)

    # byte, halfword and word writes, pipelined
    responses = await master.write([0x1001, 0x1002, 0x1004], [0x5A, 0xBEEF, 0x12345678], size=[1, 2, 4], pip=True, sync=True, format_amba=True)
    assert [response["resp"].value for response in responses] == [0, 0, 0]

    responses = await master.read([0x1010, WAIT_ADDRESS], size=[4, 4], pip=True, sync=True)
    assert [int(response["data"], 16) for response in responses] == [0xA5001010, 0xA5000000 | WAIT_ADDRESS]

    writes = [transfer for transfer in transfers if transfer["write"]]
    reads = [transfer for transfer in transfers if not transfer["write"]]
    assert [transfer["address"] for transfer in writes] == [0x1001, 0x1002, 0x1004]
    assert [transfer["strobe"] for transfer in writes] == [0b0010, 0b1100, 0b1111]
    assert [transfer["write_data"] for transfer in writes] == [0x00005A00, 0xBEEF0000, 0x12345678]
    assert all(transfer["strobe"] == 0 for transfer in reads)
    assert all(transfer["protection"] == 0x4 for transfer in transfers)

    # an APB error, the transfer reaches the target
    count = len(transfers)
    await expect_two_cycle_error(dut, ERROR_ADDRESS, WORD)
    assert len(transfers) == count + 1

    # a misaligned halfword, rejected before APB
    count = len(transfers)
    await expect_two_cycle_error(dut, 0x1001, HALFWORD)
    assert len(transfers) == count
