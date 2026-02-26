import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge

# Constants based on spi.v
CMD_READ  = 0x03
CMD_WRITE = 0x02

async def do_start(dut):
    """Initialize the DUT and reset."""
    clock = Clock(dut.clk, 100, unit="ns") # 10 MHz
    cocotb.start_soon(clock.start())
    
    dut.rst_n.value = 0
    dut.addr.value = 0
    dut.start_read.value = 0
    dut.inc.value = 0
    dut.dec.value = 0
    dut.spi_miso.value = 0
    dut.cs_wait_cycles.value = 15  # Was a parameter, now a wire input
    
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    # Wait for CS_WAIT_CYCLES (15) to expire
    await ClockCycles(dut.clk, 20)
    
    assert dut.spi_cs.value == 1, "CS should be high after reset"

async def expect_spi_transfer(dut, byte_val):
    """Verifies that 8 bits of data are shifted out on MOSI on falling edges of SCK."""
    for i in range(8):
        # Initial state before edge
        # We expect SCK to go High then Low. Data is driven on falling edge of previous (or CS fall) and sampled on Rising.
        # But wait, typical SPI mode 0:
        # CPOL=0, CPHA=0: Clock idle low. Data driven on CS fall / SCK fall. Sampled on SCK rise.
        # dut spi.v logic:
        # TRANSFER state: 
        #   if sck=0: sck<=1 (Rise), sample MISO.
        #   else: sck<=0 (Fall), shift out MOSI.
        # So MOSI changes on falling edge.
        
        # Wait for Rising Edge (Sample point for Slave)
        await RisingEdge(dut.spi_sck)
        # Check MOSI which was set up on previous falling edge
        expected_bit = (byte_val >> (7-i)) & 1
        assert dut.spi_mosi.value == expected_bit, f"Bit {7-i} of byte 0x{byte_val:02x} mismactch. Got {dut.spi_mosi.value}, expected {expected_bit}"

        # Wait for Falling Edge (Shift point)
        await FallingEdge(dut.spi_sck)

async def drive_miso_byte(dut, byte_val):
    """Drives MISO with a byte value, bit by bit."""
    for i in range(8):
        # Master samples on Rising Edge. So we must drive before Rising Edge.
        # We can drive on Falling Edge.
        # Wait for falling edge to drive the next bit
        # But for the very first bit, we might need to drive immediately or after the previous byte's last falling edge. 
        # In this loop, we are synchronized to the master's clock.
        
        # Determine bit
        bit = (byte_val >> (7-i)) & 1
        dut.spi_miso.value = bit
        
        await RisingEdge(dut.spi_sck) # Master samples here
        await FallingEdge(dut.spi_sck)

@cocotb.test()
async def test_read_operation(dut):
    """Test a basic Read operation: Send CMD 0x03, Address, and read a byte."""
    await do_start(dut)
    
    addr = 0x1234 # 13-bit effective: 0x1234 & 0x1FFF = 0x1234
    
    dut.addr.value = addr
    dut.start_read.value = 1
    await ClockCycles(dut.clk, 1)
    dut.start_read.value = 0
    
    # Wait for CS to go low
    await FallingEdge(dut.spi_cs)
    
    # Needs to match logic in spi.v:
    # 1. CMD_READ (0x03)
    await expect_spi_transfer(dut, CMD_READ)
    
    # 2. Address High Byte (extended to 16 bits in verilog: {3'b0, addr}) -> {5'b0, 13-bit addr} -> 16 bits
    # full_addr = {3'b0, 13-bit addr}. (Actually in code: `wire [15:0] full_addr = {3'b000, addr};`)
    # Wait, code says `wire [15:0] full_addr = {3'b000, addr};` where addr is 13 bits. total 16 bits.
    # High byte: (0x1234 >> 8) & 0xFF = 0x12
    # Low byte: 0x1234 & 0xFF = 0x34
    
    await expect_spi_transfer(dut, (addr >> 8) & 0xFF)
    await expect_spi_transfer(dut, addr & 0xFF)
    
    # 3. Dummy Byte (0x00) - For Read command in some SPI RAMs, or just wait cycles?
    # spi.v line 95: `shift_reg <= {CMD_READ, full_addr, 8'h00};` -> It sends 0x00 as dummy? No, wait. 
    # That shift_reg is 32 bits. 8 cmd + 16 addr + 8 data?
    # If it's a READ, the last 8 bits of shift_reg are initially 0x00.
    # But during the last 8 bits, we expect to READ from MISO, effectively shifting in data.
    # The MOSI during the data phase will be whatever was in the shift register bits [7:0] initially?
    # Yes, `shift_reg <= {CMD_READ, full_addr, 8'h00};`
    # So it sends 0x00 on MOSI while reading.
    
    # The "Dummy" usually means high-Z or don't care, but here it drives 0x00.
    # Let's interact as a slave. Send back 0xA5.
    
    # We need to concurrently expect MOSI 0x00 and Drive MISO 0xA5.
    
    # Helper to check MOSI 0 while driving MISO
    expected_data = 0xA5
    for i in range(8):
        # Drive MISO
        bit = (expected_data >> (7-i)) & 1
        dut.spi_miso.value = bit
        
        # Check MOSI (should be 0)
        await RisingEdge(dut.spi_sck)
        assert dut.spi_mosi.value == 0, f"Data phase MOSI bit {7-i} should be 0"
        
        await FallingEdge(dut.spi_sck)
        
    await RisingEdge(dut.spi_cs) # CS should go high
    
    await ClockCycles(dut.clk, 20)
    assert dut.read_valid.value == 1, "read_valid should be high"
    assert dut.weight.value == expected_data, f"Read weight should be 0x{expected_data:02x}, got 0x{dut.weight.value:02x}"

@cocotb.test()
async def test_update_operation(dut):
    """Test Increment operation: Read valid -> Inc -> Write CMD 0x02."""
    # Assuming we are already in valid state from previous test? 
    # Better to restart cleanly or just continue if state allows.
    # Let's restart to be sure.
    await do_start(dut)
    
    # 1. Perform Read to get to Valid state
    addr = 0x0ABC
    initial_val = 0x10
    
    dut.addr.value = addr
    dut.start_read.value = 1
    await ClockCycles(dut.clk, 1)
    dut.start_read.value = 0
    
    await FallingEdge(dut.spi_cs)
    
    # Consume Command & Address
    # We can just wait for 24 clock cycles (8 cmd + 16 addr)
    for _ in range(24):
        await FallingEdge(dut.spi_sck)
        
    # Drive Data (Read value)
    for i in range(8):
        dut.spi_miso.value = (initial_val >> (7-i)) & 1
        await RisingEdge(dut.spi_sck)
        await FallingEdge(dut.spi_sck)
        
    await RisingEdge(dut.spi_cs)
    await ClockCycles(dut.clk, 20)
    assert dut.read_valid.value == 1
    assert dut.weight.value == initial_val
    
    # Wait for Recovery Time (CS_WAIT_CYCLES = 15)
    await ClockCycles(dut.clk, 20)
    
    # 2. Perform Increment
    dut.inc.value = 1
    await ClockCycles(dut.clk, 1)
    dut.inc.value = 0
    
    # Expect Write Operation
    # Wait for CS Fall if not already low
    if dut.spi_cs.value == 1:
        await FallingEdge(dut.spi_cs)
    
    # Expect CMD_WRITE (0x02)
    await expect_spi_transfer(dut, CMD_WRITE)
    
    # Expect Address
    await expect_spi_transfer(dut, (addr >> 8) & 0xFF)
    await expect_spi_transfer(dut, addr & 0xFF)
    
    # Expect Data (Initial + 1 = 0x11)
    expected_new_val = initial_val + 1
    await expect_spi_transfer(dut, expected_new_val)
    
    await RisingEdge(dut.spi_cs)
    await ClockCycles(dut.clk, 20)
    assert dut.write_done.value == 1, "write_done should be asserted"

