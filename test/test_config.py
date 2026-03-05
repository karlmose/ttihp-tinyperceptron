"""
Configuration/control tests for pred_top.

Tests:
  - test_set_cs_wait:  Verify OP_SET_CS_WAIT changes the register
  - test_reset_buffer: Verify OP_RESET_BUF clears state mid-prediction
  - test_set_clk_div:  Verify OP_SET_CLK_DIV changes the SPI clock divisor
"""

import cocotb
from cocotb.triggers import ClockCycles
from helpers import (
    start_clocks, parse_read_response,
    set_ram, ram_addr, to_unsigned_8,
    OP_RESP_VALID, OP_RESP_INVALID,
)


@cocotb.test()
async def test_set_cs_wait(dut):
    """Verify OP_SET_CS_WAIT changes the CS wait cycles register."""
    spi = await start_clocks(dut)

    cs_wait = int(dut.dut.slave.cs_wait_cycles.value)
    dut._log.info(f"Default cs_wait_cycles: {cs_wait}")
    assert cs_wait == 15, f"Expected default 15, got {cs_wait}"

    await spi.cmd_set_cs_wait(30)
    await ClockCycles(dut.clk, 10)

    cs_wait = int(dut.dut.slave.cs_wait_cycles.value)
    dut._log.info(f"After set: cs_wait_cycles: {cs_wait}")
    assert cs_wait == 30, f"Expected 30, got {cs_wait}"


@cocotb.test()
async def test_reset_buffer(dut):
    """Verify OP_RESET_BUF clears the perceptron state mid-prediction."""
    spi = await start_clocks(dut)

    set_ram(dut, ram_addr(0, 0x50), to_unsigned_8(100))
    await spi.cmd_add_weight(0x50)

    # Poll until prediction ready
    opcode, _, sum_val = await spi.cmd_read_poll()
    assert opcode == OP_RESP_VALID
    assert sum_val == 100, f"Expected 100 before reset, got {sum_val}"

    # Reset mid-prediction (cancel, not update)
    await spi.cmd_reset_buffer()
    await ClockCycles(dut.clk, 20)

    # Read — should report invalid (no weights loaded)
    resp = await spi.cmd_read_raw()
    opcode, _, _ = parse_read_response(resp)
    dut._log.info(f"After reset, OP_READ opcode: {opcode:#x}")
    assert opcode == OP_RESP_INVALID, f"Expected INVALID after reset, got {opcode:#x}"


@cocotb.test()
async def test_set_cs_wait_boundaries(dut):
    """Set cs_wait to 0 and 255 — boundary values must be accepted."""
    spi = await start_clocks(dut)

    # Set to 0
    await spi.cmd_set_cs_wait(0)
    await ClockCycles(dut.clk, 10)
    cs_wait = int(dut.dut.slave.cs_wait_cycles.value)
    assert cs_wait == 0, f"Expected cs_wait=0, got {cs_wait}"
    dut._log.info(f"cs_wait=0 ✓")

    # Set to 255
    await spi.cmd_set_cs_wait(255)
    await ClockCycles(dut.clk, 10)
    cs_wait = int(dut.dut.slave.cs_wait_cycles.value)
    assert cs_wait == 255, f"Expected cs_wait=255, got {cs_wait}"
    dut._log.info(f"cs_wait=255 ✓")

    # Restore to default for subsequent tests
    await spi.cmd_set_cs_wait(15)
    await ClockCycles(dut.clk, 10)
    cs_wait = int(dut.dut.slave.cs_wait_cycles.value)
    assert cs_wait == 15, f"Expected cs_wait=15, got {cs_wait}"


@cocotb.test()
async def test_double_reset_isolation(dut):
    """Add weight, reset, add different weight → verify only 2nd contributes."""
    spi = await start_clocks(dut)

    # First weight: +100
    set_ram(dut, ram_addr(0, 0x50), to_unsigned_8(100))
    await spi.cmd_add_weight(0x50)

    opcode, _, sum1 = await spi.cmd_read_poll()
    assert opcode == OP_RESP_VALID
    assert sum1 == 100, f"Before reset, expected 100, got {sum1}"

    # Reset
    await spi.cmd_reset_buffer()
    await ClockCycles(dut.clk, 20)

    # Verify reset cleared state
    resp = await spi.cmd_read_raw()
    opcode_after_reset, _, _ = parse_read_response(resp)
    assert opcode_after_reset == OP_RESP_INVALID, \
        f"After reset, expected INVALID, got {opcode_after_reset:#x}"

    # Second weight: +25 (different)
    set_ram(dut, ram_addr(0, 0x60), to_unsigned_8(25))
    await spi.cmd_add_weight(0x60)

    opcode2, valid2, sum2 = await spi.cmd_read_poll()
    assert opcode2 == OP_RESP_VALID, f"Expected VALID, got {opcode2:#x}"
    assert valid2 == 1, "Valid bit should be 1"
    assert sum2 == 25, f"After reset+new weight, expected 25, got {sum2}"
    dut._log.info(f"Double reset isolation: sum={sum2} (isolated from first {sum1}) ✓")


@cocotb.test()
async def test_set_clk_div(dut):
    """Verify OP_SET_CLK_DIV changes the SPI master clock divisor."""
    spi = await start_clocks(dut)

    # Check default: 1 (div-by-4, 50MHz → 12.5MHz)
    clk_div = int(dut.dut.slave.spi_clk_div.value)
    assert clk_div == 1, f"Expected default clk_div=1, got {clk_div}"

    # Set to 3 (div-by-16)
    await spi.cmd_set_clk_div(3)
    await ClockCycles(dut.clk, 10)

    clk_div = int(dut.dut.slave.spi_clk_div.value)
    assert clk_div == 3, f"Expected clk_div=3, got {clk_div}"

    # Verify functionality still works at the new clock rate
    set_ram(dut, ram_addr(0, 0x42), to_unsigned_8(77))
    await spi.cmd_add_weight(0x42)

    opcode, valid_bit, sum_signed = await spi.cmd_read_poll(max_attempts=20)
    assert opcode == OP_RESP_VALID, f"Expected VALID at clk_div=3, got {opcode:#x}"
    assert sum_signed == 77, f"Expected 77 at clk_div=3, got {sum_signed}"

    # Restore default
    await spi.cmd_set_clk_div(1)
    await ClockCycles(dut.clk, 10)
    clk_div = int(dut.dut.slave.spi_clk_div.value)
    assert clk_div == 1, f"Expected restored clk_div=1, got {clk_div}"


@cocotb.test()
async def test_set_clk_div_boundaries(dut):
    """Set clk_div to 0 (fastest, /2) and 7 (slowest, /256) — both accepted."""
    spi = await start_clocks(dut)

    # Fastest: div-by-2
    await spi.cmd_set_clk_div(0)
    await ClockCycles(dut.clk, 10)
    clk_div = int(dut.dut.slave.spi_clk_div.value)
    assert clk_div == 0, f"Expected clk_div=0, got {clk_div}"

    # Slowest: div-by-256
    await spi.cmd_set_clk_div(7)
    await ClockCycles(dut.clk, 10)
    clk_div = int(dut.dut.slave.spi_clk_div.value)
    assert clk_div == 7, f"Expected clk_div=7, got {clk_div}"

    # Restore default
    await spi.cmd_set_clk_div(2)
    await ClockCycles(dut.clk, 10)
