`timescale 1ns / 1ps 
 
module jpeg_decoder_top ( 
    input wire clk, input wire rst_n, 
    input wire [7:0] byte_in, input wire byte_valid, output wire byte_ready, 
    output wire [7:0] r_out, output wire [7:0] g_out, output wire [7:0] b_out, 
    output wire pixel_valid, 
    output wire [15:0] img_width, output wire [15:0] img_height, output wire idle 
); 
 
    // Signals 
    wire parser_ready, dhttable_loaded, start_scan; 
    wire [3:0] num_components; 
    wire acc_ready_for_input;
     
    // Huffman Tables Signals 
    wire [7:0] dc0_len[0:15], dc0_val[0:161]; 
    wire [7:0] dc1_len[0:15], dc1_val[0:161]; 
    wire [7:0] ac0_len[0:15], ac0_val[0:161]; 
    wire [7:0] ac1_len[0:15], ac1_val[0:161]; 
 
    // Generated Codes 
    wire [15:0] code_dc0[0:255], code_dc1[0:255], code_ac0[0:255], code_ac1[0:255]; 
    wire [4:0] len_dc0[0:255], len_dc1[0:255], len_ac0[0:255], len_ac1[0:255]; 
    wire d0_done, d1_done, a0_done, a1_done; 
 
    // Component & Quantization 
    wire [511:0] q_table_0, q_table_1; 
    wire [2:0] comp_h[0:2], comp_v[0:2]; 
    wire [1:0] comp_q_id[0:2]; 
 
    // Internal Control 
    wire bs_byte_ready, bit_out, bit_valid, bit_ready; 
    wire enable_dc, enable_ac, is_reading_bits; 
    wire coeff_valid, blk_done; 
    wire [5:0] coeff_idx; wire signed [11:0] coeff_val; 
    wire [1023:0] blk_flat; wire blk_valid, blk_ready; 
    wire signed [1023:0] dct_flat; 
    reg signed [15:0] idct_in[0:63]; wire signed [15:0] idct_out[0:63]; 
    wire mcu_ready; 
     
    // --- SỬA ĐỔI: Tín hiệu mới --- 
    wire image_complete;  
 
    // MUX Input 
    wire parser_active = byte_valid && !start_scan; 
    wire bs_active = byte_valid && start_scan; 
    assign byte_ready = (!start_scan) ? parser_ready : bs_byte_ready; 
    assign bit_ready = (enable_dc || enable_ac || is_reading_bits) 
                       && !image_complete 
                       && acc_ready_for_input;
 
    // 1. PARSER 
    jpeg_header_parser u_parser ( 
        .clk(clk), .rst_n(rst_n), 
        .byte_in(byte_in), .byte_valid(parser_active), .parser_ready(parser_ready), 
        .img_height(img_height), .img_width(img_width), .num_components(num_components), 
        .dhttable_loaded(dhttable_loaded), .start_scan(start_scan), 
        .dc0_len_out(dc0_len), .dc0_val_out(dc0_val), 
        .dc1_len_out(dc1_len), .dc1_val_out(dc1_val), 
        .ac0_len_out(ac0_len), .ac0_val_out(ac0_val), 
        .ac1_len_out(ac1_len), .ac1_val_out(ac1_val), 
        .q_quant_table_flat(q_table_0), .q_quant_table_1_flat(q_table_1), 
        .comp_h_samp(comp_h), .comp_v_samp(comp_v), .comp_quant_id(comp_q_id) 
    ); 
 
    // 2. GENERATORS
    // SỬA LỖI: Đổi trigger từ 'dhttable_loaded' thành 'start_scan'
    // Để đảm bảo tất cả dữ liệu DHT đã được parser đọc xong trước khi generator chạy.
    
    jpeg_huffman_generator g_dc0 (
        .clk(clk), .rst_n(rst_n), 
        .start(start_scan),           // <--- SỬA Ở ĐÂY (Cũ: dhttable_loaded)
        .huff_count_in(dc0_len), .huff_val_in(dc0_val), 
        .huff_code_out(code_dc0), .huff_len_out(len_dc0), 
        .done(d0_done)
    );

    jpeg_huffman_generator g_dc1 (
        .clk(clk), .rst_n(rst_n), 
        .start(start_scan),           // <--- SỬA Ở ĐÂY
        .huff_count_in(dc1_len), .huff_val_in(dc1_val), 
        .huff_code_out(code_dc1), .huff_len_out(len_dc1), 
        .done(d1_done)
    );

    jpeg_huffman_generator g_ac0 (
        .clk(clk), .rst_n(rst_n), 
        .start(start_scan),           // <--- SỬA Ở ĐÂY
        .huff_count_in(ac0_len), .huff_val_in(ac0_val), 
        .huff_code_out(code_ac0), .huff_len_out(len_ac0), 
        .done(a0_done)
    );

    jpeg_huffman_generator g_ac1 (
        .clk(clk), .rst_n(rst_n), 
        .start(start_scan),           // <--- SỬA Ở ĐÂY
        .huff_count_in(ac1_len), .huff_val_in(ac1_val), 
        .huff_code_out(code_ac1), .huff_len_out(len_ac1), 
        .done(a1_done)
    );
 
    // 3. READER 
    jpeg_bitstream_reader u_bs (.clk(clk), .rst_n(rst_n), .byte_in(byte_in), .byte_valid(bs_active), 
.byte_ready(bs_byte_ready), .bit_out(bit_out), .bit_valid(bit_valid), .bit_ready(bit_ready)); 
 
    // 4. LOGIC CHỌN BẢNG (Giữ nguyên logic is_420) 
    // Detect mode: 2x2 subsampling = 4:2:0 
    wire is_420 = (comp_h[0] == 2 && comp_v[0] == 2); 
     
    // Logic đếm blk_cnt cũng cần sửa để đồng bộ, nhưng ta sẽ dùng logic trong Entropy Decoder đã sửa. 
    // Ở đây chỉ cần logic chọn bảng Huffman (Table 0 cho Y, Table 1 cho Cb/Cr) 
    // Logic use_tb1 ở đây chỉ phụ thuộc vào số block đã xử lý CỦA RIÊNG MẠCH DECODER (mạch này nằm trong top, không nằm trong mcu_manager) 
    // Để đơn giản, ta giữ nguyên logic đếm blk_cnt cục bộ ở đây phục vụ việc MUX Huffman Table 
    reg [2:0] blk_cnt_mux; 
    wire [2:0] max_blk_mux = is_420 ? 5 : 2; 
    always @(posedge clk or negedge rst_n) begin 
        if(!rst_n) blk_cnt_mux <= 0; 
        else if(blk_done) begin 
            if(blk_cnt_mux == max_blk_mux) blk_cnt_mux <= 0;  
            else blk_cnt_mux <= blk_cnt_mux + 1; 
        end 
    end 
    wire use_tb1 = is_420 ? (blk_cnt_mux >= 4) : (blk_cnt_mux >= 1); 
 
    wire all_gen_done = d0_done && d1_done && a0_done && a1_done; 
    wire en_dc0 = enable_dc && !use_tb1; 
    wire en_dc1 = enable_dc && use_tb1; 
    wire en_ac0 = enable_ac && !use_tb1; 
    wire en_ac1 = enable_ac && use_tb1; 
     

    // 5. ENTROPY DECODER (Integrated)
    
    // Config Bit Ready
    assign bit_ready = is_reading_bits && !image_complete; 

    jpeg_entropy_decoder u_ent ( 
        .clk(clk), .rst_n(rst_n), 
        
        // Huffman Tables
        .dc0_code(code_dc0), .dc0_len(len_dc0),
        .dc1_code(code_dc1), .dc1_len(len_dc1),
        .ac0_code(code_ac0), .ac0_len(len_ac0),
        .ac1_code(code_ac1), .ac1_len(len_ac1),
        
        // Bitstream
        .bit_in(bit_out), .bit_valid(bit_valid), 
        .is_reading_bits(is_reading_bits),
        
        // Output
        .coeff_valid(coeff_valid), .coeff_index(coeff_idx), .coeff_value(coeff_val), 
        .block_done(blk_done), 
        .output_ready(acc_ready_for_input),
        
        // Config
        .is_420(is_420)  
    ); 

 
    coeff_accumulator #(.WIDTH(16)) u_acc (
        .clk(clk), 
        .rst_n(rst_n), 
        .coeff_in({{4{coeff_val[11]}}, coeff_val}), 
        .coeff_index(coeff_idx), 
        .coeff_valid(coeff_valid), 
        .block_done(blk_done), 
        .block_out_flat(blk_flat), 
        .block_valid(blk_valid), 
        .block_ready(blk_ready),
        // Nối dây mới
        .acc_ready_for_input(acc_ready_for_input) 
    );
 
    // MUX Quantization 
    wire [511:0] sel_q = use_tb1 ? q_table_1 : q_table_0; 
    
    // FIX: Latch Q-Table when block is done to align with u_acc output buffer
    reg [511:0] q_table_latched;
    always @(posedge clk) begin
        if (blk_done) q_table_latched <= sel_q;
    end

    wire [1023:0] q_16; 
    genvar i; 
    generate for(i=0; i<64; i=i+1) assign q_16[i*16 +: 16] = {8'h00, q_table_latched[i*8 +: 8]}; endgenerate 
 
    jpeg_transform_block #(.WIDTH_IN(16), .WIDTH_OUT(16)) u_trans (.zz_in_flat(blk_flat), 
.quant_flat(q_16), .dct_out_flat(dct_flat)); 
 
    generate for(i=0; i<64; i=i+1) always @(*) idct_in[i] = dct_flat[(i+1)*16-1 : i*16]; 
endgenerate 
    jpeg_idct_2d u_idct (.clk(clk), .matrix_in(idct_in), .matrix_out(idct_out)); 
 
    assign blk_ready = mcu_ready; 

    
 
    mcu_manager u_mcu ( 
        .clk(clk), .rst_n(rst_n),  
        .block_in(idct_out), .block_valid(blk_valid), 
        .comp_h_samp(comp_h), .comp_v_samp(comp_v),  
        .r_out(r_out), .g_out(g_out), .b_out(b_out),  
        .pixel_valid(pixel_valid), .ready(mcu_ready), 
        // --- SỬA ĐỔI: Thêm kết nối --- 
        .img_width(img_width), 
        .img_height(img_height), 
        .image_complete(image_complete) 
    ); 
 
    // --- SỬA ĐỔI: Logic IDLE --- 
    // Idle = Chưa start scan HOẶC Đã xong ảnh 
    assign idle = !start_scan || image_complete; 
 
endmodule