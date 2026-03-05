`default_nettype none
`timescale 1ns/1ps

module pred_slave_spi (
    input wire clk,          // System/Master Clock
    input wire rst_n,        // Active Low Reset

    // SPI Interface
    input wire sck,
    input wire scs,
    input wire mosi,
    output wire miso,

    // Read data (for OP_READ response)
    input wire [11:0] read,
    input wire read_valid,

    // Update-done signal from perceptron
    input wire update_done,

    // Perceptron control outputs
    output reg add_weight_valid,    // Pulse: OP_ADD
    output reg update_weight_valid, // Pulse: OP_UPDATE
    output reg reset_buffer_valid,  // Pulse: OP_RESET_BUF
    output reg [11:0] index,        // 12-bit payload
    output reg update_sign,         // LSB of payload for Update

    // Configuration outputs
    output reg [7:0] cs_wait_cycles, // Runtime-configurable CS wait
    output reg [1:0] spi_clk_div     // SPI master clock divisor bit-select (div = 2^(n+1))
);

    // SPI Signals
    wire spi_processing;
    wire spi_start_next = 1'b1; // Always ready
    wire [15:0] spi_data_recv;
    reg [15:0] spi_data_send;
    wire spi_ready;
    reg spi_reset;

    // 2FF synchronizers for SPI inputs (external clock domain)
    reg [1:0] sck_sync;
    reg [1:0] scs_sync;
    reg [1:0] mosi_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sck_sync <= 2'b00;
            scs_sync <= 2'b11;
            mosi_sync <= 2'b00;
        end else begin
            sck_sync <= {sck_sync[0], sck};
            scs_sync <= {scs_sync[0], scs};
            mosi_sync <= {mosi_sync[0], mosi};
        end
    end

    wire sck_clean  = sck_sync[1];
    wire scs_clean  = scs_sync[1];
    wire mosi_clean = mosi_sync[1];

    // SPI Module (Slave, 16-bit)
    spi_module #(
        .SPI_MASTER(1'b0),
        .SPI_WORD_LEN(16),
        .CPOL(1'b0),
        .CPHA(1'b0)
    ) spi_inst (
        .master_clock(clk),
        .SCLK_OUT(),
        .SCLK_IN(sck_clean),
        .SS_OUT(),
        .SS_IN(scs_clean),
        .OUTPUT_SIGNAL(miso),
        .processing_word(spi_processing),
        .process_next_word(spi_start_next),
        .data_word_send(spi_data_send),
        .INPUT_SIGNAL(mosi_clean),
        .data_word_recv(spi_data_recv),
        .do_reset(spi_reset),
        .is_ready(spi_ready)
    );

    // Decoding Logic
    reg prev_processing;

    // Opcodes (received)
    localparam OP_ADD          = 4'b0001;
    localparam OP_UPDATE       = 4'b0010;
    localparam OP_READ         = 4'b0011;
    localparam OP_SET_CS_WAIT  = 4'b0100;
    localparam OP_RESET_BUF    = 4'b0101;
    localparam OP_SET_CLK_DIV  = 4'b0110;

    // Opcodes (sent in response)
    localparam OP_WRITE_READ_VALID   = 4'b0001;
    localparam OP_WRITE_READ_INVALID = 4'b0010;
    localparam OP_WRITE_UPDATE_DONE  = 4'b0011;

    // Update-done latch (set by pulse, cleared on OP_READ)
    reg update_done_flag;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_reset <= 1'b1;
            spi_data_send <= 16'd0;
            prev_processing <= 1'b0;

            add_weight_valid <= 1'b0;
            update_weight_valid <= 1'b0;
            reset_buffer_valid <= 1'b0;
            index <= 12'd0;
            update_sign <= 1'b0;
            cs_wait_cycles <= 8'd8;
            spi_clk_div <= 2'd1;  // Default: div-by-4 (50MHz → 12.5MHz)
            update_done_flag <= 1'b0;
        end else begin
            spi_reset <= 1'b0;
            prev_processing <= spi_processing;

            // Default pulses low
            add_weight_valid <= 1'b0;
            update_weight_valid <= 1'b0;
            reset_buffer_valid <= 1'b0;

            // Latch update_done pulse from perceptron
            if (update_done) update_done_flag <= 1'b1;

            // Falling edge of SPI processing = word complete
            if (prev_processing && !spi_processing) begin
                case (spi_data_recv[15:12])
                    OP_ADD: begin
                        add_weight_valid <= 1'b1;
                        index <= spi_data_recv[11:0];
                        spi_data_send <= 16'd0;
                    end
                    OP_UPDATE: begin
                        update_weight_valid <= 1'b1;
                        index <= spi_data_recv[11:0];
                        update_sign <= spi_data_recv[0];
                        spi_data_send <= 16'd0;
                    end
                    OP_READ: begin
                        if (update_done_flag) begin
                            spi_data_send <= {OP_WRITE_UPDATE_DONE, 12'd0};
                            update_done_flag <= 1'b0;
                        end else if (read_valid) begin
                            spi_data_send <= {OP_WRITE_READ_VALID, read};
                        end else begin
                            spi_data_send <= {OP_WRITE_READ_INVALID, 12'd0};
                        end
                    end
                    OP_SET_CS_WAIT: begin
                        cs_wait_cycles <= spi_data_recv[7:0];
                        spi_data_send <= 16'd0;
                    end
                    OP_RESET_BUF: begin
                        reset_buffer_valid <= 1'b1;
                        spi_data_send <= 16'd0;
                    end
                    OP_SET_CLK_DIV: begin
                        spi_clk_div <= spi_data_recv[1:0];
                        spi_data_send <= 16'd0;
                    end
                    default: begin
                        spi_data_send <= 16'd0;
                    end
                endcase
            end
        end
    end

endmodule
