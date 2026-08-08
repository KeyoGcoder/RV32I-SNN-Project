`timescale 1ns/1ps

// Self-checking testbench for the RV32I single-cycle control decoder.
module tb_control_unit;
    reg  [6:0] opcode;
    wire       reg_write;
    wire       alu_src;
    wire       mem_read;
    wire       mem_write;
    wire       mem_to_reg;
    wire       branch;
    wire       jump;
    wire [1:0] alu_op;
    integer    failures;

    control_unit dut (
        .opcode     (opcode),
        .reg_write  (reg_write),
        .alu_src    (alu_src),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .mem_to_reg (mem_to_reg),
        .branch     (branch),
        .jump       (jump),
        .alu_op     (alu_op)
    );

    // Check every control output for one instruction opcode.
    task check_controls;
        input [6:0] test_opcode;
        input       expected_reg_write;
        input       expected_alu_src;
        input       expected_mem_read;
        input       expected_mem_write;
        input       expected_mem_to_reg;
        input       expected_branch;
        input       expected_jump;
        input [1:0] expected_alu_op;
        input [8*48-1:0] test_name;
        begin
            opcode = test_opcode;
            #1;
            if ((reg_write  !== expected_reg_write)  ||
                (alu_src    !== expected_alu_src)    ||
                (mem_read   !== expected_mem_read)   ||
                (mem_write  !== expected_mem_write)  ||
                (mem_to_reg !== expected_mem_to_reg) ||
                (branch     !== expected_branch)     ||
                (jump       !== expected_jump)       ||
                (alu_op     !== expected_alu_op)) begin
                $display("FAIL: %0s", test_name);
                $display("      Expected rw=%b as=%b mr=%b mw=%b mtr=%b br=%b j=%b op=%b",
                         expected_reg_write, expected_alu_src, expected_mem_read,
                         expected_mem_write, expected_mem_to_reg, expected_branch,
                         expected_jump, expected_alu_op);
                $display("      Got      rw=%b as=%b mr=%b mw=%b mtr=%b br=%b j=%b op=%b",
                         reg_write, alu_src, mem_read, mem_write, mem_to_reg,
                         branch, jump, alu_op);
                failures = failures + 1;
            end else begin
                $display("PASS: %0s", test_name);
            end
        end
    endtask

    initial begin
        opcode   = 7'b0;
        failures = 0;

        check_controls(7'b0110011, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                       2'b10, "R-type");
        check_controls(7'b0010011, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                       2'b10, "I-type ALU");
        check_controls(7'b0000011, 1'b1, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0,
                       2'b00, "LOAD");
        check_controls(7'b0100011, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0,
                       2'b00, "STORE");
        check_controls(7'b1100011, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0,
                       2'b01, "BRANCH");
        check_controls(7'b1101111, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1,
                       2'b00, "JAL");
        check_controls(7'b1100111, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1,
                       2'b00, "JALR");
        check_controls(7'b0110111, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                       2'b00, "LUI");
        check_controls(7'b0010111, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                       2'b00, "AUIPC");
        check_controls(7'b1111111, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                       2'b00, "illegal opcode");

        if (failures == 0)
            $display("PASS: ALL CONTROL UNIT TESTS PASSED");
        else
            $display("FAIL: CONTROL UNIT TESTBENCH HAS %0d FAILURE(S)", failures);

        $finish;
    end
endmodule
