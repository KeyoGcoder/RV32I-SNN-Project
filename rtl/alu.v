// Combinational 32-bit ALU for RV32I arithmetic, logic, shift, and compare
// operations. alu_control selects the operation defined by the datapath.
module alu (
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    input  wire [3:0]  alu_control,
    output reg  [31:0] result,
    output wire        zero
);

    // A default value and a case for every supported operation ensure that
    // all output paths are assigned, preventing inferred latches.
    always @(*) begin
        result = 32'b0;

        case (alu_control)
            4'b0000: result = operand_a + operand_b;                  // ADD
            4'b0001: result = operand_a - operand_b;                  // SUB
            4'b0010: result = operand_a & operand_b;                  // AND
            4'b0011: result = operand_a | operand_b;                  // OR
            4'b0100: result = operand_a ^ operand_b;                  // XOR
            4'b0101: result = operand_a << operand_b[4:0];            // SLL
            4'b0110: result = operand_a >> operand_b[4:0];            // SRL
            4'b0111: result = $signed(operand_a) >>> operand_b[4:0];  // SRA
            4'b1000: result = ($signed(operand_a) < $signed(operand_b)) ?
                              32'd1 : 32'd0;                           // SLT
            4'b1001: result = (operand_a < operand_b) ?
                              32'd1 : 32'd0;                           // SLTU
            default: result = 32'b0;
        endcase
    end

    // The zero flag is asserted for every operation whose result is zero.
    assign zero = (result == 32'b0);

endmodule
