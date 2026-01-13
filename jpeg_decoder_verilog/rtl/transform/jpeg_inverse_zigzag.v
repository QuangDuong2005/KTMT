module jpeg_inverse_zigzag
#(
    parameter WIDTH = 16
)
(
    input  wire [WIDTH*64-1:0] zz_in_flat,      // Input: Zigzag order
    output wire [WIDTH*64-1:0] matrix_out_flat  // Output: Row-Major order
);


    // Hàm trả về vị trí Zigzag tương ứng với vị trí Matrix (Compile-time constant)
    // Hàm này chỉ chạy lúc biên dịch để xác định cách nối dây, không tốn tài nguyên chạy thực
    function integer get_zig_loc;
        input integer idx;
        begin
            case(idx)
                 0: get_zig_loc = 0;   1: get_zig_loc = 1;   2: get_zig_loc = 5;   3: get_zig_loc = 6;
                 4: get_zig_loc = 14;  5: get_zig_loc = 15;  6: get_zig_loc = 27;  7: get_zig_loc = 28;
                 8: get_zig_loc = 2;   9: get_zig_loc = 4;  10: get_zig_loc = 7;  11: get_zig_loc = 13;
                12: get_zig_loc = 16; 13: get_zig_loc = 26; 14: get_zig_loc = 29; 15: get_zig_loc = 42;
                16: get_zig_loc = 3;  17: get_zig_loc = 8;  18: get_zig_loc = 12; 19: get_zig_loc = 17;
                20: get_zig_loc = 25; 21: get_zig_loc = 30; 22: get_zig_loc = 41; 23: get_zig_loc = 43;
                24: get_zig_loc = 9;  25: get_zig_loc = 11; 26: get_zig_loc = 18; 27: get_zig_loc = 24;
                28: get_zig_loc = 31; 29: get_zig_loc = 40; 30: get_zig_loc = 44; 31: get_zig_loc = 53;
                32: get_zig_loc = 10; 33: get_zig_loc = 19; 34: get_zig_loc = 23; 35: get_zig_loc = 32;
                36: get_zig_loc = 39; 37: get_zig_loc = 45; 38: get_zig_loc = 52; 39: get_zig_loc = 54;
                40: get_zig_loc = 20; 41: get_zig_loc = 22; 42: get_zig_loc = 33; 43: get_zig_loc = 38;
                44: get_zig_loc = 46; 45: get_zig_loc = 51; 46: get_zig_loc = 55; 47: get_zig_loc = 60;
                48: get_zig_loc = 21; 49: get_zig_loc = 34; 50: get_zig_loc = 37; 51: get_zig_loc = 47;
                52: get_zig_loc = 50; 53: get_zig_loc = 56; 54: get_zig_loc = 59; 55: get_zig_loc = 61;
                56: get_zig_loc = 35; 57: get_zig_loc = 36; 58: get_zig_loc = 48; 59: get_zig_loc = 49;
                60: get_zig_loc = 57; 61: get_zig_loc = 58; 62: get_zig_loc = 62; 63: get_zig_loc = 63;
                default: get_zig_loc = 0;
            endcase
        end
    endfunction


    // Sử dụng generate loop để "nối dây"
    genvar i;
    generate
        for (i = 0; i < 64; i = i + 1) begin : MAP_LOOP
            // Gọi hàm hằng số để lấy index nối dây
            localparam integer zig_pos = get_zig_loc(i);
           
            // Thực hiện nối dây cứng (Hardwired mapping)
            assign matrix_out_flat[(i+1)*WIDTH-1 : i*WIDTH] =
                   zz_in_flat[(zig_pos+1)*WIDTH-1 : zig_pos*WIDTH];
        end
    endgenerate


endmodule
