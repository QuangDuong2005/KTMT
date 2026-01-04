`timescale 1ns / 1ps
module jpeg_bitstream_reader (
    input  wire       clk,
    input  wire       rst_n,
    // Input Byte
    input  wire [7:0] byte_in,
    input  wire       byte_valid,
    output reg        byte_ready, 
    // Output Bit
    output wire       bit_out,
    output reg        bit_valid,
    input  wire       bit_ready
);

    reg [7:0] shift_reg;        
    reg [2:0] bit_cnt;          
    reg       has_data;         
    reg       prev_byte_was_ff; 

    // Bit output luôn là MSB của thanh ghi dịch
    assign bit_out = shift_reg[7];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 8'd0;
            bit_cnt   <= 3'd7;
            has_data  <= 1'b0;
            bit_valid <= 1'b0;
            byte_ready <= 1'b1;
            prev_byte_was_ff <= 1'b0;
        end else begin
            
            // ---------------------------------------------------------
            // 1. LOGIC NẠP BYTE (LOAD)
            // ---------------------------------------------------------
            if (!has_data) begin
                // Nếu chưa có data, bit_valid phải tắt
                // TRỪ KHI: Đây là cycle chuyển giao ngay lập tức (Pipeline)
                // Để an toàn, ta tắt valid khi đói data
                bit_valid <= 1'b0; 
                
                if (byte_valid && byte_ready) begin
                    // --- XỬ LÝ BYTE STUFFING (FF 00 -> Bỏ qua 00) ---
                    if (prev_byte_was_ff && (byte_in == 8'h00)) begin
                        // Skip byte 00, giữ trạng thái ready để nhận byte kế tiếp
                        prev_byte_was_ff <= 1'b0; 
                    end 
                    else begin
                        // Load Byte mới
                        shift_reg  <= byte_in;   
                        bit_cnt    <= 3'd7;      
                        has_data   <= 1'b1;      
                        byte_ready <= 1'b0;      
                        
                        if (byte_in == 8'hFF) prev_byte_was_ff <= 1'b1;
                        else prev_byte_was_ff <= 1'b0;
                    end
                end 
                else begin
                    byte_ready <= 1'b1;
                end
            end 
            
            // ---------------------------------------------------------
            // 2. LOGIC BẮN BIT (SHIFT) - ĐÃ SỬA LỖI TIMING
            // ---------------------------------------------------------
            else begin
                // Luôn bật valid khi đang có data
                bit_valid <= 1'b1; 
                
                // CRITICAL FIX: Thêm điều kiện (bit_valid) vào đây
                // Ý nghĩa: Chỉ dịch khi "Chúng ta đang đưa Valid ra ngoài" VÀ "Họ sẵn sàng nhận"
                // Ở Cycle đầu tiên khi has_data lên 1, bit_valid trong register vẫn là 0 -> KHÔNG DỊCH.
                if (bit_valid && bit_ready) begin
                    if (bit_cnt == 0) begin
                        // Đã bắn xong bit cuối cùng (LSB)
                        has_data   <= 1'b0;      
                        bit_valid  <= 1'b0;      
                        byte_ready <= 1'b1;      
                    end else begin
                        // Dịch trái để đẩy bit tiếp theo lên MSB
                        shift_reg <= {shift_reg[6:0], 1'b0}; 
                        bit_cnt   <= bit_cnt - 1;
                    end
                end
            end
        end
    end
endmodule