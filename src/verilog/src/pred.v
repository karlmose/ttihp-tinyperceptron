// Perceptron Top Level
// Wires together: perceptron (core), ram_interface (SPI master to RAM),
// and pred_slave_spi (SPI slave for commands).
// Two external SPI buses, each on its own clock domain.

`default_nettype none
`timescale 1ns/1ps

module pred_top (
    input wire clk,
    input wire rst_n,

    // SPI slave bus (command/control — external clock domain)
    input  wire slave_sck_ext,   // _ext = external clock domain
    input  wire slave_scs_ext,
    input  wire slave_mosi_ext,
    output wire slave_miso,

    // SPI RAM bus (weight memory — external clock domain)
    output wire ram_spi_cs,
    output wire ram_spi_sck,
    output wire ram_spi_mosi,
    input  wire ram_spi_miso_ext // _ext = external clock domain
);

    // -----------------------------------------------------------------
    // CDC: 2FF sync for RAM MISO (external clock domain → system clock)
    // (pred_slave_spi already syncs its own SPI inputs internally)
    // -----------------------------------------------------------------
    reg [1:0] ram_miso_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ram_miso_sync <= 2'b0;
        else        ram_miso_sync <= {ram_miso_sync[0], ram_spi_miso_ext};
    end
    wire ram_miso_clean = ram_miso_sync[1];

    // -----------------------------------------------------------------
    // Internal wires: pred_slave_spi → perceptron
    // -----------------------------------------------------------------
    wire        slave_add_weight;
    wire        slave_update;
    wire        slave_reset_buffer;
    wire [11:0] slave_index;
    wire        slave_update_sign;

    // -----------------------------------------------------------------
    // Internal wires: pred_slave_spi → ram_interface
    // -----------------------------------------------------------------
    wire [7:0] cs_wait_cycles;
    wire [1:0] spi_clk_div;

    // -----------------------------------------------------------------
    // Internal wires: perceptron ↔ ram_interface
    // -----------------------------------------------------------------
    wire [12:0] ram_addr;
    wire        ram_start_read;
    wire        ram_inc;
    wire        ram_dec;
    wire [7:0]  ram_weight;
    wire        ram_read_valid;
    wire        ram_write_done;
    wire        ram_busy;

    // -----------------------------------------------------------------
    // Internal wires: perceptron → pred_slave_spi (readback)
    // -----------------------------------------------------------------
    wire [10:0] perc_sum;
    wire        perc_valid;
    wire        perc_update_done;

    // -----------------------------------------------------------------
    // Module Instantiations
    // -----------------------------------------------------------------

    pred_slave_spi slave (
        .clk(clk),
        .rst_n(rst_n),

        // SPI pins (slave syncs _ext inputs internally)
        .sck(slave_sck_ext),
        .scs(slave_scs_ext),
        .mosi(slave_mosi_ext),
        .miso(slave_miso),

        // Readback from perceptron: {valid, sum[10:0]}
        .read({perc_valid, perc_sum}),
        .read_valid(perc_valid),
        .update_done(perc_update_done),

        // Control outputs → perceptron
        .add_weight_valid(slave_add_weight),
        .update_weight_valid(slave_update),
        .reset_buffer_valid(slave_reset_buffer),
        .index(slave_index),
        .update_sign(slave_update_sign),

        // Configuration → ram_interface
        .cs_wait_cycles(cs_wait_cycles),
        .spi_clk_div(spi_clk_div)
    );

    perceptron perc (
        .clk(clk),
        .rst_n(rst_n),

        // Control from slave
        .weight_addr(slave_index[9:0]),
        .add_weight(slave_add_weight),
        .reset_buffer(slave_reset_buffer),
        .update(slave_update),
        .update_sign(slave_update_sign),

        // Status
        .sign_out(),
        .valid(perc_valid),
        .sum(perc_sum),
        .update_done(perc_update_done),

        // RAM interface
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

        .cs_wait_cycles(cs_wait_cycles),
        .spi_clk_div(spi_clk_div),

        .addr(ram_addr),
        .start_read(ram_start_read),
        .inc(ram_inc),
        .dec(ram_dec),
        .weight(ram_weight),
        .read_valid(ram_read_valid),
        .write_done(ram_write_done),
        .busy(ram_busy),

        // SPI pins (outputs driven from system clock, external slave samples them)
        .spi_cs(ram_spi_cs),
        .spi_sck(ram_spi_sck),
        .spi_mosi(ram_spi_mosi),
        .spi_miso(ram_miso_clean)
    );

endmodule