`timescale 1ns / 1ps

module jpeg_ycbcr_to_rgb #(
    parameter IMG_WIDTH = 2048
)(
    input  wire        clk,
    input  wire        rst_n,      
    input  wire        valid_in,
    input  wire [1:0]  subsample_mode,
    
    // Input từ IDCT
    input  wire signed [8:0] y_idct,
    input  wire signed [8:0] cb_idct,
    input  wire signed [8:0] cr_idct,

    // Output ra màn hình
    output reg  [7:0]  r_out,
    output reg  [7:0]  g_out,
    output reg  [7:0]  b_out,
    output reg         valid_out
);

    // 1. Pixel Counter
    reg [15:0] x;
    reg y_lsb;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 0;
            y_lsb <= 0;
        end else if (valid_in) begin
            if (x == IMG_WIDTH-1) begin
                x <= 0;
                y_lsb <= ~y_lsb; // Đảo bit LSB của y mỗi khi hết dòng
            end else begin
                x <= x + 1;
            end
        end
    end

    // 2. Upsampling & Latch (Bilinear Horizontal)
    reg signed [8:0] cb_lat, cr_lat;
    reg signed [8:0] cb_prev, cr_prev;
    wire latch_cbcr;

    // Logic xác định khi nào cần lấy mẫu Cb/Cr mới
    assign latch_cbcr = (subsample_mode == 2'b00) ? valid_in :
                        (subsample_mode == 2'b01) ? (valid_in && (x[0] == 0)) :
                        (subsample_mode == 2'b10) ? (valid_in && (x[0] == 0) && (y_lsb == 0)) : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cb_lat <= 0; cr_lat <= 0;
            cb_prev <= 0; cr_prev <= 0;
        end else if (latch_cbcr) begin
            cb_prev <= cb_lat;
            cr_prev <= cr_lat;
            cb_lat <= cb_idct;
            cr_lat <= cr_idct;
        end
    end

    // Nội suy mượt theo phương ngang
    wire signed [9:0] cb_interp;
    assign cb_interp = (subsample_mode == 2'b00) ? $signed({cb_lat[8], cb_lat}) :
                       (x[0] == 0) ? $signed({cb_lat[8], cb_lat}) :
                       ($signed({cb_lat[8], cb_lat}) + $signed({cb_prev[8], cb_prev})) >>> 1;

    wire signed [9:0] cr_interp;
    assign cr_interp = (subsample_mode == 2'b00) ? $signed({cr_lat[8], cr_lat}) :
                       (x[0] == 0) ? $signed({cr_lat[8], cr_lat}) :
                       ($signed({cr_lat[8], cr_lat}) + $signed({cr_prev[8], cr_prev})) >>> 1;

    // 3. Color Space Conversion (BT.601 Fixed-point x256)
    // YCbCr -> RGB
    // R = Y + 1.402 * Cr
    // G = Y - 0.344136 * Cb - 0.714136 * Cr
    // B = Y + 1.772 * Cb
    
    // Level shift: JPEG YCbCr input is centered at 0 (-128 to 127). RGB output is 0 to 255.
    // Thực tế input IDCT đã là signed +/-. Ta cần cộng 128 vào Y để về range 0-255 trước khi convert
    wire signed [10:0] y_val = y_idct + 11'sd128; 
    wire signed [10:0] cb_off = cb_interp; // Cb đã centered tại 0
    wire signed [10:0] cr_off = cr_interp; // Cr đã centered tại 0

    wire signed [23:0] r_full, g_full, b_full;

    // Hệ số nhân (x256): 1.402->359, 0.344->88, 0.714->183, 1.772->454
    assign r_full = ($signed({13'd0, y_val}) << 8) + (cr_off * 11'sd359);
    assign g_full = ($signed({13'd0, y_val}) << 8) - (cb_off * 11'sd88) - (cr_off * 11'sd183);
    assign b_full = ($signed({13'd0, y_val}) << 8) + (cb_off * 11'sd454);

    // Dịch bit để chia 256
    wire signed [23:0] r_sh = r_full >>> 8;
    wire signed [23:0] g_sh = g_full >>> 8;
    wire signed [23:0] b_sh = b_full >>> 8;

    // 4. Output Logic với Saturation (Kẹp giá trị 0-255)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_out <= 0; g_out <= 0; b_out <= 0; valid_out <= 0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                // Red Saturation
                if (r_sh[23]) r_out <= 8'd0; // Âm -> 0
                else if (|r_sh[22:8]) r_out <= 8'd255; // Lớn hơn 255 -> 255
                else r_out <= r_sh[7:0];

                // Green Saturation
                if (g_sh[23]) g_out <= 8'd0;
                else if (|g_sh[22:8]) g_out <= 8'd255;
                else g_out <= g_sh[7:0];

                // Blue Saturation
                if (b_sh[23]) b_out <= 8'd0;
                else if (|b_sh[22:8]) b_out <= 8'd255;
                else b_out <= b_sh[7:0];
            end
        end
    end

endmodule