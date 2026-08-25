import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer
from cocotbext.ahb import AHBBus, AHBLiteMaster


AHB_SIGNALS = {
    "haddr": "haddr",
    "hsize": "hsize",
    "htrans": "htrans",
    "hwdata": "hwdata",
    "hrdata": "hrdata",
    "hwrite": "hwrite",
    "hready": "hreadyout",
    "hresp": "hresp",
}

AHB_OPTIONAL_SIGNALS = {
    "hburst": "hburst",
    "hmastlock": "hmastlock",
    "hprot": "hprot",
    "hsel": "hsel",
}


def ahb_bus(dut):
    return AHBBus.from_prefix(
        dut,
        "S_AHB",
        signals=AHB_SIGNALS,
        optional_signals=AHB_OPTIONAL_SIGNALS,
    )


async def reset_dut(dut):
    dut.RST_N.value = 0
    dut.S_AHB_hreadyin.value = 0
    dut.M_APB_pready.value = 0
    dut.M_APB_prdata.value = 0
    dut.M_APB_pslverr.value = 0
    dut.M_APB_pruser.value = 0
    dut.M_APB_pbuser.value = 0
    await RisingEdge(dut.CLK)
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1
    await RisingEdge(dut.CLK)


async def follow_ready(dut):
    while True:
        await FallingEdge(dut.CLK)
        await Timer(1, "ps")
        dut.S_AHB_hreadyin.value = dut.S_AHB_hreadyout.value


async def apb_responder(dut, transfers):
    current = None
    wait_cycles = 0
    completed = False

    while True:
        await FallingEdge(dut.CLK)

        dut.M_APB_pready.value = 0
        dut.M_APB_prdata.value = 0
        dut.M_APB_pslverr.value = 0
        dut.M_APB_pruser.value = 0
        dut.M_APB_pbuser.value = 0

        if not int(dut.RST_N.value):
            current = None
            wait_cycles = 0
            completed = False
            continue

        selected = int(dut.M_APB_psel.value)
        enabled = int(dut.M_APB_penable.value)

        if selected and not enabled:
            current = {
                "address": int(dut.M_APB_paddr.value),
                "write": int(dut.M_APB_pwrite.value),
                "write_data": int(dut.M_APB_pwdata.value),
                "strobe": int(dut.M_APB_pstrb.value),
                "protection": int(dut.M_APB_pprot.value),
            }
            wait_cycles = 1 if current["address"] == 0x1020 else 0
            completed = False

        if selected and enabled and current is not None:
            dut.M_APB_prdata.value = 0xA5000000 | current["address"]

            if wait_cycles:
                wait_cycles -= 1
            else:
                error = current["address"] == 0x10F0
                dut.M_APB_pready.value = 1
                dut.M_APB_pslverr.value = error

                if not completed:
                    transfers.append(dict(current))
                    completed = True


async def expect_two_cycle_error(dut, address, size):
    while not int(dut.S_AHB_hreadyout.value):
        await RisingEdge(dut.CLK)

    await FallingEdge(dut.CLK)
    dut.S_AHB_haddr.value = address
    dut.S_AHB_hsel.value = 1
    dut.S_AHB_htrans.value = 2
    dut.S_AHB_hwrite.value = 0
    dut.S_AHB_hsize.value = size
    dut.S_AHB_hburst.value = 0
    dut.S_AHB_hprot.value = 3
    dut.S_AHB_hmastlock.value = 0
    dut.S_AHB_hwdata.value = 0

    await RisingEdge(dut.CLK)
    await FallingEdge(dut.CLK)
    dut.S_AHB_hsel.value = 0
    dut.S_AHB_htrans.value = 0

    for _ in range(12):
        await Timer(1, "ps")
        if int(dut.S_AHB_hresp.value):
            assert int(dut.S_AHB_hreadyout.value) == 0
            break
        await RisingEdge(dut.CLK)
        await FallingEdge(dut.CLK)
    else:
        raise AssertionError("bridge did not begin the AHB error response")

    await RisingEdge(dut.CLK)
    await FallingEdge(dut.CLK)
    await Timer(1, "ps")
    assert int(dut.S_AHB_hresp.value) == 1
    assert int(dut.S_AHB_hreadyout.value) == 1

    await RisingEdge(dut.CLK)
    await FallingEdge(dut.CLK)
    await Timer(1, "ps")
    assert int(dut.S_AHB_hresp.value) == 0


@cocotb.test()
async def test_ahb_apb_bridge(dut):
    cocotb.start_soon(Clock(dut.CLK, 10, "ns").start())
    await reset_dut(dut)

    transfers = []
    cocotb.start_soon(follow_ready(dut))
    cocotb.start_soon(apb_responder(dut, transfers))

    bus = ahb_bus(dut)
    master = AHBLiteMaster(bus, dut.CLK, dut.RST_N, timeout=50)

    write_responses = await master.write(
        [0x1001, 0x1002, 0x1004],
        [0x5A, 0xBEEF, 0x12345678],
        size=[1, 2, 4],
        pip=True,
        sync=True,
        format_amba=True,
    )

    assert len(write_responses) == 3
    assert all(response["resp"].value == 0 for response in write_responses)

    read_responses = await master.read(
        [0x1010, 0x1020],
        size=[4, 4],
        pip=True,
        sync=True,
    )

    assert len(read_responses) == 2
    assert [int(response["data"], 16) for response in read_responses] == [
        0xA5001010,
        0xA5001020,
    ]

    writes = [transfer for transfer in transfers if transfer["write"]]
    assert [transfer["address"] for transfer in writes] == [
        0x1001,
        0x1002,
        0x1004,
    ]
    assert [transfer["strobe"] for transfer in writes] == [0x2, 0xC, 0xF]
    assert [transfer["write_data"] for transfer in writes] == [
        0x00005A00,
        0xBEEF0000,
        0x12345678,
    ]
    assert all(transfer["protection"] == 0x4 for transfer in transfers)
    assert all(
        transfer["strobe"] == 0
        for transfer in transfers
        if not transfer["write"]
    )

    transfer_count = len(transfers)
    await expect_two_cycle_error(dut, 0x10F0, 2)
    assert len(transfers) == transfer_count + 1

    transfer_count = len(transfers)
    await expect_two_cycle_error(dut, 0x1001, 1)
    assert len(transfers) == transfer_count
