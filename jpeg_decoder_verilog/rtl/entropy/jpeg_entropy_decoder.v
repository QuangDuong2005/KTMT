`timescale 1ns/1ps

module jpeg_entropy_decoder (
    input wire clk,
    input wire rst_n,

    // Huffman Tables
    input wire [15:0] dc0_code [0:255],
    input wire [4:0]  dc0_len  [0:255],
    input wire [15:0] dc1_code [0:255],
    input wire [4:0]  dc1_len  [0:255],
    input wire [15:0] ac0_code [0:255],
    input wire [4:0]  ac0_len  [0:255],
    input wire [15:0] ac1_code [0:255],
    input wire [4:0]  ac1_len  [0:255],

    // Bitstream
    input wire bit_in,
    input wire bit_valid,
    output reg is_reading_bits,

    // Output
    output reg coeff_valid,
    output reg [5:0] coeff_index,
    output reg signed [11:0] coeff_value,
    output reg block_done,
    
    // Flow Control
    input wire output_ready,
    
    // Config
    input wire is_420,
    
    // Debug
    output reg [31:0] dbg_buffer,
    output reg [5:0]  dbg_count
);

    // Integers
    integer k, j;

    // Registers
    reg [31:0] buffer;
    reg [5:0]  cnt;
    reg [3:0]  state;
    
    // Internal state
    reg [5:0] idx; 
    reg [2:0] mcu_blk_cnt; 
    reg signed [11:0] pred_dc_y, pred_dc_cb, pred_dc_cr;
    reg [3:0] size_reg;
    reg [3:0] run_reg;
    reg [4:0] bits_needed;
    
    // FIX: Add register to save AC value during ZR run
    reg signed [11:0] saved_ac_val;

    // Huffman Search Results
    reg found;
    reg [4:0] found_len;
    reg [7:0] found_sym;
    
    // Configuration Constants
    wire [2:0] max_blk_cnt = is_420 ? 3'd5 : 3'd2;
    wire [2:0] y_limit     = is_420 ? 3'd4 : 3'd1;
    reg use_table1;

    // Handshake Logic
    // We request bits if cnt < 24.
    // We accept bits if we requested them (is_reading_bits) AND they are valid.
    wire handshaked_bit = bit_valid && is_reading_bits;

    // FSM States
    localparam S_IDLE       = 4'd0;
    localparam S_HUFF_DC    = 4'd1;
    localparam S_VLI_DC     = 4'd2;
    localparam S_HUFF_AC    = 4'd3;
    localparam S_VLI_AC     = 4'd4;
    localparam S_PROCESS_AC = 4'd5;
    localparam S_ZRL        = 4'd6;
    localparam S_EOB        = 4'd7;

    // ===========================================
    // COMBINATIONAL LOGIC: HUFFMAN SEARCH
    // ===========================================
    always @(*) begin
        if (is_420) use_table1 = (mcu_blk_cnt >= 4);
        else        use_table1 = (mcu_blk_cnt >= 1);
        
        found = 0; 
        found_len = 0; 
        found_sym = 0;
        
        // Search window mask
        // Only run loop if we have at least 1 bit
        if (cnt > 0) begin
           for (k = 1; k <= 16; k = k + 1) begin
               // Don't access buffer if cnt < k
               if (!found && cnt >= k) begin
                   // Extract top k bits
                   // buffer >> (cnt - k)
                   reg [15:0] pattern;
                   pattern = (buffer >> (cnt - k)) & ((32'd1 << k) - 1);
                   
                   for (j = 0; j < 256; j = j + 1) begin
                       if (!found) begin
                           if (state == S_HUFF_DC) begin
                               if (use_table1) begin
                                   if (dc1_len[j] == k && dc1_code[j] == pattern) begin
                                       found = 1; found_len = k[4:0]; found_sym = j[7:0];
                                   end
                               end else begin
                                   if (dc0_len[j] == k && dc0_code[j] == pattern) begin
                                       found = 1; found_len = k[4:0]; found_sym = j[7:0];
                                   end
                               end
                           end else if (state == S_HUFF_AC) begin
                               if (use_table1) begin
                                   if (ac1_len[j] == k && ac1_code[j] == pattern) begin
                                       found = 1; found_len = k[4:0]; found_sym = j[7:0];
                                   end
                               end else begin
                                   if (ac0_len[j] == k && ac0_code[j] == pattern) begin
                                       found = 1; found_len = k[4:0]; found_sym = j[7:0];
                                   end
                               end
                           end
                       end
                   end
               end
           end
        end
    end

    // ===========================================
    // VLI FUNCTION
    // ===========================================
    function signed [11:0] func_decode_vli;
        input [15:0] bits;
        input [3:0] sz;
        begin
            if (sz == 0) func_decode_vli = 12'sd0;
            else begin
                if ((bits >> (sz - 1)) & 1'b1) func_decode_vli = $signed(bits);
                else func_decode_vli = $signed(bits) - $signed(16'd1 << sz) + 16'd1;
            end
        end
    endfunction

    // Debug Global Counter
    integer global_blk_count;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
             global_blk_count <= 0;
             $display("ENT: RESET. is_420=%d, max_blk=%d", is_420, max_blk_cnt);
             // Dump checks
             $display("TBL: AC0[0x02] Len=%d, Code=%h", ac0_len[2], ac0_code[2]);
             $display("TBL: AC0[0x00] Len=%d, Code=%h", ac0_len[0], ac0_code[0]); // EOB
        end else if(block_done) begin
            $display("BLOCK DONE: Idx=%0d, MCU_Cnt=%0d, DC_Y=%0d, BufferCnt=%0d", 
                     global_blk_count, mcu_blk_cnt, pred_dc_y, cnt);
            global_blk_count <= global_blk_count + 1;
        end
    end

    // ===========================================
    // SEQUENTIAL LOGIC
    // ===========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer <= 0;
            cnt <= 0;
            state <= S_IDLE;
            idx <= 0;
            mcu_blk_cnt <= 0;
            pred_dc_y <= 0; pred_dc_cb <= 0; pred_dc_cr <= 0;
            coeff_valid <= 0; 
            block_done <= 0;
            is_reading_bits <= 0;
            bits_needed <= 0;
            size_reg <= 0;
            run_reg <= 0;
            coeff_value <= 0;
            coeff_index <= 0; 
            global_blk_count <= 0;
        end else begin
            // ---------------------------
            // 1. INPUT BIT HANDLING
            // ---------------------------
            // Default: Shift in bit if handshake OK
            reg [5:0] next_cnt;
            reg [31:0] next_buffer;
            
            // Calculate speculative next buffer/cnt based on input
            if (handshaked_bit) begin
                next_buffer = (buffer << 1) | bit_in;
                next_cnt = cnt + 1;
            end else begin
                next_buffer = buffer;
                next_cnt = cnt;
            end
            
            // ---------------------------
            // 2. STATE MACHINE CONSUMPTION
            // ---------------------------
            coeff_valid <= 0;
            block_done <= 0;
            
            // FIX: Only advance state if downstream is ready
            if (output_ready) begin
                case (state)
                    S_IDLE: begin
                        state <= S_HUFF_DC;
                    end
                    
                    S_HUFF_DC: begin
                        if (found) begin
                            // ... (Consumption logic)
                            next_cnt = next_cnt - found_len; 
                            
                            
                            $display("BLK %0d: DC Huff Found: Len=%0d, Sym=%02h", global_blk_count, found_len, found_sym);

                            size_reg <= found_sym[3:0];
                            run_reg  <= found_sym[7:4];
                            
                            if (found_sym[3:0] == 0) begin
                                 // DC Diff=0
                                 reg signed [11:0] dc_val;
                                 if (mcu_blk_cnt < y_limit) begin
                                     dc_val = pred_dc_y;
                                 end else if (mcu_blk_cnt == y_limit) begin
                                     dc_val = pred_dc_cb;
                                 end else begin
                                     dc_val = pred_dc_cr;
                                 end
                                 coeff_value <= dc_val;
                                 coeff_valid <= 1; coeff_index <= 0; idx <= 1;
                                 state <= S_HUFF_AC;
                                 $display("BLK %0d: DC Diff=0, Val=%0d", global_blk_count, dc_val);
                            end else begin
                                bits_needed <= found_sym[3:0];
                                state <= S_VLI_DC;
                            end
                        end
                    end
                    
                    S_VLI_DC: begin
                        if (next_cnt >= bits_needed) begin
                            reg [15:0] extracted;
                            reg signed [11:0] diff;
                            
                            extracted = (next_buffer >> (next_cnt - bits_needed)) & ((1 << bits_needed)-1);
                            diff = func_decode_vli(extracted, bits_needed);
                            
                            // Consume
                            next_cnt = next_cnt - bits_needed;
                            
                             if (mcu_blk_cnt < y_limit) begin
                                 pred_dc_y <= pred_dc_y + diff;
                                 coeff_value <= pred_dc_y + diff;
                             end else if (mcu_blk_cnt == y_limit) begin
                                 pred_dc_cb <= pred_dc_cb + diff;
                                 coeff_value <= pred_dc_cb + diff;
                             end else begin
                                 pred_dc_cr <= pred_dc_cr + diff;
                                 coeff_value <= pred_dc_cr + diff;
                             end
                             coeff_valid <= 1; coeff_index <= 0; idx <= 1;
                             state <= S_HUFF_AC;
                             $display("BLK %0d: DC Diff=%0d", global_blk_count, diff);
                        end
                    end
                    
                    S_HUFF_AC: begin
                        if (found) begin
                            next_cnt = next_cnt - found_len;
                            
                            size_reg <= found_sym[3:0];
                            run_reg  <= found_sym[7:4];
                            
                            // $display("BLK %0d: AC Huff Found: Len=%0d, Sym=%02h, BufLow=%04h, Cnt=%0d", global_blk_count, found_len, found_sym, buffer[15:0], cnt);
    
                            if (found_sym == 8'h00) begin
                                state <= S_EOB;
                            end else if (found_sym == 8'hF0) begin
                                state <= S_ZRL;
                                run_reg <= 16;
                            end else begin
                                bits_needed <= found_sym[3:0];
                                state <= S_VLI_AC;
                            end
                        end
                    end
                    
                    S_VLI_AC: begin
                         if (next_cnt >= bits_needed) begin
                            reg [15:0] extracted;
                            reg signed [11:0] val;
                            extracted = (next_buffer >> (next_cnt - bits_needed)) & ((1 << bits_needed)-1);
                            val = func_decode_vli(extracted, bits_needed);
                            
                            // $display("BLK %0d: AC VLI: Sz=%d, Bits=%h, Val=%d, BufLow=%04h, Cnt=%0d", global_blk_count, bits_needed, extracted, val, buffer[15:0], next_cnt);

                            next_cnt = next_cnt - bits_needed;
                            
                            state <= S_PROCESS_AC;
                            saved_ac_val <= val; 
                         end
                    end
                    
                    S_PROCESS_AC: begin
                        if (run_reg > 0) begin
                            coeff_value <= 0; coeff_index <= idx; coeff_valid <= 1;
                            idx <= idx + 1;
                            run_reg <= run_reg - 1;
                            if (idx == 63) begin
                                state <= S_IDLE; block_done <= 1;
                                if (mcu_blk_cnt == max_blk_cnt) mcu_blk_cnt <= 0;
                                else mcu_blk_cnt <= mcu_blk_cnt + 1;
                                idx <= 0;
                            end
                        end else begin
                            coeff_valid <= 1; coeff_index <= idx; 
                            coeff_value <= saved_ac_val;
                            
                            $display("BLK %0d: AC Idx=%0d, Val=%0d", global_blk_count, idx, saved_ac_val);
    
                            if (idx == 63) begin
                                state <= S_IDLE; block_done <= 1;
                                
                                if (mcu_blk_cnt == max_blk_cnt) begin
                                    mcu_blk_cnt <= 0;
                                    $display("ENT: MCU Wrap. Old=%d, New=0, Max=%d", mcu_blk_cnt, max_blk_cnt);
                                end else begin
                                    mcu_blk_cnt <= mcu_blk_cnt + 1;
                                    $display("ENT: MCU Inc. Old=%d, New=%d", mcu_blk_cnt, mcu_blk_cnt + 1);
                                end
                                
                                idx <= 0;
                            end else begin
                                 idx <= idx + 1;
                                 state <= S_HUFF_AC;
                            end
                        end
                    end
                    
                    S_ZRL: begin
                         if (run_reg > 0) begin
                            coeff_value <= 0; coeff_index <= idx; coeff_valid <= 1;
                            idx <= idx + 1;
                            run_reg <= run_reg - 1;
                            if (idx == 63) begin
                                 state <= S_IDLE; block_done <= 1;
                                 if (mcu_blk_cnt == max_blk_cnt) mcu_blk_cnt <= 0;
                                 else mcu_blk_cnt <= mcu_blk_cnt + 1;
                                 idx <= 0;
                            end
                         end else begin
                            state <= S_HUFF_AC;
                         end
                    end
                    
                    S_EOB: begin
                        if (idx <= 63) begin
                            coeff_value <= 0; coeff_index <= idx; coeff_valid <= 1;
                            if (idx == 63) begin
                                 state <= S_IDLE; block_done <= 1;
                                 if (mcu_blk_cnt == max_blk_cnt) mcu_blk_cnt <= 0;
                                 else mcu_blk_cnt <= mcu_blk_cnt + 1;
                                 idx <= 0;
                            end else idx <= idx + 1;
                        end
                    end
                endcase
            end
            
            // ---------------------------
            // 3. COMMIT UPDATES
            // ---------------------------
            buffer <= next_buffer;
            cnt <= next_cnt;
            
            // ---------------------------
            // 4. FLOW CONTROL UPDATE
            // ---------------------------
            // Request more bits if we have room (e.g. < 24)
            if (next_cnt < 24) is_reading_bits <= 1;
            else is_reading_bits <= 0;
            
        end
    end
    
    // Debug
    always @(*) begin
        dbg_buffer = buffer;
        dbg_count = cnt;
    end

endmodule