module jpeg_transform_block
#(
    parameter WIDTH_IN  = 16,
    parameter WIDTH_OUT = 32 // IDCT input width (thường cần to hơn 16 một chút để tránh tràn số khi nhân)
)
(
    input  wire signed [WIDTH_IN*64-1:0]  zz_in_flat,   // Input: Zigzag
    input  wire        [WIDTH_IN*64-1:0]  quant_flat,   // Input: Zigzag (Standard JPEG DQT)
    output wire signed [WIDTH_OUT*64-1:0] dct_out_flat  // Output: Row-Major (Ready for IDCT)
);

    // Dây nối trung gian: Kết quả sau khi Dequant vẫn đang là Zigzag
    wire signed [WIDTH_OUT*64-1:0] dequant_out_zigzag;

    // 1. Dequantization TRƯỚC (Vì cả 2 đều đang là Zigzag)
    // Zigzag Coeff * Zigzag Quant = Zigzag Dequantized
    jpeg_dequant #(
        .WIDTH_IN(WIDTH_IN),
        .WIDTH_Q(WIDTH_IN),
        .WIDTH_OUT(WIDTH_OUT)
    ) deq (
        .matrix_in_flat(zz_in_flat), 
        .quant_flat(quant_flat),
        .dct_out_flat(dequant_out_zigzag)
    );

    // 2. Inverse Zigzag SAU (Sắp xếp lại để vào IDCT)
    // Zigzag -> Row Major
    jpeg_inverse_zigzag #(.WIDTH(WIDTH_OUT)) i_zz (
        .zz_in_flat(dequant_out_zigzag),
        .matrix_out_flat(dct_out_flat)
    );

endmodule