/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  // List all unused inputs to prevent warnings
  wire _unused = &{ena, clk, rst_n, 1'b0, ui_in[7:4], uio_in};

  // -----------------------------------------------------------------
  // Pin Mapping
  // -----------------------------------------------------------------

  // Bidirectional IOs (uio)
  // uio[0]: ram_spi_cs (Output)
  // uio[1]: ram_spi_mosi (Output)
  // uio[2]: ram_spi_miso_ext (Input)
  // uio[3]: ram_spi_sck (Output)
  // uio[7:4]: Unused (Input)

  assign uio_out = {
      4'b0000,           // [7:4]
      ram_spi_sck,       // [3]
      1'b0,              // [2] Input
      ram_spi_mosi,      // [1]
      ram_spi_cs         // [0]
  };

  assign uio_oe = 8'b0000_1011; // [3], [1], [0] are outputs

  wire slave_miso;
  wire ram_spi_cs;
  wire ram_spi_sck;
  wire ram_spi_mosi;

  assign uo_out = {
      7'b0000000,        // [7:1] Unused/Debug
      slave_miso         // [0]
  };

  pred_top tt_perceptron (
    .clk(clk),
    .rst_n(rst_n),

    // SPI Slave
    .slave_sck_ext(ui_in[0]),
    .slave_scs_ext(ui_in[1]),
    .slave_mosi_ext(ui_in[2]),
    .slave_miso(slave_miso),

    // SPI Master (RAM)
    .ram_spi_cs(ram_spi_cs),
    .ram_spi_sck(ram_spi_sck),
    .ram_spi_mosi(ram_spi_mosi),
    .ram_spi_miso_ext(uio_in[2])
  );

endmodule
