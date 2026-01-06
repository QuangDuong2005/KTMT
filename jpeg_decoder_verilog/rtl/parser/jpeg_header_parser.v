module jpeg_header_parser (
    input wire clk,
    input wire rst_n,
    
    // Luồng byte đầu vào
    input wire [7:0] byte_in,
    input wire byte_valid,
    output reg parser_ready,

    // Thông tin ảnh
    output reg [15:0] img_height,
    output reg [15:0] img_width,
    output reg [3:0]  num_components,
    
    // Tín hiệu điều khiển
    output reg dhttable_loaded,
    output reg start_scan, // = 1 khi gặp SOS (FF DA)
    
    // Output Huffman Tables
    output reg [7:0] dht_len_out [0:15],
    output reg [7:0] dht_val_out [0:161],

    // --- OUTPUT MỚI: Bảng lượng tử phẳng (Fix lỗi Crash Iverilog) ---
    output wire [511:0] q_quant_table_flat,
    output wire [511:0] q_quant_table_1_flat,

    // Component Info
    output reg [2:0] comp_h_samp [0:2],
    output reg [2:0] comp_v_samp [0:2],
    output reg [1:0] comp_quant_id [0:2]
);

    // ==================================================================
    // 1. ĐỊNH NGHĨA TRẠNG THÁI
    // ==================================================================
    localparam ST_IDLE          = 0;
    localparam ST_MARKER_FF     = 1; // Tìm byte FF
    localparam ST_MARKER_ID     = 2; // Đọc byte định danh (D8, C0, C4...)
    localparam ST_LENGTH_HI     = 3; // Đọc độ dài marker (High byte)
    localparam ST_LENGTH_LO     = 4; // Đọc độ dài marker (Low byte)
    localparam ST_SKIP_DATA     = 5; // Bỏ qua dữ liệu không quan trọng
    
    // Trạng thái xử lý DQT (Quantization Table)
    localparam ST_DQT_INFO      = 6;
    localparam ST_DQT_READ      = 7;
    
    // Trạng thái xử lý SOF0 (Start of Frame)
    localparam ST_SOF_PREC      = 8;
    localparam ST_SOF_H_HI      = 9;
    localparam ST_SOF_H_LO      = 10;
    localparam ST_SOF_W_HI      = 11;
    localparam ST_SOF_W_LO      = 12;
    localparam ST_SOF_COMP      = 13;
    localparam ST_SOF_C_ID      = 20;
    localparam ST_SOF_C_SAMP    = 21;
    localparam ST_SOF_C_QT      = 22;
    localparam ST_SOF_SKIP      = 14;

    // Trạng thái xử lý DHT (Huffman Table)
    localparam ST_DHT_INFO      = 15;
    localparam ST_DHT_COUNTS    = 16;
    localparam ST_DHT_SYMBOLS   = 17;

    // Trạng thái SOS (Start of Scan)
    localparam ST_SOS_SKIP      = 18;
    localparam ST_DONE          = 19;

    reg [4:0] state;
    reg [15:0] length_cnt; // Đếm số byte còn lại trong marker segment
    reg [7:0]  marker_type;

    // Bộ nhớ trong cho bảng lượng tử (4 bảng, mỗi bảng 64 byte)
    reg [7:0] qtable_mem [0:3][0:63]; 
    reg [1:0] current_dqt_id;
    reg [5:0] dqt_idx;

    // Bộ đếm cho DHT
    reg [3:0] dht_len_idx;
    reg [7:0] dht_val_cnt;
    reg [7:0] total_syms;

    reg [3:0] comp_cnt; // Đếm số component đã đọc
    reg [1:0] current_comp_id;

    // ==================================================================
    // 2. FSM (MÁY TRẠNG THÁI)
    // ==================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            parser_ready <= 1;
            img_height <= 0;
            img_width <= 0;
            num_components <= 0;
            dhttable_loaded <= 0;
            start_scan <= 0;
            length_cnt <= 0;
            dqt_idx <= 0;
            current_dqt_id <= 0;
        end else begin
            // Chỉ xử lý khi có byte valid và chưa bắt đầu quét ảnh (start_scan)
            if (byte_valid && !start_scan) begin
                case (state)
                    // --------------------------------------------------
                    // TÌM MARKER
                    // --------------------------------------------------
                    ST_IDLE: begin
                        if (byte_in == 8'hFF) state <= ST_MARKER_ID;
                    end

                    ST_MARKER_FF: begin // Trạng thái đệm nếu gặp nhiều FF liên tiếp
                        if (byte_in != 8'hFF) begin
                            // Byte này là ID marker
                            // Logic xử lý nhảy ở case dưới, ở đây chuyển tiếp
                            // (Code tối ưu gộp vào ST_MARKER_ID)
                        end
                    end

                    ST_MARKER_ID: begin
                        if (byte_in == 8'hFF) begin
                            // Vẫn là padding FF, đợi tiếp
                            state <= ST_MARKER_ID;
                        end else if (byte_in == 8'h00) begin
                            // FF 00 không phải marker (byte stuffing), quay lại tìm FF
                            state <= ST_IDLE;
                        end else begin
                            // Đã tìm thấy Marker hợp lệ (FF XX)
                            marker_type <= byte_in;
                            case (byte_in)
                                8'hD8: state <= ST_IDLE; // SOI (Start Image) -> Tiếp tục tìm
                                8'hC0: state <= ST_LENGTH_HI; // SOF0 (Frame Info)
                                8'hC4: state <= ST_LENGTH_HI; // DHT (Huffman)
                                8'hDB: state <= ST_LENGTH_HI; // DQT (Quantization)
                                8'hDA: state <= ST_LENGTH_HI; // SOS (Start Scan)
                                8'hD9: state <= ST_IDLE; // EOI (End)
                                default: state <= ST_LENGTH_HI; // Các marker khác (APPn, COM...) -> Đọc len để skip
                            endcase
                        end
                    end

                    // --------------------------------------------------
                    // ĐỌC ĐỘ DÀI (LENGTH)
                    // --------------------------------------------------
                    ST_LENGTH_HI: begin
                        length_cnt[15:8] <= byte_in;
                        state <= ST_LENGTH_LO;
                    end

                    ST_LENGTH_LO: begin
                        length_cnt[7:0] <= byte_in;
                        // Length bao gồm cả 2 byte độ dài, nên trừ 2 để ra số byte data còn lại
                        // Tuy nhiên gán vào length_cnt ở chu kỳ sau sẽ là (Length - 2)
                        // Ta xử lý trừ ở logic chuyển trạng thái tiếp theo
                        
                        case (marker_type)
                            8'hC0: state <= ST_SOF_PREC;
                            8'hDB: state <= ST_DQT_INFO;
                            8'hC4: state <= ST_DHT_INFO;
                            8'hDA: state <= ST_SOS_SKIP; // Đọc header SOS xong thì start
                            default: state <= ST_SKIP_DATA;
                        endcase
                    end

                    // --------------------------------------------------
                    // SKIP DATA (APPn, COM...)
                    // --------------------------------------------------
                    ST_SKIP_DATA: begin
                        // length_cnt ở đây là giá trị thực tế byte in
                        // Cần logic trừ dần length_cnt
                        // Lưu ý: length_cnt đang chứa giá trị full (vd 16). 
                        // Ta đã đọc 2 byte length rồi.
                        // Logic đơn giản hóa:
                        if (length_cnt <= 3) state <= ST_IDLE; // 2 byte len + 1 byte đang đọc = 3
                        else length_cnt <= length_cnt - 1;
                    end

                    // --------------------------------------------------
                    // XỬ LÝ DQT (BẢNG LƯỢNG TỬ)
                    // --------------------------------------------------
                    ST_DQT_INFO: begin
                        // Byte này chứa: Precision (4 bit cao) và ID (4 bit thấp)
                        current_dqt_id <= byte_in[1:0]; // Chỉ lấy ID 0-3
                        dqt_idx <= 0;
                        length_cnt <= length_cnt - 1;
                        state <= ST_DQT_READ;
                    end

                    ST_DQT_READ: begin
                        qtable_mem[current_dqt_id][dqt_idx] <= byte_in;
                        length_cnt <= length_cnt - 1;
                        if (dqt_idx == 63) begin
                            // Đã đọc xong 64 byte của 1 bảng
                            if (length_cnt <= 3) state <= ST_IDLE; // Hết data
                            else state <= ST_DQT_INFO; // Có thể còn bảng tiếp theo trong cùng marker
                        end else begin
                            dqt_idx <= dqt_idx + 1;
                        end
                    end

                    // --------------------------------------------------
                    // XỬ LÝ SOF0 (START OF FRAME)
                    // --------------------------------------------------
                    ST_SOF_PREC: begin // Bỏ qua Precision (thường là 8)
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_H_HI;
                    end
                    ST_SOF_H_HI: begin
                        img_height[15:8] <= byte_in;
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_H_LO;
                    end
                    ST_SOF_H_LO: begin
                        img_height[7:0] <= byte_in;
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_W_HI;
                    end
                    ST_SOF_W_HI: begin
                        img_width[15:8] <= byte_in;
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_W_LO;
                    end
                    ST_SOF_W_LO: begin
                        img_width[7:0] <= byte_in;
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_COMP;
                    end
                    ST_SOF_COMP: begin
                        num_components <= byte_in[3:0];
                        comp_cnt <= 0;
                        length_cnt <= length_cnt - 1;
                        if (byte_in > 0) state <= ST_SOF_C_ID;
                        else state <= ST_SOF_SKIP;
                    end
                    ST_SOF_C_ID: begin
                        // Byte_in = Comp ID (1=Y, 2=Cb, 3=Cr OR 0,1,2 thường là 1,2,3)
                        // Ta map vào index 0,1,2 dựa vào comp_cnt
                        // current_comp_id <= byte_in; // Có thể lưu lại nếu cần
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_C_SAMP;
                    end
                    ST_SOF_C_SAMP: begin
                        // H (high 4), V (low 4)
                        comp_h_samp[comp_cnt] <= byte_in[7:4];
                        comp_v_samp[comp_cnt] <= byte_in[3:0];
                        length_cnt <= length_cnt - 1;
                        state <= ST_SOF_C_QT;
                    end
                    ST_SOF_C_QT: begin
                        comp_quant_id[comp_cnt] <= byte_in[1:0];
                        length_cnt <= length_cnt - 1;
                        comp_cnt <= comp_cnt + 1;
                        if (comp_cnt + 1 < num_components) state <= ST_SOF_C_ID;
                        else state <= ST_SOF_SKIP;
                    end
                    ST_SOF_SKIP: begin
                        if (length_cnt <= 3) state <= ST_IDLE;
                        else length_cnt <= length_cnt - 1;
                    end

                    // --------------------------------------------------
                    // XỬ LÝ DHT (HUFFMAN TABLE)
                    // --------------------------------------------------
                    ST_DHT_INFO: begin
                        // Byte này là Class/ID (VD: 00 cho DC0, 10 cho AC0)
                        // Để đơn giản cho decoder này, ta lưu thẳng vào mảng tuyến tính
                        // (Thực tế cần decode Class/ID để map đúng)
                        dht_len_idx <= 0;
                        total_syms <= 0;
                        length_cnt <= length_cnt - 1;
                        state <= ST_DHT_COUNTS;
                    end

                    ST_DHT_COUNTS: begin
                        // Đọc 16 byte đếm số lượng mã
                        dht_len_out[dht_len_idx] <= byte_in;
                        total_syms <= total_syms + byte_in;
                        length_cnt <= length_cnt - 1;
                        if (dht_len_idx == 15) begin
                            dht_val_cnt <= 0;
                            state <= ST_DHT_SYMBOLS;
                        end else begin
                            dht_len_idx <= dht_len_idx + 1;
                        end
                    end

                    ST_DHT_SYMBOLS: begin
                        // Đọc các symbol
                        dht_val_out[dht_val_cnt] <= byte_in;
                        dht_val_cnt <= dht_val_cnt + 1;
                        length_cnt <= length_cnt - 1;
                        // Kiểm tra xem đã đọc đủ symbol chưa hoặc hết marker chưa
                        if (length_cnt <= 3) begin
                            dhttable_loaded <= 1; // Báo hiệu đã có Huffman
                            state <= ST_IDLE;
                        end
                    end

                    // --------------------------------------------------
                    // XỬ LÝ SOS (START OF SCAN)
                    // --------------------------------------------------
                    ST_SOS_SKIP: begin
                        // SOS Header có vài byte (Scan select, Spectral selection...)
                        // Ta skip hết cho đến khi hết length
                        if (length_cnt <= 3) begin
                            start_scan <= 1; // Kích hoạt giải mã Entropy
                            parser_ready <= 0; // Parser ngừng nhận dữ liệu header
                            state <= ST_DONE;
                        end else begin
                            length_cnt <= length_cnt - 1;
                        end
                    end

                    ST_DONE: begin
                        // Ở trạng thái này mãi mãi cho đến reset
                        start_scan <= 1;
                    end
                    
                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

    // ==================================================================
    // 3. LOGIC OUTPUT: BẢNG LƯỢNG TỬ (FLATTEN)
    // ==================================================================
    // Đây là phần sửa lỗi Assertion của Iverilog.
    // Thay vì để Top module truy cập qtable_mem[][], ta đưa nó ra wire này.
    
    genvar k;
    generate
        for (k = 0; k < 64; k = k + 1) begin : flatten_q
            // Xuất bảng lượng tử ID 0 (Luma - Độ sáng)
            assign q_quant_table_flat[k*8 +: 8] = qtable_mem[0][k];
            // Xuất bảng lượng tử ID 1 (Chroma - Màu)
            assign q_quant_table_1_flat[k*8 +: 8] = qtable_mem[1][k];
        end
    endgenerate

endmodule