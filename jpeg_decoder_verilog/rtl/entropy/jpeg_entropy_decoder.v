`timescale 1ns/1ps

module jpeg_entropy_decoder (
    input  wire        clk,
    input  wire        rst_n,

    // Huffman Interface
    input  wire [7:0]  symbol_in, 
    input  wire        symbol_valid,
    output reg         huff_enable,

    // Bitstream Interface
    input  wire        bit_in,
    input  wire        bit_valid,

    // Coefficient Output
    output reg         coeff_valid,
    output reg  [5:0]  coeff_index,
    output reg  signed [11:0] coeff_value,
    output reg         block_done,
    output wire        is_reading_bits
);

    // ================= STATES =================
    localparam S_IDLE       = 2'd0;
    localparam S_OUTPUT_RUN = 2'd1;
    localparam S_READ_BITS  = 2'd2;
    localparam S_PAD_ZERO   = 2'd3;

    // ================= REGISTERS =================
    reg [1:0] state;
    reg [3:0] size_reg;
    reg [4:0] run_cnt;
    reg [4:0] bits_read_cnt;
    reg [15:0] amp_bits_reg;
    reg signed [11:0] dc_prev;
    reg [5:0] idx;

    assign is_reading_bits = (state == S_READ_BITS);

    // ================= COMBINATIONAL LOGIC & SAFETY =================
    
    // SAFETY FIX: Che chắn bit_in. Nếu bit_valid=0, ép về 0 để tránh lan truyền X
    wire safe_bit_in = bit_valid ? bit_in : 1'b0; 
    
    // Shift Register Input logic
    wire [15:0] current_amp_comb = (amp_bits_reg << 1) | safe_bit_in;

    // --- CRITICAL FIX: FUNCTION VLI CHUẨN JPEG ---
    // Hàm cũ giải mã sai số âm khi Size > 1. Hàm này tuân thủ chuẩn JPEG ITU-T.81
    function signed [11:0] func_decode_vli;
        input [15:0] bits;
        input [3:0]  sz;
        reg [15:0] val_masked;
        begin
            if (sz == 0) func_decode_vli = 12'sd0;
            else begin
                // B1: Mask chỉ lấy 'sz' bit thấp nhất, loại bỏ rác ở bit cao
                val_masked = bits & ((1 << sz) - 1);
                
                // B2: Kiểm tra bit dấu (MSB của phần sz)
                // Nếu MSB = 1: Số dương (Positive)
                if ((bits >> (sz - 1)) & 1'b1) begin
                    func_decode_vli = $signed(val_masked[11:0]);
                end 
                // Nếu MSB = 0: Số âm (Negative) -> Công thức JPEG: Val - (2^Sz - 1)
                else begin
                    func_decode_vli = $signed(val_masked[11:0]) - $signed(16'd1 << sz) + 16'd1;
                end
            end
        end
    endfunction

    // TỐI ƯU: Tính trước giá trị giải mã để dùng chung cho cả DC và AC
    wire signed [11:0] vli_decoded;
    assign vli_decoded = func_decode_vli(current_amp_comb, size_reg);

    // ================= SEQUENTIAL LOGIC =================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
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
            // Default signals per clock
            coeff_valid <= 0;
            block_done  <= 0;

            case (state)
                // ---------------------------------------------------------
                // STATE: IDLE - Nhận Symbol Huffman (Run/Size)
                // ---------------------------------------------------------
                S_IDLE: begin
                    huff_enable <= 1'b1;
                    
                    if (symbol_valid) begin
                        huff_enable <= 1'b0;
                        size_reg <= symbol_in[3:0];

                        // --- TRƯỜNG HỢP DC (Hệ số đầu tiên - idx 0) ---
                        if (idx == 0) begin
                            run_cnt <= 0; // DC luôn kề nhau, không có Run
                            
                            // FIX: DC Size=0 nghĩa là Diff=0 -> Output DC cũ
                            if (symbol_in[3:0] == 0) begin
                                coeff_valid <= 1;
                                coeff_value <= dc_prev; 
                                coeff_index <= 0;
                                idx <= 1;
                                state <= S_IDLE; // Xong DC, chờ AC
                            end else begin
                                // Có Diff, cần đọc thêm bit
                                state <= S_READ_BITS;
                                bits_read_cnt <= 0;
                                amp_bits_reg <= 0;
                            end
                        end 
                        // --- TRƯỜNG HỢP AC (Hệ số AC - idx > 0) ---
                        else begin
                            run_cnt <= {1'b0, symbol_in[7:4]}; // Lấy Run count

                            if (symbol_in == 8'h00) begin 
                                // EOB (End of Block)
                                state <= S_PAD_ZERO; 
                            end
                            else if (symbol_in == 8'hF0) begin 
                                // ZRL (Zero Run Length) - 16 số 0
                                run_cnt <= 16;
                                state <= S_OUTPUT_RUN;
                            end 
                            else if (symbol_in[7:4] > 0) begin 
                                // Có Run > 0 thường
                                state <= S_OUTPUT_RUN;
                            end
                            else begin 
                                // Không Run, chỉ đọc Size (Diff value)
                                state <= S_READ_BITS;
                                bits_read_cnt <= 0;
                                amp_bits_reg <= 0;
                            end
                        end
                    end
                end

                // ---------------------------------------------------------
                // STATE: OUTPUT RUN - Xuất các số 0 (cho ZRL hoặc Run)
                // ---------------------------------------------------------
                S_OUTPUT_RUN: begin
                    huff_enable <= 1'b0;

                    // SAFETY FIX: Nếu index tràn 63 -> Force thoát để tránh treo
                    if (idx > 63) begin
                        block_done <= 1;
                        idx <= 0;
                        state <= S_IDLE;
                    end else begin
                        // Xuất số 0
                        coeff_valid <= 1;
                        coeff_value <= 0;
                        coeff_index <= idx;

                        // Logic chuyển trạng thái
                        if (idx == 63) begin
                            // Đã chạm đáy block
                            block_done <= 1;
                            idx <= 0;
                            state <= S_IDLE;
                        end else begin
                            idx <= idx + 1; 
                            
                            // Xử lý giảm biến đếm Run
                            if (run_cnt > 1) begin
                                run_cnt <= run_cnt - 1;
                            end else begin
                                // Hết Run
                                if (size_reg == 0) begin
                                    // ZRL (Size=0) -> Xong việc
                                    state <= S_IDLE;
                                end else begin
                                    // Run thường -> Đọc giá trị AC tiếp theo
                                    state <= S_READ_BITS;
                                    bits_read_cnt <= 0;
                                    amp_bits_reg <= 0;
                                end
                            end
                        end
                    end
                end

                // ---------------------------------------------------------
                // STATE: READ BITS - Đọc bit VLI từ bitstream
                // ---------------------------------------------------------
                S_READ_BITS: begin
                    huff_enable <= 1'b0;

                    if (bit_valid) begin
                        amp_bits_reg <= current_amp_comb; // Shift bit vào
                        bits_read_cnt <= bits_read_cnt + 1;

                        // Đã đọc đủ số bit yêu cầu
                        if (bits_read_cnt + 1 == size_reg) begin
                            coeff_valid <= 1;
                            coeff_index <= idx;

                            // Tính toán giá trị và cập nhật
                            if (idx == 0) begin 
                                // DC: Cộng dồn Diff
                                dc_prev <= dc_prev + vli_decoded;
                                coeff_value <= dc_prev + vli_decoded;
                            end else begin 
                                // AC: Giá trị độc lập
                                coeff_value <= vli_decoded;
                            end

                            // Kiểm tra kết thúc block
                            if (idx == 63) begin
                                block_done <= 1;
                                idx <= 0;
                                state <= S_IDLE;
                            end else begin
                                idx <= idx + 1;
                                state <= S_IDLE;
                            end
                        end
                    end
                end

                // ---------------------------------------------------------
                // STATE: PAD ZERO - Điền nốt số 0 khi gặp EOB
                // ---------------------------------------------------------
                S_PAD_ZERO: begin
                    huff_enable <= 1'b0;
                    
                    if (idx > 63) begin
                        block_done <= 1;
                        idx <= 0;
                        state <= S_IDLE;
                    end else begin
                        coeff_valid <= 1;
                        coeff_value <= 0;
                        coeff_index <= idx;

                        if (idx == 63) begin
                            block_done <= 1;
                            idx <= 0;
                            state <= S_IDLE;
                        end else begin
                            idx <= idx + 1;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule