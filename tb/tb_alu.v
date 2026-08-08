`timescale 1ns/1ps

// Self-checking testbench for the 32-bit RV32I ALU.
module tb_alu;
    reg  [31:0] operand_a;
    reg  [31:0] operand_b;
    reg  [3:0]  alu_control;
    wire [31:0] result;
    wire        zero;
    integer     failures;

    alu dut (
        .operand_a   (operand_a),
        .operand_b   (operand_b),
        .alu_control (alu_control),
        .result      (result),
        .zero        (zero)
    );

    // Apply one combinational operation and check both result and zero flag.
    task check_alu;
        input [31:0] test_a;
        input [31:0] test_b;
        input [3:0]  test_control;
        input [31:0] expected_result;
        input        expected_zero;
        input [8*56-1:0] test_name;
        begin
            operand_a   = test_a;
            operand_b   = test_b;
            alu_control = test_control;
            #1;
            if ((result !== expected_result) || (zero !== expected_zero)) begin
                $display("FAIL: %0s. Expected result=%h zero=%b, got result=%h zero=%b",
                         test_name, expected_result, expected_zero, result, zero);
                failures = failures + 1;
            end else begin
                $display("PASS: %0s", test_name);
            end
        end
    endtask

    initial begin
        operand_a   = 32'b0;
        operand_b   = 32'b0;
        alu_control = 4'b0;
        failures    = 0;

        // Arithmetic operations, including 32-bit modular overflow behavior.
        check_alu(32'd15, 32'd27, 4'b0000, 32'd42, 1'b0, "ADD");
        check_alu(32'h7FFF_FFFF, 32'd1, 4'b0000, 32'h8000_0000, 1'b0,
                  "ADD wrap-around overflow");
        check_alu(32'd42, 32'd15, 4'b0001, 32'd27, 1'b0, "SUB");
        check_alu(32'd0, 32'd1, 4'b0001, 32'hFFFF_FFFF, 1'b0,
                  "SUB wrap-around underflow");

        // Bitwise logical operations.
        check_alu(32'hF0F0_AA55, 32'h0FF0_0F0F, 4'b0010, 32'h00F0_0A05,
                  1'b0, "AND");
        check_alu(32'hF0F0_AA55, 32'h0FF0_0F0F, 4'b0011, 32'hFFF0_AF5F,
                  1'b0, "OR");
        check_alu(32'hF0F0_AA55, 32'h0FF0_0F0F, 4'b0100, 32'hFF00_A55A,
                  1'b0, "XOR");

        // Shift operations use only operand_b[4:0], including edge shifts.
        check_alu(32'h0000_0001, 32'd31, 4'b0101, 32'h8000_0000, 1'b0,
                  "SLL by 31");
        check_alu(32'h0000_0001, 32'd32, 4'b0101, 32'h0000_0001, 1'b0,
                  "SLL ignores shift bits above bit 4");
        check_alu(32'h8000_0000, 32'd31, 4'b0110, 32'h0000_0001, 1'b0,
                  "SRL by 31");
        check_alu(32'h8000_0000, 32'd4, 4'b0111, 32'hF800_0000, 1'b0,
                  "SRA sign extension");
        check_alu(32'h8000_0000, 32'd31, 4'b0111, 32'hFFFF_FFFF, 1'b0,
                  "SRA by 31");

        // Signed comparisons distinguish positive and negative operands.
        check_alu(32'd1, 32'd2, 4'b1000, 32'd1, 1'b0, "SLT positive operands");
        check_alu(32'hFFFF_FFFF, 32'd1, 4'b1000, 32'd1, 1'b0,
                  "SLT negative operand");
        check_alu(32'd1, 32'hFFFF_FFFF, 4'b1000, 32'd0, 1'b1,
                  "SLT positive greater than negative");

        // Unsigned comparison treats all operand bits as an unsigned magnitude.
        check_alu(32'hFFFF_FFFF, 32'd1, 4'b1001, 32'd0, 1'b1,
                  "SLTU unsigned comparison false");
        check_alu(32'd1, 32'hFFFF_FFFF, 4'b1001, 32'd1, 1'b0,
                  "SLTU unsigned comparison true");

        // Equal subtraction verifies explicit zero-flag behavior.
        check_alu(32'h1234_5678, 32'h1234_5678, 4'b0001, 32'b0, 1'b1,
                  "zero flag for zero result");

        // Unsupported control values are specified to return a zero result.
        check_alu(32'hAAAA_AAAA, 32'h5555_5555, 4'b1111, 32'b0, 1'b1,
                  "unsupported ALU control returns zero");

        if (failures == 0)
            $display("PASS: ALL ALU TESTS PASSED");
        else
            $display("FAIL: ALU TESTBENCH HAS %0d FAILURE(S)", failures);

        $finish;
    end
endmodule
