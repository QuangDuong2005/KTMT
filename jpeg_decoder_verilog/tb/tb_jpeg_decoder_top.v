`timescale 1ns / 1ps

module tb_jpeg_decoder_top;

    // =========================================================================
    // 1. KHAI BÁO TÍN HIỆU
    // =========================================================================
    reg clk;
    reg rst_n;
    
    // Input Stream
    reg [7:0] byte_in;
    reg       byte_valid;
    wire      parser_ready;

    // Output Stream
    wire [7:0] r_out, g_out, b_out;
    wire       rgb_valid;

    // Biến hỗ trợ
    integer file_log, img_file;
    integer idx, k, m;
    reg [7:0] file_rom [0:65535]; 

    // =========================================================================
    // 2. KẾT NỐI TOP MODULE (DUT)
    // =========================================================================
    jpeg_decoder_top uut (
        .clk(clk),
        .rst_n(rst_n),
        .byte_in(byte_in),
        .byte_valid(byte_valid),
        .parser_ready(parser_ready),
        .r_out(r_out),
        .g_out(g_out),
        .b_out(b_out),
        .rgb_valid(rgb_valid)
    );

    // =========================================================================
    // 3. LOGIC CƠ BẢN (CLOCK, SEND DATA)
    // =========================================================================
    always #10 clk = ~clk;

    task send_byte(input [7:0] data);
        begin
            integer timeout;
            timeout = 0;
            while (parser_ready == 0) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 50000) begin
                    $display("❌ TIMEOUT: Parser bận quá lâu (kẹt tại %t)!", $time);
                    $finish;
                end
            end
            
            byte_in <= data;
            byte_valid <= 1;
            @(posedge clk);
            
            byte_valid <= 0;
            #1;
        end
    endtask

    // =========================================================================
    // 4. MAIN PROCESS
    // =========================================================================
    initial begin
        //$dumpfile("sim/wave_top.fst");
        //$dumpvars(0, tb_jpeg_decoder_top);

        // Mở file Log chi tiết
        file_log = $fopen("sim/output_log.txt", "w");
        $fdisplay(file_log, "===========================================");
        $fdisplay(file_log, "      JPEG DECODER - FULL DEBUG LOG        ");
        $fdisplay(file_log, "===========================================");

        // Mở file ảnh kết quả (.ppm)
        img_file = $fopen("sim/output_image.ppm", "w");
        $fwrite(img_file, "P3\n160 120\n255\n"); // Header giả định

        // Nạp file Hex
        $readmemh("data/test.hex", file_rom);
        if (file_rom[0] === 8'bx) begin
             $display("❌ LỖI: Không đọc được file data/test.hex");
             $finish;
        end

        // Reset
        clk = 0; rst_n = 0; byte_in = 0; byte_valid = 0;
        #100; rst_n = 1; #20;

        $display("--- [START] System Simulation ---");

        // Gửi dữ liệu
        for (idx = 0; idx < 65536; idx = idx + 1) begin
            if (file_rom[idx] === 8'bx) begin
                $display("-> End of Input File at index %d", idx);
                idx = 65536; 
            end else begin
                send_byte(file_rom[idx]);
            end
        end

        #50000; // Chờ xử lý nốt
        $display("--- [DONE] Simulation Finished ---");
        $fclose(file_log);
        $fclose(img_file);
        $finish;
    end

    // =========================================================================
    // 5. MONITOR & LOGGING (PHẦN QUAN TRỌNG NHẤT)
    // =========================================================================
    
    // --- A. Log Header Info & Tables (Từ module u_parser) ---
    // Sử dụng event control để bắt thời điểm nạp xong
    
    always @(posedge uut.u_parser.qtable_loaded) begin
        #1; // Delay để data ổn định
        $fdisplay(file_log, "\n[TIME %t] >>> DQT LOADED (ID: %d)", $time, uut.u_parser.qtable_id_loaded);
        for (k=0; k<64; k=k+1) begin
            $fwrite(file_log, "%02x ", uut.u_parser.qtable_mem[uut.u_parser.qtable_id_loaded][k]);
            if ((k+1)%8 == 0) $fdisplay(file_log, "");
        end
    end

    always @(posedge uut.u_parser.dhttable_loaded) begin
        #1;
        $fdisplay(file_log, "\n[TIME %t] >>> DHT LOADED (Class: %d, ID: %d)", 
                  $time, uut.u_parser.dht_table_class, uut.u_parser.dht_table_id);
        $fdisplay(file_log, "Total Symbols: %d", uut.u_parser.dht_sym_count);
        // In 32 symbol đầu tiên để kiểm tra
        for (k=0; k < uut.u_parser.dht_sym_count && k < 32; k=k+1) begin
             $fwrite(file_log, "%02x ", uut.u_parser.dht_sym_mem[{uut.u_parser.dht_table_class, uut.u_parser.dht_table_id[2:0]}][k]);
        end
        $fdisplay(file_log, "...");
    end

    always @(posedge uut.u_parser.start_scan) begin
        $fdisplay(file_log, "\n[TIME %t] >>> START OF SCAN (SOS)", $time);
        $fdisplay(file_log, "Image Size Detected: %d x %d", uut.w_img_width, uut.w_img_height);
    end

    // --- B. Log Kết quả Giải mã Entropy & Transform ---
    // Chúng ta bắt tín hiệu valid của Accumulator (khi gom đủ 64 coeff)
    
    always @(posedge clk) begin
        if (uut.u_accum.block_valid) begin
            $fdisplay(file_log, "\n[TIME %t] >>> BLOCK DECODED (Zigzag & Quantized)", $time);
            
            // In ra 64 hệ số (Raw từ Entropy, chưa Dequant)
            // Lưu ý: uut.w_raw_block_flat là dây 1 chiều, ta phải cắt bit để in
            for (k=0; k<64; k=k+1) begin
                // Cắt 12 bit từ vector phẳng
                $fwrite(file_log, "%d ", $signed(uut.w_raw_block_flat[k*12 +: 12])); 
                if ((k+1)%8 == 0) $fdisplay(file_log, "");
            end
        end
    end

    // --- C. Log Kết quả IDCT (Pixel Values) ---
    // Bắt tín hiệu valid đầu vào của Serializer (tức là đầu ra của IDCT)
    
    always @(posedge clk) begin
        if (uut.u_serializer.block_valid && uut.u_serializer.ready) begin
            $fdisplay(file_log, "\n[TIME %t] >>> IDCT OUTPUT (Pixel Block Y)", $time);
            
            // In 64 pixel (IDCT output)
            for (k=0; k<64; k=k+1) begin
                // Truy cập mảng w_idct_out_array trong Top module
                $fwrite(file_log, "%d ", uut.w_idct_out_array[k]);
                if ((k+1)%8 == 0) $fdisplay(file_log, "");
            end
        end
    end

    // --- D. Log Final RGB Pixel ---
    always @(posedge clk) begin
        if (rgb_valid) begin
            // Ghi ra file ảnh PPM
            $fwrite(img_file, "%d %d %d\n", r_out, g_out, b_out);
            
            // Ghi ra log (tùy chọn, coi chừng file log quá lớn)
            // Chỉ ghi 10 pixel đầu tiên để check
            if ($time < 500000) begin 
                $fdisplay(file_log, "[TIME %t] Pixel Out: R=%d G=%d B=%d", $time, r_out, g_out, b_out);
            end
        end
    end

endmodule
