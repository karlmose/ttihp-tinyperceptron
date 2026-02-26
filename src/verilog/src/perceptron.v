// Perceptron Core — SPI-unaware weight accumulator
// Drives ram_interface control signals, exposes sum for external readout

`default_nettype none
`timescale 1ns/1ps

module perceptron (
    input wire clk,
    input wire rst_n,

    // Control inputs (from pred_slave_spi)
    input wire [9:0] weight_addr,
    input wire add_weight,
    input wire reset_buffer,
    input wire update,
    input wire update_sign,

    // Status outputs
    output wire sign_out,
    output wire valid,
    output wire [10:0] sum,
    output wire update_done,

    // RAM interface control (directly to ram_interface)
    output wire [12:0] ram_addr,
    output wire ram_start_read,
    output wire ram_inc,
    output wire ram_dec,
    input wire [7:0] ram_weight,
    input wire ram_read_valid,
    input wire ram_write_done,
    input wire ram_busy
);

    // State definitions
    localparam STATE_PREDICT = 1'b0;
    localparam STATE_UPDATE  = 1'b1;

    // Registers
    reg [10:0] sum_reg;
    reg [69:0] index_buffer; // 7x10 bit addresses
    reg [2:0] no_in_buffer;
    reg [2:0] no_processed_in_buffer;
    reg state;
    reg ram_read_valid_d;
    reg ram_write_done_d;
    reg data_ready_for_write;
    reg update_done_reg;

    // Outputs
    assign sign_out = sum_reg[10];
    assign valid = (state == STATE_PREDICT) && no_in_buffer > 0 &&
                   no_processed_in_buffer == no_in_buffer;
    assign sum = sum_reg;
    assign update_done = update_done_reg;

    // RAM interface address: {buffer_slot[2:0], index[9:0]}
    assign ram_addr = {no_processed_in_buffer, index_buffer[no_processed_in_buffer * 10 +: 10]};

    // Read when not busy and we have unprocessed entries
    assign ram_start_read = (!ram_busy && no_processed_in_buffer < no_in_buffer) &&
                            ((state == STATE_PREDICT) ||
                             (state == STATE_UPDATE && !data_ready_for_write));

    wire do_write = (state == STATE_UPDATE && no_processed_in_buffer < no_in_buffer &&
                     data_ready_for_write && !ram_write_done && !ram_busy);
    assign ram_inc = (do_write && update_sign);
    assign ram_dec = (do_write && !update_sign);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_PREDICT;
            ram_read_valid_d <= 1'b0;
            ram_write_done_d <= 1'b0;
            data_ready_for_write <= 1'b0;
            sum_reg <= 11'd0;
            index_buffer <= 70'd0;
            no_in_buffer <= 3'd0;
            no_processed_in_buffer <= 3'd0;
            update_done_reg <= 1'b0;
        end else begin
            ram_read_valid_d <= ram_read_valid;
            ram_write_done_d <= ram_write_done;
            update_done_reg <= 1'b0; // default: clear pulse

            if (reset_buffer) begin
                state <= STATE_PREDICT;
                no_in_buffer <= 3'd0;
                no_processed_in_buffer <= 3'd0;
                sum_reg <= 11'd0;
                data_ready_for_write <= 1'b0;
            end else begin
                case (state)
                    STATE_PREDICT: begin
                        if (no_processed_in_buffer < no_in_buffer) begin
                            if (ram_read_valid && !ram_read_valid_d) begin
                                sum_reg <= sum_reg + {{3{ram_weight[7]}}, ram_weight};
                                no_processed_in_buffer <= no_processed_in_buffer + 3'd1;
                            end
                        end

                        if (add_weight && no_in_buffer < 7) begin
                            index_buffer[no_in_buffer * 10 +: 10] <= weight_addr;
                            no_in_buffer <= no_in_buffer + 3'd1;
                        end

                        if (update && no_processed_in_buffer == no_in_buffer) begin
                            no_processed_in_buffer <= 3'd0;
                            state <= STATE_UPDATE;
                        end
                    end

                    STATE_UPDATE: begin
                        if (ram_read_valid && !ram_read_valid_d) data_ready_for_write <= 1'b1;

                        if (no_processed_in_buffer < no_in_buffer) begin
                            if (ram_write_done && !ram_write_done_d) begin
                                if (no_processed_in_buffer + 3'd1 == no_in_buffer) begin
                                    // Last weight written — auto-reset
                                    update_done_reg <= 1'b1;
                                    state <= STATE_PREDICT;
                                    no_in_buffer <= 3'd0;
                                    no_processed_in_buffer <= 3'd0;
                                    sum_reg <= 11'd0;
                                    data_ready_for_write <= 1'b0;
                                end else begin
                                    no_processed_in_buffer <= no_processed_in_buffer + 3'd1;
                                    data_ready_for_write <= 1'b0;
                                end
                            end
                        end
                    end
                endcase
            end
        end
    end

endmodule
