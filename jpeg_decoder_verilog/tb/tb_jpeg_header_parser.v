// module tb_jpeg_header_parser_full;
//     reg clk, rst_n;
//     reg [7:0] byte_in;
//     reg byte_valid;
//     wire parser_ready;

//     wire [15:0] img_height;
//     wire [15:0] img_width;
//     wire qtable_loaded;
//     wire [1:0] qtable_id_loaded;
//     wire dhttable_loaded;
//     wire dht_table_class;
//     wire [3:0] dht_table_id;
//     wire [8:0] dht_sym_count;
//     wire start_scan;
//     wire [7:0] scan_byte_out;
//     wire scan_byte_valid;

//     integer file_log, idx, k;
//     reg [7:0] file_rom [0:65535];

//     jpeg_header_parser_full uut (
//         .clk(clk), .rst_n(rst_n),
//         .byte_in(byte_in), .byte_valid(byte_valid), .parser_ready(parser_ready),
//         .img_height(img_height), .img_width(img_width),
//         .qtable_loaded(qtable_loaded), .qtable_id_loaded(qtable_id_loaded),
//         .dhttable_loaded(dhttable_loaded), .dht_table_class(dht_table_class),
//         .dht_table_id(dht_table_id), .dht_sym_count(dht_sym_count),
//         .start_scan(start_scan), .scan_byte_out(scan_byte_out), .scan_byte_valid(scan_byte_valid)
//     );

//     always #10 clk = ~clk;

//     // Task gửi byte
//     task send_byte(input [7:0] data);
//         begin
//             wait(parser_ready == 1'b1);
//             @(posedge clk); 
//             byte_in = data;
//             byte_valid = 1'b1;
//             @(posedge clk); 
//             byte_valid = 1'b0;
//             #1; 
//         end
//     endtask

//     // --- MAIN PROCESS ---
//     initial begin
//         $dumpfile("sim/wave_parser_full.vcd");
//         $dumpvars(0, tb_jpeg_header_parser_full);
//         file_log = $fopen("sim/output_log.txt", "w");
        
//         // Đọc hex file (đảm bảo file test.hex của bạn đúng định dạng hex text)
//         $readmemh("data/test.hex", file_rom);

//         clk = 0; rst_n = 0; byte_in = 0; byte_valid = 0;
//         #50; rst_n = 1; #20;

//         $display("--- [TEST START] ---");
        
//         for (idx = 0; idx < 65536; idx = idx + 1) begin
//             if (file_rom[idx] === 8'bx) begin
//                 $display("-> End of File detected at index %d", idx);
//                 idx = 65536; // Break
//             end else begin
//                 send_byte(file_rom[idx]);
//             end
//         end
        
//         #500;
//         $fclose(file_log);
//         $finish;
//     end

//     // --- MONITOR LOGIC (FIXED) ---
//     // Sử dụng negedge clk để kiểm tra tín hiệu sau khi nó đã được set ở posedge
//     always @(negedge clk) begin
//         if (rst_n) begin
//             // 1. Log DQT
//             if (qtable_loaded) begin
//                 $fdisplay(file_log, "\n[TIME %t] >>> DQT LOADED | ID: %d", $time, qtable_id_loaded);
//                 for (k = 0; k < 64; k = k + 1) begin
//                     $fwrite(file_log, "%02x ", uut.qtable_mem[qtable_id_loaded][k][7:0]);
//                     if ((k + 1) % 8 == 0) $fdisplay(file_log, ""); 
//                 end
//             end

//             // 2. Log DHT
//             if (dhttable_loaded) begin
//                 $fdisplay(file_log, "\n[TIME %t] >>> DHT LOADED | Class: %d | ID: %d | Count: %d", 
//                           $time, dht_table_class, dht_table_id, dht_sym_count);
//                 $fdisplay(file_log, "Symbols:");
//                 for (k = 0; k < dht_sym_count; k = k + 1) begin
//                     // Truy cập index mở rộng
//                     $fwrite(file_log, "%02x ", uut.dht_sym_mem[{dht_table_class, dht_table_id}][k]);
//                     if ((k + 1) % 16 == 0) $fdisplay(file_log, "");
//                 end
//                 $fdisplay(file_log, "");
//             end

//             // 3. Log SOS
//             if (start_scan) begin
//                 $fdisplay(file_log, "\n[TIME %t] >>> SOS DETECTED - Size: %d x %d", $time, img_width, img_height);
//                 $display("SOS Detected in Console! Check log file.");
//             end
//         end
//     end

// endmodule

`timescale 1ns / 1ps

module tb_jpeg_header_parser;

    // -------------------------------------------------------------------------
    // 1. Khai báo tín hiệu và Biến
    // -------------------------------------------------------------------------
    reg clk;
    reg rst_n;
    reg [7:0] byte_in;
    reg byte_valid;
    wire parser_ready;

    // Các tín hiệu Output từ Module
    wire [15:0] img_height;
    wire [15:0] img_width;
    wire qtable_loaded;
    wire [1:0] qtable_id_loaded;
    wire dhttable_loaded;
    wire dht_table_class;
    wire [3:0] dht_table_id;
    wire [8:0] dht_sym_count;
    wire start_scan;
    wire [7:0] scan_byte_out;
    wire scan_byte_valid;

    // Biến cho Testbench
    integer file_log, idx, k;
    reg [7:0] file_rom [0:65535]; // Bộ nhớ đệm file hex (64KB)

    // -------------------------------------------------------------------------
    // 2. Kết nối Module (DUT)
    // -------------------------------------------------------------------------
    jpeg_header_parser_full uut (
        .clk(clk),
        .rst_n(rst_n),
        .byte_in(byte_in),
        .byte_valid(byte_valid),
        .parser_ready(parser_ready),
        .img_height(img_height),
        .img_width(img_width),
        .qtable_loaded(qtable_loaded),
        .qtable_id_loaded(qtable_id_loaded),
        .dhttable_loaded(dhttable_loaded),
        .dht_table_class(dht_table_class),
        .dht_table_id(dht_table_id),
        .dht_sym_count(dht_sym_count),
        .start_scan(start_scan),
        .scan_byte_out(scan_byte_out),
        .scan_byte_valid(scan_byte_valid)
    );

    // -------------------------------------------------------------------------
    // 3. Tạo xung Clock
    // -------------------------------------------------------------------------
    always #10 clk = ~clk;

    // -------------------------------------------------------------------------
    // 4. Task gửi byte (Flow Control)
    // -------------------------------------------------------------------------
    task send_byte(input [7:0] data);
        begin
            // Chờ module sẵn sàng
            while (parser_ready == 0) begin
                @(posedge clk);
            end
            
            // Gửi dữ liệu
            @(posedge clk); 
            byte_in = data;
            byte_valid = 1'b1;
            
            // Kết thúc gửi
            @(posedge clk); 
            byte_valid = 1'b0;
            #1; // Delay nhỏ
        end
    endtask

    // -------------------------------------------------------------------------
    // 5. Chương trình chính (MAIN)
    // -------------------------------------------------------------------------
    initial begin
        // Cấu hình Waveform
        $dumpfile("sim/wave_parser_full.vcd");
        $dumpvars(0, tb_jpeg_header_parser_full);

        // Mở file Log
        file_log = $fopen("sim/output_log.txt", "w");
        if (file_log == 0) begin
            $display("❌ ERROR: Không thể tạo file output_log.txt");
            $finish;
        end

        // --- NẠP FILE HEX VÀO BỘ NHỚ ---
        // Đảm bảo bạn đã tạo file 'data/test.hex' chuẩn
        $readmemh("data/test.hex", file_rom);

        // Khởi tạo
        clk = 0; rst_n = 0; byte_in = 0; byte_valid = 0;
        
        // Reset hệ thống
        #50; rst_n = 1; #20;

        $display("--- [TEST START] Đang đọc file data/test.hex ---");
        
        // Kiểm tra xem file có dữ liệu không
        if (file_rom[0] === 8'bx) begin
            $display("❌ LỖI: Không đọc được file hex. Kiểm tra đường dẫn 'data/test.hex'");
            $finish;
        end

        // Vòng lặp gửi toàn bộ file
        for (idx = 0; idx < 65536; idx = idx + 1) begin
            if (file_rom[idx] === 8'bx) begin
                $display("-> Kết thúc file tại byte thứ %d", idx);
                idx = 65536; // Thoát vòng lặp
            end else begin
                send_byte(file_rom[idx]);
            end
        end
        
        #500;
        $display("--- [TEST] Completed ---");
        $fclose(file_log);
        $finish;
    end

    // -------------------------------------------------------------------------
    // 6. LOGIC GHI LOG (MONITOR)
    // -------------------------------------------------------------------------
    // Sử dụng negedge clk để đảm bảo dữ liệu từ DUT đã ổn định
    always @(negedge clk) begin
        if (rst_n) begin
            
            // --- Ghi log Bảng Lượng Tử (DQT) ---
            if (qtable_loaded) begin
                $fdisplay(file_log, "\n--------------------------------------------------");
                $fdisplay(file_log, "[TIME %t] DQT LOADED | Table ID: %d", $time, qtable_id_loaded);
                $fdisplay(file_log, "--------------------------------------------------");
                
                for (k = 0; k < 64; k = k + 1) begin
                    // In số Hex 2 chữ số
                    $fwrite(file_log, "%02x ", uut.qtable_mem[qtable_id_loaded][k]);
                    if ((k + 1) % 8 == 0) $fdisplay(file_log, ""); // Xuống dòng mỗi 8 số
                end
            end

            // --- Ghi log Bảng Huffman (DHT) ---
            if (dhttable_loaded) begin
                $fdisplay(file_log, "\n--------------------------------------------------");
                $fdisplay(file_log, "[TIME %t] DHT LOADED | Class: %s | ID: %d | Total Symbols: %d", 
                          $time, (dht_table_class ? "AC" : "DC"), dht_table_id, dht_sym_count);
                $fdisplay(file_log, "--------------------------------------------------");
                
                $fdisplay(file_log, "Symbols Dump:");
                for (k = 0; k < dht_sym_count; k = k + 1) begin
                    // Truy cập bộ nhớ Huffman trong DUT
                    // Index = {Class(1 bit), ID(4 bits)}
                    $fwrite(file_log, "%02x ", uut.dht_sym_mem[{dht_table_class, dht_table_id}][k]);
                    if ((k + 1) % 16 == 0) $fdisplay(file_log, "");
                end
                $fdisplay(file_log, "");
            end

            // --- Ghi log SOS (Bắt đầu Scan) ---
            if (start_scan) begin
                $fdisplay(file_log, "\n==================================================");
                $fdisplay(file_log, "[TIME %t] SOS DETECTED - START SCAN", $time);
                $fdisplay(file_log, "Detected Image Size: Width=%d, Height=%d", img_width, img_height);
                $fdisplay(file_log, "==================================================");
                $fdisplay(file_log, "Scan Data Stream:");
                
                // In ra màn hình console để dễ thấy
                $display("✅ SOS DETECTED! Image Size: %dx%d", img_width, img_height);
            end
            
            // --- Ghi dữ liệu Pass-through ---
            if (scan_byte_valid) begin
                $fdisplay(file_log, "%02x", scan_byte_out);
            end
        end
    end

endmodule