`timescale 1ns / 1ps 
 
module jpeg_bitstream_reader ( 
    input wire clk, 
    input wire rst_n, 
    input wire [7:0] byte_in, 
    input wire byte_valid, 
    output reg byte_ready, 
    output reg bit_out, 
    output reg bit_valid, 
    input wire bit_ready 
); 
 
    localparam S_IDLE = 0; 
    localparam S_READ_BYTE = 1; 
    localparam S_SHIFT = 2; 
 
    reg [1:0] state; 
    reg [7:0] shift_reg; 
    reg [3:0] bits_left; 
    reg last_was_ff; 

    // Combinatorial Output Logic
    assign bit_valid = (state == S_SHIFT && bits_left > 0);
    assign bit_out   = shift_reg[7];
 
    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin 
            state <= S_IDLE; 
            shift_reg <= 0; 
            bits_left <= 0; 
            last_was_ff <= 0; 
            byte_ready <= 1; 
            // bit_valid/out are combinatorial now
        end else begin 
            case (state) 
                S_IDLE: begin 
                    if (bits_left > 0) begin 
                        state <= S_SHIFT; 
                    end else begin 
                        byte_ready <= 1; 
                        state <= S_READ_BYTE; 
                    end 
                end 
 
                S_READ_BYTE: begin 
                    if (byte_valid && byte_ready) begin 
                        byte_ready <= 0; 
                         
                        if (last_was_ff && byte_in == 8'h00) begin 
                            // $display("BS: Skip Stuffing 00 after FF");
                            last_was_ff <= 0; 
                            state <= S_IDLE;  
                        end else begin 
                            // $display("BS: Read Byte %h", byte_in);
                            shift_reg <= byte_in; 
                            bits_left <= 8; 
                            last_was_ff <= (byte_in == 8'hFF); 
                            state <= S_SHIFT; 
                        end 
                    end 
                end 
 
                S_SHIFT: begin 
                    if (bits_left > 0) begin 
                        // Shift if downstream is ready
                         
                        if (bit_ready) begin 
                            shift_reg <= {shift_reg[6:0], 1'b0}; 
                            bits_left <= bits_left - 1; 
                        end 
                    end else begin 
                        state <= S_IDLE; 
                    end 
                end 
            endcase 
        end 
    end 
endmodule