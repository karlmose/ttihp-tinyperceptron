// Perceptron core — accumulates signed weights from RAM, supports predict and update

`default_nettype none
`timescale 1ns/1ps

module perceptron #(
    parameter ADDR_WIDTH  = 9,
    parameter MAX_WEIGHTS = 4
) (
    input wire clk,
    input wire rst_n,

    input wire [ADDR_WIDTH-1:0] weight_addr,
    input wire add_weight,
    input wire reset_buffer,
    input wire update,
    input wire update_sign,

    output wire sign_out,
    output wire valid,
    output wire [10:0] sum,
    output wire update_done,

    output wire [ADDR_WIDTH+1:0] ram_addr,
    output wire ram_start_read,
    output wire ram_inc,
    output wire ram_dec,
    input wire [7:0] ram_weight,
    input wire ram_read_valid,
    input wire ram_write_done,
    input wire ram_busy
);

    localparam STATE_PREDICT = 1'b0;
    localparam STATE_UPDATE  = 1'b1;

    reg [10:0] sum_reg;
    reg [MAX_WEIGHTS*ADDR_WIDTH-1:0] index_buffer;
    reg [2:0] weight_count;
    reg [2:0] processed_count;
    reg state;
    reg ram_read_valid_prev;
    reg ram_write_done_prev;
    reg write_data_ready;
    reg update_done_reg;

    assign sign_out = sum_reg[10];
    assign valid = (state == STATE_PREDICT) && weight_count > 0 &&
                   processed_count == weight_count;
    assign sum = sum_reg;
    assign update_done = update_done_reg;

    assign ram_addr = {processed_count[1:0], index_buffer[processed_count * ADDR_WIDTH +: ADDR_WIDTH]};

    assign ram_start_read = (!ram_busy && processed_count < weight_count) &&
                            ((state == STATE_PREDICT) ||
                             (state == STATE_UPDATE && !write_data_ready));

    wire do_write = (state == STATE_UPDATE && processed_count < weight_count &&
                     write_data_ready && !ram_write_done && !ram_busy);
    assign ram_inc = do_write && update_sign;
    assign ram_dec = do_write && !update_sign;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= STATE_PREDICT;
            ram_read_valid_prev  <= 1'b0;
            ram_write_done_prev  <= 1'b0;
            write_data_ready     <= 1'b0;
            sum_reg              <= 11'd0;
            index_buffer         <= {(MAX_WEIGHTS*ADDR_WIDTH){1'b0}};
            weight_count         <= 3'd0;
            processed_count      <= 3'd0;
            update_done_reg      <= 1'b0;
        end else begin
            ram_read_valid_prev <= ram_read_valid;
            ram_write_done_prev <= ram_write_done;
            update_done_reg <= 1'b0;

            if (reset_buffer) begin
                state           <= STATE_PREDICT;
                weight_count    <= 3'd0;
                processed_count <= 3'd0;
                sum_reg         <= 11'd0;
                write_data_ready <= 1'b0;
            end else begin
                case (state)
                    STATE_PREDICT: begin
                        if (processed_count < weight_count) begin
                            if (ram_read_valid && !ram_read_valid_prev) begin
                                sum_reg <= sum_reg + {{3{ram_weight[7]}}, ram_weight};
                                processed_count <= processed_count + 3'd1;
                            end
                        end

                        if (add_weight && weight_count < MAX_WEIGHTS[2:0]) begin
                            index_buffer[weight_count * ADDR_WIDTH +: ADDR_WIDTH] <= weight_addr;
                            weight_count <= weight_count + 3'd1;
                        end

                        if (update && weight_count > 0 && processed_count == weight_count) begin
                            processed_count <= 3'd0;
                            state <= STATE_UPDATE;
                        end
                    end

                    STATE_UPDATE: begin
                        if (ram_read_valid && !ram_read_valid_prev)
                            write_data_ready <= 1'b1;

                        if (processed_count < weight_count) begin
                            if (ram_write_done && !ram_write_done_prev) begin
                                if (processed_count + 3'd1 == weight_count) begin
                                    update_done_reg  <= 1'b1;
                                    state            <= STATE_PREDICT;
                                    weight_count     <= 3'd0;
                                    processed_count  <= 3'd0;
                                    sum_reg          <= 11'd0;
                                    write_data_ready <= 1'b0;
                                end else begin
                                    processed_count  <= processed_count + 3'd1;
                                    write_data_ready <= 1'b0;
                                end
                            end
                        end
                    end
                endcase
            end
        end
    end

endmodule
