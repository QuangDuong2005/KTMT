`timescale 1ns/1ps

// ============================================================
// MODULE: JPEG ENTROPY DECODER
// Chức năng:
//  - Giải mã Huffman (Run/Size)
//  - Đọc bit VLI từ bitstream
//  - Khôi phục 64 hệ số DCT (DC + AC) cho mỗi block 8x8
//  - Xuất hệ số theo thứ tự zigzag index (0 → 63)
// ============================================================

module jpeg_entropy_decoder (
    input  wire        clk,
    input  wire        rst_n,

    // ================= HUFFMAN INTERFACE =================
    // symbol_in  : byte Huffman đã giải mã (Run/Size)
    // symbol_valid : báo symbol hợp lệ
    output reg         huff_enable,  // cho phép Huffman decoder chạy tiếp

    input  wire [7:0]  symbol_in, 
    input  wire        symbol_valid,

    // ================= BITSTREAM INTERFACE =================
    // bit_in    : bit dữ liệu VLI
    // bit_valid : bit hợp lệ
    input  wire        bit_in,
    input  wire        bit_valid,

    // ================= OUTPUT COEFFICIENT =================
    // coeff_valid : hệ số hợp lệ
    // coeff_index : vị trí zigzag (0..63)
    // coeff_value : giá trị hệ số sau giải mã entropy
    output reg         coeff_valid,
    output reg  [5:0]  coeff_index,
    output reg  signed [11:0] coeff_value,

    // Báo đã giải mã xong 1 block 8x8
    output reg         block_done,

    // Dùng debug: báo đang đọc bit VLI
    output wire        is_reading_bits
);

    // ====================================================
    // 1. FSM STATES
    // ====================================================
    // FSM điều khiển toàn bộ quá trình entropy decoding
    localparam S_IDLE       = 2'd0; // Chờ Huffman symbol
    localparam S_OUTPUT_RUN = 2'd1; // Xuất chuỗi số 0 (Run-length)
    localparam S_READ_BITS  = 2'd2; // Đọc bit VLI
    localparam S_PAD_ZERO   = 2'd3; // Điền 0 khi gặp EOB

    // ====================================================
    // 2. REGISTERS
    // ====================================================
    reg [1:0] state;              // trạng thái FSM
    reg [3:0] size_reg;           // số bit VLI cần đọc (Size)
    reg [4:0] run_cnt;            // số lượng số 0 cần xuất
    reg [4:0] bits_read_cnt;      // đếm số bit VLI đã đọc
    reg [15:0] amp_bits_reg;      // thanh ghi shift lưu bit VLI
    reg signed [11:0] dc_prev;    // lưu DC trước đó (differential)
    reg [5:0] idx;                // chỉ số zigzag (0..63)

    assign is_reading_bits = (state == S_READ_BITS);

    // ====================================================
    // 3. SAFETY LOGIC
    // ====================================================
    // Nếu bit_valid = 0 → ép bit_in = 0
    // Tránh lan truyền giá trị X trong mô phỏng
    wire safe_bit_in = bit_valid ? bit_in : 1'b0;

    // Dịch trái + ghép bit mới vào thanh ghi VLI
    wire [15:0] current_amp_comb =
        (amp_bits_reg << 1) | safe_bit_in;

    // ====================================================
    // 4. HÀM GIẢI MÃ VLI (CỰC KỲ QUAN TRỌNG)
    // ====================================================
    // JPEG KHÔNG dùng bù 2 cho số âm
    // Quy tắc:
    //   - MSB = 1 → số dương
    //   - MSB = 0 → số âm
    //   - Giá trị âm = bits - (2^Size - 1)
    function signed [11:0] func_decode_vli;
        input [15:0] bits;
        input [3:0]  sz;
        reg [15:0] val_masked;
        begin
            // Nếu Size = 0 → giá trị = 0
            if (sz == 0)
                func_decode_vli = 12'sd0;
            else begin
                // Lấy đúng sz bit thấp nhất
                val_masked = bits & ((1 << sz) - 1);

                // Kiểm tra bit dấu (MSB của sz bit)
                if ((bits >> (sz - 1)) & 1'b1) begin
                    // Số dương
                    func_decode_vli = $signed(val_masked[11:0]);
                end else begin
                    // Số âm (theo chuẩn JPEG)
                    func_decode_vli =
                        $signed(val_masked[11:0])
                        - $signed(16'd1 << sz)
                        + 16'd1;
                end
            end
        end
    endfunction

    // Giải mã trước VLI để dùng chung cho DC & AC
    wire signed [11:0] vli_decoded;
    assign vli_decoded = func_decode_vli(current_amp_comb, size_reg);

    // ====================================================
    // 5. FSM SEQUENTIAL LOGIC (TRÁI TIM MODULE)
    // ====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset toàn bộ
            state <= S_IDLE;
            huff_enable <= 1'b1;
            idx <= 0;
            dc_prev <= 0;
            coeff_valid <= 0;
            block_done <= 0;
            run_cnt <= 0;
            size_reg <= 0;
            bits_read_cnt <= 0;
            amp_bits_reg <= 0;
            coeff_value <= 0;
            coeff_index <= 0;
        end else begin
            // Default mỗi clock
            coeff_valid <= 0;
            block_done  <= 0;

            case (state)

                // ------------------------------------------------
                // STATE: IDLE
                // Nhận Huffman symbol (Run/Size)
                // ------------------------------------------------
                S_IDLE: begin
                    huff_enable <= 1'b1;

                    if (symbol_valid) begin
                        huff_enable <= 1'b0;
                        size_reg <= symbol_in[3:0];

                        // ---------- DC COEFFICIENT ----------
                        if (idx == 0) begin
                            run_cnt <= 0;

                            // Size = 0 → DC không đổi
                            if (symbol_in[3:0] == 0) begin
                                coeff_valid <= 1;
                                coeff_value <= dc_prev;
                                coeff_index <= 0;
                                idx <= 1;
                            end else begin
                                // Có diff → đọc VLI
                                state <= S_READ_BITS;
                                bits_read_cnt <= 0;
                                amp_bits_reg <= 0;
                            end
                        end
                        // ---------- AC COEFFICIENT ----------
                        else begin
                            run_cnt <= symbol_in[7:4];

                            if (symbol_in == 8'h00) begin
                                // EOB
                                state <= S_PAD_ZERO;
                            end
                            else if (symbol_in == 8'hF0) begin
                                // ZRL → 16 số 0
                                run_cnt <= 16;
                                state <= S_OUTPUT_RUN;
                            end
                            else if (symbol_in[7:4] > 0) begin
                                // Run > 0
                                state <= S_OUTPUT_RUN;
                            end
                            else begin
                                // Run = 0 → đọc VLI ngay
                                state <= S_READ_BITS;
                                bits_read_cnt <= 0;
                                amp_bits_reg <= 0;
                            end
                        end
                    end
                end

                // ------------------------------------------------
                // STATE: OUTPUT_RUN
                // Xuất chuỗi số 0 theo Run-length
                // ------------------------------------------------
                S_OUTPUT_RUN: begin
                    huff_enable <= 1'b0;

                    coeff_valid <= 1;
                    coeff_value <= 0;
                    coeff_index <= idx;

                    if (idx == 63) begin
                        block_done <= 1;
                        idx <= 0;
                        state <= S_IDLE;
                    end else begin
                        idx <= idx + 1;

                        if (run_cnt > 1)
                            run_cnt <= run_cnt - 1;
                        else begin
                            if (size_reg == 0)
                                state <= S_IDLE;
                            else begin
                                state <= S_READ_BITS;
                                bits_read_cnt <= 0;
                                amp_bits_reg <= 0;
                            end
                        end
                    end
                end

                // ------------------------------------------------
                // STATE: READ_BITS
                // Đọc bit VLI từ bitstream
                // ------------------------------------------------
                S_READ_BITS: begin
                    huff_enable <= 1'b0;

                    if (bit_valid) begin
                        amp_bits_reg <= current_amp_comb;
                        bits_read_cnt <= bits_read_cnt + 1;

                        // Đọc đủ Size bit
                        if (bits_read_cnt + 1 == size_reg) begin
                            coeff_valid <= 1;
                            coeff_index <= idx;

                            if (idx == 0) begin
                                // DC: cộng dồn sai phân
                                dc_prev <= dc_prev + vli_decoded;
                                coeff_value <= dc_prev + vli_decoded;
                            end else begin
                                // AC: giá trị trực tiếp
                                coeff_value <= vli_decoded;
                            end

                            if (idx == 63) begin
                                block_done <= 1;
                                idx <= 0;
                            end else
                                idx <= idx + 1;

                            state <= S_IDLE;
                        end
                    end
                end

                // ------------------------------------------------
                // STATE: PAD_ZERO
                // Điền số 0 còn lại khi gặp EOB
                // ------------------------------------------------
                S_PAD_ZERO: begin
                    huff_enable <= 1'b0;

                    coeff_valid <= 1;
                    coeff_value <= 0;
                    coeff_index <= idx;

                    if (idx == 63) begin
                        block_done <= 1;
                        idx <= 0;
                        state <= S_IDLE;
                    end else
                        idx <= idx + 1;
                end

            endcase
        end
    end
endmodule
