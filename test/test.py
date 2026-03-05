# SPDX-FileCopyrightText: 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

"""TT wrapper smoke test — verifies SPI command path through TT pin mapping."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

OP_READ = 0x3
OP_RESP_INVALID = 0x2
SPI_HALF_NS = 200


async def spi_send_word(dut, word_16bit, half_period=SPI_HALF_NS):
    received = 0

    dut.ui_in.value = dut.ui_in.value.to_unsigned() & ~(1 << 1)
    await Timer(half_period * 2, unit="ns")

    for i in range(15, -1, -1):
        bit = (word_16bit >> i) & 1
        base = dut.ui_in.value.to_unsigned() & ~0x7
        dut.ui_in.value = base | (bit << 2)

        await Timer(half_period, unit="ns")
        dut.ui_in.value = dut.ui_in.value.to_unsigned() | 1
        await Timer(1, unit="ns")
        received |= (int(dut.uo_out.value) & 1) << i
        await Timer(half_period - 1, unit="ns")
        dut.ui_in.value = dut.ui_in.value.to_unsigned() & ~1

    await Timer(half_period * 2, unit="ns")
    dut.ui_in.value = dut.ui_in.value.to_unsigned() | (1 << 1)
    await Timer(half_period * 4, unit="ns")

    return received


@cocotb.test()
async def test_tt_spi_smoke(dut):
    """Send OP_READ through TT pins with no weights — expect OP_RESP_INVALID."""
    clock = Clock(dut.clk, 10, unit="ns")  # 100MHz
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0b010
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 30)

    await spi_send_word(dut, OP_READ << 12)
    resp = await spi_send_word(dut, 0x0000)

    opcode = (resp >> 12) & 0xF
    dut._log.info(f"OP_READ response: {resp:#06x}, opcode={opcode:#x}")
    assert opcode == OP_RESP_INVALID, \
        f"Expected OP_RESP_INVALID ({OP_RESP_INVALID:#x}), got {opcode:#x}"
