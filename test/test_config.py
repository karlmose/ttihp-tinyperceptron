"""Configuration/control tests — CS wait, buffer reset, clock divisor."""

import cocotb
from cocotb.triggers import ClockCycles
from helpers import (
    start_clocks, parse_read_response,
    set_ram, ram_addr, to_unsigned_8,
    OP_RESP_VALID, OP_RESP_INVALID,
)


@cocotb.test()
async def test_set_cs_wait(dut):
    spi = await start_clocks(dut)

    cs_wait = int(dut.dut.slave.cs_wait_cfg.value)
    assert cs_wait == 3, f"Expected default 3, got {cs_wait}"

    await spi.cmd_set_cs_wait(5)
    await ClockCycles(dut.clk, 10)

    cs_wait = int(dut.dut.slave.cs_wait_cfg.value)
    assert cs_wait == 5, f"Expected 5, got {cs_wait}"


@cocotb.test()
async def test_reset_buffer(dut):
    spi = await start_clocks(dut)

    set_ram(dut, ram_addr(0, 0x50), to_unsigned_8(100))
    await spi.cmd_add_weight(0x50)

    opcode, _, sum_val = await spi.cmd_read_poll()
    assert opcode == OP_RESP_VALID
    assert sum_val == 100, f"Expected 100 before reset, got {sum_val}"

    await spi.cmd_reset_buffer()
    await ClockCycles(dut.clk, 20)

    resp = await spi.cmd_read_raw()
    opcode, _, _ = parse_read_response(resp)
    assert opcode == OP_RESP_INVALID, f"Expected INVALID after reset, got {opcode:#x}"


@cocotb.test()
async def test_set_cs_wait_boundaries(dut):
    spi = await start_clocks(dut)

    await spi.cmd_set_cs_wait(0)
    await ClockCycles(dut.clk, 10)
    assert int(dut.dut.slave.cs_wait_cfg.value) == 0

    await spi.cmd_set_cs_wait(7)
    await ClockCycles(dut.clk, 10)
    assert int(dut.dut.slave.cs_wait_cfg.value) == 7

    await spi.cmd_set_cs_wait(3)
    await ClockCycles(dut.clk, 10)
    assert int(dut.dut.slave.cs_wait_cfg.value) == 3


@cocotb.test()
async def test_double_reset_isolation(dut):
    spi = await start_clocks(dut)

    set_ram(dut, ram_addr(0, 0x50), to_unsigned_8(100))
    await spi.cmd_add_weight(0x50)

    opcode, _, sum1 = await spi.cmd_read_poll()
    assert opcode == OP_RESP_VALID
    assert sum1 == 100

    await spi.cmd_reset_buffer()
    await ClockCycles(dut.clk, 20)

    resp = await spi.cmd_read_raw()
    opcode_after, _, _ = parse_read_response(resp)
    assert opcode_after == OP_RESP_INVALID

    set_ram(dut, ram_addr(0, 0x60), to_unsigned_8(25))
    await spi.cmd_add_weight(0x60)

    opcode2, valid2, sum2 = await spi.cmd_read_poll()
    assert opcode2 == OP_RESP_VALID
    assert valid2 == 1
    assert sum2 == 25, f"After reset+new weight, expected 25, got {sum2}"


@cocotb.test()
async def test_set_clk_div(dut):
    spi = await start_clocks(dut)

    clk_div = int(dut.dut.slave.spi_clk_div.value)
    assert clk_div == 2, f"Expected default clk_div=2, got {clk_div}"

    await spi.cmd_set_clk_div(3)
    await ClockCycles(dut.clk, 10)
    assert int(dut.dut.slave.spi_clk_div.value) == 3

    set_ram(dut, ram_addr(0, 0x42), to_unsigned_8(77))
    await spi.cmd_add_weight(0x42)

    opcode, _, sum_signed = await spi.cmd_read_poll(max_attempts=20)
    assert opcode == OP_RESP_VALID
    assert sum_signed == 77, f"Expected 77 at clk_div=3, got {sum_signed}"

    await spi.cmd_set_clk_div(2)
    await ClockCycles(dut.clk, 10)
    assert int(dut.dut.slave.spi_clk_div.value) == 2


@cocotb.test()
async def test_set_clk_div_boundaries(dut):
    spi = await start_clocks(dut)

    await spi.cmd_set_clk_div(0)
    await ClockCycles(dut.clk, 10)
    assert int(dut.dut.slave.spi_clk_div.value) == 0

    await spi.cmd_set_clk_div(3)
    await ClockCycles(dut.clk, 10)
    assert int(dut.dut.slave.spi_clk_div.value) == 3

    await spi.cmd_set_clk_div(2)
    await ClockCycles(dut.clk, 10)
