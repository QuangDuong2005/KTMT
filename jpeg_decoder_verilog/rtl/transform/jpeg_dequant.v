module jpeg_dequant
#(
    parameter WIDTH_IN  = 16,
    parameter WIDTH_Q   = 16,
    parameter WIDTH_OUT = 32
)
(
    input  wire signed [WIDTH_IN*64-1:0]  matrix_in_flat,
    input  wire        [WIDTH_Q*64-1:0]   quant_flat,    
    output wire signed [WIDTH_OUT*64-1:0] dct_out_flat
);

    genvar i;
    generate
        for (i = 0; i < 64; i = i + 1) begin : MULT_LOOP
            wire signed [WIDTH_IN-1:0]  val;
            // Ép kiểu Q thành signed với độ rộng lớn hơn 1 bit để tránh mất bit dấu
            wire signed [WIDTH_Q:0]     q_val_expanded; 
            wire signed [WIDTH_OUT-1:0] mult_res;

            assign val = matrix_in_flat[i*WIDTH_IN +: WIDTH_IN];
            
            // Q luôn dương, ta thêm 0 vào MSB và coi nó là số signed
            assign q_val_expanded = $signed({1'b0, quant_flat[i*WIDTH_Q +: WIDTH_Q]});

            // Phép nhân signed: 16-bit * 17-bit = 33-bit (cắt lấy WIDTH_OUT)
            assign mult_res = val * q_val_expanded;

            assign dct_out_flat[i*WIDTH_OUT +: WIDTH_OUT] = mult_res;
        end
    endgenerate
endmodule