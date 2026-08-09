// Single-cycle RV32I datapath integration.
// All inter-module datapath and control connections are wires.
module top (
    input wire clk,
    input wire reset
);

    wire [31:0] pc_out;
    wire [31:0] next_pc;
    wire [31:0] pc_plus_four;
    wire [31:0] instruction;
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] immediate;
    wire [31:0] alu_operand_b;
    wire [31:0] alu_result;
    wire [31:0] read_data;
    wire [31:0] write_back_data;
    wire        alu_zero;
    wire        reg_write;
    wire        alu_src;
    wire        mem_read;
    wire        mem_write;
    wire        mem_to_reg;
    wire        branch;
    wire        jump;
    wire        jalr;
    wire [1:0]  alu_op;
    wire [3:0]  alu_control;
    wire        is_r_type;

    // The program counter advances every clock; reset behavior is inside pc.
    pc u_pc (
        .clk     (clk),
        .reset   (reset),
        .enable  (1'b1),
        .next_pc (next_pc),
        .pc_out  (pc_out)
    );

    // Fetch the current 32-bit instruction using the byte-addressed PC.
    instruction_memory u_instruction_memory (
        .pc          (pc_out),
        .instruction (instruction)
    );

    // Decode the instruction class into the main single-cycle controls.
    control_unit u_control_unit (
        .opcode     (instruction[6:0]),
        .reg_write  (reg_write),
        .alu_src    (alu_src),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .mem_to_reg (mem_to_reg),
        .branch     (branch),
        .jump       (jump),
        .jalr       (jalr),
        .alu_op     (alu_op)
    );

    // Read source registers and synchronously write the selected result.
    register_file u_register_file (
        .clk          (clk),
        .reset        (reset),
        .rs1          (instruction[19:15]),
        .rs2          (instruction[24:20]),
        .rd           (instruction[11:7]),
        .write_data   (write_back_data),
        .write_enable (reg_write),
        .read_data1   (rs1_data),
        .read_data2   (rs2_data)
    );

    // Generate the correctly arranged RV32I immediate for this instruction.
    immediate_generator u_immediate_generator (
        .instruction (instruction),
        .immediate   (immediate)
    );

    // Select register or immediate data as the ALU's second operand.
    assign alu_operand_b = alu_src ? immediate : rs2_data;

    // Derive the ALU operation from ALUOp and the R/I-type funct fields.
    // Branch comparison uses subtraction so the ALU zero flag detects BEQ.
    assign is_r_type = (instruction[6:0] == 7'b0110011);
    assign alu_control = (alu_op == 2'b00) ? 4'b0000 :
                         (alu_op == 2'b01) ? 4'b0001 :
                         (alu_op == 2'b10) ?
                         ((instruction[14:12] == 3'b000) ?
                          ((is_r_type && instruction[30]) ? 4'b0001 : 4'b0000) :
                          (instruction[14:12] == 3'b111) ? 4'b0010 :
                          (instruction[14:12] == 3'b110) ? 4'b0011 :
                          (instruction[14:12] == 3'b100) ? 4'b0100 :
                          (instruction[14:12] == 3'b001) ? 4'b0101 :
                          (instruction[14:12] == 3'b101) ?
                          (instruction[30] ? 4'b0111 : 4'b0110) :
                          (instruction[14:12] == 3'b010) ? 4'b1000 :
                          (instruction[14:12] == 3'b011) ? 4'b1001 : 4'b0000) :
                         4'b0000;

    // Execute the requested arithmetic, logical, address, or comparison work.
    alu u_alu (
        .operand_a   (rs1_data),
        .operand_b   (alu_operand_b),
        .alu_control (alu_control),
        .result      (alu_result),
        .zero        (alu_zero)
    );

    // Access word-addressed data memory using the ALU result as its address.
    data_memory u_data_memory (
        .clk        (clk),
        .reset      (reset),
        .address    (alu_result),
        .write_data (rs2_data),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .read_data  (read_data)
    );

    // Loads write memory data; all other register writes use the ALU result.
    // Loads write memory data; jumps write the return address (PC+4);
    // all other register writes use the ALU result.
    assign write_back_data = (jump || jalr) ? pc_plus_four :
                              mem_to_reg ? read_data : alu_result;

    // Select the next sequential PC, a taken branch target, or a jump target.
   // Select the next sequential PC, a taken branch target, or a jump target.
    assign pc_plus_four = pc_out + 32'd4;
    assign next_pc = jump ? (pc_out + immediate) :
                     jalr ? ((rs1_data + immediate) & ~32'b1) :
                     ((branch && alu_zero) ? (pc_out + immediate) : pc_plus_four);

endmodule
