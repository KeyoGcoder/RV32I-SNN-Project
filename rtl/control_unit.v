// Combinational single-cycle control decoder for supported RV32I opcodes.
module control_unit (
    input  wire [6:0] opcode,
    output reg        reg_write,
    output reg        alu_src,
    output reg        mem_read,
    output reg        mem_write,
    output reg        mem_to_reg,
    output reg        branch,
    output reg        jump,
    output reg        jalr,
    output reg  [1:0] alu_op
);

    localparam [6:0] OPCODE_R_TYPE = 7'b0110011;
    localparam [6:0] OPCODE_I_TYPE = 7'b0010011;
    localparam [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam [6:0] OPCODE_STORE  = 7'b0100011;
    localparam [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam [6:0] OPCODE_JAL    = 7'b1101111;
    localparam [6:0] OPCODE_JALR   = 7'b1100111;
    localparam [6:0] OPCODE_LUI    = 7'b0110111;
    localparam [6:0] OPCODE_AUIPC  = 7'b0010111;

    // Defaults make unsupported instructions side-effect free and guarantee
    // all control outputs are assigned in this combinational process.
    always @(*) begin
        reg_write  = 1'b0;
        alu_src    = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = 1'b0;
        branch     = 1'b0;
        jump       = 1'b0;
        jalr       = 1'b0;
        alu_op     = 2'b00;

        case (opcode)
            // R-type uses two registers and writes its ALU result to rd.
            OPCODE_R_TYPE: begin
                reg_write = 1'b1;
                alu_op    = 2'b10;
            end

            // I-type ALU operations use an immediate as the second ALU input.
            OPCODE_I_TYPE: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b10;
            end

            // LOAD forms an address by addition and writes memory data to rd.
            OPCODE_LOAD: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
                alu_op     = 2'b00;
            end

            // STORE forms an address by addition and writes data to memory.
            OPCODE_STORE: begin
                alu_src   = 1'b1;
                mem_write = 1'b1;
                alu_op    = 2'b00;
            end

            // BRANCH selects branch comparison in the downstream ALU control.
            OPCODE_BRANCH: begin
                branch = 1'b1;
                alu_op = 2'b01;
            end

            // JAL writes the link address and requests an unconditional jump.
            OPCODE_JAL: begin
                reg_write = 1'b1;
                jump      = 1'b1;
                alu_op    = 2'b00;
            end

            // JALR uses rs1 plus its immediate target and writes a link address.
            OPCODE_JALR: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                jalr      = 1'b1;
                alu_op    = 2'b00;
            end

            // LUI supplies an upper immediate to rd through the immediate path.
            OPCODE_LUI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b00;
            end

            // AUIPC adds the upper immediate to the program counter path.
            OPCODE_AUIPC: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b00;
            end

            default: begin
                reg_write  = 1'b0;
                alu_src    = 1'b0;
                mem_read   = 1'b0;
                mem_write  = 1'b0;
                mem_to_reg = 1'b0;
                branch     = 1'b0;
                jump       = 1'b0;
                jalr       = 1'b0;
                alu_op     = 2'b00;
            end
        endcase
    end

endmodule
