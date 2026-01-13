`timescale 1ns / 1ps

module jpeg_ycbcr_to_rgb #(
    parameter IMG_WIDTH = 2048
)(
    input  wire        clk,
    input  wire        rst_n,      
    input  wire        valid_in,
    input  wire [1:0]  subsample_mode,
    
    input  wire signed [8:0] y_idct,
    input  wire signed [8:0] cb_idct,
    input  wire signed [8:0] cr_idct,

    output reg  [7:0]  r_out,
    output reg  [7:0]  g_out,
    output reg  [7:0]  b_out,
    output reg         valid_out
);

    // 1. Pixel Counter (Giữ nguyên logic của bạn)
    reg [15:0] x;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) x <= 0;
        else if (valid_in) x <= (x == IMG_WIDTH-1) ? 0 : x + 1;
    end

    // 2. Latch Cb/Cr (Mặc định là 0 trong miền signed = trung tính)
    reg signed [8:0] cb_lat, cr_lat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cb_lat <= 9'sd0; cr_lat <= 9'sd0; 
        end else if (valid_in) begin
            cb_lat <= cb_idct;
            cr_lat <= cr_idct;
        end
    end

    // 3. Color Space Conversion (BT.601)
    wire signed [10:0] y_val  = y_idct + 11'sd128; // Shift Y về 0-255
    wire signed [23:0] r_full, g_full, b_full;

    // R = Y + 1.402*Cr | G = Y - 0.344*Cb - 0.714*Cr | B = Y + 1.772*Cb
    assign r_full = ($signed({13'd0, y_val}) << 8) + (cr_lat * 11'sd359);
    assign g_full = ($signed({13'd0, y_val}) << 8) - (cb_lat * 11'sd88) - (cr_lat * 11'sd183);
    assign b_full = ($signed({13'd0, y_val}) << 8) + (cb_lat * 11'sd454);

    wire signed [23:0] r_sh = r_full >>> 8;
    wire signed [23:0] g_sh = g_full >>> 8;
    wire signed [23:0] b_sh = b_full >>> 8;

    // 4. Output với Saturation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_out <= 0; g_out <= 0; b_out <= 0; valid_out <= 0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                r_out <= (r_sh[23]) ? 8'd0 : (|r_sh[22:8]) ? 8'd255 : r_sh[7:0];
                g_out <= (g_sh[23]) ? 8'd0 : (|g_sh[22:8]) ? 8'd255 : g_sh[7:0];
                b_out <= (b_sh[23]) ? 8'd0 : (|b_sh[22:8]) ? 8'd255 : b_sh[7:0];
            end
        end
    end
endmodule