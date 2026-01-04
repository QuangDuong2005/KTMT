`timescale 1ns / 1ps

module tb_jpeg_debug;

    // =========================================================================
    // 1. KHAI BÁO TÍN HIỆU & BIẾN
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

    // File I/O
    integer file_log, img_file;
    integer idx, k;
    reg [7:0] file_rom [0:65535]; // Bộ nhớ input
    reg header_written;

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
    // 3. TẠO CLOCK & TASK GỬI DỮ LIỆU
    // =========================================================================
    always #10 clk = ~clk; // Chu kỳ 20ns

    task send_byte(input [7:0] data);
        begin
            integer timeout;
            timeout = 0;
            
            // Chờ hệ thống sẵn sàng (Flow Control)
            while (parser_ready == 0) begin
                @(posedge clk);
                timeout = timeout + 1;
                // Nếu chờ quá lâu (> 2000 chu kỳ) -> Báo lỗi Deadlock
                if (timeout > 2000) begin
                    $fdisplay(file_log, "\n[ERROR] %t: Hệ thống bị TREO (parser_ready=0 quá lâu)!", $time);
                    $display("❌ DEADLOCK DETECTED! Check log.");
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
    // 4. CHƯƠNG TRÌNH CHÍNH (MAIN)
    // =========================================================================
    initial begin
        // --- Cấu hình Waveform (FST cho nhẹ) ---
        $dumpfile("sim/wave_debug.fst");
        // Dump level 0 (tất cả mọi tín hiệu con) để debug kỹ
        $dumpvars(0, tb_jpeg_debug);

        // --- Mở file Log ---
        file_log = $fopen("sim/output_log.txt", "w");
        $fdisplay(file_log, "========== JPEG DECODER DEBUG TRACE ==========");

        // --- Mở file ảnh Output ---
        img_file = $fopen("sim/output_image.ppm", "w");
        
        // --- Nạp file Hex ---
        $readmemh("data/test.hex", file_rom);
        if (file_rom[0] === 8'bx) begin
            $display("❌ LỖI: Không tìm thấy file data/test.hex");
            $finish;
        end

        // --- Reset ---
        clk = 0; rst_n = 0; byte_in = 0; byte_valid = 0; header_written = 0;
        #100; rst_n = 1; #20;

        $display("--- [START] Bắt đầu nạp dữ liệu ---");
        $fdisplay(file_log, "[%t] System Reset Released", $time);

        // --- Vòng lặp gửi dữ liệu ---
        for (idx = 0; idx < 65536; idx = idx + 1) begin
            if (file_rom[idx] === 8'bx) begin
                $fdisplay(file_log, "[%t] Đã gửi hết file Input (%0d bytes)", $time, idx);
                idx = 65536; // Break
            end else begin
                send_byte(file_rom[idx]);
            end
        end

        // Chờ pipeline xả hết dữ liệu
        #50000; 
        
        $display("--- [DONE] Mô phỏng hoàn tất ---");
        $fclose(file_log);
        $fclose(img_file);
        $finish;
    end

    // =========================================================================
    // 5. CÁC ĐIỂM GIÁM SÁT (MONITOR POINTS) - DEBUG TỪNG PHẦN
    // =========================================================================

    // --- A. GIÁM SÁT HEADER PARSER ---
    always @(posedge uut.u_parser.start_scan) begin
        $display("📸 Đã tìm thấy SOS. Kích thước ảnh: %0d x %0d", uut.w_img_width, uut.w_img_height);
        $fdisplay(file_log, "\n--- [PARSER] SOS DETECTED ---");
        $fdisplay(file_log, "Image Size: %0d x %0d", uut.w_img_width, uut.w_img_height);
        
        // Ghi Header PPM tự động
        if (!header_written) begin
            $fwrite(img_file, "P3\n%0d %0d\n255\n", uut.w_img_width, uut.w_img_height);
            header_written <= 1;
        end
    end

    // --- B. GIÁM SÁT ENTROPY DECODER (Quan trọng nhất) ---
    // In ra từng hệ số DCT được giải mã
    always @(posedge clk) begin
        if (uut.u_entropy.coeff_valid) begin
            $fdisplay(file_log, "[ENTROPY] Valid Coeff: Idx=%0d, Val=%0d", 
                      uut.u_entropy.coeff_index, uut.u_entropy.coeff_value);
        end
        
        // Nếu gặp EOB (Block Done)
        if (uut.u_entropy.block_done) begin
            $fdisplay(file_log, "[ENTROPY] --- EOB (End of Block) ---");
        end
    end

    // --- C. GIÁM SÁT ACCUMULATOR (Block hoàn chỉnh) ---
    // Khi Accumulator gom đủ 64 số, in ra cả block để kiểm tra
    always @(posedge clk) begin
        if (uut.u_accum.block_valid) begin
            $fdisplay(file_log, "\n[ACCUM] >>> 8x8 BLOCK READY (Zigzag Order) <<<");
            for (k=0; k<64; k=k+1) begin
                // Cắt 12 bit từ vector phẳng
                $fwrite(file_log, "%6d ", $signed(uut.w_raw_block_flat[k*12 +: 12]));
                if ((k+1)%8 == 0) $fdisplay(file_log, "");
            end
            $fdisplay(file_log, "");
        end
    end

    // --- D. GIÁM SÁT IDCT OUTPUT (Giá trị Pixel thô) ---
    always @(posedge clk) begin
        if (uut.u_serializer.block_valid && uut.u_serializer.ready) begin
            $fdisplay(file_log, "\n[IDCT] >>> 8x8 PIXEL BLOCK OUTPUT <<<");
            for (k=0; k<64; k=k+1) begin
                $fwrite(file_log, "%4d ", uut.w_idct_out_array[k]);
                if ((k+1)%8 == 0) $fdisplay(file_log, "");
            end
            $fdisplay(file_log, "");
        end
    end

    // --- E. GIÁM SÁT FINAL PIXEL (RGB) ---
    integer px_cnt = 0;
    always @(posedge clk) begin
        if (rgb_valid) begin
            // Ghi vào file ảnh
            $fwrite(img_file, "%d %d %d\n", r_out, g_out, b_out);
            
            // Ghi vào log (Giới hạn 100 pixel đầu để đỡ lag)
            if (px_cnt < 100) begin
                $fdisplay(file_log, "[COLOR] Pixel #%0d: R=%d G=%d B=%d", px_cnt, r_out, g_out, b_out);
            end
            px_cnt = px_cnt + 1;
        end
    end

endmodule