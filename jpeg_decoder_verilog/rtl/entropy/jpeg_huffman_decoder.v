`timescale 1ns/1ps

module jpeg_huffman_decoder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,      // Chỉ decode/nạp bit khi = 1
    input  wire        start,       // Load table

    // Bitstream Input
    input  wire        bit_in,
    input  wire        bit_valid,

    // Huffman Tables
    input  wire [15:0] huff_code_in [0:255],
    input  wire [4:0]  huff_len_in  [0:255],

    output reg  [7:0]  symbol_out,
    output reg         symbol_valid
);

    // ================= BUFFERS =================
    reg [31:0] shift_buf;
    reg [5:0]  bit_count;

    // ================= TABLES =================
    reg [15:0] tbl_code [0:255];
    reg [4:0]  tbl_len  [0:255];
    integer i;

    // ================= SEARCH SIGNALS =================
    integer k, j;
    reg found;
    reg [4:0] found_len;
    reg [7:0] found_symbol;

    // ================= LOGIC TỔ HỢP TÍNH TOÁN NEXT STATE =================
    // Biến tạm để tính toán giá trị tiếp theo của buffer và count
    reg [31:0] next_shift_buf;
    reg [5:0]  next_bit_count;

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
        // Lưu ý: found được tính dựa trên shift_buf CŨ (đã ổn định từ clock trước)
        // Nhưng ta áp dụng cắt bỏ lên next_shift_buf để giữ lại bit mới (nếu có)
        if (enable && found) begin
            if (next_bit_count >= found_len) begin
                // Mask để giữ lại phần dư. VD: Buf=1011 (4 bit), Found=10 (2 bit) -> Dư 11
                // next_bit_count lúc này đã bao gồm cả bit mới (nếu có)
                next_shift_buf = next_shift_buf & ((1 << (next_bit_count - found_len)) - 1);
                next_bit_count = next_bit_count - found_len;
            end else begin
                // Trường hợp hy hữu (lỗi logic nếu xảy ra): reset
                next_shift_buf = 0;
                next_bit_count = 0;
            end
        end
    end

    // ================= MAIN SEQUENTIAL LOGIC =================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_buf    <= 32'd0;
            bit_count    <= 6'd0;
            symbol_out   <= 8'd0;
            symbol_valid <= 1'b0;
            
            // Reset tables (Optional, tốn resource mô phỏng)
            for (i = 0; i < 256; i = i + 1) begin
                tbl_code[i] <= 16'd0;
                tbl_len[i]  <= 5'd0;
            end
        end else begin
            symbol_valid <= 1'b0;

            // Load Tables
            if (start) begin
                for (i = 0; i < 256; i = i + 1) begin
                    tbl_code[i] <= huff_code_in[i];
                    tbl_len[i]  <= huff_len_in[i];
                end
            end

            // Cập nhật Buffer & Count từ logic tổ hợp
            if (enable) begin
                shift_buf <= next_shift_buf;
                bit_count <= next_bit_count;
                
                // Output Symbol nếu tìm thấy
                if (found) begin
                    symbol_out   <= found_symbol;
                    symbol_valid <= 1'b1;
                end
            end
        end
    end

    // ================= LOGIC TÌM KIẾM (COMBINATIONAL) =================
    // Tách phần tìm kiếm ra always @(*) để code gọn hơn
    // Logic này dựa trên shift_buf hiện tại (đã chốt từ clock trước)
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