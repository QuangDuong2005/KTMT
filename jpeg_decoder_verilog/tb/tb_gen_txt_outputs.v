`timescale 1ns / 1ps

// ============================================================================
// MODULE: tb_gen_txt_outputs
// PURPOSE: Verify JPEG Decoder by dumping intermediate signals to TXT files.
// ============================================================================

module tb_gen_txt_outputs;

    // ============================================================
    // 1. PARAMETERS & SIGNALS
    // ============================================================
    parameter CLK_PERIOD      = 10;                 
    parameter INPUT_HEX_FILE  = "test.hex";         
    parameter MAX_IMG_SIZE    = 65536;              

    reg clk;
    reg rst_n;
    reg  [7:0] byte_in;    
    reg        byte_valid; 
    wire       byte_ready; 
    wire [7:0] r_out, g_out, b_out; 
    wire       pixel_valid;         
    wire [15:0] img_width, img_height; 
    wire        idle;                  

    reg [7:0] image_rom [0:MAX_IMG_SIZE-1]; 
    integer data_ptr;                
    reg     simulation_running;      
    reg     has_started_scan;        

    // File Handlers
    integer f_header;
    integer f_entropy;
    integer f_zigzag; // To store "ZigZag" data (actually Entropy output which is in ZigZag order)
    integer f_dequant; // To store Dequantized data
    integer f_idct;   // To store IDCT output
    integer f_output; // Final RGB

    // Helper vars
    integer i, j;
    reg [15:0] temp_val;

    // ============================================================
    // 2. DUT INSTANTIATION
    // ============================================================
    jpeg_decoder_top u_top (
        .clk(clk),
        .rst_n(rst_n),
        .byte_in(byte_in),
        .byte_valid(byte_valid),
        .byte_ready(byte_ready),
        .r_out(r_out),
        .g_out(g_out),
        .b_out(b_out),
        .pixel_valid(pixel_valid),
        .img_width(img_width),
        .img_height(img_height),
        .idle(idle)
    );

    // ============================================================
    // 3. CLOCK GENERATION
    // ============================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ============================================================
    // 4. MAIN TEST PROCESS
    // ============================================================
    initial begin
        $dumpfile("wave_debug.vcd");
        $dumpvars(0, tb_gen_txt_outputs);

        // Open Files
        f_header = $fopen("output_header_parser.txt", "w");
        f_entropy = $fopen("output_entropy_decoder.txt", "w");
        f_zigzag  = $fopen("output_zigzag.txt", "w");
        f_dequant = $fopen("output_dequant.txt", "w");
        f_idct    = $fopen("output_idct.txt", "w");
        f_output  = $fopen("output_mcu.txt", "w");

        if (!f_header || !f_entropy || !f_zigzag || !f_dequant || !f_idct || !f_output) begin
            $display("ERROR: Cannot open one or more output files.");
            $finish;
        end

        // Init
        rst_n = 0;
        byte_valid = 0;
        byte_in = 0;
        data_ptr = 0;
        simulation_running = 1;
        has_started_scan = 0;

        $readmemh(INPUT_HEX_FILE, image_rom);

        #100 rst_n = 1;
        #20;

        $display("START: Feeding JPEG stream...");

        while (simulation_running) begin
            if (data_ptr < MAX_IMG_SIZE && image_rom[data_ptr] !== 8'bx) begin
                byte_in    = image_rom[data_ptr];
                byte_valid = 1;
            end else begin
                // Padding if needed
                if (!idle) begin
                    byte_in    = 8'h00;
                    byte_valid = 1;
                end else begin
                    byte_valid = 0;
                end
            end

            @(posedge clk);

            if (byte_valid && byte_ready) begin
                if (image_rom[data_ptr] !== 8'bx)
                    data_ptr = data_ptr + 1;
            end

            // --- CHECK END ---
            if (has_started_scan && idle) begin
                repeat(100) @(posedge clk);
                $display("SUCCESS: Simulation complete.");
                simulation_running = 0;
            end

            // Safety limit
            if (data_ptr > 50000 && !has_started_scan) begin
                 $display("TIMEOUT: Header parsing stuck.");
                 simulation_running = 0;
            end
        end
        
        // Close files
        $fclose(f_header);
        $fclose(f_entropy);
        $fclose(f_zigzag);
        $fclose(f_dequant);
        $fclose(f_idct);
        $fclose(f_output);
        $finish;
    end

    // ============================================================
    // 5. DUMPING TASKS logic
    // ============================================================

    // --- 5.1 HEADER PARSER DUMP ---
    // Trigger when start_scan rises
    reg old_start_scan;
    always @(posedge clk) begin
        if (!rst_n) old_start_scan <= 0;
        else begin
            if (u_top.start_scan && !old_start_scan) begin
                $display("Dumping Header Info...");
                $fwrite(f_header, "Image Dimensions: %0dx%0d\n", u_top.img_width, u_top.img_height);
                $fwrite(f_header, "Num Components: %0d\n", u_top.num_components);
                
                // Dump Quant Tables
                $fwrite(f_header, "\nQuantization Table 0 (Luma):\n");
                for(i=0; i<64; i=i+1) begin
                    $fwrite(f_header, "%0d ", u_top.u_parser.qtable_mem[0][i]);
                    if ((i+1)%8 == 0) $fwrite(f_header, "\n");
                end

                $fwrite(f_header, "\nQuantization Table 1 (Chroma):\n");
                for(i=0; i<64; i=i+1) begin
                    $fwrite(f_header, "%0d ", u_top.u_parser.qtable_mem[1][i]);
                    if ((i+1)%8 == 0) $fwrite(f_header, "\n");
                end

                // Dump Huffman Counts (Lengths)
                $fwrite(f_header, "\nHuffman DC0 Counts:\n");
                for(i=0; i<16; i=i+1) $fwrite(f_header, "%0d ", u_top.u_parser.dc0_len_out[i]);
                $fwrite(f_header, "\nHuffman AC0 Counts:\n");
                for(i=0; i<16; i=i+1) $fwrite(f_header, "%0d ", u_top.u_parser.ac0_len_out[i]);
                $fwrite(f_header, "\nHuffman DC1 Counts:\n");
                for(i=0; i<16; i=i+1) $fwrite(f_header, "%0d ", u_top.u_parser.dc1_len_out[i]);
                $fwrite(f_header, "\nHuffman AC1 Counts:\n");
                for(i=0; i<16; i=i+1) $fwrite(f_header, "%0d ", u_top.u_parser.ac1_len_out[i]);
                $fwrite(f_header, "\n");
                
                has_started_scan <= 1;
            end
            old_start_scan <= u_top.start_scan;
        end
    end

    // --- 5.2 BLOCK DATA DUMPS (ENTROPY, ZIGZAG, DEQUANT, IDCT) ---
    // Trigger on u_top.blk_valid && u_top.blk_ready
    // Note: 'blk_valid' from top is output of u_acc.
    
    integer blk_idx = 0;
    
    always @(posedge clk) begin
        if (rst_n && u_top.blk_valid && u_top.blk_ready) begin
            $fwrite(f_entropy, "Block %0d:\n", blk_idx);
            $fwrite(f_zigzag,  "Block %0d:\n", blk_idx);
            $fwrite(f_dequant, "Block %0d:\n", blk_idx);
            $fwrite(f_idct,    "Block %0d (Input to MCU):\n", blk_idx); // output of IDCT

            // 1. ENTROPY OUTPUT (stored in blk_flat) which is also the ZIGZAG ORDERED data
            // Since the user asked for "entropy decoder" and "zig zag" separately:
            // "Entropy Decoder" usually produces run-level or a vector of coeffs.
            // "Zig Zag" usually refers to the reordering. 
            // Here: blk_flat IS the ZigZag ordered vector (Output of Entropy).
            // So I will write blk_flat to "output_entropy_decoder.txt" AND "output_zigzag.txt" 
            // (or maybe zigzag.txt refers to the Reordered Natural Order? This is ambiguous).
            // Let's assume:
            // output_entropy_decoder.txt -> The ZigZag vector (raw coeffs)
            // output_zigzag.txt -> The ZigZag vector (same) OR maybe the scan order? 
            // In a DECODER:
            // Entropy -> [ZigZag Vector] -> Dequant -> [ZigZag Dequant] -> Inverse ZigZag -> [Natural Dequant] -> IDCT -> [Natural Spatial]
            // I will dump:
            // f_entropy: The blk_flat (ZigZag Vector)
            // f_zigzag:  The blk_flat (Same, to satisfy the list requirement or maybe I verify the order is ZZ)
            // f_dequant: The dct_out_flat (Natural Dequantized)
            // f_idct:    The idct_out
            
            // Loop 64 elements
            for(i=0; i<64; i=i+1) begin
                // Extract 16-bit signed
                // blk_flat is [16*64-1 : 0]. Element 0 is [15:0].
                // But wait, standard ZigZag usually puts DC at index 0.
                
                // DATA 1: Entropy Out (ZigZag Order)
                // u_top.blk_flat is 1024 bits.
                // Verilog array slice needs constant or careful indexing.
                // u_top.blk_flat[ i*16 +: 16 ]
                
                // Writing to f_entropy
                $fwrite(f_entropy, "%0d ", $signed(u_top.blk_flat[i*16 +: 16]));
                if ((i+1)%8 == 0) $fwrite(f_entropy, "\n");
                
                // Writing to f_zigzag (Same as entropy out here because logic is packed)
                $fwrite(f_zigzag, "%0d ", $signed(u_top.blk_flat[i*16 +: 16]));
                if ((i+1)%8 == 0) $fwrite(f_zigzag, "\n");
                
                // DATA 2: Dequantized & Inverse-ZigZagged (Natural Order)
                // u_top.dct_flat
                $fwrite(f_dequant, "%0d ", $signed(u_top.dct_flat[i*16 +: 16]));
                if ((i+1)%8 == 0) $fwrite(f_dequant, "\n");
                
                // DATA 3: IDCT Output
                // u_top.idct_out[i] (This is an array of 16-bit)
                // Need to verify if u_top.idct_out is an array or flat.
                // in jpeg_decoder_top: wire signed [15:0] idct_out[0:63];
                // Accessing array in hierarchical might assume specific index.
                // I will try u_top.idct_out[i].
                $fwrite(f_idct, "%0d ", u_top.idct_out[i]);
                if ((i+1)%8 == 0) $fwrite(f_idct, "\n");
            end
             
            $fwrite(f_entropy, "\n");
            $fwrite(f_zigzag,  "\n");
            $fwrite(f_dequant, "\n");
            $fwrite(f_idct,    "\n");
            
            blk_idx = blk_idx + 1;
        end
    end

    // --- 5.3 OUTPUT RGB DUMP ---
    always @(posedge clk) begin
        if (rst_n && pixel_valid) begin
            $fwrite(f_output, "%d %d %d\n", r_out, g_out, b_out);
        end
    end

endmodule
