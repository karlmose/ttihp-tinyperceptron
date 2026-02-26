`default_nettype none
`timescale 1ns/1ps

module ram_interface (
    input wire clk,             // System Clock
    input wire rst_n,

    input wire [7:0] cs_wait_cycles, // Configurable CS recovery time

    input wire [12:0] addr,     // 13-bit address
    input wire start_read,      // Pulse to start reading
    input wire inc,             // Pulse to increment weight
    input wire dec,             // Pulse to decrement weight
    
    output wire [7:0] weight,   // Last read/written weight
    output reg read_valid,      // High when weight is read
    output reg write_done,      // High when write is done
    output wire busy,           // High during Transaction OR Recovery
    
    // SPI interface
    output wire spi_cs,
    output wire spi_sck,
    output wire spi_mosi,
    input wire spi_miso
);

    reg [7:0] wait_cnt;

    // SPI Module Signals
    wire sclk_gend; // Generated clock from divider
    wire spi_processing;
    reg spi_start;
    reg [31:0] spi_data_to_send;
    wire [31:0] spi_data_received;
    wire spi_ready;
    
    // Direct assignment as requested
    assign weight = spi_data_received[7:0];

    // States
    localparam STATE_IDLE = 2'd0;
    localparam STATE_START_SPI = 2'd1;
    localparam STATE_WAIT_SPI = 2'd2;

    reg [2:0] state;
    reg is_write_op;

    assign busy = (state != STATE_IDLE) || (wait_cnt != 0);

    // -------------------------------------------------------------------------
    // Clock Divider (System / 8) -> Generates toggle for SPI Logic
    // -------------------------------------------------------------------------
    wire clk_div_ready;
    reg clk_div_reset;
    
    clock_divider #(.DIV_N(3)) clk_gen (
        .clk_in(clk),
        .clk_out(sclk_gend),
        .do_reset(clk_div_reset),
        .is_ready(clk_div_ready)
    );

    // -------------------------------------------------------------------------
    // SPI Master Module
    // -------------------------------------------------------------------------
    reg spi_reset;

    spi_module #(
        .SPI_MASTER(1'b1),
        .SPI_WORD_LEN(32),
        .CPOL(1'b0),
        .CPHA(1'b0)
    ) spi_inst (
        .master_clock(clk),
        .SCLK_OUT(spi_sck),
        .SCLK_IN(sclk_gend),
        .SS_OUT(spi_cs),
        .SS_IN(1'b1),
        .OUTPUT_SIGNAL(spi_mosi),
        .processing_word(spi_processing),
        .process_next_word(spi_start),
        .data_word_send(spi_data_to_send),
        .INPUT_SIGNAL(spi_miso),
        .data_word_recv(spi_data_received),
        .do_reset(spi_reset),
        .is_ready(spi_ready)
    );

    wire [15:0] full_addr = {3'b000, addr};
    localparam CMD_READ  = 8'h03;
    localparam CMD_WRITE = 8'h02;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            wait_cnt <= 8'd0;
            
            spi_start <= 1'b0;
            spi_data_to_send <= 32'd0;
            is_write_op <= 1'b0;
            read_valid <= 1'b0;
            write_done <= 1'b0;
            
            spi_reset <= 1'b1;
            clk_div_reset <= 1'b1;
        end else begin
            // Clear resets
            spi_reset <= 1'b0;
            clk_div_reset <= 1'b0;

            // Wait Count Logic
            if (!spi_cs) begin 
                wait_cnt <= cs_wait_cycles;
            end else if (wait_cnt > 0) begin
                wait_cnt <= wait_cnt - 1'b1;
            end

             case (state)
                STATE_IDLE: begin
                    spi_start <= 1'b0;

                    if (wait_cnt == 0 && spi_ready && !spi_processing) begin
                        if (start_read) begin
                            // READ
                            is_write_op <= 1'b0;
                            read_valid <= 1'b0;
                            write_done <= 1'b0;
                            
                            spi_data_to_send <= {CMD_READ, full_addr, 8'h00};
                            spi_start <= 1'b1;
                            state <= STATE_START_SPI;
                        end else if ((inc || dec) && read_valid) begin
                            // WRITE (Inc/Dec) - Only if we have a valid weight read
                            is_write_op <= 1'b1;
                            read_valid <= 1'b0;
                            write_done <= 1'b0;
                            
                            // Calculate next weight and send
                            spi_data_to_send <= {CMD_WRITE, full_addr, 
                                (inc && !dec && weight != 8'h7F) ? weight + 8'd1 :
                                (dec && !inc && weight != 8'h80) ? weight - 8'd1 :
                                weight
                            };
                            
                            read_valid <= 1'b0; 
                            
                            spi_start <= 1'b1;
                            state <= STATE_START_SPI;
                        end
                    end
                end
                
                STATE_START_SPI: begin
                    if (spi_processing) begin
                        spi_start <= 1'b0;
                        state <= STATE_WAIT_SPI;
                    end
                end

                STATE_WAIT_SPI: begin
                    if (!spi_processing) begin
                        if (is_write_op) begin
                            write_done <= 1'b1;
                        end else begin
                            read_valid <= 1'b1;
                        end
                        state <= STATE_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
