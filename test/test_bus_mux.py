import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer


async def reset_dut(dut):
    dut.RST_N.value = 0
    await RisingEdge(dut.CLK)
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1
    await RisingEdge(dut.CLK)


def port(dut, prefix, name):
    return getattr(dut, f"{prefix}_{name}")


async def apb_transfer(dut, address):
    dut.S_APB_paddr.value = address
    dut.S_APB_psel.value = 1
    dut.S_APB_penable.value = 0
    await RisingEdge(dut.CLK)

    dut.S_APB_penable.value = 1
    await Timer(1, "ps")

    if address < 0x1000:
        target = 0
        offset = address
    elif address < 0x2000:
        target = 1
        offset = address - 0x1000
    else:
        target = None
        offset = None

    if target is None:
        assert int(dut.S_APB_pready.value) == 1
        assert int(dut.S_APB_pslverr.value) == 1
        assert int(dut.M_APB0_psel.value) == 0
        assert int(dut.M_APB1_psel.value) == 0
    else:
        selected = f"M_APB{target}"
        other = f"M_APB{1 - target}"
        assert int(port(dut, selected, "psel").value) == 1
        assert int(port(dut, selected, "penable").value) == 1
        assert int(port(dut, selected, "paddr").value) == offset
        assert int(port(dut, selected, "pwrite").value) == 1
        assert int(port(dut, selected, "pwdata").value) == 0xA5A51234
        assert int(port(dut, selected, "pstrb").value) == 0xD
        assert int(port(dut, selected, "pprot").value) == 5
        assert int(port(dut, selected, "pauser").value) == 6
        assert int(port(dut, selected, "pwuser").value) == 7
        assert int(port(dut, other, "psel").value) == 0
        assert int(dut.S_APB_pready.value) == 1
        assert int(dut.S_APB_prdata.value) == 0x11000000 | target
        assert int(dut.S_APB_pslverr.value) == target

    await RisingEdge(dut.CLK)
    dut.S_APB_psel.value = 0
    dut.S_APB_penable.value = 0


@cocotb.test()
async def test_apb_slave_mux(dut):
    if dut._name != "mkTestApbSlaveMux":
        return

    cocotb.start_soon(Clock(dut.CLK, 10, "ns").start())
    dut.S_APB_psel.value = 0
    dut.S_APB_penable.value = 0
    dut.S_APB_pwrite.value = 1
    dut.S_APB_pwdata.value = 0xA5A51234
    dut.S_APB_pstrb.value = 0xD
    dut.S_APB_pprot.value = 5
    dut.S_APB_pauser.value = 6
    dut.S_APB_pwuser.value = 7

    for target in range(2):
        prefix = f"M_APB{target}"
        port(dut, prefix, "pready").value = 1
        port(dut, prefix, "prdata").value = 0x11000000 | target
        port(dut, prefix, "pslverr").value = target
        port(dut, prefix, "pruser").value = target + 2
        port(dut, prefix, "pbuser").value = target + 4

    await reset_dut(dut)

    await apb_transfer(dut, 0x0040)
    await apb_transfer(dut, 0x1044)
    await apb_transfer(dut, 0x3000)


def drive_apb_master(dut, index, selected, enabled=0):
    prefix = f"S_APB{index}"
    port(dut, prefix, "paddr").value = 0x100 + index * 0x40
    port(dut, prefix, "psel").value = selected
    port(dut, prefix, "penable").value = enabled
    port(dut, prefix, "pwrite").value = index
    port(dut, prefix, "pwdata").value = 0xA5000000 | index
    port(dut, prefix, "pstrb").value = 0xF - index
    port(dut, prefix, "pprot").value = 2 + index
    port(dut, prefix, "pauser").value = 4 + index
    port(dut, prefix, "pwuser").value = 6 + index


def check_apb_master_selected(dut, selected, enabled, ready=1):
    prefix = f"S_APB{selected}"
    assert int(dut.M_APB_psel.value) == 1
    assert int(dut.M_APB_penable.value) == enabled
    assert int(dut.M_APB_paddr.value) == 0x100 + selected * 0x40
    assert int(dut.M_APB_pwrite.value) == selected
    assert int(dut.M_APB_pwdata.value) == 0xA5000000 | selected
    assert int(dut.M_APB_pstrb.value) == 0xF - selected
    assert int(dut.M_APB_pprot.value) == 2 + selected
    assert int(dut.M_APB_pauser.value) == 4 + selected
    assert int(dut.M_APB_pwuser.value) == 6 + selected
    assert int(port(dut, prefix, "pready").value) == ready
    assert int(port(dut, prefix, "prdata").value) == 0x55001234
    assert int(port(dut, prefix, "pslverr").value) == 1
    assert int(port(dut, prefix, "pruser").value) == 9
    assert int(port(dut, prefix, "pbuser").value) == 10
    assert int(port(dut, f"S_APB{1 - selected}", "pready").value) == 0


@cocotb.test()
async def test_apb_master_mux(dut):
    if dut._name != "mkTestApbMasterMux":
        return

    cocotb.start_soon(Clock(dut.CLK, 10, "ns").start())
    for index in range(2):
        drive_apb_master(dut, index, 0)
    dut.M_APB_pready.value = 1
    dut.M_APB_prdata.value = 0x55001234
    dut.M_APB_pslverr.value = 1
    dut.M_APB_pruser.value = 9
    dut.M_APB_pbuser.value = 10
    await reset_dut(dut)

    dut.M_APB_pready.value = 0
    drive_apb_master(dut, 1, 1)
    await RisingEdge(dut.CLK)
    drive_apb_master(dut, 0, 1)
    drive_apb_master(dut, 1, 1, 1)
    await FallingEdge(dut.CLK)
    await Timer(1, "ps")
    check_apb_master_selected(dut, 1, 1, ready=0)

    dut.M_APB_pready.value = 1
    await RisingEdge(dut.CLK)
    drive_apb_master(dut, 1, 0)
    await FallingEdge(dut.CLK)
    await Timer(1, "ps")
    check_apb_master_selected(dut, 0, 0)

    drive_apb_master(dut, 0, 0)
    await reset_dut(dut)

    drive_apb_master(dut, 0, 1)
    drive_apb_master(dut, 1, 1)
    await FallingEdge(dut.CLK)
    await Timer(1, "ps")
    check_apb_master_selected(dut, 0, 0)

    await RisingEdge(dut.CLK)
    drive_apb_master(dut, 0, 1, 1)
    await FallingEdge(dut.CLK)
    await Timer(1, "ps")
    check_apb_master_selected(dut, 0, 1)

    await RisingEdge(dut.CLK)
    drive_apb_master(dut, 0, 0)
    await FallingEdge(dut.CLK)
    await Timer(1, "ps")
    check_apb_master_selected(dut, 1, 0)

    await RisingEdge(dut.CLK)
    drive_apb_master(dut, 1, 1, 1)
    await FallingEdge(dut.CLK)
    await Timer(1, "ps")
    check_apb_master_selected(dut, 1, 1)

    await RisingEdge(dut.CLK)
    drive_apb_master(dut, 0, 1)
    drive_apb_master(dut, 1, 1)
    await FallingEdge(dut.CLK)
    await Timer(1, "ps")
    check_apb_master_selected(dut, 0, 0)


@cocotb.test()
async def test_ahb_slave_mux(dut):
    if dut._name != "mkTestAhbSlaveMux":
        return

    cocotb.start_soon(Clock(dut.CLK, 10, "ns").start())
    dut.S_AHB_hsel.value = 0
    dut.S_AHB_htrans.value = 0
    dut.S_AHB_haddr.value = 0
    dut.S_AHB_hwrite.value = 1
    dut.S_AHB_hsize.value = 2
    dut.S_AHB_hburst.value = 0
    dut.S_AHB_hprot.value = 9
    dut.S_AHB_hmastlock.value = 1
    dut.S_AHB_hwdata.value = 0xA5000000
    dut.S_AHB_hreadyin.value = 0

    for target in range(2):
        prefix = f"M_AHB{target}"
        port(dut, prefix, "hready").value = 1
        port(dut, prefix, "hrdata").value = 0x22000000 | target
        port(dut, prefix, "hresp").value = 0

    await reset_dut(dut)

    addresses = [0x0040, 0x1044, 0x0080, 0x3000]
    expected_targets = [0, 1, 0, None]
    address_index = 0
    data_index = None
    miss_first_seen = False
    completed = 0
    cycles = 0

    while completed < len(addresses):
        await FallingEdge(dut.CLK)

        await Timer(1, "ps")
        ready = int(dut.S_AHB_hreadyout.value)
        dut.S_AHB_hreadyin.value = ready
        await Timer(1, "ps")
        for target_port in range(2):
            assert int(
                port(dut, f"M_AHB{target_port}", "hreadyin").value
            ) == ready

        if data_index is not None:
            target = expected_targets[data_index]
            if target is None:
                assert int(dut.S_AHB_hresp.value) == 1
                if ready:
                    assert miss_first_seen
                    miss_first_seen = False
                    completed += 1
                else:
                    assert not miss_first_seen
                    miss_first_seen = True
            elif ready:
                assert int(dut.S_AHB_hresp.value) == 0
                assert int(dut.S_AHB_hrdata.value) == 0x22000000 | target
                completed += 1

        if ready:
            data_index = address_index if address_index < len(addresses) else None
            if address_index < len(addresses):
                address = addresses[address_index]
                target = expected_targets[address_index]
                dut.S_AHB_hsel.value = 1
                dut.S_AHB_htrans.value = 2
                dut.S_AHB_haddr.value = address

                await Timer(1, "ps")
                for target_port in range(2):
                    prefix = f"M_AHB{target_port}"
                    assert int(port(dut, prefix, "hsel").value) == int(
                        target == target_port
                    )
                    assert int(port(dut, prefix, "htrans").value) == 2
                    assert int(port(dut, prefix, "hwrite").value) == 1
                    assert int(port(dut, prefix, "hsize").value) == 2
                    assert int(port(dut, prefix, "hburst").value) == 0
                    assert int(port(dut, prefix, "hprot").value) == 9
                    assert int(port(dut, prefix, "hmastlock").value) == 1
                    if target == target_port:
                        assert int(port(dut, prefix, "haddr").value) == (
                            address - target_port * 0x1000
                        )

                address_index += 1
            else:
                dut.S_AHB_hsel.value = 0
                dut.S_AHB_htrans.value = 0

        await RisingEdge(dut.CLK)
        cycles += 1
        assert cycles < 20

    assert cycles <= 8


def drive_ahb_master(
    dut,
    index,
    address=0,
    transfer=0,
    data=0,
    burst=0,
    lock=0,
):
    prefix = f"S_AHB{index}"
    port(dut, prefix, "haddr").value = address
    port(dut, prefix, "hsel").value = int(transfer != 0)
    port(dut, prefix, "htrans").value = transfer
    port(dut, prefix, "hwrite").value = index & 1
    port(dut, prefix, "hsize").value = 2
    port(dut, prefix, "hburst").value = burst
    port(dut, prefix, "hprot").value = 8 + index
    port(dut, prefix, "hmastlock").value = lock
    port(dut, prefix, "hwdata").value = data
    port(dut, prefix, "hreadyin").value = 1


def check_ahb_downstream(dut, selected, address, transfer, data):
    assert int(dut.M_AHB_hsel.value) == int(transfer != 0)
    assert int(dut.M_AHB_htrans.value) == transfer
    assert int(dut.M_AHB_haddr.value) == address
    assert int(dut.M_AHB_hwrite.value) == (selected & 1)
    assert int(dut.M_AHB_hsize.value) == 2
    assert int(dut.M_AHB_hprot.value) == 8 + selected
    assert int(dut.M_AHB_hwdata.value) == data


def check_ahb_idle(dut, data):
    assert int(dut.M_AHB_hsel.value) == 0
    assert int(dut.M_AHB_htrans.value) == 0
    assert int(dut.M_AHB_hwdata.value) == data


def check_ready(dut, *ready_indices):
    expected = set(ready_indices)
    for index in range(3):
        assert int(port(dut, f"S_AHB{index}", "hreadyout").value) == int(
            index in expected
        )


def check_response_owner(dut, owner):
    for index in range(3):
        prefix = f"S_AHB{index}"
        if index == owner:
            assert int(port(dut, prefix, "hrdata").value) == 0x66001234
            assert int(port(dut, prefix, "hresp").value) == 1
        else:
            assert int(port(dut, prefix, "hrdata").value) == 0
            assert int(port(dut, prefix, "hresp").value) == 0


async def sample_falling(dut):
    await FallingEdge(dut.CLK)
    await Timer(1, "ps")


@cocotb.test()
async def test_ahb_master_mux(dut):
    if dut._name != "mkTestAhbMasterMux":
        return

    cocotb.start_soon(Clock(dut.CLK, 10, "ns").start())
    for index in range(3):
        drive_ahb_master(dut, index)
    dut.M_AHB_hready.value = 1
    dut.M_AHB_hrdata.value = 0x66001234
    dut.M_AHB_hresp.value = 1
    await reset_dut(dut)

    # An uncontended manager retains full AHB address/data overlap.
    drive_ahb_master(dut, 0, 0x100, 2)
    await sample_falling(dut)
    check_ahb_downstream(dut, 0, 0x100, 2, 0)
    check_ready(dut, 0)
    check_response_owner(dut, None)

    await RisingEdge(dut.CLK)
    drive_ahb_master(dut, 0, 0x104, 2, 0xA0000100)
    await sample_falling(dut)
    check_ahb_downstream(dut, 0, 0x104, 2, 0xA0000100)
    check_ready(dut, 0)
    check_response_owner(dut, 0)

    # Three continuously requesting managers rotate at SINGLE boundaries.
    for index in range(3):
        drive_ahb_master(dut, index)
    await reset_dut(dut)

    drive_ahb_master(dut, 0, 0x100, 2)
    drive_ahb_master(dut, 1, 0x200, 2)
    drive_ahb_master(dut, 2, 0x300, 2)
    await sample_falling(dut)
    check_ahb_downstream(dut, 0, 0x100, 2, 0)
    check_ready(dut, 0)

    # A downstream wait state freezes the selected address phase.
    dut.M_AHB_hready.value = 0
    await RisingEdge(dut.CLK)
    await sample_falling(dut)
    check_ahb_downstream(dut, 0, 0x100, 2, 0)
    check_ready(dut)

    dut.M_AHB_hready.value = 1
    await RisingEdge(dut.CLK)
    drive_ahb_master(dut, 0, 0x104, 2, 0xA0000100)
    await sample_falling(dut)
    check_ahb_idle(dut, 0xA0000100)
    check_ready(dut, 0)
    check_response_owner(dut, 0)

    # The handover bubble also remains stable across downstream wait states.
    dut.M_AHB_hready.value = 0
    await RisingEdge(dut.CLK)
    await sample_falling(dut)
    check_ahb_idle(dut, 0xA0000100)
    check_ready(dut)
    check_response_owner(dut, 0)

    dut.M_AHB_hready.value = 1
    await RisingEdge(dut.CLK)
    drive_ahb_master(dut, 0, 0x108, 2, 0xA0000104)
    await sample_falling(dut)
    check_ahb_downstream(dut, 1, 0x200, 2, 0)
    check_ready(dut, 1)
    check_response_owner(dut, None)

    await RisingEdge(dut.CLK)
    drive_ahb_master(dut, 1, 0x204, 2, 0xB0000200)
    await sample_falling(dut)
    check_ahb_idle(dut, 0xB0000200)
    check_ready(dut, 1)
    check_response_owner(dut, 1)

    await RisingEdge(dut.CLK)
    drive_ahb_master(dut, 1, 0x208, 2, 0xB0000204)
    await sample_falling(dut)
    check_ahb_downstream(dut, 2, 0x300, 2, 0)
    check_ready(dut, 2)
    check_response_owner(dut, None)

    await RisingEdge(dut.CLK)
    drive_ahb_master(dut, 2, 0x304, 2, 0xC0000300)
    await sample_falling(dut)
    check_ahb_idle(dut, 0xC0000300)
    check_ready(dut, 2)
    check_response_owner(dut, 2)

    await RisingEdge(dut.CLK)
    drive_ahb_master(dut, 2, 0x308, 2, 0xC0000304)
    await sample_falling(dut)
    check_ahb_downstream(dut, 0, 0x104, 2, 0)
    check_ready(dut)
    check_response_owner(dut, None)

    await RisingEdge(dut.CLK)
    await sample_falling(dut)
    check_ahb_idle(dut, 0xA0000104)
    check_ready(dut, 0)
    check_response_owner(dut, 0)

    # Fixed-length bursts remain intact and rotate only after their final beat.
    for index in range(3):
        drive_ahb_master(dut, index)
    await reset_dut(dut)

    drive_ahb_master(dut, 0, 0x400, 2, burst=3)
    drive_ahb_master(dut, 1, 0x500, 2)
    for beat in range(4):
        await sample_falling(dut)
        transfer = 2 if beat == 0 else 3
        data = 0 if beat == 0 else 0xD0000000 | (0x400 + 4 * (beat - 1))
        check_ahb_downstream(dut, 0, 0x400 + 4 * beat, transfer, data)
        check_ready(dut, 0)
        assert int(dut.M_AHB_hburst.value) == 3

        await RisingEdge(dut.CLK)
        drive_ahb_master(
            dut,
            0,
            0x404 + 4 * beat,
            3 if beat < 3 else 2,
            0xD0000000 | (0x400 + 4 * beat),
            burst=3 if beat < 3 else 0,
        )

    await sample_falling(dut)
    check_ahb_idle(dut, 0xD000040C)
    check_ready(dut, 0)

    await RisingEdge(dut.CLK)
    await sample_falling(dut)
    check_ahb_downstream(dut, 1, 0x500, 2, 0)

    # Locked transfers retain ownership until an unlocked boundary completes.
    for index in range(3):
        drive_ahb_master(dut, index)
    await reset_dut(dut)

    drive_ahb_master(dut, 0, 0x600, 2, lock=1)
    drive_ahb_master(dut, 1, 0x700, 2)
    for beat in range(3):
        await sample_falling(dut)
        data = 0 if beat == 0 else 0xE0000000 | (0x600 + 4 * (beat - 1))
        check_ahb_downstream(dut, 0, 0x600 + 4 * beat, 2, data)
        assert int(dut.M_AHB_hmastlock.value) == int(beat < 2)
        check_ready(dut, 0)

        await RisingEdge(dut.CLK)
        drive_ahb_master(
            dut,
            0,
            0x604 + 4 * beat,
            2,
            0xE0000000 | (0x600 + 4 * beat),
            lock=int(beat == 0),
        )

    await sample_falling(dut)
    check_ahb_idle(dut, 0xE0000608)
    check_ready(dut, 0)

    await RisingEdge(dut.CLK)
    await sample_falling(dut)
    check_ahb_downstream(dut, 1, 0x700, 2, 0)
