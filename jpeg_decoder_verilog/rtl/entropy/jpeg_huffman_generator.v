`timescale 1ns / 1ps 
 
module jpeg_huffman_generator( 
    input wire clk, 
    input wire rst_n, 
    input wire start, 
    input wire [7:0] huff_count_in [0:15], 
    input wire [7:0] huff_val_in [0:161], 
    output reg [15:0] huff_code_out [0:255], 
    output reg [4:0] huff_len_out [0:255], 
    output reg done 
); 
    integer i, j; 
    integer code; 
    integer idx; 
 
    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin 
            done <= 0; 
            for (i = 0; i < 256; i = i + 1) begin  
                huff_code_out[i] <= 0;  
                huff_len_out[i] <= 0;  
            end 
        end else if (start) begin 
            // --- TỐI ƯU: Chỉ chạy vòng lặp tính toán nếu chưa xong (done=0) --- 
            if (!done) begin 
                // 1. Clear bảng tạm 
                for (i = 0; i < 256; i = i + 1) begin  
                    huff_code_out[i] <= 0;  
                    huff_len_out[i] <= 0;  
                end 
 
                // 2. Thuật toán tạo mã Huffman (Canonical) 
                code = 0; 
                idx = 0; 
                for (i = 0; i < 16; i = i + 1) begin // i = bit length - 1 
                    for (j = 0; j < huff_count_in[i]; j = j + 1) begin 
                        // Map Symbol (huff_val_in) -> Code & Length 
                        huff_len_out[ huff_val_in[idx] ] <= i + 1; 
                        huff_code_out[ huff_val_in[idx] ] <= code[15:0]; 
                        idx = idx + 1; 
                        code = code + 1; 
                    end 
                    code = code << 1; 
                end 
                 
                // Đánh dấu đã xong 
                done <= 1'b1; 
            end 
        end else begin 
            // Nếu start xuống 0, reset done để cho phép chạy lại lần sau (nếu cần) 
            done <= 1'b0; 
        end 
    end 
endmodule