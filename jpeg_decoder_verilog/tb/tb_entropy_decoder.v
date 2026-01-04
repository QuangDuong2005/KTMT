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
    integer idx;
    
    // Bộ nhớ đệm 512KB (Kệ warning "Not enough words", nó chỉ báo là file hex nhỏ hơn 512KB thôi)
    reg [7:0] file_rom [0:524287]; 

    // Biến quản lý trạng thái
    reg header_written;
    integer pixel_cnt;      // Đếm số pixel đã nhận thực tế
    integer total_pixels;   // Tổng số pixel dự kiến (Width * Height)
    integer timeout_cnt;    // Bộ đếm an toàn

    // =========================================================================
    // 2. KẾT NỐI DUT
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
    // 3. CLOCK & TASK
    // =========================================================================
    always #10 clk = ~clk; // 50MHz

    task send_byte(input [7:0] data);
        begin
            integer wait_time;
            wait_time = 0;
            // Chờ Parser sẵn sàng
            while (parser_ready == 0) begin
                @(posedge clk);
                wait_time = wait_time + 1;
                if (wait_time > 1000000) begin 
                    $display("❌ TIMEOUT: Parser bị treo khi gửi byte %h", data);
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
        // Khởi tạo
        header_written = 0;
        pixel_cnt = 0;
        total_pixels = 0; // Mặc định là 0, sẽ update khi đọc được Header
        timeout_cnt = 0;

        // Mở file Log
        file_log = $fopen("sim/output_log.txt", "w");
        $fdisplay(file_log, "===========================================");
        $fdisplay(file_log, "      JPEG DECODER - FULL DEBUG LOG        ");
        $fdisplay(file_log, "===========================================");

        // Mở file Ảnh PPM
        img_file = $fopen("sim/output_image.ppm", "w");

        // Load HEX
        $readmemh("data/test.hex", file_rom);
        // Kiểm tra byte đầu tiên
        if (file_rom[0] === 8'bx) begin
             $display("❌ LỖI: File hex rỗng hoặc không đọc được!");
             $finish;
        end

        // Reset
        clk = 0; rst_n = 0; byte_in = 0; byte_valid = 0;
        #100; rst_n = 1; #20;

        $display("--- [START] System Simulation (Smart Wait Mode) ---");

        // --- GIAI ĐOẠN 1: Gửi dữ liệu ảnh ---
        for (idx = 0; idx < 524288; idx = idx + 1) begin
            if (file_rom[idx] === 8'bx) begin
                $display("-> Đã gửi hết file input tại index %d", idx);
                idx = 524288; // Thoát vòng lặp
            end else begin
                send_byte(file_rom[idx]);
            end
        end

        // --- GIAI ĐOẠN 2: Flush Pipeline ---
        // Gửi byte 0x00 để đẩy các bit cuối cùng ra
        $display("-> Đang gửi Dummy Bytes (0x00) để đẩy dữ liệu...");
        repeat(200) @(posedge clk) send_byte(8'h00); 

        // --- GIAI ĐOẠN 3: Chờ kết quả (QUAN TRỌNG NHẤT) ---
        // Vòng lặp này sẽ giữ cho mô phỏng chạy cho đến khi đủ pixel
        
        $display("-> *** BẮT ĐẦU CHỜ GIẢI MÃ... ***");
        
        // Điều kiện lặp: 
        // 1. Chưa biết tổng số pixel (total_pixels == 0)
        // 2. HOẶC Số pixel đã nhận (pixel_cnt) vẫn nhỏ hơn tổng số
        // 3. VÀ Chưa hết thời gian chờ tối đa (20 triệu clock)
        while ((total_pixels == 0 || pixel_cnt < total_pixels) && timeout_cnt < 20000000) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
            
            // Cập nhật total_pixels ngay khi Header được parser đọc xong
            if (total_pixels == 0 && uut.w_img_width > 0 && uut.w_img_height > 0) begin
                 total_pixels = uut.w_img_width * uut.w_img_height;
                 $display("   [INFO] Đã xác định mục tiêu: Cần giải mã %0d pixels", total_pixels);
            end
            
            // In tiến độ mỗi 500,000 chu kỳ để bạn biết nó không bị treo
            if (timeout_cnt % 500000 == 0) begin
                $display("   ... Đang chạy: Đã nhận %0d / %0d pixels (Time: %0d)", pixel_cnt, total_pixels, timeout_cnt);
            end
        end

        // Kiểm tra kết quả
        if (pixel_cnt >= total_pixels && total_pixels > 0) begin
             $display("✅ THÀNH CÔNG: Đã giải mã đủ %0d pixels.", pixel_cnt);
        end else begin
             $display("⚠️ CẢNH BÁO: Dừng do hết thời gian! Mới được %0d / %0d pixels.", pixel_cnt, total_pixels);
             $display("   (Có thể do bộ giải mã bị kẹt hoặc clock không cấp đủ)");
        end
        
        $display("--- [DONE] Simulation Finished ---");
        $fclose(file_log);
        $fclose(img_file);
        $finish;
    end

    // =========================================================================
    // 5. MONITOR & GHI FILE
    // =========================================================================
    
    // A. Tự động ghi Header PPM
    always @(posedge clk) begin
        if (uut.u_parser.start_scan && !header_written) begin
            // Ghi Header P3 width height 255
            $fwrite(img_file, "P3\n%0d %0d\n255\n", uut.w_img_width, uut.w_img_height);
            header_written <= 1;
        end
    end

    // B. Đếm & Ghi Pixel
    always @(posedge clk) begin
        if (rgb_valid) begin
            // Tăng biến đếm (cực kỳ quan trọng cho vòng lặp while ở trên)
            pixel_cnt <= pixel_cnt + 1;
            
            if (header_written) begin
                $fwrite(img_file, "%d %d %d\n", r_out, g_out, b_out);
            end
        end
    end

    // C. Log phụ (Debug)
    always @(posedge uut.u_parser.start_scan) begin
        $fdisplay(file_log, "\n[TIME %t] >>> START OF SCAN (SOS)", $time);
    end

endmodule