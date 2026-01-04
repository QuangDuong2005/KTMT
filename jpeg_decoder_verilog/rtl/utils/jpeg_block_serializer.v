module jpeg_block_serializer (
    input wire clk,
    input wire rst_n,
    
    // Input Block (64 bytes)
    input wire block_valid,
    input wire [511:0] block_in,
    output reg ready,

    // Output Pixels
    output reg pixel_valid,
    output reg [7:0] pixel_out,
    output reg block_done // Pulse báo hiệu xong 1 block
);

    reg active;
    reg [5:0] cnt;
    reg [511:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready <= 1;
            active <= 0;
            pixel_valid <= 0;
            pixel_out <= 0;
            block_done <= 0;
            cnt <= 0;
            shift_reg <= 0;
        end else begin
            block_done <= 0; // Mặc định về 0

            if (ready && block_valid) begin
                ready <= 0;
                active <= 1;
                shift_reg <= block_in; // Load dữ liệu
                cnt <= 0;
                // Output pixel đầu tiên ngay lập tức
                pixel_out <= block_in[7:0]; 
                pixel_valid <= 1;
            end else if (active) begin
                if (cnt == 63) begin
                    active <= 0;
                    ready <= 1;
                    pixel_valid <= 0;
                    block_done <= 1; // Pulse xong
                end else begin
                    cnt <= cnt + 1;
                    // Dịch 8 bit
                    shift_reg <= {8'h00, shift_reg[511:8]};
                    // Output pixel tiếp theo (cần lấy từ shift_reg mới ở chu kỳ sau? 
                    // Cách viết này lấy shift_reg[15:8] cho chu kỳ sau)
                    pixel_out <= shift_reg[15:8]; 
                    pixel_valid <= 1;
                end
            end else begin
                pixel_valid <= 0;
            end
        end
    end
endmodule