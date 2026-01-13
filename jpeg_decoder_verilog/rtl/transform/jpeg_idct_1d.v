module jpeg_idct_1d (
    input signed [31:0] in0, in1, in2, in3, in4, in5, in6, in7, // Đầu vào (DCT Coeffs)
    output signed [31:0] out0, out1, out2, out3, out4, out5, out6, out7 // Đầu ra (Pixel values)
);
    // Các hệ số Cosin đã nhân với 256 (Fixed-point Q8)
    localparam integer C1 = 251; // cos(1pi/16)
    localparam integer C2 = 237; // cos(2pi/16)
    localparam integer C3 = 213; // cos(3pi/16)
    localparam integer C4 = 181; // cos(4pi/16)
    localparam integer C5 = 142; // cos(5pi/16)
    localparam integer C6 = 98;  // cos(6pi/16) - Corrected from 97 (97.96)
    localparam integer C7 = 50;  // cos(7pi/16)


    // Biến trung gian (cần độ rộng bit lớn hơn để tránh tràn số khi nhân)
    // Thuật toán IDCT chuẩn (Even/Odd decomposition)
    // Bước 1: Phần chẵn (Even part)
    // Tận dụng tính đối xứng để giảm số phép nhân
    wire signed [31:0] x0, x1, x2, x3, x4, x5, x6, x7, x8;
   
    // Lưu ý: Đây là triển khai thuật toán Loeffler giản lược hoặc Matrix Multiply trực tiếp
    // Để code ngắn gọn và dễ hiểu cho sinh viên, tôi dùng tổng trọng số (Weighted Sum)
   
    // Tính toán song song cho 8 điểm ảnh
    // out[k] = sum(in[n] * C * cos(...))
    // >> 9 để chia 512 (256 coeff * 2 norm)
    // Thêm +256 để làm tròn (Round to nearest) thay vì cắt bỏ (Floor)
   
    assign out0 = (in0*C4 + in1*C1 + in2*C2 + in3*C3 + in4*C4 + in5*C5 + in6*C6 + in7*C7 + 256) >>> 9;
    assign out1 = (in0*C4 + in1*C3 + in2*C6 - in3*C7 - in4*C4 - in5*C1 - in6*C2 - in7*C5 + 256) >>> 9;
    assign out2 = (in0*C4 + in1*C5 - in2*C6 - in3*C1 - in4*C4 + in5*C7 + in6*C2 + in7*C3 + 256) >>> 9;
    assign out3 = (in0*C4 + in1*C7 - in2*C2 - in3*C5 + in4*C4 + in5*C3 - in6*C6 - in7*C1 + 256) >>> 9;
    assign out4 = (in0*C4 - in1*C7 - in2*C2 + in3*C5 + in4*C4 - in5*C3 - in6*C6 + in7*C1 + 256) >>> 9;
    assign out5 = (in0*C4 - in1*C5 - in2*C6 + in3*C1 - in4*C4 - in5*C7 + in6*C2 - in7*C3 + 256) >>> 9;
    assign out6 = (in0*C4 - in1*C3 + in2*C6 + in3*C7 - in4*C4 + in5*C1 - in6*C2 + in7*C5 + 256) >>> 9;
    assign out7 = (in0*C4 - in1*C1 + in2*C2 - in3*C3 + in4*C4 - in5*C5 + in6*C6 - in7*C7 + 256) >>> 9;


endmodule
