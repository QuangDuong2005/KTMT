`timescale 1ns / 1ps

// ============================================================================
// MODULE: tb_jpeg_decoder_top
// MÔ TẢ:
//  - Testbench kiểm tra toàn bộ hệ thống giải mã JPEG.
//  - Chức năng:
//    1. Tạo xung Clock và Reset.
//    2. Đọc file hex ảnh JPEG (test.hex).
//    3. Cấp dữ liệu byte-by-byte cho bộ giải mã (DUT).
//    4. Thu thập pixel đầu ra và ghi vào file ảnh (output_image.ppm).
//    5. [MỚI] Tự động in bảng DQT và DHT ra màn hình console để kiểm tra Header.
// ============================================================================

module tb_jpeg_decoder_top;

    // ============================================================
    // 1. CÁC THAM SỐ VÀ TÍN HIỆU (PARAMETERS & SIGNALS)
    // ============================================================
    parameter CLK_PERIOD      = 10;                 // Chu kỳ clock (10ns = 100MHz)
    parameter INPUT_HEX_FILE  = "test.hex";         // File đầu vào chứa dữ liệu ảnh hex
    parameter OUTPUT_PPM_FILE = "output_image.ppm"; // File ảnh kết quả (định dạng PPM)
    parameter MAX_IMG_SIZE    = 65536;              // Kích thước tối đa bộ đệm input

    // --- Tín hiệu điều khiển hệ thống ---
    reg clk;
    reg rst_n;

    // --- Giao tiếp Input (Stream byte) ---
    reg  [7:0] byte_in;    // Byte dữ liệu gửi vào
    reg        byte_valid; // Cờ báo byte hợp lệ
    wire       byte_ready; // Cờ báo Decoder sẵn sàng nhận

    // --- Giao tiếp Output (Pixel RGB) ---
    wire [7:0] r_out, g_out, b_out; // Giá trị màu Red, Green, Blue
    wire       pixel_valid;         // Cờ báo pixel hợp lệ

    // --- Thông tin trạng thái từ Decoder ---
    wire [15:0] img_width, img_height; // Kích thước ảnh giải mã được
    wire        idle;                  // Trạng thái nghỉ của Decoder

    // --- Bộ nhớ mô phỏng ---
    reg [7:0] image_rom [0:MAX_IMG_SIZE-1]; // Bộ nhớ chứa file input

    // --- Biến hỗ trợ mô phỏng ---
    integer file_out;                // File handler cho output
    integer pixel_count;             // Đếm số pixel đã giải mã
    integer data_ptr;                // Con trỏ đọc dữ liệu input
    integer cycles_since_last_pixel; // Bộ đếm timeout
    reg     simulation_running;      // Cờ điều khiển vòng lặp chính
    reg     has_started_scan;        // Cờ đánh dấu đã qua giai đoạn Header

    // ============================================================
    // 2. KẾT NỐI DUT (DEVICE UNDER TEST)
    // ============================================================
    jpeg_decoder_top u_top (
        .clk(clk),
        .rst_n(rst_n),
        .byte_in(byte_in),
        .byte_valid(byte_valid),
        .byte_ready(byte_ready),
        .r_out(r_out),
        .g_out(g_out),
        .b_out(b_out),
        .pixel_valid(pixel_valid),
        .img_width(img_width),
        .img_height(img_height),
        .idle(idle)
    );

    // ============================================================
    // 3. TẠO XUNG CLOCK
    // ============================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ============================================================
    // 4. THIẾT LẬP GHI SÓNG (WAVEFORM DUMP)
    // ============================================================
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_jpeg_decoder_top);
    end

    // ============================================================
    // [MỚI] 5. TASK: IN BẢNG DQT VÀ DHT (DEBUG TASK)
    // ============================================================
    // Task này truy cập trực tiếp vào các biến nội bộ của module Parser
    // để in ra giá trị các bảng mà Decoder đã đọc được.
    task print_internal_tables;
        integer i, j, k;
        reg [7:0] val;
        begin
            $display("\n");
            $display("##################################################");
            $display("#          JPEG INTERNAL TABLES DUMP             #");
            $display("##################################################");

            // --- 5.1. IN BẢNG LƯỢNG TỬ (DQT) ---
            // Truy cập vào mảng: u_top.u_parser.qtable_mem
            $display("\n--- [DQT] QUANTIZATION TABLES ---");
            
            for (k = 0; k < 2; k = k + 1) begin
                if (k == 0) $display("Table ID 0 (Luminance):");
                else        $display("Table ID 1 (Chrominance):");
                
                $display("      0  1  2  3  4  5  6  7");
                $display("    ------------------------");
                
                for (i = 0; i < 8; i = i + 1) begin
                    $write("Row %1d| ", i);
                    for (j = 0; j < 8; j = j + 1) begin
                        // Hierarchical reference: u_top -> u_parser -> qtable_mem
                        val = u_top.u_parser.qtable_mem[k][i*8 + j]; 
                        $write("%2x ", val);
                    end
                    $write("\n");
                end
                $display("");
            end

            // --- 5.2. IN BẢNG HUFFMAN (DHT) ---
            // In ra số lượng mã (Counts) cho mỗi độ dài bit (1..16)
            $display("\n--- [DHT] HUFFMAN TABLES (BITS COUNTS) ---");
            
            // In bảng DC Luma (ID 0)
            $display("DHT DC Table ID 0 (Luma):");
            $write("  BITS (1-16): ");
            for (i = 0; i < 16; i = i + 1) begin
                val = u_top.u_parser.dc0_len_out[i];
                $write("%2x ", val);
            end
            $write("\n");

            // In bảng AC Luma (ID 0)
            $display("DHT AC Table ID 0 (Luma):");
            $write("  BITS (1-16): ");
            for (i = 0; i < 16; i = i + 1) begin
                val = u_top.u_parser.ac0_len_out[i];
                $write("%2x ", val);
            end
            $write("\n");

            // In bảng DC Chroma (ID 1)
            $display("DHT DC Table ID 1 (Chroma):");
            $write("  BITS (1-16): ");
            for (i = 0; i < 16; i = i + 1) begin
                val = u_top.u_parser.dc1_len_out[i];
                $write("%2x ", val);
            end
            $write("\n");

            // In bảng AC Chroma (ID 1)
            $display("DHT AC Table ID 1 (Chroma):");
            $write("  BITS (1-16): ");
            for (i = 0; i < 16; i = i + 1) begin
                val = u_top.u_parser.ac1_len_out[i];
                $write("%2x ", val);
            end
            $write("\n");
            
            $display("##################################################\n");
        end
    endtask

    // ============================================================
    // 6. QUÁ TRÌNH MÔ PHỎNG CHÍNH (MAIN STIMULUS)
    // ============================================================
    initial begin
        // --- 6.1. Khởi tạo biến ---
        rst_n = 0;
        byte_valid = 0;
        byte_in = 0;
        data_ptr = 0;
        pixel_count = 0;
        cycles_since_last_pixel = 0;
        simulation_running = 1;
        has_started_scan = 0;

        // --- 6.2. Mở file Output ---
        file_out = $fopen(OUTPUT_PPM_FILE, "w");
        if (!file_out) begin
            $display("ERROR: Cannot open PPM file");
            $finish;
        end

        // --- 6.3. Load dữ liệu Input ---
        $readmemh(INPUT_HEX_FILE, image_rom);

        // --- 6.4. Reset hệ thống ---
        #100 rst_n = 1; // Thả reset sau 100ns
        #20;

        $display("START: Feeding JPEG stream...");

        // --- 6.5. Vòng lặp cấp dữ liệu ---
        while (simulation_running) begin

            // Logic gửi dữ liệu:
            // Nếu chưa hết file -> Gửi byte tiếp theo từ ROM
            if (data_ptr < MAX_IMG_SIZE && image_rom[data_ptr] !== 8'bx) begin
                byte_in    = image_rom[data_ptr];
                byte_valid = 1;
            end else begin
                // Nếu hết file nhưng Decoder chưa xong (chưa Idle) -> Gửi Padding 0x00
                if (!idle) begin
                    byte_in    = 8'h00;
                    byte_valid = 1;
                end else begin
                    // Nếu đã xong hết -> Ngắt valid
                    byte_valid = 0;
                end
            end

            @(posedge clk);

            // Handshake: Nếu Decoder nhận (Ready=1) thì tăng con trỏ đọc
            if (byte_valid && byte_ready) begin
                if (image_rom[data_ptr] !== 8'bx)
                    data_ptr = data_ptr + 1;
            end

            // --- KIỂM TRA HEADER ---
            // Nếu phát hiện Decoder bắt đầu Scan (xong Header), thực hiện in bảng debug
            if (u_top.start_scan && !has_started_scan) begin
                $display("INFO: SOS detected -> Start Scan Phase!");
                // Gọi task in bảng
                print_internal_tables(); 
                has_started_scan = 1;
            end

            // --- ĐIỀU KIỆN KẾT THÚC ---
            // Nếu đã scan xong và Decoder quay về IDLE -> Thành công
            if (has_started_scan && idle) begin
                repeat(100) @(posedge clk); // Chờ thêm chút để xả pipeline
                $display("SUCCESS: Decoder returned to IDLE. Image decoding complete.");
                simulation_running = 0;
            end

            // --- WATCHDOG (CHÓ CANH CỔNG) ---
            // Phòng trường hợp mô phỏng bị treo
            if (pixel_valid)
                cycles_since_last_pixel = 0;
            else if (has_started_scan)
                cycles_since_last_pixel = cycles_since_last_pixel + 1;

            if (cycles_since_last_pixel > 100000) begin
                $display("TIMEOUT: No pixel output for 100,000 cycles.");
                simulation_running = 0;
            end

            // Timeout nếu kẹt ở Header quá lâu
            if (!has_started_scan && data_ptr > 20000) begin
                $display("TIMEOUT: Stuck in Header parsing (Data ptr > 20000).");
                simulation_running = 0;
            end
        end

        // --- 6.6. Kết thúc ---
        #100;
        $fclose(file_out);
        $display("DONE: Generated %s with %0d pixels.", OUTPUT_PPM_FILE, pixel_count);
        $finish;
    end

    // ============================================================
    // 7. GHI FILE ẢNH (OUTPUT WRITER)
    // ============================================================
    // ============================================================
    // 7. GHI FILE ẢNH (BUFFERED OUTPUT WRITER)
    // ============================================================
    // Nguyên lý: mcu_manager trả về pixel theo thứ tự Block 16x16 (hoặc 8x8).
    // PPM cần thứ tự Raster (Dòng 0, Dòng 1...).
    // Cần Buffer để sắp xếp lại vị trí (x,y) trước khi ghi file.

    reg header_written = 0;
    
    // Buffer kích thước lớn (đủ cho 512x512)
    reg [7:0] buf_r [0:262143]; 
    reg [7:0] buf_g [0:262143]; 
    reg [7:0] buf_b [0:262143];
    
    // Biến tính toán toạ độ
    integer blk_size;
    integer mcu_w_grid;
    integer local_idx, mcu_idx;
    integer mcu_r, mcu_c;
    integer loc_r, loc_c;
    integer glob_x, glob_y;
    integer flat_addr;
    integer padded_width;

    always @(posedge clk) begin
        if (pixel_valid) begin
            // 7.1. Lấy kích thước Block dựa trên chế độ 4:2:0 hay 4:4:4
            // u_top.is_420 được định nghĩa trong jpeg_decoder_top
            if (u_top.is_420) blk_size = 16;
            else blk_size = 8;
            
            // Số lượng MCU trên 1 dòng (đã padding)
            // (img_width + blk_size - 1) / blk_size
            mcu_w_grid = (img_width + blk_size - 1) / blk_size;
            padded_width = mcu_w_grid * blk_size;

            // 7.2. Tính địa chỉ (x,y)
            // Pixel count tăng dần: 0..255 (MCU 0), 256..511 (MCU 1)...
            mcu_idx = pixel_count / (blk_size * blk_size);
            local_idx = pixel_count % (blk_size * blk_size);
            
            mcu_r = mcu_idx / mcu_w_grid;
            mcu_c = mcu_idx % mcu_w_grid;
            
            loc_r = local_idx / blk_size;
            loc_c = local_idx % blk_size;
            
            glob_y = mcu_r * blk_size + loc_r;
            glob_x = mcu_c * blk_size + loc_c;
            
            // 7.3. Lưu vào Buffer (nếu toạ độ nằm trong ảnh thực)
            // Note: mcu_manager có thể padding, ta cứ lưu hết hoặc chỉ lưu phần valid
            // Ở đây lưu theo toạ độ phẳng:
            flat_addr = glob_y * img_width + glob_x;
            
            // Chỉ lưu và đếm nếu toạ độ < kích thước ảnh (Crop padding)
            if (glob_x < img_width && glob_y < img_height) begin
                buf_r[flat_addr] = (r_out === 8'bx) ? 0 : r_out;
                buf_g[flat_addr] = (g_out === 8'bx) ? 0 : g_out;
                buf_b[flat_addr] = (b_out === 8'bx) ? 0 : b_out;
            end
            
            pixel_count = pixel_count + 1;
        end
    end

    // 7.4. Ghi ra File khi kết thúc
    integer xx, yy, addr_ptr;
    initial begin
        wait(simulation_running == 0); // Chờ mô phỏng xong
        
        if (img_width > 0 && img_height > 0) begin
             $display("WRITING PPM FILE...");
             $fwrite(file_out, "P3\n%d %d\n255\n", img_width, img_height);
             
             for (yy = 0; yy < img_height; yy = yy + 1) begin
                 for (xx = 0; xx < img_width; xx = xx + 1) begin
                     addr_ptr = yy * img_width + xx;
                     $fwrite(file_out, "%d %d %d\n", buf_r[addr_ptr], buf_g[addr_ptr], buf_b[addr_ptr]);
                 end
             end
             $display("PPM WRITE COMPLETE.");
        end
    end

endmodule