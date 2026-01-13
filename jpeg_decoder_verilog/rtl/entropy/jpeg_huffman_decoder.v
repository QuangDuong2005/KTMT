`timescale 1ns/1ps 
 
module jpeg_huffman_decoder ( 
    input wire clk, 
    input wire rst_n, 
    input wire enable, // Chỉ decode/nạp bit khi = 1 
    input wire start, // Load table 
    // Bitstream Input 
    input wire bit_in, 
    input wire bit_valid, 
    // Huffman Tables 
    input wire [15:0] huff_code_in [0:255], 
    input wire [4:0] huff_len_in [0:255], 
    output reg [7:0] symbol_out, 
    output reg symbol_valid 
); 
    // ================= BUFFERS ================= 
    reg [31:0] shift_buf; 
    reg [5:0] bit_count; 
 
    // ================= TABLES ================= 
    reg [15:0] tbl_code [0:255]; 
    reg [4:0] tbl_len [0:255]; 
    integer i; 
     
    // Flag tối ưu hiệu năng 
    reg tables_loaded; 
 
    // ================= SEARCH SIGNALS ================= 
    integer k, j; 
    reg found; 
    reg [4:0] found_len; 
    reg [7:0] found_symbol; 
 
    // ================= LOGIC TỔ HỢP TÍNH TOÁN NEXT STATE ================= 
    reg [31:0] next_shift_buf; 
    reg [5:0] next_bit_count; 
 
    always @(*) begin 
        // 1. Mặc định giữ nguyên 
        next_shift_buf = shift_buf; 
        next_bit_count = bit_count; 
 
        // 2. Nếu có bit mới vào -> Thêm vào buffer 
        if (enable && bit_valid) begin 
            next_shift_buf = (next_shift_buf << 1) | bit_in; 
            next_bit_count = next_bit_count + 1; 
        end 
 
        // 3. Nếu tìm thấy Symbol -> Cắt bớt phần đầu buffer 
        if (enable && found) begin 
            if (next_bit_count >= found_len) begin 
                next_shift_buf = next_shift_buf & ((1 << (next_bit_count - found_len)) - 1); 
                next_bit_count = next_bit_count - found_len; 
            end else begin 
                // Lỗi logic hy hữu: Reset 
                next_shift_buf = 0; 
                next_bit_count = 0; 
            end 
        end 
    end 
 
    // ================= MAIN SEQUENTIAL LOGIC ================= 
    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin 
            shift_buf <= 32'd0; 
            bit_count <= 6'd0; 
            symbol_out <= 8'd0; 
            symbol_valid <= 1'b0; 
            tables_loaded <= 0; 
            // Reset tables (Optional) 
            for (i = 0; i < 256; i = i + 1) begin 
                tbl_code[i] <= 16'd0; 
                tbl_len[i] <= 5'd0; 
            end 
        end else begin 
            symbol_valid <= 1'b0; 
 
            // --- TỐI ƯU: Load Tables (Chỉ chạy 1 lần) --- 
            if (start) begin 
                if (!tables_loaded) begin 
                    for (i = 0; i < 256; i = i + 1) begin 
                        tbl_code[i] <= huff_code_in[i]; 
                        tbl_len[i] <= huff_len_in[i]; 
                    end 
                    tables_loaded <= 1; 
                end 
            end else begin 
                tables_loaded <= 0; // Reset flag nếu start mất 
            end 
 
            // Cập nhật Buffer & Count từ logic tổ hợp 
            if (enable) begin 
                shift_buf <= next_shift_buf; 
                bit_count <= next_bit_count; 
                // Output Symbol nếu tìm thấy 
                if (found) begin 
                    symbol_out <= found_symbol; 
                    symbol_valid <= 1'b1; 
                end 
            end 
        end 
    end 
 
    // ================= LOGIC TÌM KIẾM (COMBINATIONAL) ================= 
    always @(*) begin 
        found = 0; 
        found_len = 0; 
        found_symbol = 0; 
 
        if (enable) begin 
            for (k = 1; k <= 16; k = k + 1) begin 
                // Chỉ tìm nếu chưa thấy và đủ bit 
                if (!found && bit_count >= k) begin 
                    for (j = 0; j < 256; j = j + 1) begin 
                        if (!found && tbl_len[j] == k) begin 
                            // So sánh mã: Lấy k bit cao nhất của shift_buf 
                            if (tbl_code[j] == (shift_buf >> (bit_count - k))) begin 
                                found = 1; 
                                found_len = k[4:0]; 
                                found_symbol = j[7:0]; 
                            end 
                        end 
                    end 
                end 
            end 
        end 
    end 
endmodule 