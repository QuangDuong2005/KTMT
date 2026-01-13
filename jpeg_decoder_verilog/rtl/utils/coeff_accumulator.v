module coeff_accumulator #(
    parameter WIDTH = 16
)(
    input  wire clk,
    input  wire rst_n,
    input  wire signed [WIDTH-1:0] coeff_in,
    input  wire [5:0]              coeff_index,
    input  wire                    coeff_valid,
    input  wire                    block_done,
    output reg  [WIDTH*64-1:0]     block_out_flat, 
    output reg                     block_valid,
    input  wire                    block_ready,
    output wire                    acc_ready_for_input
);

    reg signed [WIDTH-1:0] mem [0:63];
    integer i;

    // Logic báo bận:
    // Nếu đang giữ block hợp lệ (valid=1) NHƯNG bên dưới chưa nhận (ready=0)
    // -> BỊ KẸT (Stalled) -> Không nhận input mới.
    wire is_stalled = block_valid && !block_ready;
    
    // Ready cho input khi KHÔNG bị kẹt
    assign acc_ready_for_input = !is_stalled;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_valid <= 0;
            block_out_flat <= 0;
            for (i=0; i<64; i=i+1) mem[i] <= 0;
        end else begin
            
            // 1. Chỉ ghi vào RAM nếu không bị kẹt (Bảo vệ dữ liệu cũ)
            if (coeff_valid && !is_stalled) begin
                mem[coeff_index] <= coeff_in;
            end
            
            // 2. Logic Handshake đầu ra
            if (block_done && !is_stalled) begin
                // Chỉ update output khi an toàn
                for (i=0; i<64; i=i+1) begin
                   // FIX: Forwarding data if writing and reading happen in same cycle
                   if (coeff_valid && (coeff_index == i))
                       block_out_flat[i*WIDTH +: WIDTH] <= coeff_in;
                   else
                       block_out_flat[i*WIDTH +: WIDTH] <= mem[i];
                end
                block_valid <= 1;
            end else if (block_ready) begin
                // Bên dưới đã nhận xong -> Xả cờ valid -> Hết kẹt
                block_valid <= 0;
            end
        end
    end
    
    // Debug Logic
    always @(posedge clk) begin
        if (block_done || block_valid || is_stalled) begin
            $display("ACC: Done=%d, Valid=%d, Ready=%d, Stalled=%d, AccReadyOut=%d", 
                     block_done, block_valid, block_ready, is_stalled, acc_ready_for_input);
        end
    end

endmodule