// Read-only instruction memory for RV32I instruction fetch.
// Each entry stores one 32-bit instruction; PC bits [31:2] select a word.
module instruction_memory #(
    parameter MEM_DEPTH = 256
) (
    input  wire [31:0] pc,
    output reg  [31:0] instruction
);

    // Storage is addressed in 32-bit words, not individual bytes.
    reg [31:0] memory [0:MEM_DEPTH-1];

    // Initialize the memory from the standard program image file.
    // Vivado supports $readmemh for inferred memory initialization.
    initial begin
        $readmemh("program.mem", memory);
    end

    // Combinational instruction fetch. The two least-significant PC bits are
    // ignored because each instruction occupies one 32-bit aligned word.
    // Invalid or unknown word addresses return unknown data in simulation.
    always @(*) begin
        if (pc[31:2] < MEM_DEPTH)
            instruction = memory[pc[31:2]];
        else
            instruction = 32'hxxxxxxxx;
    end

endmodule
