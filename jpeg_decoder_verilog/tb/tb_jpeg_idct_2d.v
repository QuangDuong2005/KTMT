`timescale 1ns / 1ps

module tb_jpeg_idct_2d;

    // ============================================================
    // 1. SIGNALS & VARIABLES
    // ============================================================
    reg clk;
    
    // Mảng unpacked array tương thích với module của bạn
    reg signed [15:0] matrix_in [0:63];
    wire signed [15:0] matrix_out [0:63];

    integer i;

    // ============================================================
    // 2. DUT INSTANTIATION
    // ============================================================
    jpeg_idct_2d dut (
        .clk(clk),
        .matrix_in(matrix_in),
        .matrix_out(matrix_out)
    );

    // ============================================================
    // 3. HELPER TASKS
    // ============================================================
    
    // Task xóa sạch input về 0
    task clear_input;
        integer k;
        begin
            for (k = 0; k < 64; k = k + 1) matrix_in[k] = 0;
        end
    endtask

    // Task in ma trận 8x8 ra màn hình console
    task print_8x8;
        input [8*20:1] name; // Tên tiêu đề (string)
        integer r, c;
        begin
            $display("--------------------------------------------------");
            $display("Matrix: %s", name);
            $display("--------------------------------------------------");
            for (r = 0; r < 8; r = r + 1) begin
                $write("Row %1d: ", r);
                for (c = 0; c < 8; c = c + 1) begin
                    // In 6 ký tự cho mỗi số để thẳng hàng
                    $write("%6d ", matrix_out[r*8 + c]);
                end
                $write("\n");
            end
            $display("\n");
        end
    endtask

    // ============================================================
    // 4. MAIN STIMULUS
    // ============================================================
    initial begin
        // Init clock (dù code của bạn đang là tổ hợp, nhưng cứ để clk cho đúng chuẩn)
        clk = 0;
        
        $display("\nSTART: Testing JPEG IDCT 2D Module...\n");

        // --- CASE 1: ZERO INPUT ---
        // Input toàn 0 -> Output phải toàn 0
        clear_input();
        #10; // Chờ tính toán tổ hợp
        print_8x8("Test 1: All Zero Input (Expect All 0)");

        // --- CASE 2: DC CONSTANT (Flat Field) ---
        // Chỉ có hệ số DC (index 0) có giá trị, AC = 0.
        // Kết quả mong đợi: Toàn bộ 64 pixel có giá trị xấp xỉ nhau (màu phẳng).
        // Phân tích lý thuyết code của bạn:
        // C4 = 181 (~0.707 * 256). 
        // Row Pass: In * C4 >> 8 ~= In * 0.707
        // Col Pass: Row * C4 >> 8 ~= (In * 0.707) * 0.707 ~= In * 0.5
        // => Nếu nhập 1000, output kỳ vọng khoảng 500.
        clear_input();
        matrix_in[0] = 1000; 
        #10;
        print_8x8("Test 2: DC Only (Input=1000) -> Expect ~500 everywhere");

        // --- CASE 3: VERTICAL STRIPES (AC Coefficient Row 0) ---
        // Kích thích hệ số AC đầu tiên của hàng 0 (matrix_in[1]).
        // Điều này sẽ tạo ra sự thay đổi tần số thấp theo chiều ngang,
        // nhưng giống nhau theo chiều dọc => Tạo ra các sọc dọc.
        clear_input();
        matrix_in[1] = 1000; 
        #10;
        print_8x8("Test 3: Vertical Pattern (Input[1]=1000)");

        // --- CASE 4: HORIZONTAL STRIPES (AC Coefficient Col 0) ---
        // Kích thích hệ số AC đầu tiên của cột 0 (matrix_in[8]).
        // Điều này tạo ra sọc ngang.
        clear_input();
        matrix_in[8] = 1000;
        #10;
        print_8x8("Test 4: Horizontal Pattern (Input[8]=1000)");

        // --- CASE 5: CHECKERBOARD (High Frequency) ---
        // Kích thích hệ số tần số cao nhất (góc dưới phải - index 63).
        clear_input();
        matrix_in[63] = 1000;
        #10;
        print_8x8("Test 5: High Freq Checkerboard (Input[63]=1000)");

        $display("Done.");
        $finish;
    end

endmodule