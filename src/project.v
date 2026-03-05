// Tiny Tapeout wrapper — maps TT pins to the perceptron SPI interfaces

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  wire _unused = &{ena, clk, rst_n, 1'b0, ui_in[7:4], uio_in};

  wire slave_miso;
  wire ram_spi_cs;
  wire ram_spi_sck;
  wire ram_spi_mosi;

  assign uio_out = {4'b0000, ram_spi_sck, 1'b0, ram_spi_mosi, ram_spi_cs};
  assign uio_oe  = 8'b0000_1011;
  assign uo_out  = {7'b0000000, slave_miso};

  pred_top perceptron (
    .clk(clk),
    .rst_n(rst_n),
    .slave_sck_ext(ui_in[0]),
    .slave_scs_ext(ui_in[1]),
    .slave_mosi_ext(ui_in[2]),
    .slave_miso(slave_miso),
    .ram_spi_cs(ram_spi_cs),
    .ram_spi_sck(ram_spi_sck),
    .ram_spi_mosi(ram_spi_mosi),
    .ram_spi_miso_ext(uio_in[2])
  );

endmodule
