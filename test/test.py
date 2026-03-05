# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

"""
Smoke test for the TT wrapper (tt_um_example / tb.v).

Bit-bangs the SPI slave interface through the TT pin mapping:
  ui_in[0] = slave_sck_ext
  ui_in[1] = slave_scs_ext
  ui_in[2] = slave_mosi_ext
  uo_out[0] = slave_miso

Sends OP_READ with no weights loaded and verifies OP_RESP_INVALID is returned.
No external RAM slave is wired, so only the SPI command path is tested.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

OP_READ = 0x3
OP_RESP_INVALID = 0x2
SPI_HALF_NS = 200


async def spi_send_word(dut, word_16bit, half_period=SPI_HALF_NS):
    """Bit-bang a 16-bit SPI word through the TT pin interface."""
    received = 0

    # CS low
    dut.ui_in.value = dut.ui_in.value.integer & ~(1 << 1)
    await Timer(half_period * 2, units="ns")

    for i in range(15, -1, -1):
        bit = (word_16bit >> i) & 1
        # Set MOSI (ui_in[2]), keep CS low (ui_in[1]=0), SCK low (ui_in[0]=0)
        base = dut.ui_in.value.integer & ~0x7  # clear bits [2:0]
        dut.ui_in.value = base | (bit << 2)     # MOSI = bit, SCK=0, CS=0

        await Timer(half_period, units="ns")

        # SCK high
        dut.ui_in.value = dut.ui_in.value.integer | 1  # ui_in[0] = 1
        await Timer(1, units="ns")
        received |= (int(dut.uo_out.value) & 1) << i  # sample MISO = uo_out[0]

        await Timer(half_period - 1, units="ns")

        # SCK low
        dut.ui_in.value = dut.ui_in.value.integer & ~1  # ui_in[0] = 0

    await Timer(half_period * 2, units="ns")

    # CS high
    dut.ui_in.value = dut.ui_in.value.integer | (1 << 1)
    await Timer(half_period * 4, units="ns")

    return received


@cocotb.test()
async def test_tt_spi_smoke(dut):
    """Send OP_READ through TT pins with no weights — expect OP_RESP_INVALID."""
    dut._log.info("Start")

    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut.ena.value = 1
    dut.ui_in.value = 0b010  # CS high (bit 1), SCK low, MOSI low
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 30)

    # Send OP_READ (no weights loaded)
    await spi_send_word(dut, OP_READ << 12)
    # Dummy word to clock out the response
    resp = await spi_send_word(dut, 0x0000)

    opcode = (resp >> 12) & 0xF
    dut._log.info(f"OP_READ response: {resp:#06x}, opcode={opcode:#x}")
    assert opcode == OP_RESP_INVALID, \
        f"Expected OP_RESP_INVALID ({OP_RESP_INVALID:#x}), got {opcode:#x}"

    dut._log.info("TT SPI smoke test passed")
