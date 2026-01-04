module jpeg_block_serializer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        block_valid,       // Báo khối IDCT đã sẵn sàng
    input  wire [511:0] block_in,         // 64 phần tử x 8 bit = 512 bit (đã trải phẳng)


    output reg         ready,             // Báo cho IDCT biết module đã sẵn sàng nhận khối mới
    output reg         pixel_valid,
    output reg signed [8:0] pixel_out     // Sign-extend lên 9 bit
);


    reg [5:0] idx; // Đếm từ 0 đến 63
    reg reading;
   
    // Tạo mảng nội bộ để dễ truy xuất (tùy chọn, hoặc dùng trực tiếp block_in)
    reg signed [7:0] internal_block [0:63];
    integer i;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx         <= 0;
            reading     <= 0;
            pixel_valid <= 0;
            pixel_out   <= 0;
            ready       <= 1; // Sẵn sàng nhận sau khi reset
        end
        else begin
            if (block_valid && ready) begin
                // Chốt toàn bộ khối dữ liệu vào mảng nội bộ
                for (i = 0; i < 64; i = i + 1) begin
                    internal_block[i] <= block_in[i*8 +: 8];
                end
                reading <= 1;
                ready   <= 0; // Đang bận xử lý, không nhận thêm khối mới
                idx     <= 0;
                pixel_valid <= 0;
            end
            else if (reading) begin
                // Xuất từng pixel một
                pixel_out   <= {internal_block[idx][7], internal_block[idx]}; // Sign-extend
                pixel_valid <= 1;


                if (idx == 63) begin
                    reading <= 0;
                    ready   <= 1; // Xử lý xong, báo sẵn sàng nhận khối tiếp theo
                    idx     <= 0;
                end else begin
                    idx <= idx + 1;
                end
            end
            else begin
                pixel_valid <= 0;
            end
        end
    end
endmodule

