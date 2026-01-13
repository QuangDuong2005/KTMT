`timescale 1ns / 1ps

module tb_parser_bitstream_integration;

    // --- Signals ---
    reg clk, rst_n;
    
    // Input Stream giả lập
    reg [7:0] byte_in;
    reg byte_valid;
    
    // Wires kết nối giữa Parser và Bitstream
    wire parser_ready;
    wire start_scan;
    wire [7:0] scan_byte_out;
    wire scan_byte_valid;
    
    // Wires đầu ra cuối cùng
    wire bitstream_byte_ready;
    wire bit_out;
    wire bit_valid;
    reg  bit_ready_from_huffman; // Giả lập Huffman ready

    // --- Instantiation ---
    
    // 1. Header Parser (DUT 1)
    jpeg_header_parser u_parser (
        .clk(clk), .rst_n(rst_n),
        .byte_in(byte_in),
        .byte_valid(byte_valid),
        .parser_ready(parser_ready),
        
        .img_height(), .img_width(), 
        .qtable_loaded(), .qtable_id_loaded(),
        .dhttable_loaded(), .dht_table_class(), .dht_table_id(), .dht_sym_count(),
        
        // Cổng quan trọng
        .start_scan(start_scan),
        .scan_byte_out(scan_byte_out),
        .scan_byte_valid(scan_byte_valid)
    );

    // 2. Bitstream Reader (DUT 2) - Nối vào Output của Parser
    jpeg_bitstream_reader u_reader (
        .clk(clk), .rst_n(rst_n),
        .byte_in(scan_byte_out),       // Nối với scan_byte_out
        .byte_valid(scan_byte_valid),  // Nối với scan_byte_valid
        .byte_ready(bitstream_byte_ready),
        
        .bit_out(bit_out),
        .bit_valid(bit_valid),
        .bit_ready(bit_ready_from_huffman)
    );

    // --- Clock Generation ---
    always #5 clk = ~clk;

    // --- Test Data Generation ---
    reg [7:0] rom_data [0:100];
    integer idx;

    initial begin
        // Chuẩn bị dữ liệu giả lập (Không cần file hex thật, tự tạo để kiểm soát)
        // 1. SOI
        rom_data[0] = 8'hFF; rom_data[1] = 8'hD8;
        // 2. SOF0 (Len=17 bytes total: FF C0 [00 11] + 15 data bytes)
        rom_data[2] = 8'hFF; rom_data[3] = 8'hC0; 
        rom_data[4] = 8'h00; rom_data[5] = 8'h11; // Length = 17
        // Fill rác cho đủ length SOF
        for (idx=6; idx<21; idx=idx+1) rom_data[idx] = 8'hAA; 
        
        // 3. SOS (Start Scan) - Quan trọng nhất
        // Marker FF DA
        rom_data[21] = 8'hFF; rom_data[22] = 8'hDA;
        // Length = 12 (00 0C)
        rom_data[23] = 8'h00; rom_data[24] = 8'h0C;
        // Skip 10 byte header của SOS
        for (idx=25; idx<35; idx=idx+1) rom_data[idx] = 8'h55;
        
        // --- SCAN DATA BẮT ĐẦU TẠI ĐÂY ---
        // Byte đầu tiên: 0x93 (Binary: 1001 0011)
        rom_data[35] = 8'h93; 
        // Byte thứ hai: 0xFF (Byte Stuffing Test)
        rom_data[36] = 8'hFF;
        // Byte thứ ba: 0x00 (Phải bị bỏ qua)
        rom_data[37] = 8'h00;
        // Byte thứ tư: 0x81 (Binary: 1000 0001) -> Phải đọc ngay sau FF
        rom_data[38] = 8'h81;
        
        // Đánh dấu kết thúc
        rom_data[39] = 8'hFF; rom_data[40] = 8'hD9; // EOI
    end

    // --- Main Driver ---
    initial begin
        $dumpfile("sim/debug_parser_reader.vcd");
        $dumpvars(0, tb_parser_bitstream_integration);

        clk = 0; rst_n = 0; byte_valid = 0; byte_in = 0;
        bit_ready_from_huffman = 0; // Chưa nhận bit vội

        #20 rst_n = 1;
        
        $display("--- BẮT ĐẦU GỬI HEADER ---");
        
        // Gửi dữ liệu Header + SOS Header
        // index chạy từ 0 đến 34 (hết phần header SOS)
        for (idx = 0; idx < 35; idx = idx + 1) begin
            send_byte(rom_data[idx]);
        end

        $display("--- HEADER ĐÃ GỬI XONG, CHUẨN BỊ VÀO SCAN DATA ---");
        
        // Lúc này Parser sẽ xử lý Header SOS (S_SKIP_SEG).
        // Ta chờ một chút để Parser chuyển trạng thái sang DONE_HDR -> PASS_THROUGH
        wait(start_scan == 1);
        $display("[TIME %t] Parser báo START SCAN!", $time);
        
        // Bắt đầu nhận bit (Giả lập Huffman Decoder luôn sẵn sàng)
        bit_ready_from_huffman = 1;

        // Gửi tiếp dữ liệu Scan (0x93, 0xFF, 0x00, 0x81)
        // Lưu ý: Parser phải ở chế độ Pass-Through mới nhận byte này đúng cách
        
        // Byte 35: 0x93
        $display("[TIME %t] Gửi Byte Scan đầu tiên: 0x93", $time);
        send_byte(rom_data[35]); 
        
        // Byte 36: 0xFF
        send_byte(rom_data[36]);
        
        // Byte 37: 0x00 (Stuffing)
        send_byte(rom_data[37]);
        
        // Byte 38: 0x81
        send_byte(rom_data[38]);

        #200;
        $finish;
    end

    // Task gửi byte (có flow control với Parser)
    task send_byte(input [7:0] data);
    begin
        // Nếu đã vào mode Scan, Parser sẽ bật Ready ở chế độ Pass-Through
        // Ta cần chờ Parser ready
        wait(parser_ready == 1);
        @(posedge clk);
        byte_in <= data;
        byte_valid <= 1;
        @(posedge clk);
        byte_valid <= 0;
        #1; // Delay nhỏ để tránh race condition trong simulation
    end
    endtask
    
    // --- Monitor Output Bits ---
    reg [7:0] captured_bits;
    integer bit_cnt = 0;
    
    always @(posedge clk) begin
        if (bit_valid && bit_ready_from_huffman) begin
            $write("%b", bit_out); // In bit ra màn hình
            bit_cnt = bit_cnt + 1;
            
            // Logic check bit (thủ công)
            // Chuỗi mong đợi: 
            // 0x93 (10010011) 
            // 0xFF (11111111) -> Bỏ qua 00
            // 0x81 (10000001)
            
            if (bit_cnt % 8 == 0) $write(" "); // Dấu cách cho dễ nhìn
        end
    end

endmodule