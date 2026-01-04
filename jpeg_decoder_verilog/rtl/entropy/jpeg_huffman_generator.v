`timescale 1ns/1ps


module jpeg_huffman_generator(
    input  wire        clk,
    input  wire        rst_n,      // Thêm mới 
    input  wire        start,


    input  wire [7:0]  huff_count_in [0:15],    // counts for lengths 1..16
    output reg  [15:0] huff_code_out [0:255], // canonical codes
    output reg  [4:0]  huff_len_out  [0:255], // code lengths
    output reg         done
);


    integer i, j;
    integer code;
    integer idx;


    always @(posedge clk) begin
       if (!rst_n) begin
            done <= 0;
            for (i = 0; i < 256; i = i + 1) begin
                huff_code_out[i] <= 0;
                huff_len_out[i]  <= 0;
            end
        end else if (start) begin
            // clear outputs
            for (i = 0; i < 256; i = i + 1) begin
                huff_code_out[i] <= 16'd0;
                huff_len_out[i]  <= 5'd0;
            end


            code = 0;
            idx  = 0;


            // canonical Huffman code generation
            for (i = 0; i < 16; i = i + 1) begin
                for (j = 0; j < huff_count_in[i]; j = j + 1) begin
                    if (idx < 256) begin
                        huff_len_out[idx]  <= i + 1;      // code length
                        huff_code_out[idx] <= code[15:0]; // code value
                    end
                    idx  = idx + 1;
                    code = code + 1;
                end
                code = code << 1;
            end


            done <= 1'b1;
        end else begin
            done <= 1'b0;
        end
    end


endmodule



