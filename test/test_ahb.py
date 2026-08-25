import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer
from cocotbext.ahb import AHBBus, AHBLiteMaster, AHBLiteSlave, AHBMonitor


AHB_SIGNALS = {
    "haddr": "haddr",
    "hsize": "hsize",
    "htrans": "htrans",
    "hwdata": "hwdata",
    "hrdata": "hrdata",
    "hwrite": "hwrite",
    "hready": "hready",
    "hresp": "hresp",
}

AHB_OPTIONAL_SIGNALS = {
    "hburst": "hburst",
    "hmastlock": "hmastlock",
    "hprot": "hprot",
    "hsel": "hsel",
}


def ahb_bus(dut, prefix, ready_signal="hready"):
    signals = dict(AHB_SIGNALS)
    signals["hready"] = ready_signal
    return AHBBus.from_prefix(
        dut,
        prefix,
        signals=signals,
        optional_signals=AHB_OPTIONAL_SIGNALS,
    )


def as_int(value):
    if hasattr(value, "to_unsigned"):
        return value.to_unsigned()
    return int(value)


async def reset_dut(dut):
    dut.RST_N.value = 0
    await RisingEdge(dut.CLK)
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1
    await RisingEdge(dut.CLK)


async def follow_slave_ready(dut):
    while True:
        await FallingEdge(dut.CLK)
        dut.S_AHB_hreadyin.value = dut.S_AHB_hreadyout.value


async def check_two_cycle_error(dut):
    await FallingEdge(dut.CLK)
    dut.S_AHB_hsel.value = 1
    dut.S_AHB_htrans.value = 2
    dut.S_AHB_haddr.value = 0x10
    dut.S_AHB_hwrite.value = 0
    dut.S_AHB_hsize.value = 2

    for _ in range(10):
        await RisingEdge(dut.CLK)
        await FallingEdge(dut.CLK)
        await Timer(1, "ps")
        if int(dut.S_AHB_hresp.value):
            assert int(dut.S_AHB_hreadyout.value) == 0
            break
    else:
        raise AssertionError("AHB slave did not begin its error response")

    dut.S_AHB_hsel.value = 0
    dut.S_AHB_htrans.value = 0
    await RisingEdge(dut.CLK)
    await FallingEdge(dut.CLK)
    await Timer(1, "ps")
    assert int(dut.S_AHB_hreadyout.value) == 1
    assert int(dut.S_AHB_hresp.value) == 1


@cocotb.test()
async def test_ahb_slave(dut):
    if "Slave" not in dut._name:
        return

    cocotb.start_soon(Clock(dut.CLK, 10, "ns").start())
    dut.S_AHB_hreadyin.value = 0
    await reset_dut(dut)
    cocotb.start_soon(follow_slave_ready(dut))
    await check_two_cycle_error(dut)
    await reset_dut(dut)

    bus = ahb_bus(dut, "S_AHB", ready_signal="hreadyout")
    AHBMonitor(bus, dut.CLK, dut.RST_N)
    master = AHBLiteMaster(bus, dut.CLK, dut.RST_N)

    addresses = [0x00, 0x04, 0x08, 0x0C, 0x20, 0x24, 0x28, 0x2C]
    values = [0xA5A50000 | index for index in range(len(addresses))]
    modes = [index & 1 for index in range(len(addresses))]
    responses = await master.custom(
        addresses,
        values,
        modes,
        size=[4] * len(addresses),
        pip=True,
        sync=True,
    )

    assert len(responses) == len(addresses)
    for index, response in enumerate(responses):
        assert response["resp"].value == 0
        assert int(response["data"], 16) == addresses[index] ^ values[index]


class MasterResponder(AHBLiteSlave):
    def _index(self, address):
        return (as_int(address) - 0x100) // 4

    def _chk_rd(self, address, _size):
        return self._index(address) != 3

    def _chk_wr(self, address, _size):
        return self._index(address) != 3

    def _rd(self, address, _size):
        return 0x55000000 | self._index(address)

    def _wr(self, address, _size, _value):
        return 0x55000000 | self._index(address)


@cocotb.test()
async def test_ahb_master(dut):
    if "Master" not in dut._name:
        return

    cocotb.start_soon(Clock(dut.CLK, 10, "ns").start())
    bus = ahb_bus(dut, "M_AHB")
    AHBMonitor(bus, dut.CLK, dut.RST_N)
    MasterResponder(bus, dut.CLK, dut.RST_N)
    dut.RST_N.value = 0
    await RisingEdge(dut.CLK)
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1

    transfers = []
    busy_seen = False
    for _ in range(100):
        await RisingEdge(dut.CLK)
        await Timer(1, "ps")
        htrans = int(dut.M_AHB_htrans.value)
        if htrans == 1:
            busy_seen = True
        if int(dut.M_AHB_hready.value) and htrans in (2, 3):
            transfers.append(
                (
                    as_int(dut.M_AHB_haddr.value),
                    htrans,
                    int(dut.M_AHB_hburst.value),
                )
            )
        if dut.done.value:
            break
    else:
        raise AssertionError("AHB master did not complete all responses")

    assert int(dut.errors.value) == 0
    assert transfers == [
        (0x100, 2, 0),
        (0x104, 2, 0),
        (0x108, 2, 3),
        (0x10C, 3, 3),
        (0x110, 3, 3),
        (0x114, 3, 3),
        (0x118, 2, 0),
        (0x11C, 2, 0),
    ]
    assert busy_seen
