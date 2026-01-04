// GD1: Tìm kiếm: FSM liên tục quét luồng byte đầu vào (S_IDLE, S_FIND_FF) tìm marker 0xFF
// GD2: Phân loại: Khi tìm thấy 0xFF, kiểm tra byte tiếp theo (S_GOT_FF):
// - Nếu là 0x00: bỏ qua -> tiếp tục tìm 0xFF
// - Ngược lại, là các marker chuẩn như D8, C0.... -> lưu marker đó vào cur_marker
// GD3: Đọc độ dài: Hầu hết các marker trừ SOI và SOS đều có 2 byte sau đó để biết segment này dài bao nhiêu. (S_READ_LEN_H, S_READ_LEN_L)
// GD4: Xử lý dữ liệu: Tùy vào loại marker, FSM nhảy vào trạng thái tương ứng
// - Marker SOF0: -> trạng thái S_READ_SOF0: trích xuất chiều dài, chiều rộng của ảnh
// - Marker DQT: -> trạng thái S_READ_DQT: đọc bảng lượng tử (phân loại 8 bit và 16 bit) và lưu trữ vào bộ nhớ qtable_mem
// - Marker DHT: -> S_READ_DHT: Đọc bảng Huffman (số lượng mã và các ký hiệu), lưu vào bộ nhớ dht_sym_mem.
// - Marker lạ: S_SKIP_SEG: Nếu gặp marker lạ (APPn) hoặc header của SOS, nó đếm lùi bytes_left để bỏ qua.
// GD5: Bàn giao (Handoff): Khi xử lý xong header của SOS (S_DONE_HDR), module bật tín hiệu start_scan và chuyển sang chế độ S_PASS_THROUGH
// đẩy toàn bộ dữ liệu ảnh nén trực tiếp cho module Entropy Decoder.
module jpeg_header_parser (
input  wire        clk,
input  wire        rst_n,
// --- Giao diện đầu vào (Nhận byte từ Testbench/RAM) ---
input  wire [7:0]  byte_in,          // Dữ liệu vào 8-bit
input  wire        byte_valid,       // Báo hiệu dữ liệu hợp lệ
output reg         parser_ready,     // =1: Sẵn sàng nhận (Handshake)

// --- Thông tin ảnh đầu ra ---
output reg [15:0]  img_height,       // Chiều cao ảnh
output reg [15:0]  img_width,        // Chiều rộng ảnh

// --- Tín hiệu báo nạp bảng (Tables) ---
output reg         qtable_loaded,    // Xung báo: Đã nạp xong 1 bảng Lượng tử
output reg  [1:0]  qtable_id_loaded, // ID của bảng vừa nạp (0..3)

output reg         dhttable_loaded,  // Xung báo: Đã nạp xong 1 bảng Huffman
output reg         dht_table_class,  // Loại bảng (0=DC, 1=AC)
output reg  [3:0]  dht_table_id,     // ID bảng (0..3)
output reg  [8:0]  dht_sym_count,    // Số lượng symbol trong bảng này

// --- Giao diện bàn giao (Pass-through) ---
output reg         start_scan,       // Xung báo: Bắt đầu phần dữ liệu nén (Scan)
output reg [7:0]   scan_byte_out,    // Dữ liệu ảnh nén chuyển tiếp
output reg         scan_byte_valid   // Báo hiệu dữ liệu chuyển tiếp hợp lệ
);

// =========================================================================
// 1. ĐỊNH NGHĨA HẰNG SỐ MARKER
// =========================================================================
localparam SOI  = 8'hD8; // Khởi đầu ảnh
localparam SOF0 = 8'hC0; // Thông số khung hình (Baseline)
localparam DQT  = 8'hDB; // Bảng Lượng tử
localparam DHT  = 8'hC4; // Bảng Huffman
localparam SOS  = 8'hDA; // Bắt đầu quét (Start Scan)

// =========================================================================
// 2. ĐỊNH NGHĨA TRẠNG THÁI FSM
// =========================================================================
localparam S_IDLE         = 5'd0;  // Chờ khởi động
localparam S_FIND_FF      = 5'd1;  // Tìm byte 0xFF
localparam S_GOT_FF       = 5'd2;  // Đã thấy 0xFF, kiểm tra byte sau nó
localparam S_READ_LEN_H   = 5'd3;  // Đọc byte cao độ dài
localparam S_READ_LEN_L   = 5'd4;  // Đọc byte thấp độ dài
localparam S_SEG_PROCESS  = 5'd5;  // Chọn nhánh xử lý
localparam S_READ_SOF0    = 5'd6;  // Đọc SOF0
localparam S_READ_DQT     = 5'd7;  // Đọc DQT
localparam S_READ_DHT     = 5'd8;  // Đọc DHT
localparam S_SKIP_SEG     = 5'd9;  // Bỏ qua segment lạ
localparam S_DONE_HDR     = 5'd10; // Hoàn tất Header SOS
localparam S_PASS_THROUGH = 5'd11; // Chế độ chuyển tiếp dữ liệu

reg [4:0] state, next_state;

// =========================================================================
// 3. CÁC THANH GHI NỘI BỘ
// =========================================================================

// Quản lý độ dài Segment
reg [15:0] seg_len;      // Độ dài toàn bộ segment
reg [15:0] bytes_left;   // Số byte còn lại cần đọc
reg [15:0] byte_cnt;     // Đếm số byte đã xử lý trong 1 mục
reg [7:0]  cur_marker;   // Lưu loại Marker hiện tại
reg        saw_ff;       // Cờ báo đã thấy 0xFF (dùng cho logic tìm kiếm)

// Biến cho DQT (Bảng Lượng tử)
reg [1:0]  cur_qtable_id;
reg        cur_qtable_pq;
reg [6:0]  q_coeff_index;       // Index 0..63
reg        waiting_second_byte; // Cờ ghép 16-bit
reg [7:0]  last_byte;           // Lưu tạm byte cao

reg [15:0] qtable_mem [0:3][0:63]; //    Bộ nhớ lưu bảng lượng tử
integer i, j;

// Biến cho DHT (Bảng Huffman)
reg [0:0]  cur_dht_tc;          // Table Class (DC/AC)
reg [3:0]  cur_dht_th;          // Table ID
reg [3:0]  dht_len_index;
reg [7:0]  dht_len_byte [0:15]; // Mảng lưu số lượng mã (Li)
reg [15:0] dht_symbols_to_read; // Tổng số symbol cần đọc
reg [8:0]  dht_symbol_index;    // Index hiện tại

reg [7:0]  dht_sym_mem [0:31][0:255]; // Bộ nhớ lưu Symbol
reg [8:0]  dht_sym_cnt [0:1][0:3];   // Lưu tổng số lượng symbol

// =========================================================================
// 4. MẠCH TUẦN TỰ (SEQUENTIAL LOGIC)
// =========================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // --- RESET TOÀN BỘ ---
        state <= S_IDLE;
        parser_ready <= 1'b1;
        saw_ff <= 1'b0;
        seg_len <= 0; bytes_left <= 0; byte_cnt <= 0; cur_marker <= 0;
        
        // Output Reset
        img_height <= 0; img_width <= 0;
        qtable_loaded <= 0; qtable_id_loaded <= 0;
        dhttable_loaded <= 0; dht_table_class <= 0; dht_table_id <= 0; dht_sym_count <= 0;
        start_scan <= 0; scan_byte_out <= 0; scan_byte_valid <= 0;

        // Xóa bộ nhớ (Optional)
        for (i=0; i<4; i=i+1) for (j=0; j<64; j=j+1) qtable_mem[i][j] <= 0;
        for (i=0; i<2; i=i+1) for (j=0; j<4; j=j+1) dht_sym_cnt[i][j] <= 0;

    end else begin
        // Tự động tắt xung báo hiệu sau 1 chu kỳ
        qtable_loaded <= 1'b0;
        dhttable_loaded <= 1'b0;
        start_scan <= 1'b0;
        scan_byte_valid <= 1'b0;

        // Cập nhật trạng thái kế tiếp
        state <= next_state;

        case (state)
            S_IDLE: begin
                saw_ff <= 1'b0; 
                parser_ready <= 1'b1;
            end

            S_FIND_FF: begin
                if (byte_valid && byte_in == 8'hFF) saw_ff <= 1'b1;
            end

            S_GOT_FF: begin
                if (byte_valid) begin
                    if (byte_in == 8'h00) saw_ff <= 1'b0; // Byte stuffing -> Bỏ qua
                    else cur_marker <= byte_in;           // Marker xịn -> Lưu lại
                end
            end

            S_READ_LEN_H: begin
                if (byte_valid) seg_len[15:8] <= byte_in;
            end

            S_READ_LEN_L: begin
                if (byte_valid) begin
                    seg_len[7:0] <= byte_in;
                    // Tính số byte dữ liệu còn lại (Trừ 2 byte length)
                    bytes_left <= ({seg_len[15:8], byte_in}) - 16'd2;
                    byte_cnt <= 0; // Reset bộ đếm
                end
            end

            // --- XỬ LÝ SOF0 (Kích thước ảnh) ---
            S_READ_SOF0: begin
                if (byte_valid) begin
                    if (byte_cnt == 1) img_height[15:8] <= byte_in;
                    else if (byte_cnt == 2) img_height[7:0]  <= byte_in;
                    else if (byte_cnt == 3) img_width[15:8]  <= byte_in;
                    else if (byte_cnt == 4) img_width[7:0]   <= byte_in;
                    
                    byte_cnt <= byte_cnt + 1;
                    if (bytes_left > 0) bytes_left <= bytes_left - 1;
                end
            end

            // --- XỬ LÝ DQT (Bảng Lượng tử) ---
            // Marker: 2 byte 0xFF 0xDB
            // 2 byte: do dai segment 
            // 1 byte: DQT info: 
            //          4 bit cao (Pq): do chinh xac 
            //          4 bit thap (Tq): id cua bang
            // QT data
            S_READ_DQT: begin
                if (byte_valid) begin
                    if (byte_cnt == 0) begin
                        // Byte đầu tiên: Thông tin bảng
                        cur_qtable_pq <= byte_in[7];
                        cur_qtable_id <= byte_in[3:0];
                        q_coeff_index <= 0;
                        waiting_second_byte <= 0;
                        
                        byte_cnt <= byte_cnt + 1;
                        if (bytes_left > 0) bytes_left <= bytes_left - 1;
                    end else begin
                        // Đọc 64 hệ số
                        if (cur_qtable_pq == 0) begin 
                            // Chế độ 8-bit
                            qtable_mem[cur_qtable_id][q_coeff_index] <= {8'd0, byte_in};
                            q_coeff_index <= q_coeff_index + 1;
                            
                            byte_cnt <= byte_cnt + 1;
                            if (bytes_left > 0) bytes_left <= bytes_left - 1;

                            if (q_coeff_index == 63) begin
                                qtable_loaded <= 1'b1;
                                qtable_id_loaded <= cur_qtable_id;
                                byte_cnt <= 0; // Reset đón bảng tiếp theo
                            end
                        end else begin 
                            // Chế độ 16-bit
                            if (!waiting_second_byte) begin
                                last_byte <= byte_in;
                                waiting_second_byte <= 1;
                                byte_cnt <= byte_cnt + 1;
                                if (bytes_left > 0) bytes_left <= bytes_left - 1;
                            end else begin
                                qtable_mem[cur_qtable_id][q_coeff_index] <= {last_byte, byte_in};
                                waiting_second_byte <= 0;
                                q_coeff_index <= q_coeff_index + 1;
                                
                                byte_cnt <= byte_cnt + 1;
                                if (bytes_left > 0) bytes_left <= bytes_left - 1;

                                if (q_coeff_index == 63) begin
                                    qtable_loaded <= 1'b1;
                                    qtable_id_loaded <= cur_qtable_id;
                                    byte_cnt <= 0;
                                end
                            end
                        end
                    end
                end
            end

            // --- XỬ LÝ DHT (Bảng Huffman) ---
            S_READ_DHT: begin
                if (byte_valid) begin
                    if (byte_cnt == 0) begin
                        // Thông tin bảng
                        cur_dht_tc <= byte_in[4];
                        cur_dht_th <= byte_in[3:0];
                        dht_len_index <= 0;
                        dht_symbols_to_read <= 0;
                        dht_symbol_index <= 0;
                        
                        byte_cnt <= byte_cnt + 1;
                        if (bytes_left > 0) bytes_left <= bytes_left - 1;
                    end else if (byte_cnt <= 16) begin
                        // Đọc Counts
                        dht_len_byte[byte_cnt-1] <= byte_in;
                        dht_symbols_to_read <= dht_symbols_to_read + byte_in;
                        dht_len_index <= dht_len_index + 1;
                        
                        byte_cnt <= byte_cnt + 1;
                        if (bytes_left > 0) bytes_left <= bytes_left - 1;
                    end else begin
                        // Đọc Symbols
                        dht_sym_mem[{cur_dht_tc, cur_dht_th}][dht_symbol_index] <= byte_in;
                        dht_symbol_index <= dht_symbol_index + 1;
                        
                        if (bytes_left > 0) bytes_left <= bytes_left - 1;

                        // Kiểm tra xong bảng chưa
                        if (dht_symbol_index + 1 >= dht_symbols_to_read) begin
                            dhttable_loaded <= 1'b1;
                            dht_table_class <= cur_dht_tc;
                            dht_table_id <= cur_dht_th;
                            dht_sym_count <= dht_symbols_to_read[8:0];
                            
                            byte_cnt <= 0; // Reset
                            dht_symbols_to_read <= 0;
                            dht_symbol_index <= 0;
                        end else begin
                            byte_cnt <= byte_cnt + 1;
                        end
                    end
                end
            end

            // --- BỎ QUA SEGMENT ---
            S_SKIP_SEG: begin
                if (byte_valid) begin
                    if (bytes_left > 0) bytes_left <= bytes_left - 1;
                end
            end

           // --- CHUYỂN TIẾP DỮ LIỆU ---
                S_PASS_THROUGH: begin
                    parser_ready <= 1'b1;

                    // Chuyển tiếp byte trực tiếp
                    if (byte_valid) begin
                        scan_byte_out <= byte_in;
                        scan_byte_valid <= 1'b1;
                    end else begin
                        scan_byte_valid <= 1'b0;
                    end
                end
                
                // THÊM: S_DONE_HDR cũng phải chuyển tiếp nếu có byte dư
                S_DONE_HDR: begin
                    start_scan <= 1'b1;
                    // Nếu byte_valid đang 1, nghĩa là đây là byte đầu tiên của scan
                    // Cần đẩy nó ra scan_byte_out luôn!
                    if (byte_valid) begin
                         scan_byte_out <= byte_in;
                         scan_byte_valid <= 1'b1;
                    end
                    next_state <= S_PASS_THROUGH;
                end
        endcase
    end
end

// =========================================================================
// 5. MẠCH TỔ HỢP (COMBINATIONAL LOGIC - CHUYỂN TRẠNG THÁI)
// =========================================================================
always @(*) begin
    next_state = state; // Mặc định giữ nguyên

    case (state)
        S_IDLE:    next_state = S_FIND_FF;

        S_FIND_FF: if (byte_valid && byte_in == 8'hFF) next_state = S_GOT_FF;

        S_GOT_FF: begin
            if (byte_valid) begin
                if (byte_in == 8'hFF) next_state = S_GOT_FF;      // Vẫn là FF
                else if (byte_in == 8'h00) next_state = S_FIND_FF; // Stuffing
                else begin
                    // Phân loại Marker
                    if (byte_in == SOI) next_state = S_FIND_FF;
                    else next_state = S_READ_LEN_H; // Mọi marker khác đều đọc length
                end
            end
        end

        S_READ_LEN_H: if (byte_valid) next_state = S_READ_LEN_L;

        S_READ_LEN_L: begin
            if (byte_valid) begin
                // Điều hướng dựa trên Marker đã lưu
                if (cur_marker == SOF0) next_state = S_READ_SOF0;
                else if (cur_marker == DQT) next_state = S_READ_DQT;
                else if (cur_marker == DHT) next_state = S_READ_DHT;
                else if (cur_marker == SOS) next_state = S_SKIP_SEG; // Skip header SOS
                else next_state = S_SKIP_SEG; // Skip APPn...
            end
        end

        // Điều kiện thoát: Khi byte_valid và bytes_left == 1 (Byte cuối cùng)
        S_READ_SOF0: if (byte_valid && bytes_left == 16'd1) next_state = S_FIND_FF;
        S_READ_DQT:  if (byte_valid && bytes_left == 16'd1) next_state = S_FIND_FF;
        S_READ_DHT:  if (byte_valid && bytes_left == 16'd1) next_state = S_FIND_FF;

        S_SKIP_SEG: begin
            if (byte_valid && bytes_left == 16'd1) begin
                // Nếu vừa skip xong header SOS thì Bàn giao
                if (cur_marker == SOS) next_state = S_DONE_HDR;
                else next_state = S_FIND_FF;
            end
        end

        S_DONE_HDR: next_state = S_PASS_THROUGH;
        S_PASS_THROUGH: next_state = S_PASS_THROUGH;

        default: next_state = S_FIND_FF;
    endcase
end
endmodule