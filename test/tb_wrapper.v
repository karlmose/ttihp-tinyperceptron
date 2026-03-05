// Testbench wrapper: pred_top + spi_ram_slave with independent clock domains

`default_nettype none
`timescale 1ns/1ps

module tb_wrapper (
    input wire clk,
    input wire rst_n,
    input wire slave_sck_ext,
    input wire slave_scs_ext,
    input wire slave_mosi_ext,
    output wire slave_miso,
    input wire ram_slave_clk
);

    wire ram_spi_cs, ram_spi_sck, ram_spi_mosi, ram_spi_miso;

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

    spi_ram_slave ram_slave (
        .clk(ram_slave_clk),
        .rst_n(rst_n),
        .sck(ram_spi_sck),
        .scs(ram_spi_cs),
        .mosi(ram_spi_mosi),
        .miso(ram_spi_miso)
    );

endmodule
