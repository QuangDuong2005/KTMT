`timescale 1ns/1ps

module mcu_manager (
    input wire clk,
    input wire rst_n,
    // Inputs from IDCT
    input wire signed [15:0] block_in [0:63],
    input wire block_valid,
    // Component Info
    input wire [2:0] comp_h_samp [0:2],
    input wire [2:0] comp_v_samp [0:2],
    // Image Dimensions
    input wire [15:0] img_width,
    input wire [15:0] img_height,
    
    output reg image_complete, // Signals full image decode
    // Output Pixels
    output reg [7:0] r_out, g_out, b_out,
    output reg pixel_valid,
    output wire ready
);

    // Buffers
    reg signed [15:0] y_blocks [0:3][0:63];
    reg signed [15:0] cb_block [0:63];
    reg signed [15:0] cr_block [0:63];

    // State
    reg [2:0] blk_count;
    reg flushing;
    reg [3:0] row, col; // 0..7 or 0..15
    reg mode_420;

    // MCU Counters
    reg [31:0] mcu_process_cnt;
    reg [31:0] mcu_total_cnt;

    integer i;

    // 1. Detect Mode (Continuously tracks input)
    always @(posedge clk) begin
        if (comp_h_samp[0] == 3'd2 && comp_v_samp[0] == 3'd2) 
            mode_420 <= 1'b1;
        else 
            mode_420 <= 1'b0;
    end

    // 2. Main Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            blk_count <= 0;
            flushing <= 0;
            row <= 0;
            col <= 0;
            pixel_valid <= 0;
            mcu_process_cnt <= 0;
            mcu_total_cnt <= 0;
            image_complete <= 0;
            // Reset buffers (optional)
        end else begin
            
            // --- FIX: Calculate Total MCUs ---
            // We wait for 'block_valid' to ensure the Header Parser has finished 
            // and mode_420 is stable. We latch it so it only calculates once.
            if (mcu_total_cnt == 0 && block_valid) begin
                if (mode_420) 
                    // 4:2:0 -> MCU is 16x16 pixels
                    mcu_total_cnt <= ((img_width + 15) >> 4) * ((img_height + 15) >> 4);
                else 
                    // 4:4:4 -> MCU is 8x8 pixels
                    mcu_total_cnt <= ((img_width + 7) >> 3) * ((img_height + 7) >> 3);
            end

            // --- Logic: Data Collection ---
            if (block_valid && !flushing && !image_complete) begin
                pixel_valid <= 0; // FIX: Ensure we don't output valid pixels while loading
                if (!mode_420) begin // 4:4:4 (3 blocks per MCU)
                    case (blk_count)
                        0: begin 
                            for(i=0; i<64; i=i+1) y_blocks[0][i] <= block_in[i]; 
                            blk_count <= 1; 
                        end
                        1: begin 
                            for(i=0; i<64; i=i+1) cb_block[i] <= block_in[i]; 
                            blk_count <= 2; 
                        end
                        2: begin
                            for(i=0; i<64; i=i+1) cr_block[i] <= block_in[i];
                            blk_count <= 0;
                            flushing <= 1; // Start Output
                        end
                    endcase
                end else begin // 4:2:0 (6 blocks per MCU)
                    if (blk_count < 4) begin
                        for(i=0; i<64; i=i+1) y_blocks[blk_count][i] <= block_in[i];
                        blk_count <= blk_count + 1;
                    end else if (blk_count == 4) begin
                        for(i=0; i<64; i=i+1) cb_block[i] <= block_in[i];
                        blk_count <= 5;
                    end else begin
                        for(i=0; i<64; i=i+1) cr_block[i] <= block_in[i];
                        blk_count <= 0;
                        flushing <= 1; // Start Output
                    end
                end
            end 
            // --- Logic: Flush Data (Pixel Generation) ---
            else if (flushing) begin
                pixel_valid <= 1;
                // Counters
                if (!mode_420) begin // 8x8 Block logic
                    if (col == 7) begin
                        col <= 0;
                        if (row == 7) begin
                            row <= 0;
                            flushing <= 0; // DONE MCU
                            mcu_process_cnt <= mcu_process_cnt + 1;
                        end else row <= row + 1;
                    end else col <= col + 1;
                end else begin // 16x16 Block logic
                    if (col == 15) begin
                        col <= 0;
                        if (row == 15) begin
                            row <= 0;
                            flushing <= 0; // DONE MCU
                            mcu_process_cnt <= mcu_process_cnt + 1;
                        end else row <= row + 1;
                    end else col <= col + 1;
                end
            end else begin
                pixel_valid <= 0;
            end

            // --- FIX: Image Complete Check ---
            // Only triggers if we have a valid total count
            if (mcu_total_cnt > 0 && mcu_process_cnt >= mcu_total_cnt) begin
                image_complete <= 1;
                $display("MCU: Image Complete! Total=%d", mcu_total_cnt);
            end
        end
    end

    // Debug State Changes
    always @(posedge clk) begin
        // if (block_valid && !flushing && !image_complete)
        //      $display("MCU: Accepted Block. BlkCount=%d, Mode420=%d", blk_count, mode_420);
        
        // if (flushing)
        //      $display("MCU: Flushing... Row=%d, Col=%d, MCU_Cnt=%d", row, col, mcu_process_cnt);
             
        // if (!ready)
        //      $display("MCU: Busy/NotReady. Flush=%d, ImgComp=%d", flushing, image_complete);
    end

    // --- Ready Signal ---
    assign ready = !flushing && !image_complete;

    // --- Color Conversion Logic (Combinational) ---
    reg signed [15:0] y_val, cb_val, cr_val;
    reg [2:0] r_s, c_s; // sub-indices

    always @(*) begin
        y_val = 0; cb_val = 0; cr_val = 0;
        r_s = 0; c_s = 0; // default
        if (!mode_420) begin
            y_val = y_blocks[0][row*8 + col];
            cb_val = cb_block[row*8 + col];
            cr_val = cr_block[row*8 + col];
        end else begin
            // Map 16x16 (row,col) to specific Y block
            r_s = row[2:0];
            c_s = col[2:0];
            
            case({row[3], col[3]})
                2'b00: y_val = y_blocks[0][r_s*8 + c_s];
                2'b01: y_val = y_blocks[1][r_s*8 + c_s];
                2'b10: y_val = y_blocks[2][r_s*8 + c_s];
                2'b11: y_val = y_blocks[3][r_s*8 + c_s];
            endcase
            
            // Upsample Cb/Cr (Nearest Neighbor)
            cb_val = cb_block[(row>>1)*8 + (col>>1)];
            cr_val = cr_block[(row>>1)*8 + (col>>1)];
        end
    end

    // YCbCr -> RGB Logic
    wire signed [31:0] r_calc, g_calc, b_calc;
    wire signed [31:0] y_shift = (y_val + 128) * 1024;

    assign r_calc = y_shift + cr_val * 1436;
    assign g_calc = y_shift - cb_val * 352 - cr_val * 731;
    assign b_calc = y_shift + cb_val * 1815;

    function [7:0] clamp(input signed [31:0] val);
        if (val < 0) clamp = 0;
        else if (val > 255*1024) clamp = 255;
        else clamp = val[17:10]; // Divide by 1024
    endfunction

    always @(posedge clk) begin
        if (flushing) begin
            r_out <= clamp(r_calc);
            g_out <= clamp(g_calc);
            b_out <= clamp(b_calc);
        end
    end

endmodule