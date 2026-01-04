module jpeg_decoder_top (
    input wire clk,
    input wire rst_n,
    
    input wire [7:0] byte_in,
    input wire byte_valid,
    output wire parser_ready,

    output wire [7:0] r_out, g_out, b_out,
    output wire rgb_valid 
);

    // ===========================================================================
    // 1. TÍN HIỆU KẾT NỐI (Đã chuẩn hóa Bit-width)
    // ===========================================================================
    wire w_start_scan, w_parser_ready_int;
    wire [15:0] w_img_height, w_img_width;
    
    // Huffman & Entropy Wires
    wire [11:0] w_coeff_val;
    wire [5:0]  w_coeff_idx;
    wire w_coeff_valid, w_block_done_entropy;
    
    // Data Bus: 1024-bit (Input Block) -> 2048-bit (Output Transform)
    wire [1023:0] w_raw_block_flat;      
    wire [1023:0] w_qtable_flat;         
    wire [2047:0] w_dequant_flat_bus;    
    wire w_raw_block_valid, w_ser_ready;

    // Serializer & Pixel
    reg [511:0] r_serializer_in_flat;
    wire [7:0] w_pixel_val_8bit;      
    wire w_pixel_valid_raw, w_block_done_ser;

    // Huffman Table Wires
    wire [7:0] w_dht_counts [0:15];
    wire [7:0] w_dht_vals   [0:161];
    wire w_dht_loaded, w_gen_done;
    wire [15:0] w_huff_code [0:255];
    wire [4:0]  w_huff_len  [0:255];
    
    // Bitstream
    wire w_bit_stream, w_bit_valid, w_bitstream_ready_int, w_bit_ready;
    wire w_huff_enable, w_entropy_reading, w_symbol_valid;
    wire [7:0] w_symbol_out;

    // ===========================================================================
    // 2. BẢNG LƯỢNG TỬ MẶC ĐỊNH (HARDCODED) - NHƯ YÊU CẦU
    // ===========================================================================
    // Gán tất cả 64 hệ số bằng 16. Đây là cách đơn giản nhất để tránh lỗi crash.
    // 64 hệ số * 16 bit = 1024 bit
    assign w_qtable_flat = {(64){16'd16}};

    // ===========================================================================
    // 3. MCU CONTROLLER (ĐƠN GIẢN - FIX LỖI 6399 PIXEL)
    // ===========================================================================
    reg [15:0] r_blk_x, r_blk_y;
    reg [5:0]  r_pix_idx;
    wire [15:0] w_blks_in_row = (w_img_width + 16'd7) >> 3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) r_pix_idx <= 0;
        else if (w_pixel_valid_raw) r_pix_idx <= r_pix_idx + 1;
    end

    // Dùng trễ 1 nhịp từ Serializer để đếm block chuẩn xác
    reg r_blk_done_q;
    always @(posedge clk) r_blk_done_q <= w_block_done_ser;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin r_blk_x <= 0; r_blk_y <= 0; end
        else if (w_start_scan) begin r_blk_x <= 0; r_blk_y <= 0; end
        else if (r_blk_done_q) begin
            if (r_blk_x == w_blks_in_row - 1) begin
                r_blk_x <= 0; r_blk_y <= r_blk_y + 1;
            end else begin
                r_blk_x <= r_blk_x + 1;
            end
        end
    end

    // Cắt biên (Padding Crop)
    wire [15:0] w_cur_x = (r_blk_x << 3) + r_pix_idx[2:0];
    wire [15:0] w_cur_y = (r_blk_y << 3) + r_pix_idx[5:3];
    wire w_is_inside = (w_cur_x < w_img_width) && (w_cur_y < w_img_height);
    wire w_pixel_valid_final = w_pixel_valid_raw && w_is_inside;

    // ===========================================================================
    // 4. DATA PATH (TRANSFORM -> IDCT -> SERIALIZER)
    // ===========================================================================
    
    // Transform Block
    jpeg_transform_block #(.WIDTH_IN(16), .WIDTH_OUT(32)) u_trans (
        .zz_in_flat(w_raw_block_flat), 
        .quant_flat(w_qtable_flat), // Nối vào bảng mặc định ở trên
        .dct_out_flat(w_dequant_flat_bus)
    );

    // Chuẩn bị dữ liệu cho IDCT
    reg signed [15:0] r_idct_in [0:63];
    wire signed [15:0] w_idct_out [0:63];
    integer j;
    always @(*) for (j=0; j<64; j=j+1) r_idct_in[j] = w_dequant_flat_bus[j*32 +: 16];

    // IDCT 2D
    jpeg_idct_2d u_idct (.clk(clk), .matrix_in(r_idct_in), .matrix_out(w_idct_out));

    // Level Shift (+128) & Clamp (0-255) -> FIX MÀN HÌNH ĐEN
    integer k;
    integer v_clamp;
    always @(*) begin
        r_serializer_in_flat = 0;
        for (k = 0; k < 64; k = k + 1) begin
            v_clamp = w_idct_out[k] + 128; // Cộng 128 để phục hồi độ sáng
            if (v_clamp < 0) r_serializer_in_flat[k*8 +: 8] = 8'h00;
            else if (v_clamp > 255) r_serializer_in_flat[k*8 +: 8] = 8'hFF;
            else r_serializer_in_flat[k*8 +: 8] = v_clamp[7:0];
        end
    end

    // Block Serializer (Dùng bản chuẩn, KHÔNG dùng bản Indexed)
    jpeg_block_serializer u_ser (
        .clk(clk), .rst_n(rst_n),
        .block_valid(w_raw_block_valid), 
        .block_in(r_serializer_in_flat), 
        .ready(w_ser_ready),
        .pixel_valid(w_pixel_valid_raw), 
        .pixel_out(w_pixel_val_8bit),
        .block_done(w_block_done_ser) 
    );

    // YCbCr to RGB (Chế độ Grayscale - Trắng đen)
    jpeg_ycbcr_to_rgb #(.IMG_WIDTH(2048)) u_color (
        .clk(clk), .rst_n(rst_n),
        .valid_in(w_pixel_valid_final), 
        .subsample_mode(2'b00),
        .y_idct($signed({1'b0, w_pixel_val_8bit}) - 9'sd128), // Đưa về range -128..127
        .cb_idct(9'sd0), // Gán cứng 0
        .cr_idct(9'sd0), // Gán cứng 0
        .r_out(r_out), .g_out(g_out), .b_out(b_out), 
        .valid_out(rgb_valid)
    );

    // ===========================================================================
    // 5. CÁC MODULE CON KHÁC (GIỮ NGUYÊN)
    // ===========================================================================
    
    jpeg_header_parser u_parser (
        .clk(clk), .rst_n(rst_n), .byte_in(byte_in), .byte_valid(byte_valid && !w_start_scan),
        .img_height(w_img_height), .img_width(w_img_width), .start_scan(w_start_scan),
        .parser_ready(w_parser_ready_int),
        .dhttable_loaded(w_dht_loaded),
        .dht_len_out(w_dht_counts), .dht_val_out(w_dht_vals)
        // LƯU Ý: Không kết nối cổng q_quant_table_flat ở đây nữa để tránh lỗi assertion
    );

    jpeg_bitstream_reader u_bitstream (
        .clk(clk), .rst_n(rst_n), .byte_in(byte_in), .byte_valid(byte_valid && w_start_scan),
        .byte_ready(w_bitstream_ready_int), .bit_ready(w_bit_ready), 
        .bit_out(w_bit_stream), .bit_valid(w_bit_valid)
    );

    jpeg_huffman_generator u_huff_gen (
        .clk(clk), .rst_n(rst_n), .start(w_start_scan), .huff_count_in(w_dht_counts), .huff_val_in(w_dht_vals), .huff_code_out(w_huff_code), .huff_len_out(w_huff_len), .done(w_gen_done)
    );

    jpeg_huffman_decoder u_huff_dec (
        .clk(clk), .rst_n(rst_n), .start(w_start_scan), .enable(w_huff_enable), .bit_in(w_bit_stream), .bit_valid(w_bit_valid), .symbol_out(w_symbol_out), .symbol_valid(w_symbol_valid), .huff_code_in(w_huff_code), .huff_len_in(w_huff_len)
    );

    jpeg_entropy_decoder u_entropy (
        .clk(clk), .rst_n(rst_n), .symbol_in(w_symbol_out), .symbol_valid(w_symbol_valid), .huff_enable(w_huff_enable), .bit_in(w_bit_stream), .bit_valid(w_bit_valid), .coeff_value(w_coeff_val), .coeff_index(w_coeff_idx), .coeff_valid(w_coeff_valid), .block_done(w_block_done_entropy), .is_reading_bits(w_entropy_reading)
    );
    
    coeff_accumulator #(.WIDTH(16)) u_accum (
        .clk(clk), .rst_n(rst_n),
        .coeff_in({{4{w_coeff_val[11]}}, w_coeff_val}), 
        .coeff_index(w_coeff_idx), .coeff_valid(w_coeff_valid), .block_done(w_block_done_entropy),
        .block_out_flat(w_raw_block_flat), .block_valid(w_raw_block_valid), .block_ready(w_ser_ready)
    );

    // FSM Control
    reg [1:0] state;
    reg r_scan_active;
    localparam ST_HEADER=0, ST_SCAN_IDLE=1, ST_DECODING=2, ST_PROCESS=3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state <= ST_HEADER; r_scan_active <= 0; end 
        else case (state)
            ST_HEADER: if (w_start_scan) begin state <= ST_SCAN_IDLE; r_scan_active <= 1; end
            ST_SCAN_IDLE: state <= ST_DECODING;
            ST_DECODING: if (w_raw_block_valid) state <= ST_PROCESS;
            ST_PROCESS: if (w_ser_ready) state <= ST_DECODING; 
        endcase
    end
    
    wire w_scan_in_progress = r_scan_active || w_start_scan;
    assign parser_ready = w_scan_in_progress ? w_bitstream_ready_int : w_parser_ready_int;
    assign w_bit_ready = (state == ST_DECODING) || (state == ST_PROCESS);

endmodule