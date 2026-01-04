module jpeg_decoder_top (
    input wire clk,
    input wire rst_n,
    
    // Input Stream
    input wire [7:0] byte_in,
    input wire byte_valid,
    output wire parser_ready,

    // Output Stream
    output wire [7:0] r_out, g_out, b_out,
    output wire rgb_valid
);

    // ===========================================================================
    // 1. KẾT NỐI TÍN HIỆU
    // ===========================================================================
    
    // Parser Signals
    wire w_start_scan;
    wire w_parser_ready_internal;
    wire [15:0] w_img_height, w_img_width;
    wire w_dht_loaded;

    // Bitstream Signals
    wire w_bit_stream;
    wire w_bit_valid;
    wire w_bitstream_ready_internal;
    wire w_bit_ready; // Tín hiệu này cực kỳ quan trọng để tránh deadlock

    // Entropy & Huffman Signals
    wire w_huff_enable;
    wire w_entropy_reading; // Entropy đang cần bit
    wire [7:0] w_symbol_out;
    wire w_symbol_valid;

    // Data Path Signals
    wire signed [11:0] w_coeff_val;
    wire [5:0] w_coeff_idx;
    wire w_coeff_valid;
    wire w_block_done;      // Entropy báo xong 1 block 8x8
    
    // Block Handling
    wire signed [12*64-1:0] w_raw_block_flat;
    wire w_raw_block_valid; // Accumulator báo có block
    wire w_accum_ready;     // Accumulator sẵn sàng nhận coeff mới

    // Transform & IDCT
    wire signed [32*64-1:0] w_dequant_out_flat;
    reg signed [15:0] r_idct_in_array [0:63];
    wire signed [15:0] w_idct_out_array [0:63];

    // Serializer & Output
    reg [511:0] r_serializer_in_flat;
    wire w_serializer_ready; // Serializer báo đã đẩy hết pixel cũ
    wire signed [8:0] w_pixel_val;
    wire w_pixel_valid;

    // ===========================================================================
    // 2. FSM ĐIỀU KHIỂN CHÍNH (MAIN CONTROLLER) - QUAN TRỌNG
    // ===========================================================================
    // Thay vì bypass ngây thơ, ta dùng máy trạng thái để quản lý từng giai đoạn
    
    localparam ST_HEADER    = 2'd0;
    localparam ST_SCAN_IDLE = 2'd1; // Chờ data, hệ thống nghỉ
    localparam ST_DECODING  = 2'd2; // Đang giải mã Huffman/Entropy
    localparam ST_PROCESS   = 2'd3; // Đang tính IDCT/Serialize
    
    reg [1:0] state;
    reg r_scan_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_HEADER;
            r_scan_active <= 0;
        end else begin
            case (state)
                ST_HEADER: begin
                    if (w_start_scan) begin
                        state <= ST_SCAN_IDLE;
                        r_scan_active <= 1;
                    end
                end
                
                ST_SCAN_IDLE: begin
                    // Ở đây ta đơn giản hóa: Nếu đang Scan, cứ cho phép decode
                    state <= ST_DECODING;
                end

                ST_DECODING: begin
                    // Trạng thái này cho phép Entropy chạy
                    // Nếu Accumulator đã đầy (w_raw_block_valid), ta chuyển sang xử lý
                    if (w_raw_block_valid) begin
                         state <= ST_PROCESS;
                    end
                end

                ST_PROCESS: begin
                    // Chờ Serializer xử lý xong block hiện tại
                    // Khi Serializer ready trở lại, nghĩa là block cũ đã xong
                    if (w_serializer_ready) begin
                        state <= ST_DECODING; // Quay lại giải mã block tiếp theo
                    end
                end
            endcase
        end
    end

    // ===========================================================================
    // 3. LOGIC DEADLOCK FIX
    // ===========================================================================
    
    // Mux Parser/Bitstream Ready
    assign parser_ready = r_scan_active ? w_bitstream_ready_internal : w_parser_ready_internal;

    // Valid Demux
    wire w_valid_to_parser    = byte_valid && !r_scan_active;
    wire w_valid_to_bitstream = byte_valid && r_scan_active;

    // FIX DEADLOCK 1: Bitstream Ready Logic
    // Bitstream được phép bắn bit nếu:
    // 1. Huffman đang enable (cần bit để dò mã)
    // 2. HOẶC Entropy đang đọc bit (để lấy giá trị biên độ)
    // 3. QUAN TRỌNG: Accumulator phải sẵn sàng! Nếu Accumulator đang đầy (chờ IDCT), 
    //    ta phải PAUSE toàn bộ chuỗi decode phía trước để tránh overwrite dữ liệu.
    
    assign w_bit_ready = (w_huff_enable || w_entropy_reading) && (state == ST_DECODING);

    // ===========================================================================
    // 4. MODULE INSTANTIATION (Đã sửa lại kết nối)
    // ===========================================================================

    // --- Header Parser (Giữ nguyên) ---
    jpeg_header_parser u_parser (
        .clk(clk), .rst_n(rst_n),
        .byte_in(byte_in),
        .byte_valid(w_valid_to_parser),
        .parser_ready(w_parser_ready_internal),
        .img_height(w_img_height), .img_width(w_img_width),
        .dhttable_loaded(w_dht_loaded),
        .start_scan(w_start_scan)
    );

    // --- Bitstream Reader (Giữ nguyên logic cũ, chỉ đổi kết nối) ---
    jpeg_bitstream_reader u_bitstream (
        .clk(clk), .rst_n(rst_n),
        .byte_in(byte_in),
        .byte_valid(w_valid_to_bitstream),
        .byte_ready(w_bitstream_ready_internal),
        .bit_ready(w_bit_ready), // <--- Logic mới điều khiển ở đây
        .bit_out(w_bit_stream),
        .bit_valid(w_bit_valid)
    );

    // --- Huffman & Entropy (Giữ nguyên logic cũ) ---
    // Lưu ý: Huffman Decoder của bạn cần latency thấp hoặc input buffer nếu không muốn bị miss symbol
    jpeg_huffman_decoder u_huff_dec (
        .clk(clk), .rst_n(rst_n),
        .start(w_dht_loaded),
        .enable(w_huff_enable),
        .bit_in(w_bit_stream),
        .bit_valid(w_bit_valid),
        .symbol_out(w_symbol_out),
        .symbol_valid(w_symbol_valid)
    );

    jpeg_entropy_decoder u_entropy (
        .clk(clk), .rst_n(rst_n),
        .symbol_in(w_symbol_out),
        .symbol_valid(w_symbol_valid),
        .huff_enable(w_huff_enable),
        .bit_in(w_bit_stream),
        .bit_valid(w_bit_valid),
        .coeff_value(w_coeff_val),
        .coeff_index(w_coeff_idx),
        .coeff_valid(w_coeff_valid),
        .block_done(w_block_done),
        .is_reading_bits(w_entropy_reading)
    );

    // --- Accumulator (SỬA LỚN: Thêm Handshake) ---
    coeff_accumulator #(.WIDTH(12)) u_accum (
        .clk(clk), .rst_n(rst_n),
        .coeff_in(w_coeff_val),
        .coeff_index(w_coeff_idx),
        .coeff_valid(w_coeff_valid),
        .block_done(w_block_done),
        // Output
        .block_out_flat(w_raw_block_flat),
        .block_valid(w_raw_block_valid),
        .block_ready(w_serializer_ready) // Kết nối trực tiếp với độ sẵn sàng của Serializer
    );

    // --- Transform Logic (Combinational) ---
    wire signed [12*64-1:0] w_quant_table_flat;
    // FIX BUG: Quant Table không thể là toàn 1. Nó phải là giá trị thực tế.
    // Tạm thời hardcode một bảng Quant "phẳng" mức trung bình để test màu
    // Ví dụ: set tất cả là 16 (shift 4)
    assign w_quant_table_flat = {(64){12'd16}}; 

    jpeg_transform_block #(.WIDTH_IN(12), .WIDTH_OUT(32)) u_transform (
        .zz_in_flat(w_raw_block_flat),
        .quant_flat(w_quant_table_flat),
        .dct_out_flat(w_dequant_out_flat)
    );

    // Chuyển Flat vector sang Array cho IDCT module
    integer i_ad;
    always @(*) begin
        for (i_ad = 0; i_ad < 64; i_ad = i_ad + 1) begin
            r_idct_in_array[i_ad] = w_dequant_out_flat[(i_ad*32) +: 16];
        end
    end

    // --- IDCT 2D (Combinational - Rất nặng nhưng tạm chấp nhận) ---
    jpeg_idct_2d u_idct (
        .clk(clk),
        .matrix_in(r_idct_in_array),
        .matrix_out(w_idct_out_array)
    );

    // --- Serializer & Level Shift Logic ---
    // Phần này thực hiện Level Shift (+128) VÀ Clipping (0-255)
    integer j_ad;
    integer val_shift;
    
    always @(*) begin
        r_serializer_in_flat = 0;
        for (j_ad = 0; j_ad < 64; j_ad = j_ad + 1) begin
            // 1. Level Shift: JPEG IDCT ra kết quả centered tại 0, cần +128 để ra 0..255
            val_shift = w_idct_out_array[j_ad] + 128; 
            
            // 2. Clipping/Saturation
            if (val_shift < 0) 
                r_serializer_in_flat[(j_ad*8) +: 8] = 8'd0;
            else if (val_shift > 255) 
                r_serializer_in_flat[(j_ad*8) +: 8] = 8'd255;
            else 
                r_serializer_in_flat[(j_ad*8) +: 8] = val_shift[7:0];
        end
    end

    jpeg_block_serializer u_serializer (
        .clk(clk), .rst_n(rst_n),
        .block_valid(w_raw_block_valid), // Chỉ nhận block khi Accumulator bắn valid
        .block_in(r_serializer_in_flat),
        .ready(w_serializer_ready),      // Báo ngược lại Accumulator
        .pixel_valid(w_pixel_valid),
        .pixel_out(w_pixel_val)
    );

    // --- Color Reconstruction (Grayscale Mode) ---
    // Tạm thời fix Y-only để debug
    jpeg_ycbcr_to_rgb #(.IMG_WIDTH(2048)) u_color (
        .clk(clk), .rst_n(rst_n),
        .valid_in(w_pixel_valid),
        .subsample_mode(2'b00),
        
        // Pixel ra từ Serializer đã là 0-255 (Unsigned).
        // Nhưng module u_color của bạn lại trừ đi 128 bên trong (xem file cũ).
        // ĐỂ AN TOÀN: Ta đưa vào giá trị đã trừ 128 để module color cộng lại.
        // Hoặc sửa module color. Ở đây tôi chọn đưa vào Y dạng signed 9-bit centered at 0.
        // NHƯNG, pixel_val từ serializer là 0..255 (đã +128).
        // Nên input vào đây là: w_pixel_val - 128.
        
        .y_idct(w_pixel_val - 9'sd128), 
        .cb_idct(9'sd0), // Kênh màu = 0 (Trắng đen)
        .cr_idct(9'sd0), // Kênh màu = 0 (Trắng đen)
        
        .r_out(r_out), .g_out(g_out), .b_out(b_out),
        .valid_out(rgb_valid)
    );

endmodule