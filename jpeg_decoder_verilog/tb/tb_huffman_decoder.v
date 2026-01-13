`timescale 1ns / 1ps

module tb_huffman_decoder;

    // --- Signals ---
    reg clk;
    reg rst_n;
    reg enable;
    reg start;
    
    // Bitstream Input
    reg bit_in;
    reg bit_valid;

    // Table Interface
    reg [15:0] huff_code_in [0:255];
    reg [4:0]  huff_len_in  [0:255];

    // Output
    wire [7:0] symbol_out;
    wire symbol_valid;

    // --- Instantiate DUT ---
    jpeg_huffman_decoder uut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .start(start),
        
        .bit_in(bit_in),
        .bit_valid(bit_valid),
        
        .huff_code_in(huff_code_in),
        .huff_len_in(huff_len_in),
        
        .symbol_out(symbol_out),
        .symbol_valid(symbol_valid)
    );

    // --- Clock ---
    always #5 clk = ~clk;

    // --- Tasks ---
    task send_bit(input b);
    begin
        @(posedge clk);
        bit_in <= b;
        bit_valid <= 1;
        @(posedge clk);
        bit_valid <= 0;
    end
    endtask

    integer i;

    // --- Test Scenario ---
    initial begin
        $dumpfile("sim/huffman_test.vcd");
        $dumpvars(0, tb_huffman_decoder);

        // Init
        clk = 0; rst_n = 0; enable = 0; start = 0;
        bit_in = 0; bit_valid = 0;
        
        // Clear Table Inputs
        for (i=0; i<256; i=i+1) begin
            huff_code_in[i] = 0;
            huff_len_in[i]  = 0;
        end

        // Setup Huffman Table giả lập (Custom Table)
        // Rule: Canonical Huffman (Mã ngắn bên trái, dài bên phải)
        
        // Symbol 0x0A -> Mã '0' (Len 1)
        huff_code_in[8'h0A] = 16'b0; 
        huff_len_in[8'h0A]  = 5'd1;

        // Symbol 0x0B -> Mã '10' (Len 2)
        huff_code_in[8'h0B] = 16'b10;
        huff_len_in[8'h0B]  = 5'd2;

        // Symbol 0x0C -> Mã '110' (Len 3)
        huff_code_in[8'h0C] = 16'b110;
        huff_len_in[8'h0C]  = 5'd3;

        // Reset Sequence
        #20 rst_n = 1;
        #10;

        // 1. Load Table
        $display("[TEST] Loading Huffman Table...");
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;
        #20; // Chờ load xong (thực ra DUT load trong 1 clock vì dùng array assignment)

        // 2. Start Decoding
        $display("[TEST] Start Decoding...");
        enable <= 1;

        // --- Case 1: Gửi bit '0' -> Expect Symbol 0x0A ---
        send_bit(0); 
        #10; // Chờ decode

        // --- Case 2: Gửi bit '1', sau đó '0' -> Expect Symbol 0x0B ---
        send_bit(1);
        send_bit(0);
        #10;

        // --- Case 3: Gửi '1', '1', '0' -> Expect Symbol 0x0C ---
        send_bit(1);
        send_bit(1);
        send_bit(0);
        #10;

        // --- Case 4: Test Race Condition (Vừa decode xong vừa nạp bit mới) ---
        // Giả sử DUT vừa decode xong 0x0C, buffer đang trống.
        // Ta gửi liên tiếp 2 mã '0' (0x0A) sát nhau
        $display("[TEST] Fast stream...");
        send_bit(0); // Decode ra 0x0A ngay lập tức
        send_bit(0); // Decode ra 0x0A tiếp theo
        
        #50;
        $finish;
    end

    // --- Monitor Output ---
    always @(posedge clk) begin
        if (symbol_valid) begin
            $display("[OUT] Time %t | Found Symbol: %h", $time, symbol_out);
        end
    end

endmodule