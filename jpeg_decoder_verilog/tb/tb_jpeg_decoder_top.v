`timescale 1ns/1ps
module tb_jpeg_decoder_top;
    reg clk, rst_n, byte_valid;
    reg [7:0] byte_in;
    wire [7:0] r, g, b;
    wire valid, ready;
    integer img_f, idx, p_cnt=0, total=0;
    reg [7:0] rom [0:524287];

    jpeg_decoder_top dut(clk, rst_n, byte_in, byte_valid, ready, r, g, b, valid);

    always #5 clk = (clk === 1'b0);

    initial begin
        $readmemh("data/test.hex", rom);
        img_f = $fopen("sim/output.ppm", "w");
        clk=0; rst_n=0; byte_valid=0; #100 rst_n=1; #20;

        // 1. Nạp hết file HEX
        for (idx=0; rom[idx] !== 8'hxx && idx < 524288; idx=idx+1) begin
            while(!ready) @(posedge clk);
            byte_in <= rom[idx]; byte_valid <= 1; @(posedge clk); byte_valid <= 0;
        end
        
        // 2. Ép Testbench ĐỢI cho đến khi đủ pixel hoặc quá lâu
        $display("[TB] Da nap xong hex. Dang doi pixel...");
        idx = 0;
        while (p_cnt < total && idx < 50000) begin
            // Bơm thêm byte 0 để đẩy pipeline
            if (ready) begin
                byte_in <= 8'h00; byte_valid <= 1; @(posedge clk); byte_valid <= 0;
            end else @(posedge clk);
            idx = idx + 1;
        end

        $display("[TB] Hoan thanh. Pixel thu duoc: %0d/%0d", p_cnt, total);
        $fclose(img_f);
        $finish;
    end

    always @(posedge clk) if (dut.w_start_scan && total==0) begin
        total = dut.w_img_width * dut.w_img_height;
        $fwrite(img_f, "P3\n%0d %0d\n255\n", dut.w_img_width, dut.w_img_height);
    end

    always @(posedge clk) if (valid) begin
        $fwrite(img_f, "%d %d %d\n", r, g, b);
        p_cnt = p_cnt + 1;
        if (p_cnt % 1000 == 0) $display("Progress: %d/%d", p_cnt, total);
    end
endmodule