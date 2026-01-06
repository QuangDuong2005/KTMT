module mcu_manager (
    input wire clk,
    input wire rst_n,
    
    // =========================================================
    // DỮ LIỆU ĐẦU VÀO TỪ KHỐI IDCT
    // block_in chứa 1 block 8x8 (64 hệ số sau IDCT)
    // block_valid báo hiệu block hiện tại hợp lệ
    // =========================================================
    input wire signed [15:0] block_in [0:63],
    input wire block_valid,

    // =========================================================
    // THÔNG TIN LẤY MẪU (sampling factor) CỦA CÁC THÀNH PHẦN
    // comp_h_samp[0], comp_v_samp[0] thường là của Y
    // Dựa vào đây để xác định ảnh là 4:4:4 hay 4:2:0
    // =========================================================
    input wire [2:0] comp_h_samp [0:2],
    input wire [2:0] comp_v_samp [0:2],

    // =========================================================
    // ĐẦU RA PIXEL RGB
    // pixel_valid = 1 khi pixel RGB hợp lệ
    // =========================================================
    output reg [7:0] r_out,
    output reg [7:0] g_out,
    output reg [7:0] b_out,
    output reg pixel_valid,

    // ready = 1 nghĩa là module sẵn sàng nhận block mới
    output wire ready
);

    // =========================================================
    // 1. KHAI BÁO TRẠNG THÁI & CHẾ ĐỘ HOẠT ĐỘNG
    // =========================================================

    // Đếm số block đã nhận trong 1 MCU
    reg [3:0] blk_count;

    // Định nghĩa chế độ màu
    localparam MODE_444 = 0; // Y, Cb, Cr cùng độ phân giải
    localparam MODE_420 = 1; // Y có độ phân giải cao hơn

    // mode xác định ảnh hiện tại là 4:4:4 hay 4:2:0
    reg mode;

    // =========================================================
    // 2. BUFFER LƯU BLOCK SAU IDCT
    // =========================================================

    // Với 4:2:0: cần 4 block Y (16x16)
    reg signed [15:0] y_blocks [0:3][0:63];

    // Cb, Cr chỉ có 1 block cho cả MCU
    reg signed [15:0] cb_block [0:63];
    reg signed [15:0] cr_block [0:63];

    // =========================================================
    // 3. BIẾN ĐIỀU KHIỂN XUẤT PIXEL
    // =========================================================

    // flushing = 1 khi đã nhận đủ block và đang xuất pixel
    reg flushing;

    // row, col: vị trí pixel hiện tại trong MCU
    // 4:4:4  → 8x8
    // 4:2:0  → 16x16
    reg [7:0] row, col;

    // =========================================================
    // 4. PHÁT HIỆN CHẾ ĐỘ LẤY MẪU (4:4:4 hay 4:2:0)
    // =========================================================
    always @(posedge clk) begin
        // Nếu Y có h = 2 và v = 2 → 4:2:0
        if (comp_h_samp[0] == 2 && comp_v_samp[0] == 2)
            mode <= MODE_420;
        else
            mode <= MODE_444;
    end

    // =========================================================
    // 5. LOGIC NHẬN BLOCK & LƯU VÀO BUFFER
    // =========================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            blk_count   <= 0;
            flushing    <= 0;
            row         <= 0;
            col         <= 0;
            pixel_valid <= 0;
        end else begin
            pixel_valid <= 0; // mặc định không xuất pixel

            // ==============================
            // NHẬN BLOCK KHI CHƯA FLUSH
            // ==============================
            if (block_valid && !flushing) begin

                // ---------- MODE 4:4:4 ----------
                // Thứ tự block: Y → Cb → Cr
                if (mode == MODE_444) begin
                    if (blk_count == 0) begin
                        for(i=0;i<64;i=i+1)
                            y_blocks[0][i] <= block_in[i];
                        blk_count <= 1;
                    end else if (blk_count == 1) begin
                        for(i=0;i<64;i=i+1)
                            cb_block[i] <= block_in[i];
                        blk_count <= 2;
                    end else if (blk_count == 2) begin
                        for(i=0;i<64;i=i+1)
                            cr_block[i] <= block_in[i];
                        blk_count <= 0;
                        flushing  <= 1; // bắt đầu xuất pixel
                        row <= 0; col <= 0;
                    end
                end 

                // ---------- MODE 4:2:0 ----------
                // Thứ tự block: Y0 Y1 Y2 Y3 → Cb → Cr
                else begin
                    if (blk_count < 4) begin
                        for(i=0;i<64;i=i+1)
                            y_blocks[blk_count][i] <= block_in[i];
                        blk_count <= blk_count + 1;
                    end else if (blk_count == 4) begin
                        for(i=0;i<64;i=i+1)
                            cb_block[i] <= block_in[i];
                        blk_count <= 5;
                    end else if (blk_count == 5) begin
                        for(i=0;i<64;i=i+1)
                            cr_block[i] <= block_in[i];
                        blk_count <= 0;
                        flushing  <= 1;
                        row <= 0; col <= 0;
                    end
                end
            end

            // =================================================
            // 6. LOGIC QUÉT PIXEL TRONG MCU
            // =================================================
            if (flushing) begin
                pixel_valid <= 1;

                // ---- 4:4:4 → quét 8x8 ----
                if (mode == MODE_444) begin
                    if (col == 7) begin
                        col <= 0;
                        if (row == 7) begin
                            row <= 0;
                            flushing <= 0; // kết thúc MCU
                        end else row <= row + 1;
                    end else col <= col + 1;
                end 

                // ---- 4:2:0 → quét 16x16 ----
                else begin
                    if (col == 15) begin
                        col <= 0;
                        if (row == 15) begin
                            row <= 0;
                            flushing <= 0;
                        end else row <= row + 1;
                    end else col <= col + 1;
                end
            end
        end
    end

    // =========================================================
    // 7. LẤY GIÁ TRỊ Y, Cb, Cr THEO PIXEL
    // =========================================================
    reg signed [15:0] y_val, cb_val, cr_val;

    always @(*) begin
        y_val = 0; cb_val = 0; cr_val = 0;

        // ---------- 4:4:4 ----------
        if (mode == MODE_444) begin
            y_val  = y_blocks[0][row*8 + col];
            cb_val = cb_block[row*8 + col];
            cr_val = cr_block[row*8 + col];
        end 
        // ---------- 4:2:0 ----------
        else begin
            // Chọn block Y phù hợp (Y0..Y3)
            reg [2:0] y_blk;
            reg [3:0] r_l, c_l;

            if (row < 8) begin
                if (col < 8) begin y_blk=0; r_l=row;     c_l=col;     end
                else          begin y_blk=1; r_l=row;     c_l=col-8;   end
            end else begin
                if (col < 8) begin y_blk=2; r_l=row-8;   c_l=col;     end
                else          begin y_blk=3; r_l=row-8;   c_l=col-8;   end
            end

            y_val = y_blocks[y_blk][r_l*8 + c_l];

            // Cb/Cr bị subsample → dùng row/2, col/2
            cb_val = cb_block[(row>>1)*8 + (col>>1)];
            cr_val = cr_block[(row>>1)*8 + (col>>1)];
        end
    end

    // =========================================================
    // 8. CHUYỂN YCbCr → RGB + LEVEL SHIFT + SATURATION
    // =========================================================
    wire signed [31:0] R_calc, G_calc, B_calc;

    localparam C_1_402 = 1436;
    localparam C_0_344 = 352;
    localparam C_0_714 = 731;
    localparam C_1_772 = 1815;

    // Level shift chỉ áp dụng cho Y và thực hiện chuyển đổi YCbCr sang RGB theo công thức
    assign R_calc = (y_val + 128)*1024 + cr_val*C_1_402;
    assign G_calc = (y_val + 128)*1024 - cb_val*C_0_344 - cr_val*C_0_714;
    assign B_calc = (y_val + 128)*1024 + cb_val*C_1_772;

    always @(posedge clk) begin
        if (flushing) begin
            r_out <= (R_calc < 0) ? 0 :
                     (R_calc > 255*1024) ? 255 : R_calc[19:10];
            g_out <= (G_calc < 0) ? 0 :
                     (G_calc > 255*1024) ? 255 : G_calc[19:10];
            b_out <= (B_calc < 0) ? 0 :
                     (B_calc > 255*1024) ? 255 : B_calc[19:10];
        end
    end

    // Sẵn sàng nhận MCU mới khi không flush
    assign ready = !flushing;

endmodule
