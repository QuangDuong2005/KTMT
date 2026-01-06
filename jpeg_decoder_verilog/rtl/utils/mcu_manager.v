module mcu_manager (
    input wire clk,
    input wire rst_n,
    
    // Inputs from IDCT
    input wire signed [15:0] block_in [0:63],
    input wire block_valid, // Tells us a new block is available on block_in

    // Component Info
    input wire [2:0] comp_h_samp [0:2],
    input wire [2:0] comp_v_samp [0:2],

    // Output Pixels
    output reg [7:0] r_out,
    output reg [7:0] g_out,
    output reg [7:0] b_out,
    output reg pixel_valid,
    output wire ready
);

    // Internal State
    reg [3:0] blk_count;
    localparam MODE_444 = 0;
    localparam MODE_420 = 1;
    reg mode; // 0 for 4:4:4, 1 for 4:2:0

    // Buffers
    reg signed [15:0] y_blocks [0:3][0:63];
    reg signed [15:0] cb_block [0:63];
    reg signed [15:0] cr_block [0:63];

    reg flushing;
    reg [7:0] row, col; // 0..15 for 4:2:0

    // Detect Mode
    always @(posedge clk) begin
        if (comp_h_samp[0] == 2 && comp_v_samp[0] == 2) mode <= MODE_420;
        else mode <= MODE_444;
    end

    // Input Logic: Store Blocks
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            blk_count <= 0;
            flushing <= 0;
            row <= 0;
            col <= 0;
            pixel_valid <= 0;
        end else begin
            pixel_valid <= 0; // Default off

            if (block_valid && !flushing) begin
                if (mode == MODE_444) begin
                    // Sequence: Y, Cb, Cr
                    if (blk_count == 0) begin
                        for(i=0;i<64;i=i+1) y_blocks[0][i] <= block_in[i];
                        blk_count <= 1;
                    end else if (blk_count == 1) begin
                        for(i=0;i<64;i=i+1) cb_block[i] <= block_in[i];
                        blk_count <= 2;
                    end else if (blk_count == 2) begin
                        for(i=0;i<64;i=i+1) cr_block[i] <= block_in[i];
                        blk_count <= 0;
                        flushing <= 1; // Start outputting
                        row <= 0; col <= 0;
                    end
                end 
                else begin // MODE_420
                    // Sequence: Y0, Y1, Y2, Y3, Cb, Cr
                    if (blk_count < 4) begin
                        for(i=0;i<64;i=i+1) y_blocks[blk_count][i] <= block_in[i];
                        blk_count <= blk_count + 1;
                    end else if (blk_count == 4) begin
                        for(i=0;i<64;i=i+1) cb_block[i] <= block_in[i];
                        blk_count <= 5;
                    end else if (blk_count == 5) begin
                        for(i=0;i<64;i=i+1) cr_block[i] <= block_in[i];
                        blk_count <= 0;
                        flushing <= 1;
                        row <= 0; col <= 0;
                    end
                end
            end

            if (flushing) begin
                pixel_valid <= 1;
                
                // --- Color Conversion & Output ---
                // Gets values from buffers based on row/col and mode
                // See Logic Below
                
                // Logic to advance row/col
                if (mode == MODE_444) begin
                    // 8x8 Block
                    if (col == 7) begin
                        col <= 0;
                        if (row == 7) begin
                            row <= 0;
                            flushing <= 0;
                            pixel_valid <= 1; // Last pixel
                        end else row <= row + 1;
                    end else col <= col + 1;
                end else begin
                    // 16x16 Block
                    if (col == 15) begin
                        col <= 0;
                        if (row == 15) begin
                            row <= 0;
                            flushing <= 0;
                            pixel_valid <= 1; // Last pixel
                        end else row <= row + 1;
                    end else col <= col + 1;
                end
            end
        end
    end

    // Combinational Logic for Output Values
    reg signed [15:0] y_val, cb_val, cr_val;
    reg signed [15:0] r_raw, g_raw, b_raw;
    
    always @(*) begin
        y_val = 0; cb_val = 0; cr_val = 0;
        
        if (mode == MODE_444) begin
            y_val  = y_blocks[0][row*8 + col];
            cb_val = cb_block[row*8 + col];
            cr_val = cr_block[row*8 + col];
        end else begin
            // 4:2:0 Logic
            // Determine which Y block
            // Y0: r<8, c<8. Y1: r<8, c>=8. Y2: r>=8, c<8. Y3: r>=8, c>=8.
            // Map 0..15 to 0..7
            
            reg [2:0] y_blk_select;
            reg [3:0] r_local, c_local;

            if (row < 8) begin
                 if (col < 8) begin y_blk_select = 0; r_local = row; c_local = col; end
                 else begin y_blk_select = 1; r_local = row; c_local = col - 8; end
            end else begin
                 if (col < 8) begin y_blk_select = 2; r_local = row - 8; c_local = col; end
                 else begin y_blk_select = 3; r_local = row - 8; c_local = col - 8; end
            end
            
            y_val = y_blocks[y_blk_select][r_local*8 + c_local];

            // Cb, Cr are subsampled (one block defines 16x16)
            // So pixel (row,col) maps to Cb pixel (row/2, col/2)
            cb_val = cb_block[(row>>1)*8 + (col>>1)];
            cr_val = cr_block[(row>>1)*8 + (col>>1)];
        end

        // YCbCr to RGB
        // Using standard formula (approximate)
        // R = Y + 1.402 * Cr
        // G = Y - 0.344136 * Cb - 0.714136 * Cr
        // B = Y + 1.772 * Cb
        
        // Note: IDCT output is typically -128..127? 
        // No, `jpeg_idct_2d` output is usually raw expanded range?
        // In top module, there was +128 logic.
        // We should add 128 to Y?
        // Standard IDCT output is centered around 0 (AC) and DC is ... 
        // Wait, typical JPEG flow:
        // Y = IDCT(Y) + 128
        // Cb = IDCT(Cb)
        // Cr = IDCT(Cr)
        
        // Let's assume IDCT outputs are signed.
        
        // Floating point to integer optimization:
        // R = Y + (Cr * 143566) >> 17  (1.402 * 2^x)
        // Simple Fixed Point (x1024):
        // R = Y + (1.402 * Cr) -> Y + (1436 * Cr) / 1024
        // G = Y - (352 * Cb) / 1024 - (731 * Cr) / 1024
        // B = Y + (1815 * Cb) / 1024
        
        // Level Shift Y blocks ONLY? 
        // Usually you level shift Y. Cb/Cr are centered at 0.
        // The previous code did +128 for grayscale.
        
        // Correct implementation:
        // y_shifted = y_val + 128;
    end
    
    wire signed [31:0] R_calc, G_calc, B_calc;
    // Multipliers (x1024)
    localparam C_1_402 = 1436;
    localparam C_0_344 = 352;
    localparam C_0_714 = 731;
    localparam C_1_772 = 1815;

    assign R_calc = (y_val + 128) * 1024 + cr_val * C_1_402;
    assign G_calc = (y_val + 128) * 1024 - cb_val * C_0_344 - cr_val * C_0_714;
    assign B_calc = (y_val + 128) * 1024 + cb_val * C_1_772;

    always @(posedge clk) begin // Register output for timing
       if (flushing) begin
           // Clamp and Shift
           if (R_calc[31] || R_calc < 0) r_out <= 0;
           else if (R_calc > 255*1024) r_out <= 255;
           else r_out <= R_calc[19:10]; // >> 10

           if (G_calc[31] || G_calc < 0) g_out <= 0;
           else if (G_calc > 255*1024) g_out <= 255;
           else g_out <= G_calc[19:10];

           if (B_calc[31] || B_calc < 0) b_out <= 0;
           else if (B_calc > 255*1024) b_out <= 255;
           else b_out <= B_calc[19:10];
       end
    end

    assign ready = !flushing;

endmodule
