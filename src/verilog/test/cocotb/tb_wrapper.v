// Testbench wrapper: instantiates pred_top + spi_ram_slave
// Exposes control signals and internal state for cocotb

`default_nettype none
`timescale 1ns/1ps

module tb_wrapper (
    input wire clk,
    input wire rst_n,

    // SPI slave bus (command interface — cocotb bit-bangs this)
    input  wire slave_sck_ext,
    input  wire slave_scs_ext,
    input  wire slave_mosi_ext,
    output wire slave_miso,

    // RAM slave clock (separate clock domain for the external RAM model)
    input wire ram_slave_clk
);

    // Internal SPI RAM bus wires
    wire ram_spi_cs;
    wire ram_spi_sck;
    wire ram_spi_mosi;
    wire ram_spi_miso;

    // DUT
    pred_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .slave_sck_ext(slave_sck_ext),
        .slave_scs_ext(slave_scs_ext),
        .slave_mosi_ext(slave_mosi_ext),
        .slave_miso(slave_miso),
        .ram_spi_cs(ram_spi_cs),
        .ram_spi_sck(ram_spi_sck),
        .ram_spi_mosi(ram_spi_mosi),
        .ram_spi_miso_ext(ram_spi_miso)
    );

    // External SPI RAM model (runs on its own clock)
    spi_ram_slave ram_slave (
        .clk(ram_slave_clk),
        .rst_n(rst_n),
        .sck(ram_spi_sck),
        .scs(ram_spi_cs),
        .mosi(ram_spi_mosi),
        .miso(ram_spi_miso)
    );

endmodule
