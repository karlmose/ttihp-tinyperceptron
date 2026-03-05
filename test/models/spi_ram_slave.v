module spi_ram_slave #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8
)(
    input wire clk,
    input wire rst_n,
    input wire sck,
    input wire scs,
    input wire mosi,
    output wire miso
);

    // 64kB RAM
    reg [7:0] memory [0:65535];

    // Internal registers
    reg [7:0] cmd;
    reg [15:0] addr;
    
    // SPI Module Signals
    wire spi_processing;
    wire spi_start_next;
    reg [7:0] spi_data_send;
    wire [7:0] spi_data_recv;
    wire spi_ready;
    
    // Command Constants
    localparam CMD_READ  = 8'h03;
    localparam CMD_WRITE = 8'h02;

    // Initialize memory
    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1) begin
            memory[i] = 8'h00;
        end
        // Pre-load some known data for testing
        memory[16'h1000] = 8'h42;
    end

    // SPI Logic - Using Library Module
    // Note: SPI_MASTER = 0 means Slave Mode.
    // In Slave Mode:
    // - SCLK_IN is the SPI Clock from Master
    // - SS_IN is Chip Select from Master
    // - process_next_word allows chaining (always ready for next byte)
    // - data_word_send must be ready BEFORE the byte starts transmission? Or can be updated?
    // Library logic: starts cycle when SS low. Shifting happens. 
    // Data is loaded into shift register at start. So for Read, we need to prep data before Byte 3 starts.

    reg spi_reset;
    
    // We need to continuously enable processing in slave mode 
    // Library docs say: "process_next_word (Flag: Set to true to process the next word after the previous word has been processed.)"
    // For slave, we just want to be always ready if SS allows.
    assign spi_start_next = 1'b1; 

    spi_module #(
        .SPI_MASTER(1'b0),
        .SPI_WORD_LEN(8),
        .CPOL(1'b0),
        .CPHA(1'b0)
    ) spi_slave_inst (
        .master_clock(clk),
        .SCLK_OUT(), // Unused for slave
        .SCLK_IN(sck),
        .SS_OUT(),   // Unused for slave
        .SS_IN(scs),
        .OUTPUT_SIGNAL(miso),
        .processing_word(spi_processing),
        .process_next_word(spi_start_next),
        .data_word_send(spi_data_send),
        .INPUT_SIGNAL(mosi),
        .data_word_recv(spi_data_recv),
        .do_reset(spi_reset),
        .is_ready(spi_ready)
    );

    // Byte FSM
    // We need to track which byte of the transaction we are receiving.
    // Transaction structure: [CMD] [ADDR_HI] [ADDR_LO] [DATA]
    // Only 4 bytes max for our protocol.
    
    reg [2:0] byte_cnt;
    reg prev_processing;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_cnt <= 0;
            spi_reset <= 1'b1;
            spi_data_send <= 8'h00;
            prev_processing <= 0;
            cmd <= 0;
            addr <= 0;
        end else begin
            spi_reset <= 0;
            
            // Monitor SPI Processing status
            prev_processing <= spi_processing;
            
            // ---------------------------------------------------------
            // 1. Data Processing Logic (Independent of CS state)
            // ---------------------------------------------------------
            if (prev_processing && !spi_processing) begin
                case (byte_cnt)
                    0: cmd <= spi_data_recv;
                    1: addr[15:8] <= spi_data_recv;
                    2: addr[7:0] <= spi_data_recv;
                    3: begin 
                        if (cmd == CMD_WRITE) begin
                            memory[addr] <= spi_data_recv;
                        end
                    end
                endcase
            end

            // ---------------------------------------------------------
            // 2. Next Byte Prep & Counter Logic
            // ---------------------------------------------------------
            if (scs) begin
                // Transaction End / Reset
                byte_cnt <= 0;
                spi_data_send <= 8'h00; 
            end else begin
                // Transaction Active
                if (prev_processing && !spi_processing) begin
                   byte_cnt <= byte_cnt + 1;
                   
                   // Prepare Data for NEXT byte
                   // If we just finished Byte 2 (AddrLo), prepare Byte 3 (Data)
                   if (byte_cnt == 2) begin
                        if (cmd == CMD_READ) begin
                             // Use composite address because addr[7:0] is updated non-blocking above
                             spi_data_send <= memory[{addr[15:8], spi_data_recv}];
                        end else begin
                            spi_data_send <= 8'h00;
                        end
                   end
                end
            end
        end
    end

endmodule
