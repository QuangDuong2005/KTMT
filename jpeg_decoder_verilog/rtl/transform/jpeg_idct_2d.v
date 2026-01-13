module jpeg_idct_2d (
    input clk, // Nếu cần pipeline thì dùng clk, ở đây ta làm tổ hợp (combinational) cho đơn giản
    // Đầu vào là mảng 1 chiều 64 phần tử (đại diện ma trận 8x8)
    input signed [15:0] matrix_in [0:63],
    // Đầu ra
    output signed [15:0] matrix_out [0:63]
);


    // --------------------------------------------------------
    // Giai đoạn 1: IDCT 1D theo Hàng (Rows)
    // --------------------------------------------------------
    wire signed [31:0] row_out [0:63]; // Kết quả trung gian sau khi biến đổi hàng
   
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : row_idct
            jpeg_idct_1d u_row (
                .in0({{16{matrix_in[i*8+0][15]}}, matrix_in[i*8+0]}), // Sign extension
                .in1({{16{matrix_in[i*8+1][15]}}, matrix_in[i*8+1]}),
                .in2({{16{matrix_in[i*8+2][15]}}, matrix_in[i*8+2]}),
                .in3({{16{matrix_in[i*8+3][15]}}, matrix_in[i*8+3]}),
                .in4({{16{matrix_in[i*8+4][15]}}, matrix_in[i*8+4]}),
                .in5({{16{matrix_in[i*8+5][15]}}, matrix_in[i*8+5]}),
                .in6({{16{matrix_in[i*8+6][15]}}, matrix_in[i*8+6]}),
                .in7({{16{matrix_in[i*8+7][15]}}, matrix_in[i*8+7]}),
               
                .out0(row_out[i*8+0]),
                .out1(row_out[i*8+1]),
                .out2(row_out[i*8+2]),
                .out3(row_out[i*8+3]),
                .out4(row_out[i*8+4]),
                .out5(row_out[i*8+5]),
                .out6(row_out[i*8+6]),
                .out7(row_out[i*8+7])
            );
        end
    endgenerate


    // --------------------------------------------------------
    // Giai đoạn 2: Chuyển vị (Transpose)
    // Hàng thành Cột để chuẩn bị cho IDCT lần 2
    // --------------------------------------------------------
    wire signed [31:0] transposed_data [0:63];
   
    genvar x, y;
    generate
        for (x = 0; x < 8; x = x + 1) begin : loop_x
            for (y = 0; y < 8; y = y + 1) begin : loop_y
                // Transpose: Hàng i, Cột j -> Hàng j, Cột i
                assign transposed_data[x*8 + y] = row_out[y*8 + x];
            end
        end
    endgenerate


    // --------------------------------------------------------
    // Giai đoạn 3: IDCT 1D theo Cột (Columns - thực chất là Hàng của ma trận đã Transpose)
    // --------------------------------------------------------
    wire signed [31:0] col_out [0:63];
   
    generate
        for (i = 0; i < 8; i = i + 1) begin : col_idct
            jpeg_idct_1d u_col (
                .in0(transposed_data[i*8+0]),
                .in1(transposed_data[i*8+1]),
                .in2(transposed_data[i*8+2]),
                .in3(transposed_data[i*8+3]),
                .in4(transposed_data[i*8+4]),
                .in5(transposed_data[i*8+5]),
                .in6(transposed_data[i*8+6]),
                .in7(transposed_data[i*8+7]),
               
                .out0(col_out[i*8+0]),
                .out1(col_out[i*8+1]),
                .out2(col_out[i*8+2]),
                .out3(col_out[i*8+3]),
                .out4(col_out[i*8+4]),
                .out5(col_out[i*8+5]),
                .out6(col_out[i*8+6]),
                .out7(col_out[i*8+7])
            );
        end
    endgenerate
   
    // --------------------------------------------------------
    // Giai đoạn 4: Transpose ngược lại (tùy chọn) và Gán Output
    // Trong JPEG, sau bước này thường là cộng 128 (Level Shift)
    // Ở đây tôi giữ nguyên giá trị để bạn xử lý ở bước tiếp theo
    // --------------------------------------------------------
    generate
        for (x = 0; x < 8; x = x + 1) begin : out_assign_x
            for (y = 0; y < 8; y = y + 1) begin : out_assign_y
                // Cần transpose lại để về đúng toạ độ x,y ban đầu
                // Cắt bit về 16 bit hoặc 8 bit tùy yêu cầu tiếp theo
                assign matrix_out[x*8 + y] = col_out[y*8 + x][15:0];
            end
        end
    endgenerate


endmodule
