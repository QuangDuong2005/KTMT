`timescale 1ns / 1ps

// ============================================================================
// MÔ TẢ CHỨC NĂNG:
// Nhiệm vụ chính của nó là:
// 1. Quét luồng byte đầu vào để tìm các Marker đặc biệt của chuẩn JPEG (bắt đầu bằng 0xFF).
// 2. Phân loại và xử lý các segment quan trọng:
//    - SOF0 (Start of Frame): Lấy kích thước ảnh (Width, Height) và cấu hình màu (Sampling).
//    - DQT (Define Quantization Table): Trích xuất bảng lượng tử hóa (Quantization Table).
//    - DHT (Define Huffman Table): Trích xuất bảng mã Huffman để giải nén dữ liệu.
//    - SOS (Start of Scan): Phát hiện điểm bắt đầu của dữ liệu ảnh nén để kích hoạt các module sau.
// 3. Bỏ qua các segment không cần thiết (APPn, COM...) để tiết kiệm tài nguyên.
// ============================================================================

module jpeg_header_parser (
    // --- Giao tiếp hệ thống ---
    input  wire        clk,        // Clock hệ thống (xung nhịp đồng bộ)
    input  wire        rst_n,      // Reset tích cực mức thấp (Active-low)

    // --- Luồng dữ liệu đầu vào ---
    input  wire [7:0]  byte_in,    // Byte dữ liệu JPEG được nạp vào từng nhịp
    input  wire        byte_valid, // Tín hiệu báo byte_in đang chứa dữ liệu hợp lệ

    // --- Tín hiệu điều khiển ---
    output reg         parser_ready, // Báo cho khối đọc file biết Parser đã sẵn sàng nhận byte tiếp theo

    // --- Thông tin ảnh (Metadata) từ SOF0 ---
    output reg [15:0]  img_height,     // Chiều cao ảnh (pixel)
    output reg [15:0]  img_width,      // Chiều rộng ảnh (pixel)
    output reg [3:0]   num_components, // Số lượng kênh màu (thường là 3: Y, Cb, Cr)

    // --- Tín hiệu trạng thái ---
    output reg         dhttable_loaded, // Cờ báo: Bảng Huffman đã được nạp xong
    output reg         start_scan,      // Cờ báo: Đã gặp SOS, bắt đầu giải mã dữ liệu ảnh (Scan data)

    // --- Bảng Huffman (Output cho Huffman Decoder) ---
    // Cấu trúc: [len] là số lượng mã, [val] là giá trị symbol tương ứng
    // DC0: Luma DC, AC0: Luma AC, DC1: Chroma DC, AC1: Chroma AC
    output reg [7:0] dc0_len_out [0:15],  // Bảng độ dài mã DC0
    output reg [7:0] dc0_val_out [0:161], // Bảng giá trị symbol DC0
    output reg [7:0] dc1_len_out [0:15], 
    output reg [7:0] dc1_val_out [0:161],
    output reg [7:0] ac0_len_out [0:15], 
    output reg [7:0] ac0_val_out [0:161],
    output reg [7:0] ac1_len_out [0:15], 
    output reg [7:0] ac1_val_out [0:161],

    // --- Bảng Lượng tử (Output cho Dequantizer) ---
    // Dữ liệu được trải phẳng (flatten) thành vector bit để dễ truyền tải
    output reg [511:0] q_quant_table_flat,   // Bảng Q0 (thường cho Luma) - 64 bytes * 8 bit
    output reg [511:0] q_quant_table_1_flat, // Bảng Q1 (thường cho Chroma)

    // --- Thông tin thành phần màu (Component Info) ---
    output reg [2:0] comp_h_samp [0:2], // Hệ số lấy mẫu ngang (Horizontal Sampling Factor) cho Y, Cb, Cr
    output reg [2:0] comp_v_samp [0:2], // Hệ số lấy mẫu dọc (Vertical Sampling Factor)
    output reg [1:0] comp_quant_id [0:2] // ID của bảng lượng tử dùng cho từng kênh màu
);

    // ============================================================
    // MÁY TRẠNG THÁI (FSM) - QUẢN LÝ QUÁ TRÌNH PHÂN TÍCH
    // ============================================================

    // --- Trạng thái cơ bản ---
    localparam ST_IDLE         = 0;  // Chờ byte 0xFF (Marker Prefix)
    localparam ST_MARKER_ID    = 1;  // Đọc byte định danh Marker (ví dụ: C0, C4, DB...)
    localparam ST_LENGTH_HI    = 2;  // Đọc byte cao của độ dài segment
    localparam ST_LENGTH_LO    = 3;  // Đọc byte thấp của độ dài segment
    localparam ST_SKIP_DATA    = 4;  // Trạng thái chờ để bỏ qua các segment không quan tâm (APPn, COM)

    // --- Trạng thái xử lý DQT (Quantization Table) ---
    localparam ST_DQT_INFO     = 5;  // Đọc thông tin bảng Q (ID, độ chính xác)
    localparam ST_DQT_READ     = 6;  // Đọc 64 giá trị của bảng Q

    // --- Trạng thái xử lý SOF0 (Start of Frame) ---
    localparam ST_SOF_PREC     = 7;  // Độ chính xác bit (thường là 8-bit)
    localparam ST_SOF_H_HI     = 8;  // Chiều cao (Byte cao)
    localparam ST_SOF_H_LO     = 9;  // Chiều cao (Byte thấp)
    localparam ST_SOF_W_HI     = 10; // Chiều rộng (Byte cao)
    localparam ST_SOF_W_LO     = 11; // Chiều rộng (Byte thấp)
    localparam ST_SOF_COMP     = 12; // Số lượng component
    localparam ST_SOF_C_ID     = 13; // ID Component (1=Y, 2=Cb, 3=Cr)
    localparam ST_SOF_C_SAMP   = 14; // Hệ số lấy mẫu (Sampling Factors)
    localparam ST_SOF_C_QT     = 15; // Bảng Q tương ứng
    localparam ST_SOF_SKIP     = 16; // Bỏ qua nếu còn dư dữ liệu trong segment

    // --- Trạng thái xử lý DHT (Huffman Table) ---
    localparam ST_DHT_INFO     = 17; // Thông tin bảng Huffman (Class: AC/DC, ID)
    localparam ST_DHT_COUNTS   = 18; // Đọc 16 byte số lượng mã (Counts)
    localparam ST_DHT_SYMBOLS  = 19; // Đọc các giá trị Symbol

    // --- Trạng thái xử lý SOS (Start of Scan) ---
    localparam ST_SOS_SKIP     = 20; // Bỏ qua header SOS, đi thẳng đến dữ liệu ảnh

    localparam ST_DONE         = 21; // Hoàn tất phân tích header

    // ============================================================
    // CÁC THANH GHI NỘI BỘ (INTERNAL REGISTERS)
    // ============================================================

    reg [4:0]  state;        // Thanh ghi lưu trạng thái hiện tại của FSM
    reg [15:0] length_cnt;   // Bộ đếm độ dài segment (để biết khi nào đọc xong một marker)
    reg [7:0]  marker_type;  // Lưu loại marker đang xử lý (ví dụ: 0xC4 cho DHT)

    // Bộ nhớ tạm cho Quantization Table (2 bảng x 64 byte)
    reg [7:0] qtable_mem [0:1][0:63];
    reg [1:0] current_dqt_id; // ID bảng Q đang đọc
    reg [5:0] dqt_idx;        // Index chạy từ 0->63 khi đọc bảng Q

    // Các biến phục vụ việc đọc Huffman Table
    reg [3:0] dht_len_idx;   // Index chạy từ 0->15 (cho 16 độ dài mã)
    reg [7:0] dht_val_cnt;   // Đếm số lượng symbol đã đọc được
    reg [7:0] total_syms;    // Tổng số symbol cần đọc trong bảng hiện tại
    reg       is_ac_table;   // Cờ: 0 = Bảng DC, 1 = Bảng AC
    reg [3:0] dht_table_id;  // ID của bảng Huffman (0 hoặc 1)

    reg [3:0] comp_cnt;      // Bộ đếm số component đã đọc trong SOF

    // ============================================================
    // LOGIC KẾT NỐI (COMBINATIONAL LOGIC)
    // Chuyển đổi mảng 2 chiều qtable_mem thành vector phẳng 1 chiều
    // để dễ dàng đưa ra output port.
    // ============================================================

    genvar k;
    generate
        for (k=0; k<64; k=k+1) begin : flat_q
            // Map từng byte của bảng Q0 và Q1 vào vị trí tương ứng trên bus output
            always @(*) q_quant_table_flat[k*8 +: 8]   = qtable_mem[0][k];
            always @(*) q_quant_table_1_flat[k*8 +: 8] = qtable_mem[1][k];
        end
    endgenerate

    // ============================================================
    // LOGIC CHÍNH (SEQUENTIAL LOGIC)
    // Điều khiển chuyển trạng thái FSM và xử lý dữ liệu
    // ============================================================

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // --- Reset bất đồng bộ ---
            state <= ST_IDLE;
            parser_ready <= 1; // Sẵn sàng đọc ngay sau khi reset
            img_height <= 0;
            img_width  <= 0;
            num_components <= 0;
            dhttable_loaded <= 0;
            start_scan <= 0;
            length_cnt <= 0;

            // Xóa sạch các bảng Huffman khi reset
            for (i=0; i<16; i=i+1) begin
                dc0_len_out[i] <= 0;
                dc1_len_out[i] <= 0;
                ac0_len_out[i] <= 0;
                ac1_len_out[i] <= 0;
            end
        end else begin
            // Chỉ xử lý khi có byte hợp lệ và CHƯA bắt đầu giải mã dữ liệu ảnh (scan)
            if (byte_valid && !start_scan) begin

                case (state)

                    // ------------------------------------------------------------
                    // GIAI ĐOẠN 1: TÌM KIẾM MARKER
                    // ------------------------------------------------------------
                    ST_IDLE: begin
                        // Mọi marker JPEG đều bắt đầu bằng 0xFF
                        if (byte_in == 8'hFF)
                            state <= ST_MARKER_ID;
                    end

                    ST_MARKER_ID: begin
                        // Xử lý byte tiếp theo sau 0xFF
                        if (byte_in == 8'hFF)
                            state <= ST_MARKER_ID; // Vẫn là padding 0xFF, tiếp tục chờ
                        else if (byte_in == 8'h00)
                            state <= ST_IDLE;      // 0xFF 00 không phải marker, quay lại tìm
                        else begin
                            // Phát hiện marker hợp lệ!
                            marker_type <= byte_in;
                            $display("MARKER FOUND: FF %x", byte_in); // Debug log

                            // Phân loại marker để chuyển trạng thái
                            case (byte_in)
                                8'hC0: state <= ST_LENGTH_HI; // SOF0 (Start Of Frame)
                                8'hC4: state <= ST_LENGTH_HI; // DHT (Huffman Table)
                                8'hDB: state <= ST_LENGTH_HI; // DQT (Quantization Table)
                                8'hDA: state <= ST_LENGTH_HI; // SOS (Start Of Scan)
                                default: state <= ST_LENGTH_HI; // Các marker khác (APPn, COM...) -> Sẽ skip
                            endcase
                        end
                    end

                    // ------------------------------------------------------------
                    // GIAI ĐOẠN 2: ĐỌC ĐỘ DÀI SEGMENT (2 BYTES)
                    // ------------------------------------------------------------
                    ST_LENGTH_HI: begin
                        length_cnt[15:8] <= byte_in; // Byte cao
                        state <= ST_LENGTH_LO;
                    end

                    ST_LENGTH_LO: begin
                        length_cnt[7:0] <= byte_in;  // Byte thấp
                        // Sau khi có độ dài, nhảy đến trạng thái xử lý tương ứng với Marker Type đã lưu
                        case (marker_type)
                            8'hC0: state <= ST_SOF_PREC;
                            8'hDB: state <= ST_DQT_INFO;
                            8'hC4: state <= ST_DHT_INFO;
                            8'hDA: state <= ST_SOS_SKIP;
                            default: state <= ST_SKIP_DATA; // Marker lạ -> Bỏ qua
                        endcase
                    end

                    // ------------------------------------------------------------
                    // GIAI ĐOẠN 3: BỎ QUA DỮ LIỆU KHÔNG CẦN THIẾT
                    // ------------------------------------------------------------
                    ST_SKIP_DATA: begin
                        // Trừ dần length_cnt cho đến khi hết segment
                        if (length_cnt <= 3) // Ngưỡng an toàn (bao gồm 2 byte length đã đọc)
                            state <= ST_IDLE;
                        else
                            length_cnt <= length_cnt - 1;
                    end

                    // ------------------------------------------------------------
                    // GIAI ĐOẠN 4: XỬ LÝ DQT (QUANTIZATION TABLE)
                    // ------------------------------------------------------------
                    ST_DQT_INFO: begin
                        // Byte đầu tiên chứa ID bảng lượng tử (bit 0-3) và độ chính xác (bit 4-7)
                        current_dqt_id <= byte_in[1:0];
                        dqt_idx <= 0;
                        length_cnt <= length_cnt - 1;
                        state <= ST_DQT_READ;
                    end

                    ST_DQT_READ: begin
                        // Đọc 64 giá trị của bảng lượng tử
                        if (current_dqt_id < 2)
                            qtable_mem[current_dqt_id][dqt_idx] <= byte_in;

                        length_cnt <= length_cnt - 1;

                        if (dqt_idx == 63) begin
                            // Đã đọc xong 1 bảng (64 byte)
                            if (length_cnt <= 3)
                                state <= ST_IDLE;    // Hết segment DQT
                            else
                                state <= ST_DQT_INFO; // Vẫn còn bảng DQT khác trong segment này
                        end else
                            dqt_idx <= dqt_idx + 1;
                    end

                    // ------------------------------------------------------------
                    // GIAI ĐOẠN 5: XỬ LÝ SOF0 (FRAME HEADER)
                    // ------------------------------------------------------------
                    ST_SOF_PREC: begin
                        // Đọc độ chính xác (Precision) - thường bỏ qua vì JPEG chuẩn là 8-bit
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_H_HI;
                    end

                    ST_SOF_H_HI: begin
                        img_height[15:8] <= byte_in; // Chiều cao byte cao
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_H_LO;
                    end

                    ST_SOF_H_LO: begin
                        img_height[7:0] <= byte_in;  // Chiều cao byte thấp
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_W_HI;
                    end

                    ST_SOF_W_HI: begin
                        img_width[15:8] <= byte_in;  // Chiều rộng byte cao
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_W_LO;
                    end

                    ST_SOF_W_LO: begin
                        img_width[7:0] <= byte_in;   // Chiều rộng byte thấp
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_COMP;
                    end

                    ST_SOF_COMP: begin
                        num_components <= byte_in[3:0]; // Số lượng component (thường là 3)
                        comp_cnt <= 0;
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_C_ID;
                    end

                    // --- Vòng lặp đọc thông tin từng Component ---
                    ST_SOF_C_ID: begin
                        // ID của Component (1=Y, 2=Cb, 3=Cr)
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_C_SAMP;
                    end

                    ST_SOF_C_SAMP: begin
                        // Hệ số lấy mẫu (Sampling Factors)
                        comp_h_samp[comp_cnt] <= byte_in[7:4]; // Horizontal
                        comp_v_samp[comp_cnt] <= byte_in[3:0]; // Vertical
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_C_QT;
                    end

                    ST_SOF_C_QT: begin
                        // Bảng lượng tử (Quantization Table ID) gán cho component này
                        comp_quant_id[comp_cnt] <= byte_in[1:0];
                        length_cnt <= length_cnt - 1;
                        comp_cnt <= comp_cnt + 1;

                        if (comp_cnt + 1 < num_components)
                            state <= ST_SOF_C_ID; // Quay lại đọc component tiếp theo
                        else if (length_cnt <= 3)
                            state <= ST_IDLE;     // Hết segment
                        else
                            state <= ST_SOF_SKIP; // Dư dữ liệu -> Bỏ qua
                    end

                    ST_SOF_SKIP: begin
                        if (length_cnt <= 3) state <= ST_IDLE;
                        else length_cnt <= length_cnt - 1;
                    end

                    // ------------------------------------------------------------
                    // GIAI ĐOẠN 6: XỬ LÝ DHT (HUFFMAN TABLE)
                    // ------------------------------------------------------------
                    ST_DHT_INFO: begin
                        // Byte thông tin: Bit 4 (Class: 0=DC, 1=AC), Bit 0-3 (ID)
                        is_ac_table <= byte_in[4];
                        dht_table_id <= byte_in[3:0];
                        dht_len_idx <= 0;
                        total_syms <= 0;
                        length_cnt <= length_cnt - 1;
                        state <= ST_DHT_COUNTS;
                    end

                    ST_DHT_COUNTS: begin
                        // Đọc 16 byte "Counts" - số lượng mã cho mỗi độ dài bit (1..16)
                        // Đồng thời lưu vào mảng len_out tương ứng (AC/DC, ID 0/1)
                        if (is_ac_table) begin
                            if (dht_table_id == 0) ac0_len_out[dht_len_idx] <= byte_in;
                            else                  ac1_len_out[dht_len_idx] <= byte_in;
                        end else begin
                            if (dht_table_id == 0) dc0_len_out[dht_len_idx] <= byte_in;
                            else                  dc1_len_out[dht_len_idx] <= byte_in;
                        end

                        total_syms <= total_syms + byte_in; // Cộng dồn tổng số symbol cần đọc tiếp theo
                        length_cnt <= length_cnt - 1;

                        if (dht_len_idx == 15) begin
                            dht_val_cnt <= 0;
                            state <= ST_DHT_SYMBOLS; // Chuyển sang đọc giá trị symbol
                        end else
                            dht_len_idx <= dht_len_idx + 1;
                    end

                    ST_DHT_SYMBOLS: begin
                        // Đọc các giá trị Symbol thực tế và lưu vào mảng val_out
                        if (is_ac_table) begin
                            if (dht_table_id == 0) ac0_val_out[dht_val_cnt] <= byte_in;
                            else                  ac1_val_out[dht_val_cnt] <= byte_in;
                        end else begin
                            if (dht_table_id == 0) dc0_val_out[dht_val_cnt] <= byte_in;
                            else                  dc1_val_out[dht_val_cnt] <= byte_in;
                        end

                        dht_val_cnt <= dht_val_cnt + 1;
                        length_cnt <= length_cnt - 1;

                        if (length_cnt <= 3) begin
                            dhttable_loaded <= 1; // Báo hiệu đã nạp bảng Huffman xong
                            state <= ST_IDLE;
                        end else if (dht_val_cnt + 1 == total_syms)
                            state <= ST_DHT_INFO; // Nếu hết symbol nhưng còn dữ liệu -> Có bảng Huffman khác
                    end

                    // ------------------------------------------------------------
                    // GIAI ĐOẠN 7: XỬ LÝ SOS (START OF SCAN)
                    // ------------------------------------------------------------
                    ST_SOS_SKIP: begin
                        // Bỏ qua phần header của SOS (chứa thông tin map component vào Huffman table)
                        // Vì ta đang làm decoder đơn giản (Baseline), ta giả định mapping mặc định.
                        if (length_cnt <= 3) begin
                            start_scan <= 1;   // Kích hoạt cờ bắt đầu giải mã
                            parser_ready <= 0; // Parser dừng hoạt động để nhường bus cho bộ giải mã entropy
                            state <= ST_DONE;
                        end else
                            length_cnt <= length_cnt - 1;
                    end

                    ST_DONE: start_scan <= 1; // Giữ trạng thái scan

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule