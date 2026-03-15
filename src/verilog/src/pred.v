// Perceptron top level — wires together SPI slave, perceptron core, and RAM interface

`default_nettype none
`timescale 1ns/1ps

module pred_top (
    input wire clk,
    input wire rst_n,

    input  wire slave_sck_ext,
    input  wire slave_scs_ext,
    input  wire slave_mosi_ext,
    output wire slave_miso,

    output wire ram_spi_cs,
    output wire ram_spi_sck,
    output wire ram_spi_mosi,
    input  wire ram_spi_miso_ext
);

    // 2FF synchronizer for RAM MISO (slave SPI inputs are synced internally)
    reg [1:0] ram_miso_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ram_miso_sync <= 2'b0;
        else        ram_miso_sync <= {ram_miso_sync[0], ram_spi_miso_ext};
    end
    wire ram_miso_synced = ram_miso_sync[1];

    wire        cmd_add_weight;
    wire        cmd_update;
    wire        cmd_reset_buffer;
    wire [8:0]  cmd_index;
    wire        cmd_update_sign;
    wire [2:0]  cfg_cs_wait_cfg;
    wire [1:0]  cfg_spi_clk_div;

    wire [10:0] ram_addr;
    wire        ram_start_read;
    wire        ram_inc;
    wire        ram_dec;
    wire [7:0]  ram_weight;
    wire        ram_read_valid;
    wire        ram_write_done;
    wire        ram_busy;

    wire [10:0] perc_sum;
    wire        perc_valid;
    wire        perc_update_done;

    pred_slave_spi slave (
        .clk(clk),
        .rst_n(rst_n),
        .sck(slave_sck_ext),
        .scs(slave_scs_ext),
        .mosi(slave_mosi_ext),
        .miso(slave_miso),
        .read({perc_valid, perc_sum}),
        .read_valid(perc_valid),
        .update_done(perc_update_done),
        .add_weight_valid(cmd_add_weight),
        .update_weight_valid(cmd_update),
        .reset_buffer_valid(cmd_reset_buffer),
        .index(cmd_index),
        .update_sign(cmd_update_sign),
        .cs_wait_cfg(cfg_cs_wait_cfg),
        .spi_clk_div(cfg_spi_clk_div)
    );

    perceptron perc (
        .clk(clk),
        .rst_n(rst_n),
        .weight_addr(cmd_index),
        .add_weight(cmd_add_weight),
        .reset_buffer(cmd_reset_buffer),
        .update(cmd_update),
        .update_sign(cmd_update_sign),
        .sign_out(),
        .valid(perc_valid),
        .sum(perc_sum),
        .update_done(perc_update_done),
        .ram_addr(ram_addr),
        .ram_start_read(ram_start_read),
        .ram_inc(ram_inc),
        .ram_dec(ram_dec),
        .ram_weight(ram_weight),
        .ram_read_valid(ram_read_valid),
        .ram_write_done(ram_write_done),
        .ram_busy(ram_busy)
    );

    ram_interface ram_if (
        .clk(clk),
        .rst_n(rst_n),
        .cs_wait_cycles(cfg_cs_wait_cfg),
        .spi_clk_div(cfg_spi_clk_div),
        .addr(ram_addr),
        .start_read(ram_start_read),
        .inc(ram_inc),
        .dec(ram_dec),
        .weight(ram_weight),
        .read_valid(ram_read_valid),
        .write_done(ram_write_done),
        .busy(ram_busy),
        .spi_cs(ram_spi_cs),
        .spi_sck(ram_spi_sck),
        .spi_mosi(ram_spi_mosi),
        .spi_miso(ram_miso_synced)
    );

endmodule
