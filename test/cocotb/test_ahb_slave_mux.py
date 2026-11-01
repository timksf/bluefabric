"""mkAhbSlaveMux through mkTestAhbSlaveMux: the upstream port S_AHB is decoded onto M_AHB0 (0x0000) and M_AHB1 (0x1000), 4 KiB each.

Back-to-back pipelined reads, the address phase of each transfer overlaps the data phase of the previous one. Target t
answers without wait states with HRDATA 0x22000000 | t. A miss is answered by the mux with a two-cycle ERROR.
"""

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge

from tb import IDLE, NONSEQ, SINGLE, WORD, Port, reset, settle, start_clock

# address and the target it decodes to, None for a miss
TRANSFERS = [(0x0040, 0), (0x1044, 1), (0x0080, 0), (0x3000, None)]

# request signals other than address and select, forwarded to every target
REQUEST = dict(hwrite=1, hsize=WORD, hburst=SINGLE, hprot=9, hmastlock=1)


@cocotb.test()
async def routes_pipelined_transfers(dut):
    start_clock(dut)
    upstream = Port(dut, "S_AHB")
    targets = [Port(dut, "M_AHB0"), Port(dut, "M_AHB1")]
    upstream.drive(hsel=0, htrans=IDLE, haddr=0, hwdata=0xA5000000, hreadyin=0, **REQUEST)
    for t, target in enumerate(targets):
        target.drive(hready=1, hrdata=0x22000000 | t, hresp=0)
    await reset(dut)

    next_transfer = 0      # index of the next address phase
    data_transfer = None   # index of the transfer in its data phase
    error_started = False  # the first cycle of a two-cycle ERROR response was seen
    completed = 0
    cycles = 0

    while completed < len(TRANSFERS):
        await FallingEdge(dut.CLK)
        await settle()

        # a single manager: HREADY follows the mux's HREADYOUT, and the mux passes it on to every target
        ready = upstream.hreadyout
        upstream.hreadyin = ready
        await settle()
        assert all(target.hreadyin == ready for target in targets)

        if data_transfer is not None:
            target = TRANSFERS[data_transfer][1]
            if target is None:
                assert upstream.hresp == 1
                assert error_started == bool(ready), "an ERROR response takes exactly two cycles"
                error_started = not ready
                completed += ready
            elif ready:
                assert upstream.read("hresp", "hrdata") == (0, 0x22000000 | target)
                completed += 1

        if ready:
            data_transfer = next_transfer if next_transfer < len(TRANSFERS) else None
            if next_transfer < len(TRANSFERS):
                address, target = TRANSFERS[next_transfer]
                upstream.drive(hsel=1, htrans=NONSEQ, haddr=address)
                await settle()
                for t, port in enumerate(targets):
                    assert port.hsel == int(target == t)
                    assert port.htrans == NONSEQ
                    assert port.read(*REQUEST) == tuple(REQUEST.values())
                    if target == t:
                        assert port.haddr == address
                next_transfer += 1
            else:
                upstream.drive(hsel=0, htrans=IDLE)

        await RisingEdge(dut.CLK)
        cycles += 1
        assert cycles < 20

    # three single-cycle transfers and one two-cycle error, pipelined
    assert cycles <= 8
