"""mkAddrMapDecoder and mkAddrMapDecoderFab through mkTestAddrMapDecoder, over the whole 8-bit address space.

Besides the main map the DUT decodes a single region covering everything (full_sel) and two adjacent halves
(adjacent_sel). The decoders are combinational, so the test never clocks the DUT.
"""

import cocotb
from cocotb.triggers import Timer

# the main map, unsorted on purpose: the declaration order sets the select bit, not the address order
REGIONS = ((0xA0, 0x10), (0x00, 0x10), (0xFF, 1), (0x40, 0x20))
HALVES = ((0x00, 0x80), (0x80, 0x80))


def select(regions, address):
    return sum(1 << i for i, (base, size) in enumerate(regions) if base <= address < base + size)


@cocotb.test()
async def decodes_every_address(dut):
    dut.CLK.value = 0
    dut.RST_N.value = 1

    for address in range(256):
        dut.address.value = address
        await Timer(1, "ns")

        expected = select(REGIONS, address)
        assert int(dut.sel.value) == expected, (address, expected)
        assert int(dut.fab_sel.value) == expected
        assert int(dut.route_sel.value) == expected
        assert int(dut.hit.value) == bool(expected)
        assert int(dut.offset.value) == (address - REGIONS[expected.bit_length() - 1][0] if expected else 0)

        assert int(dut.full_sel.value) == 1
        assert int(dut.adjacent_sel.value) == select(HALVES, address)
