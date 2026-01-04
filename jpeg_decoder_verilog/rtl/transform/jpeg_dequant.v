module jpeg_dequant
#(
    parameter WIDTH_IN  = 16,
    parameter WIDTH_Q   = 16,
    parameter WIDTH_OUT = 32
)
(
    // Input: Dữ liệu ảnh đã sắp xếp Row-Major (từ Inverse Zigzag)
    input  wire signed [WIDTH_IN*64-1:0]  matrix_in_flat,
    // Input: Bảng lượng tử Row-Major (từ RAM/Register bên ngoài)
    input  wire        [WIDTH_Q*64-1:0]   quant_flat,    
    // Output: Kết quả nhân
    output wire signed [WIDTH_OUT*64-1:0] dct_out_flat
);


    genvar i;
    generate
        for (i = 0; i < 64; i = i + 1) begin : MULT_LOOP
            // Khai báo dây cục bộ để code dễ đọc hơn
            wire signed [WIDTH_IN-1:0]  val;
            wire signed [WIDTH_Q-1:0]   q_val;
            wire signed [WIDTH_OUT-1:0] mult_res;


            // Cắt bit (Slicing)
            assign val   = matrix_in_flat[(i+1)*WIDTH_IN-1 : i*WIDTH_IN];
            // Q-table thường không âm, nhưng ta ép kiểu signed để phép nhân an toàn
            assign q_val = $signed({1'b0, quant_flat[(i+1)*WIDTH_Q-1 : i*WIDTH_Q]}); // Zero-extend nếu cần


            // Nhân: Result = Val * Q
            assign mult_res = val * q_val;


            // Gán vào output
            assign dct_out_flat[(i+1)*WIDTH_OUT-1 : i*WIDTH_OUT] = mult_res;
        end
    endgenerate


endmodule
