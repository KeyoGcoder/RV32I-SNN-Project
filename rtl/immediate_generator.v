// RV32I immediate decoder. The opcode determines how instruction bits are
// assembled into a 32-bit immediate value.
module immediate_generator (
    input  wire [31:0] instruction,
    output reg  [31:0] immediate
);

    localparam [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam [6:0] OPCODE_JALR   = 7'b1100111;
    localparam [6:0] OPCODE_STORE  = 7'b0100011;
    localparam [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam [6:0] OPCODE_LUI    = 7'b0110111;
    localparam [6:0] OPCODE_AUIPC  = 7'b0010111;
    localparam [6:0] OPCODE_JAL    = 7'b1101111;

    // Decode only supported RV32I opcodes. A default assignment guarantees
    // combinational behavior and returns zero for unsupported instructions.
    always @(*) begin
        immediate = 32'b0;

        case (instruction[6:0])
            // I-type: bits [31:20] are a signed 12-bit immediate.
            OPCODE_OP_IMM,
            OPCODE_LOAD,
            OPCODE_JALR: begin
                immediate = {{20{instruction[31]}}, instruction[31:20]};
            end

            // S-type: the signed immediate is split between [31:25] and [11:7].
            OPCODE_STORE: begin
                immediate = {{20{instruction[31]}}, instruction[31:25],
                             instruction[11:7]};
            end

            // B-type: branch offsets are signed, split across the instruction,
            // and have an implicit zero least-significant bit.
            OPCODE_BRANCH: begin
                immediate = {{19{instruction[31]}}, instruction[31],
                             instruction[7], instruction[30:25],
                             instruction[11:8], 1'b0};
            end

            // U-type: the 20-bit upper immediate occupies bits [31:12].
            OPCODE_LUI,
            OPCODE_AUIPC: begin
                immediate = {instruction[31:12], 12'b0};
            end

            // J-type: jump offsets are signed, split across the instruction,
            // and have an implicit zero least-significant bit.
            OPCODE_JAL: begin
                immediate = {{11{instruction[31]}}, instruction[31],
                             instruction[19:12], instruction[20],
                             instruction[30:21], 1'b0};
            end

            default: begin
                immediate = 32'b0;
            end
        endcase
    end

endmodule
