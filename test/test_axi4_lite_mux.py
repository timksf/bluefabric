import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer


async def reset_dut(dut):
    dut.RST_N.value = 0
    await RisingEdge(dut.CLK)
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1
    await RisingEdge(dut.CLK)


async def complete_channel(dut, valid, ready):
    for _ in range(20):
        await Timer(1, "ps")
        if int(ready.value):
            await RisingEdge(dut.CLK)
            valid.value = 0
            return
        await FallingEdge(dut.CLK)
    raise AssertionError(f"{valid._name} did not receive ready")


async def receive_response(dut, valid, ready, payload, stall_cycles):
    ready.value = 0
    for _ in range(20):
        await FallingEdge(dut.CLK)
        await Timer(1, "ps")
        if int(valid.value):
            expected = tuple(int(signal.value) for signal in payload)
            break
    else:
        raise AssertionError(f"{valid._name} was not asserted")

    for _ in range(stall_cycles):
        await RisingEdge(dut.CLK)
        await FallingEdge(dut.CLK)
        await Timer(1, "ps")
        assert int(valid.value) == 1
        assert tuple(int(signal.value) for signal in payload) == expected

    ready.value = 1
    await RisingEdge(dut.CLK)
    ready.value = 0
    return expected


async def axi_read(dut, address, stall_cycles=0):
    dut.S_AXI_araddr.value = address
    dut.S_AXI_arprot.value = 5
    dut.S_AXI_arvalid.value = 1
    await complete_channel(
        dut,
        dut.S_AXI_arvalid,
        dut.S_AXI_arready,
    )
    return await receive_response(
        dut,
        dut.S_AXI_rvalid,
        dut.S_AXI_rready,
        (dut.S_AXI_rdata, dut.S_AXI_rresp),
        stall_cycles,
    )


async def axi_write(dut, address, data, strobe, w_before_aw=False):
    dut.S_AXI_wdata.value = data
    dut.S_AXI_wstrb.value = strobe

    if w_before_aw:
        dut.S_AXI_wvalid.value = 1
        await FallingEdge(dut.CLK)
        await Timer(1, "ps")
        assert int(dut.S_AXI_wready.value) == 0

    dut.S_AXI_awaddr.value = address
    dut.S_AXI_awprot.value = 6
    dut.S_AXI_awvalid.value = 1
    await complete_channel(
        dut,
        dut.S_AXI_awvalid,
        dut.S_AXI_awready,
    )

    if not w_before_aw:
        dut.S_AXI_wvalid.value = 1
    await complete_channel(
        dut,
        dut.S_AXI_wvalid,
        dut.S_AXI_wready,
    )

    (response,) = await receive_response(
        dut,
        dut.S_AXI_bvalid,
        dut.S_AXI_bready,
        (dut.S_AXI_bresp,),
        2,
    )
    return response


@cocotb.test()
async def test_axi4_lite_slave_mux(dut):
    cocotb.start_soon(Clock(dut.CLK, 10, "ns").start())

    dut.S_AXI_arvalid.value = 0
    dut.S_AXI_araddr.value = 0
    dut.S_AXI_arprot.value = 0
    dut.S_AXI_rready.value = 0
    dut.S_AXI_awvalid.value = 0
    dut.S_AXI_awaddr.value = 0
    dut.S_AXI_awprot.value = 0
    dut.S_AXI_wvalid.value = 0
    dut.S_AXI_wdata.value = 0
    dut.S_AXI_wstrb.value = 0
    dut.S_AXI_bready.value = 0
    await reset_dut(dut)

    assert await axi_read(dut, 0x0040, 2) == (0x10500040, 0)
    assert await axi_read(dut, 0x1044) == (0x20500044, 2)
    assert await axi_read(dut, 0x0FFE) == (0, 3)
    assert await axi_read(dut, 0x3000) == (0, 3)

    assert await axi_write(
        dut,
        0x0080,
        0xA5A50001,
        0xD,
        w_before_aw=True,
    ) == 0
    assert int(dut.write_count.value) == 1
    assert int(dut.last_write_target.value) == 0
    assert int(dut.last_write_address.value) == 0x0080
    assert int(dut.last_write_data.value) == 0xA5A50001
    assert int(dut.last_write_strobe.value) == 0xD
    assert int(dut.last_write_protection.value) == 6

    assert await axi_write(dut, 0x1084, 0xA5A50002, 0x7) == 2
    assert int(dut.write_count.value) == 2
    assert int(dut.last_write_target.value) == 1
    assert int(dut.last_write_address.value) == 0x0084

    assert await axi_write(dut, 0x3000, 0xA5A50003, 0xF) == 3
    assert int(dut.write_count.value) == 2

    read_task = cocotb.start_soon(axi_read(dut, 0x0090, 1))
    write_task = cocotb.start_soon(
        axi_write(dut, 0x1094, 0xA5A50004, 0xF)
    )
    assert await read_task == (0x10500090, 0)
    assert await write_task == 2
    assert int(dut.write_count.value) == 3
    assert int(dut.last_write_target.value) == 1
    assert int(dut.last_write_address.value) == 0x0094
