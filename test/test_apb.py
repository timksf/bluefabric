import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge


async def reset_dut(dut):
    dut.RST_N.value = 0
    await RisingEdge(dut.CLK)
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1
    await RisingEdge(dut.CLK)


async def apb_transfer(dut, address, write, data, strobe, protection, address_user, write_user):
    dut.S_APB_paddr.value = address
    dut.S_APB_pwrite.value = write
    dut.S_APB_pwdata.value = data
    dut.S_APB_pstrb.value = strobe
    dut.S_APB_pprot.value = protection
    dut.S_APB_pauser.value = address_user
    dut.S_APB_pwuser.value = write_user
    dut.S_APB_psel.value = 1
    dut.S_APB_penable.value = 0
    await RisingEdge(dut.CLK)

    dut.S_APB_penable.value = 1
    wait_cycles = 0
    while True:
        await RisingEdge(dut.CLK)
        if dut.S_APB_pready.value:
            result = (
                int(dut.S_APB_prdata.value),
                int(dut.S_APB_pslverr.value),
                int(dut.S_APB_pruser.value),
                int(dut.S_APB_pbuser.value),
            )
            break
        wait_cycles += 1

    dut.S_APB_psel.value = 0
    dut.S_APB_penable.value = 0
    await RisingEdge(dut.CLK)
    assert wait_cycles == 0
    return result


@cocotb.test()
async def test_apb_slave(dut):
    if "Slave" not in dut._name:
        return

    cocotb.start_soon(Clock(dut.CLK, 10, "ns").start())
    dut.S_APB_psel.value = 0
    dut.S_APB_penable.value = 0
    await reset_dut(dut)

    for index in range(16):
        address = index * 4
        data = 0xA5A50000 | index
        result = await apb_transfer(
            dut,
            address,
            index & 1,
            data,
            0xF ^ (index & 0x3),
            index & 0x7,
            index & 0xF,
            (index + 1) & 0xF,
        )
        assert result == (
            address ^ data,
            int(bool(address & 0x10)),
            index & 0xF,
            (index + 1) & 0xF,
        )


@cocotb.test()
async def test_apb_master(dut):
    if "Master" not in dut._name:
        return

    cocotb.start_soon(Clock(dut.CLK, 10, "ns").start())
    dut.M_APB_pready.value = 0
    dut.M_APB_prdata.value = 0
    dut.M_APB_pslverr.value = 0
    dut.M_APB_pruser.value = 0
    dut.M_APB_pbuser.value = 0
    await reset_dut(dut)

    transaction = 0
    delay = 0
    completing = False

    while not dut.done.value:
        await FallingEdge(dut.CLK)

        if completing:
            transaction += 1
            delay = transaction % 3
            completing = False

        dut.M_APB_pready.value = 0

        if dut.M_APB_psel.value and dut.M_APB_penable.value:
            assert int(dut.M_APB_paddr.value) == 0x100 + transaction * 4
            assert int(dut.M_APB_pwrite.value) == (transaction & 1)
            assert int(dut.M_APB_pwdata.value) == 0xA5000000 | transaction
            assert int(dut.M_APB_pstrb.value) == (0xF if transaction & 1 else 0)
            assert int(dut.M_APB_pprot.value) == (transaction & 0x7)
            assert int(dut.M_APB_pauser.value) == transaction
            assert int(dut.M_APB_pwuser.value) == transaction + 1

            if delay:
                delay -= 1
            else:
                dut.M_APB_prdata.value = 0x55000000 | transaction
                dut.M_APB_pslverr.value = int(transaction == 3)
                dut.M_APB_pruser.value = transaction + 1
                dut.M_APB_pbuser.value = transaction + 2
                dut.M_APB_pready.value = 1
                completing = True

    assert int(dut.errors.value) == 0
    assert transaction == 8
