"""
Shared helpers for pred_top cocotb tests.

Provides:
  - SpiMasterDriver: bit-bangs the 16-bit SPI slave interface
  - start_clocks(): initializes clocks, reset, and returns an SPI driver
  - RAM access helpers: set_ram(), get_ram(), ram_addr()
  - Signed conversion helpers
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

# ─────────────────────────────────────────────────────────────────────────────
# Opcodes (match pred_slave_spi.v)
# ─────────────────────────────────────────────────────────────────────────────
OP_ADD         = 0x1
OP_UPDATE      = 0x2
OP_READ        = 0x3
OP_SET_CS_WAIT = 0x4
OP_RESET_BUF   = 0x5

# Response opcodes
OP_RESP_VALID       = 0x1
OP_RESP_INVALID     = 0x2
OP_RESP_UPDATE_DONE = 0x3


# ─────────────────────────────────────────────────────────────────────────────
# SPI Master Driver
# ─────────────────────────────────────────────────────────────────────────────
class SpiMasterDriver:
    """Drives slave_sck_ext, slave_scs_ext, slave_mosi_ext; reads slave_miso."""

    def __init__(self, dut, half_period_ns=200):
        self.dut = dut
        self.half_period = half_period_ns

    async def send_word(self, word_16bit):
        """Send a 16-bit word and return the 16-bit response."""
        dut = self.dut
        received = 0

        dut.slave_scs_ext.value = 0
        await Timer(self.half_period * 2, unit="ns")

        for i in range(15, -1, -1):
            bit = (word_16bit >> i) & 1
            dut.slave_mosi_ext.value = bit

            await Timer(self.half_period, unit="ns")
            dut.slave_sck_ext.value = 1
            await Timer(1, unit="ns")
            received |= (int(dut.slave_miso.value) & 1) << i

            await Timer(self.half_period - 1, unit="ns")
            dut.slave_sck_ext.value = 0

        await Timer(self.half_period * 2, unit="ns")
        dut.slave_scs_ext.value = 1
        await Timer(self.half_period * 4, unit="ns")

        return received

    async def cmd_add_weight(self, index_10bit):
        """Send OP_ADD with a 10-bit index (zero-extended to 12 bits)."""
        word = (OP_ADD << 12) | (index_10bit & 0x3FF)
        await self.send_word(word)

    async def cmd_update(self, sign):
        """Send OP_UPDATE. sign=1 → increment, sign=0 → decrement."""
        word = (OP_UPDATE << 12) | (sign & 1)
        await self.send_word(word)

    async def cmd_read_raw(self):
        """Send OP_READ, then a dummy word to get the response. Returns raw 16-bit."""
        await self.send_word(OP_READ << 12)
        return await self.send_word(0x0000)

    async def cmd_read_poll(self, max_attempts=10):
        """Poll OP_READ until OP_RESP_VALID. Returns (opcode, valid_bit, sum_signed).
        Raises AssertionError if max_attempts exceeded."""
        for attempt in range(1, max_attempts + 1):
            resp = await self.cmd_read_raw()
            opcode, valid_bit, sum_signed = parse_read_response(resp)
            if opcode == OP_RESP_VALID:
                return opcode, valid_bit, sum_signed
            if opcode == OP_RESP_UPDATE_DONE:
                raise AssertionError(
                    f"Got OP_RESP_UPDATE_DONE while polling for VALID (attempt {attempt})")
        raise AssertionError(
            f"OP_READ did not return VALID after {max_attempts} attempts")

    async def cmd_update_and_wait(self, sign, max_attempts=10):
        """Send OP_UPDATE, then poll OP_READ until OP_RESP_UPDATE_DONE.
        Returns the raw response word."""
        await self.cmd_update(sign)
        for attempt in range(1, max_attempts + 1):
            resp = await self.cmd_read_raw()
            opcode = (resp >> 12) & 0xF
            if opcode == OP_RESP_UPDATE_DONE:
                return resp
        raise AssertionError(
            f"OP_READ did not return UPDATE_DONE after {max_attempts} attempts")

    async def cmd_set_cs_wait(self, val_8bit):
        """Send OP_SET_CS_WAIT."""
        word = (OP_SET_CS_WAIT << 12) | (val_8bit & 0xFF)
        await self.send_word(word)

    async def cmd_reset_buffer(self):
        """Send OP_RESET_BUF."""
        await self.send_word(OP_RESET_BUF << 12)


# ─────────────────────────────────────────────────────────────────────────────
# Clock / Reset
# ─────────────────────────────────────────────────────────────────────────────
async def start_clocks(dut, sys_period_ns=10, ram_period_ns=10, spi_half_ns=200):
    """Start system clock and RAM slave clock. Returns SpiMasterDriver."""
    sys_clk = Clock(dut.clk, sys_period_ns, unit="ns")
    cocotb.start_soon(sys_clk.start())

    ram_clk = Clock(dut.ram_slave_clk, ram_period_ns, unit="ns")
    cocotb.start_soon(ram_clk.start())

    dut.rst_n.value = 0
    dut.slave_sck_ext.value = 0
    dut.slave_scs_ext.value = 1
    dut.slave_mosi_ext.value = 0

    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 30)

    return SpiMasterDriver(dut, half_period_ns=spi_half_ns)


# ─────────────────────────────────────────────────────────────────────────────
# Response Parsing
# ─────────────────────────────────────────────────────────────────────────────
def parse_read_response(resp):
    """Parse OP_READ response → (opcode, valid_bit, sum_signed)."""
    opcode = (resp >> 12) & 0xF
    payload = resp & 0xFFF
    valid_bit = (payload >> 11) & 1
    sum_raw = payload & 0x7FF
    sum_signed = sum_raw - 2048 if sum_raw >= 1024 else sum_raw
    return opcode, valid_bit, sum_signed


# ─────────────────────────────────────────────────────────────────────────────
# RAM Helpers
# ─────────────────────────────────────────────────────────────────────────────
def to_signed_8(val):
    return val - 256 if val >= 128 else val

def to_unsigned_8(val):
    return val & 0xFF

def ram_addr(slot, index):
    """Compute RAM address: {slot[2:0], index[9:0]}."""
    return ((slot & 0x7) << 10) | (index & 0x3FF)

def set_ram(dut, addr_16, value_8):
    dut.ram_slave.memory[addr_16].value = value_8

def get_ram(dut, addr_16):
    return int(dut.ram_slave.memory[addr_16].value)


# ─────────────────────────────────────────────────────────────────────────────
# Assertion Helpers
# ─────────────────────────────────────────────────────────────────────────────
def assert_sum_in_range(sum_val, lo, hi, msg=""):
    """Assert that sum_val is within [lo, hi] inclusive."""
    assert lo <= sum_val <= hi, \
        f"Sum {sum_val} not in [{lo}, {hi}]{': ' + msg if msg else ''}"


async def predict_update_verify(spi, dut, indices, ram_slots, sign, expected_vals,
                                label=""):
    """Full predict → update → verify RAM cycle.

    Args:
        spi: SpiMasterDriver
        dut: DUT handle
        indices: list of 10-bit weight indices to add
        ram_slots: list of (slot, index) tuples for RAM addresses to check
        sign: 1=increment, 0=decrement
        expected_vals: list of expected signed-8 values after update
        label: optional description for assertion messages
    """
    from helpers import OP_RESP_VALID

    # Add all weights
    for idx in indices:
        await spi.cmd_add_weight(idx)

    # Poll until valid
    opcode, valid_bit, sum_signed = await spi.cmd_read_poll()
    assert opcode == OP_RESP_VALID, \
        f"[{label}] Expected VALID opcode, got {opcode:#x}"
    assert valid_bit == 1, f"[{label}] Valid bit should be 1"

    # Update + wait for done
    await spi.cmd_update_and_wait(sign)

    # Verify RAM contents
    for (slot, index), expected in zip(ram_slots, expected_vals):
        addr = ram_addr(slot, index)
        actual = to_signed_8(get_ram(dut, addr))
        assert actual == expected, \
            f"[{label}] RAM[{slot},{index:#x}] expected {expected}, got {actual}"
