`timescale 1ns/1ps

// Self-checking integration testbench for the RV32I single-cycle top level.
module tb_top;
    reg     clk;
    reg     reset;
    integer failures;
    integer program_file;

    top dut (
        .clk   (clk),
        .reset (reset)
    );

    // Generate a 100 MHz processor clock.
    always #5 clk = ~clk;

    // Check the PC, architectural register values, and data memory word zero.
    task check_state;
        input [31:0] expected_pc;
        input [31:0] expected_x1;
        input [31:0] expected_x2;
        input [31:0] expected_x3;
        input [31:0] expected_x4;
        input [31:0] expected_x5;
        input [31:0] expected_x6;
        input [31:0] expected_memory_zero;
        input [8*56-1:0] test_name;
        begin
            if ((dut.pc_out                         !== expected_pc)          ||
                (dut.u_register_file.registers[1]  !== expected_x1)          ||
                (dut.u_register_file.registers[2]  !== expected_x2)          ||
                (dut.u_register_file.registers[3]  !== expected_x3)          ||
                (dut.u_register_file.registers[4]  !== expected_x4)          ||
                (dut.u_register_file.registers[5]  !== expected_x5)          ||
                (dut.u_register_file.registers[6]  !== expected_x6)          ||
                (dut.u_data_memory.memory[0]       !== expected_memory_zero)) begin
                $display("FAIL: %0s", test_name);
                $display("      PC=%h x1=%h x2=%h x3=%h x4=%h x5=%h x6=%h mem[0]=%h",
                         dut.pc_out, dut.u_register_file.registers[1],
                         dut.u_register_file.registers[2],
                         dut.u_register_file.registers[3],
                         dut.u_register_file.registers[4],
                         dut.u_register_file.registers[5],
                         dut.u_register_file.registers[6], dut.u_data_memory.memory[0]);
                failures = failures + 1;
            end else begin
                $display("PASS: %0s", test_name);
            end
        end
    endtask

    // Confirm that the exercised datapath state contains no unknown values.
    task check_no_unknowns;
        begin
            if (((^dut.pc_out)                        === 1'bx) ||
                ((^dut.u_register_file.registers[1]) === 1'bx) ||
                ((^dut.u_register_file.registers[2]) === 1'bx) ||
                ((^dut.u_register_file.registers[3]) === 1'bx) ||
                ((^dut.u_register_file.registers[4]) === 1'bx) ||
                ((^dut.u_register_file.registers[5]) === 1'bx) ||
                ((^dut.u_register_file.registers[6]) === 1'bx) ||
                ((^dut.u_data_memory.memory[0])      === 1'bx)) begin
                $display("FAIL: unknown value propagated into exercised state");
                failures = failures + 1;
            end else begin
                $display("PASS: no unknown values in exercised state");
            end
        end
    endtask

    initial begin
        clk      = 1'b0;
        reset    = 1'b0;
        failures = 0;

        // Create the program image: ADDI, ADD, SW, LW, BEQ, JAL, and targets.
        program_file = $fopen("program.mem", "w");
        if (program_file == 0) begin
            $display("FAIL: could not create program.mem");
            $finish;
        end
        $fdisplay(program_file, "%08h", 32'h0050_0093); // addi x1, x0, 5
        $fdisplay(program_file, "%08h", 32'h0070_0113); // addi x2, x0, 7
        $fdisplay(program_file, "%08h", 32'h0020_81B3); // add  x3, x1, x2
        $fdisplay(program_file, "%08h", 32'h0030_2023); // sw   x3, 0(x0)
        $fdisplay(program_file, "%08h", 32'h0000_2203); // lw   x4, 0(x0)
        $fdisplay(program_file, "%08h", 32'h0032_0463); // beq  x4, x3, 8
        $fdisplay(program_file, "%08h", 32'h0010_0293); // skipped: addi x5, x0, 1
        $fdisplay(program_file, "%08h", 32'h0080_006F); // jal  x0, 8
        $fdisplay(program_file, "%08h", 32'h0020_0293); // skipped: addi x5, x0, 2
        $fdisplay(program_file, "%08h", 32'h0090_0313); // addi x6, x0, 9
        $fdisplay(program_file, "%08h", 32'h0000_006F); // jal  x0, 0 (halt loop)
        $fclose(program_file);

        // Reload after file creation so initialization does not depend on order.
        #1;
        $readmemh("program.mem", dut.u_instruction_memory.memory);

        // Reset the PC, register file, and data memory before executing.
        reset = 1'b1;
        @(posedge clk);
        #1;
        reset = 1'b0;
        check_state(32'h0000_0000, 32'b0, 32'b0, 32'b0, 32'b0, 32'b0, 32'b0,
                    32'b0, "synchronous reset state");

        @(posedge clk); #1;
        check_state(32'h0000_0004, 32'd5, 32'b0, 32'b0, 32'b0, 32'b0, 32'b0,
                    32'b0, "ADDI x1 and normal PC increment");
        @(posedge clk); #1;
        check_state(32'h0000_0008, 32'd5, 32'd7, 32'b0, 32'b0, 32'b0, 32'b0,
                    32'b0, "ADDI x2 and normal PC increment");
        @(posedge clk); #1;
        check_state(32'h0000_000C, 32'd5, 32'd7, 32'd12, 32'b0, 32'b0, 32'b0,
                    32'b0, "ADD x3 register write");
        @(posedge clk); #1;
        check_state(32'h0000_0010, 32'd5, 32'd7, 32'd12, 32'b0, 32'b0, 32'b0,
                    32'd12, "SW writes data memory");
        @(posedge clk); #1;
        check_state(32'h0000_0014, 32'd5, 32'd7, 32'd12, 32'd12, 32'b0, 32'b0,
                    32'd12, "LW reads data memory into x4");
        @(posedge clk); #1;
        check_state(32'h0000_001C, 32'd5, 32'd7, 32'd12, 32'd12, 32'b0, 32'b0,
                    32'd12, "BEQ takes branch target");
        @(posedge clk); #1;
        check_state(32'h0000_0024, 32'd5, 32'd7, 32'd12, 32'd12, 32'b0, 32'b0,
                    32'd12, "JAL takes jump target");
        @(posedge clk); #1;
        check_state(32'h0000_0028, 32'd5, 32'd7, 32'd12, 32'd12, 32'b0, 32'd9,
                    32'd12, "jump target ADDI executes");

        check_no_unknowns;

        if (failures == 0)
            $display("PASS: ALL TOP-LEVEL INTEGRATION TESTS PASSED");
        else
            $display("FAIL: TOP-LEVEL TESTBENCH HAS %0d FAILURE(S)", failures);

        $finish;
    end
endmodule
