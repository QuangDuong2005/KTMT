module jpeg_transform_block
#(
    parameter WIDTH_IN  = 16,
    parameter WIDTH_OUT = 32
)
(
    input  wire signed [WIDTH_IN*64-1:0]  zz_in_flat, // Input: Hệ số Zigzag
    input  wire        [WIDTH_IN*64-1:0]  quant_flat, // Input: Bảng Q (được nạp từ TB)
    output wire signed [WIDTH_OUT*64-1:0] dct_out_flat // Output: Kết quả cuối
);


    // Dây nối giữa Inverse Zigzag và Dequant
    wire signed [WIDTH_IN*64-1:0] matrix_row_major;


    // 1. Inverse Zigzag: Sắp xếp lại vị trí (Zigzag -> Row Major)
    // (Đảm bảo bạn dùng file inverse_zigzag.v đã fix ở bước trước)
    jpeg_inverse_zigzag #(.WIDTH(WIDTH_IN)) i_zz (
        .zz_in_flat(zz_in_flat),
        .matrix_out_flat(matrix_row_major)
    );


    // 2. Dequantization: Nhân với bảng Q
    jpeg_dequant #(
        .WIDTH_IN(WIDTH_IN),
        .WIDTH_Q(WIDTH_IN),
        .WIDTH_OUT(WIDTH_OUT)
    ) deq (
        .matrix_in_flat(matrix_row_major),
        .quant_flat(quant_flat),
        .dct_out_flat(dct_out_flat)
    );


endmodule
