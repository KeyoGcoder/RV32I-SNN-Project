// 32-bit RV32I program counter register.
// Reset has priority over enable and is sampled on the rising clock edge.
module pc (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [31:0] next_pc,
    output reg  [31:0] pc_out
);

    // A clocked process models a flip-flop bank; no latches are inferred.
    always @(posedge clk) begin
        if (reset)
            pc_out <= 32'b0;
        else if (enable)
            pc_out <= next_pc;
    end

endmodule
