module coeff_accumulator #(
    parameter WIDTH = 16
)(
    input  wire clk,
    input  wire rst_n,
    input  wire signed [WIDTH-1:0] coeff_in,
    input  wire [5:0]              coeff_index,
    input  wire                    coeff_valid,
    input  wire                    block_done,
    output reg  [WIDTH*64-1:0]     block_out_flat, // 16*64 = 1024
    output reg                     block_valid,
    input  wire                    block_ready
);
    reg signed [WIDTH-1:0] mem [0:63];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_valid <= 0;
            for (i=0; i<64; i=i+1) mem[i] <= 0;
        end else begin
            if (coeff_valid) mem[coeff_index] <= coeff_in;
            
            if (block_done) begin
                for (i=0; i<64; i=i+1) 
                    block_out_flat[i*WIDTH +: WIDTH] <= mem[i];
                block_valid <= 1;
            end else if (block_ready) begin
                block_valid <= 0;
            end
        end
    end
endmodule