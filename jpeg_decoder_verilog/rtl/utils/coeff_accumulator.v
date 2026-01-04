`timescale 1ns / 1ps

module coeff_accumulator #(
    parameter WIDTH = 12 // Độ rộng hệ số DCT từ Entropy Decoder
)(
    input  wire        clk,
    input  wire        rst_n,

    // --- Input từ Entropy Decoder (Serial Stream) ---
    input  wire signed [WIDTH-1:0] coeff_in,      // Giá trị hệ số
    input  wire        [5:0]       coeff_index,   // Vị trí trong block (0-63)
    input  wire                    coeff_valid,   // Báo hiệu có hệ số mới
    input  wire                    block_done,    // Báo hiệu đã xong 1 block (gặp EOB hoặc đủ 64 số)

    // --- Output sang Transform Block (Parallel Block) ---
    // Output là một vector phẳng khổng lồ chứa 64 hệ số
    output reg  signed [WIDTH*64-1:0] block_out_flat,
    output reg                        block_valid,
    input  wire                       block_ready // Tín hiệu từ module sau báo đã xử lý xong
);

    // Bộ nhớ đệm (Buffer) lưu tạm 64 hệ số của block đang xây dựng
    reg signed [WIDTH-1:0] buffer [0:63];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_valid <= 1'b0;
            block_out_flat <= {(WIDTH*64){1'b0}};
            for (i = 0; i < 64; i = i + 1) begin
                buffer[i] <= {WIDTH{1'b0}};
            end
        end else begin
            // 1. Logic Ghi vào Buffer (Accumulate)
            if (coeff_valid) begin
                buffer[coeff_index] <= coeff_in;
            end

            // 2. Logic Bắn Block đi (Dispatch)
            if (block_done) begin
                block_valid <= 1'b1;
                
                // "Phẳng hóa" (Flatten) mảng buffer thành 1 vector dài
                // Lưu ý: Đây là logic tuần tự, cập nhật tại clock edge
                // coeff_in cuối cùng (nếu có cùng lúc với block_done) cần được xử lý cẩn thận
                // Trong thiết kế này, giả định coeff cuối cùng đã được ghi vào buffer hoặc 
                // block_done đến sau coeff cuối cùng 1 chu kỳ.
                
                // Để an toàn và đơn giản, ta copy toàn bộ buffer ra output
                // Nếu coeff_valid và block_done cùng lúc, ta cần ghi coeff đó vào vị trí tương ứng trong output luôn
                for (i = 0; i < 64; i = i + 1) begin
                    if (coeff_valid && (coeff_index == i)) 
                        block_out_flat[(i*WIDTH) +: WIDTH] <= coeff_in;
                    else
                        block_out_flat[(i*WIDTH) +: WIDTH] <= buffer[i];
                end

                // Reset buffer chuẩn bị cho block mới (QUAN TRỌNG: AC coefficients thường là 0)
                // Ta reset ngay sau khi bắn dữ liệu đi
                for (i = 0; i < 64; i = i + 1) begin
                    buffer[i] <= {WIDTH{1'b0}};
                end

            end else if (block_valid && block_ready) begin
                // Nếu module sau đã nhận xong (Handshake thành công), hạ cờ valid
                block_valid <= 1'b0;
            end
        end
    end

endmodule