`timescale 1ns / 1ps

module tb_jpeg_transform_block;

    // ============================================================
    // 1. PARAMETERS & SIGNALS
    // ============================================================
    parameter WIDTH_IN  = 16;
    parameter WIDTH_OUT = 32;

    // Inputs (Flattened 1D arrays)
    reg signed [WIDTH_IN*64-1:0] zz_in_flat;
    reg        [WIDTH_IN*64-1:0] quant_flat;

    // Output
    wire signed [WIDTH_OUT*64-1:0] dct_out_flat;

    // Biến phụ trợ để chạy vòng lặp gán dữ liệu
    integer i;

    // ============================================================
    // 2. DUT INSTANTIATION
    // ============================================================
    jpeg_transform_block #(
        .WIDTH_IN(WIDTH_IN),
        .WIDTH_OUT(WIDTH_OUT)
    ) u_dut (
        .zz_in_flat(zz_in_flat),
        .quant_flat(quant_flat),
        .dct_out_flat(dct_out_flat)
    );

    // ============================================================
    // 3. HELPER TASK: IN MA TRẬN 8x8 TỪ FLATTEN ARRAY (ĐÃ SỬA LỖI)
    // ============================================================
    task print_output_matrix;
        input [8*20:1] test_name;
        integer r, c;
        reg signed [WIDTH_OUT-1:0] val;
        begin
            $display("--------------------------------------------------");
            $display("Test: %s", test_name);
            $display("--------------------------------------------------");
            
            for (r = 0; r < 8; r = r + 1) begin
                $write("Row %1d: ", r);
                for (c = 0; c < 8; c = c + 1) begin
                    
                    // --- SỬA LỖI TẠI ĐÂY ---
                    // Cú pháp cũ (Lỗi): val = dct_out_flat[ ((r*8 + c) + 1)*WIDTH_OUT - 1 : (r*8 + c)*WIDTH_OUT ];
                    
                    // Cú pháp mới (Dùng toán tử +:):
                    // Lấy bắt đầu từ bit thấp (LSB) và lấy lên WIDTH_OUT bit
                    val = dct_out_flat[ (r*8 + c)*WIDTH_OUT +: WIDTH_OUT ];
                    
                    // In ra (chiếm 6 ký tự)
                    $write("%6d ", val);
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
        $display("\nSTART: Testing JPEG Transform Block (Dequant + Inverse Zigzag)...\n");

        // --------------------------------------------------------
        // TEST CASE 1: KIỂM TRA SẮP XẾP (INVERSE ZIGZAG)
        // --------------------------------------------------------
        // - Gán Quantization = 1 (để không làm thay đổi giá trị)
        // - Gán Input = Index chạy từ 0 đến 63.
        // - MONG ĐỢI: Output sẽ hiển thị map vị trí Zigzag.
        //   Ví dụ: Tại hàng 0, cột 1 (Raster index 1), giá trị phải là 1 (Zigzag index 1).
        //          Tại hàng 1, cột 0 (Raster index 8), giá trị phải là 2 (Zigzag index 2).
        //          Tại hàng 0, cột 2 (Raster index 2), giá trị phải là 5 (Zigzag index 5).
        
        for (i = 0; i < 64; i = i + 1) begin
            // Input[i] = i
            zz_in_flat[(i+1)*WIDTH_IN-1 -: WIDTH_IN] = i; 
            // Quant[i] = 1
            quant_flat[(i+1)*WIDTH_IN-1 -: WIDTH_IN] = 1;
        end

        #10; // Chờ tính toán tổ hợp
        print_output_matrix("Zigzag Reordering Check (Quant=1)");
        $display("Expectation: You should see the Zigzag pattern table (0, 1, 5, 6, 14...)");


        // --------------------------------------------------------
        // TEST CASE 2: KIỂM TRA NHÂN (DEQUANTIZATION)
        // --------------------------------------------------------
        // - Gán Input = 10 (tất cả các vị trí)
        // - Gán Quantization = 5 (tất cả các vị trí)
        // - MONG ĐỢI: Output = 50 tại mọi vị trí (10 * 5)
        
        for (i = 0; i < 64; i = i + 1) begin
            zz_in_flat[(i+1)*WIDTH_IN-1 -: WIDTH_IN] = 10; 
            quant_flat[(i+1)*WIDTH_IN-1 -: WIDTH_IN] = 5;
        end

        #10;
        print_output_matrix("Math Check (10 * 5)");


        // --------------------------------------------------------
        // TEST CASE 3: KẾT HỢP (REAL SCENARIO)
        // --------------------------------------------------------
        // Giả sử chỉ có hệ số DC (index 0) và AC1 (index 1)
        // DC: val=10, Q=2 -> Expect 20 tại Row 0, Col 0
        // AC1: val=5, Q=3 -> Expect 15 tại Row 0, Col 1 (Zigzag index 1 maps to Raster 0,1)
        // AC2: val=2, Q=4 -> Expect 8 tại Row 1, Col 0 (Zigzag index 2 maps to Raster 1,0)
        
        // Reset về 0 trước
        for (i = 0; i < 64; i = i + 1) begin
            zz_in_flat[(i+1)*WIDTH_IN-1 -: WIDTH_IN] = 0;
            quant_flat[(i+1)*WIDTH_IN-1 -: WIDTH_IN] = 1;
        end

        // Gán giá trị cụ thể
        // Index 0 (DC)
        zz_in_flat[1*WIDTH_IN-1 -: WIDTH_IN] = 10; 
        quant_flat[1*WIDTH_IN-1 -: WIDTH_IN] = 2;

        // Index 1 (Zigzag 1 -> Raster 0,1)
        zz_in_flat[2*WIDTH_IN-1 -: WIDTH_IN] = 5; 
        quant_flat[2*WIDTH_IN-1 -: WIDTH_IN] = 3;

        // Index 2 (Zigzag 2 -> Raster 1,0)
        zz_in_flat[3*WIDTH_IN-1 -: WIDTH_IN] = 2; 
        quant_flat[3*WIDTH_IN-1 -: WIDTH_IN] = 4;

        #10;
        print_output_matrix("Specific Values Check");

        $finish;
    end

endmodule
