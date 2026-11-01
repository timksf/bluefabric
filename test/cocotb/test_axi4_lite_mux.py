"""mkAxi4LiteSlaveMux with BlueAXI targets through mkTestAxi4LiteMux.

The select inputs sel_rd/sel_wr pick the target per request: bit 0 target 0, bit 1 target 1, zero or both a DECERR from
the mux. Target t answers reads with (t + 1) << 28 | ARPROT << 20 | ARADDR, target 0 with OKAY and target 1 with
SLVERR. The DUT records the last write a target received in its last_write_* outputs.
"""

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge

from tb import DECERR, OKAY, SLVERR, Port, reset, settle, start_clock

TARGET0, TARGET1, NONE, BOTH = 0b01, 0b10, 0b00, 0b11


async def handshake(dut, valid, ready):
    """Holds VALID until READY, then drops it after the handshake edge."""
    for _ in range(20):
        await settle()
        if int(ready.value):
            await RisingEdge(dut.CLK)
            valid.value = 0
            return
        await FallingEdge(dut.CLK)
    raise AssertionError(f"{valid._name} did not receive ready")


async def receive(dut, valid, ready, payload, stall_cycles):
    """Waits for VALID, checks the payload stays stable for stall_cycles with READY low, then accepts it."""
    ready.value = 0
    for _ in range(20):
        await FallingEdge(dut.CLK)
        await settle()
        if int(valid.value):
            expected = tuple(int(signal.value) for signal in payload)
            break
    else:
        raise AssertionError(f"{valid._name} was not asserted")

    for _ in range(stall_cycles):
        await RisingEdge(dut.CLK)
        await FallingEdge(dut.CLK)
        await settle()
        assert int(valid.value) == 1
        assert tuple(int(signal.value) for signal in payload) == expected

    ready.value = 1
    await RisingEdge(dut.CLK)
    ready.value = 0
    return expected


async def read(dut, address, stall_cycles=0, select=TARGET0):
    """Returns (RDATA, RRESP)."""
    axi = Port(dut, "S_AXI")
    dut.sel_rd.value = select
    axi.drive(araddr=address, arprot=5, arvalid=1)
    await handshake(dut, axi.signal("arvalid"), axi.signal("arready"))
    dut.sel_rd.value = 0
    return await receive(dut, axi.signal("rvalid"), axi.signal("rready"), (axi.signal("rdata"), axi.signal("rresp")), stall_cycles)


async def write(dut, address, data, strobe, w_before_aw=False, select=TARGET0):
    """Returns BRESP. With w_before_aw, W is offered a cycle before AW and must wait for it."""
    axi = Port(dut, "S_AXI")
    dut.sel_wr.value = select
    axi.drive(wdata=data, wstrb=strobe)

    if w_before_aw:
        axi.wvalid = 1
        await FallingEdge(dut.CLK)
        await settle()
        assert axi.wready == 0

    axi.drive(awaddr=address, awprot=6, awvalid=1)
    data_handshake = cocotb.start_soon(handshake(dut, axi.signal("wvalid"), axi.signal("wready"))) if w_before_aw else None
    await handshake(dut, axi.signal("awvalid"), axi.signal("awready"))

    # the select and the address only matter while AW is offered
    dut.sel_wr.value = 0
    axi.drive(awaddr=0xFFFF, awprot=0)
    if w_before_aw:
        await data_handshake
    else:
        axi.wvalid = 1
        await handshake(dut, axi.signal("wvalid"), axi.signal("wready"))

    (response,) = await receive(dut, axi.signal("bvalid"), axi.signal("bready"), (axi.signal("bresp"),), stall_cycles=2)
    return response


def last_write(dut):
    names = ("write_count", "last_write_target", "last_write_address", "last_write_data", "last_write_strobe", "last_write_protection")
    return tuple(int(getattr(dut, name).value) for name in names)


@cocotb.test()
async def routes_by_select(dut):
    start_clock(dut)
    dut.sel_rd.value = 0
    dut.sel_wr.value = 0
    Port(dut, "S_AXI").drive(arvalid=0, araddr=0, arprot=0, rready=0, awvalid=0, awaddr=0, awprot=0, wvalid=0, wdata=0, wstrb=0, bready=0)
    await reset(dut)

    # the address does not decode anything, only the select does
    assert await read(dut, 0x0040, stall_cycles=2) == (0x10500040, OKAY)
    assert await read(dut, 0x0044, select=TARGET1) == (0x20500044, SLVERR)
    assert await read(dut, 0x1044, select=TARGET1) == (0x20501044, SLVERR)
    assert await read(dut, 0xFFFE) == (0x1050FFFE, OKAY)
    assert await read(dut, 0x0040, stall_cycles=2, select=NONE) == (0, DECERR)
    assert await read(dut, 0x0040, stall_cycles=2, select=BOTH) == (0, DECERR)

    assert await write(dut, 0x0080, 0xA5A50001, 0xD, w_before_aw=True) == OKAY
    assert last_write(dut) == (1, 0, 0x0080, 0xA5A50001, 0xD, 6)

    assert await write(dut, 0x1084, 0xA5A50002, 0x7, select=TARGET1) == SLVERR
    assert last_write(dut)[:3] == (2, 1, 0x1084)

    # rejected writes never reach a target
    assert await write(dut, 0x0080, 0xA5A50003, 0xF, select=NONE) == DECERR
    assert await write(dut, 0x0080, 0xA5A50003, 0xF, w_before_aw=True, select=BOTH) == DECERR
    assert last_write(dut)[0] == 2

    # a read and a write in flight at the same time
    concurrent_read = cocotb.start_soon(read(dut, 0x0090, stall_cycles=1))
    concurrent_write = cocotb.start_soon(write(dut, 0x0094, 0xA5A50004, 0xF, select=TARGET1))
    assert await concurrent_read == (0x10500090, OKAY)
    assert await concurrent_write == SLVERR
    assert last_write(dut)[:3] == (3, 1, 0x0094)
