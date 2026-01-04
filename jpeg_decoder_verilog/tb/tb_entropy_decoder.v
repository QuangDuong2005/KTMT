`timescale 1ns / 1ps

module tb_entropy_decoder;

    // Tín hiệu
    reg clk, rst_n;
    reg [7:0] symbol_in; reg symbol_valid; wire huff_enable;
    reg bit_in; reg bit_valid; wire is_reading_bits;
    wire coeff_valid; wire [5:0] coeff_index; wire signed [11:0] coeff_value; wire block_done;

    // DUT
    jpeg_entropy_decoder uut (
        .clk(clk), .rst_n(rst_n),
        .symbol_in(symbol_in), .symbol_valid(symbol_valid), .huff_enable(huff_enable),
        .bit_in(bit_in), .bit_valid(bit_valid),
        .coeff_valid(coeff_valid), .coeff_index(coeff_index), .coeff_value(coeff_value),
        .block_done(block_done), .is_reading_bits(is_reading_bits)
    );

    always #10 clk = ~clk;

    // --- Task Gửi Symbol ---
    task send_symbol(input [3:0] run, input [3:0] size);
    begin
        wait(huff_enable == 1);
        @(posedge clk);
        symbol_in <= {run, size};
        symbol_valid <= 1;
        @(posedge clk);
        symbol_valid <= 0;
    end
    endtask

    // --- Task Gửi Bit ---
    task send_vli_bits(input [3:0] count, input [15:0] bits);
    integer k;
    begin
        wait(is_reading_bits == 1);
        for (k = count - 1; k >= 0; k = k - 1) begin
            @(posedge clk);
            bit_in <= bits[k];
            bit_valid <= 1;
        end
        @(posedge clk);
        bit_valid <= 0;
    end
    endtask

    // --- Task: Chờ Output (Sync Barrier) ---
    // Task này sẽ treo cho đến khi nhận đủ N coeff đầu ra
    task wait_for_coeffs(input integer count);
    integer cnt;
    begin
        cnt = 0;
        while (cnt < count) begin
            @(posedge clk);
            if (coeff_valid) cnt = cnt + 1;
        end
    end
    endtask

    // --- MAIN TEST ---
    initial begin
        $dumpfile("sim/entropy_robust.vcd");
        $dumpvars(0, tb_entropy_decoder);

        clk = 0; rst_n = 0;
        symbol_in = 0; symbol_valid = 0; bit_in = 0; bit_valid = 0;

        $display("--- ROBUST ENTROPY TEST START ---");
        #30 rst_n = 1; #20;

        // 1. DC (Run=0, Size=3) -> Expect 1 output
        $display("[TEST 1] DC...");
        send_symbol(0, 3);
        send_vli_bits(3, 3'b101);
        wait_for_coeffs(1); // Chờ 1 coeff ra lò

        // 2. AC (Run=0, Size=2) -> Expect 1 output
        $display("[TEST 2] AC...");
        send_symbol(0, 2);
        send_vli_bits(2, 2'b01);
        wait_for_coeffs(1);

        // 3. AC Run (Run=4, Size=1) -> Expect 5 outputs (4 số 0 + 1 giá trị)
        $display("[TEST 3] AC Run...");
        send_symbol(4, 1);
        // Lưu ý: Gửi bit song song với việc chờ coeff (vì DUT vừa xuất 0 vừa đợi bit)
        // Ta dùng fork-join để chạy song song: 1 luồng gửi bit, 1 luồng chờ output
        fork
            send_vli_bits(1, 1'b1);
            wait_for_coeffs(5); // 4 zeros + 1 value
        join

        // 4. ZRL (16 Zeros) -> Expect 16 outputs
        $display("[TEST 4] ZRL...");
        send_symbol(4'hF, 0);
        wait_for_coeffs(16);
        $display("       -> ZRL Done.");

        // 5. EOB -> Expect điền nốt số 0 (Từ index hiện tại đến 63)
        // Hiện tại index là: 1 (DC) + 1 (AC) + 5 (Run) + 16 (ZRL) = 23
        // Cần điền từ 23 đến 63 -> 41 số 0.
        $display("[TEST 5] EOB...");
        send_symbol(0, 0);
        
        // Chờ đến khi Block Done
        wait(block_done == 1);
        $display("[SUCCESS] Block Done!");

        #50 $finish;
    end

    // Monitor
    always @(posedge clk) begin
        if (coeff_valid) begin
            $display("OUT Idx: %2d | Val: %4d", coeff_index, coeff_value);
        end
    end

endmodule