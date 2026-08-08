`timescale 1ns/1ps

// Self-checking testbench for word-addressed instruction memory.
module tb_instruction_memory;
    reg  [31:0] pc;
    wire [31:0] instruction;
    integer     failures;
    integer     program_file;

    // A small depth makes the out-of-range case easy to exercise.
    instruction_memory #(
        .MEM_DEPTH(4)
    ) dut (
        .pc          (pc),
        .instruction (instruction)
    );

    // Compare a fetched instruction with the expected 32-bit word.
    task check_instruction;
        input [31:0] address;
        input [31:0] expected_instruction;
        input [8*48-1:0] test_name;
        begin
            pc = address;
            #1;
            if (instruction !== expected_instruction) begin
                $display("FAIL: %0s. Expected %h, got %h", test_name,
                         expected_instruction, instruction);
                failures = failures + 1;
            end else begin
                $display("PASS: %0s", test_name);
            end
        end
    endtask

    // Confirm that invalid accesses deliberately return an unknown value.
    task check_unknown_instruction;
        input [31:0] address;
        input [8*48-1:0] test_name;
        begin
            pc = address;
            #1;
            if ((^instruction) !== 1'bx) begin
                $display("FAIL: %0s. Expected unknown data, got %h", test_name,
                         instruction);
                failures = failures + 1;
            end else begin
                $display("PASS: %0s", test_name);
            end
        end
    endtask

    initial begin
        pc       = 32'b0;
        failures = 0;

        // Create the hexadecimal program image used by this simulation.
        program_file = $fopen("program.mem", "w");
        if (program_file == 0) begin
            $display("FAIL: could not create program.mem");
            $finish;
        end
        $fdisplay(program_file, "%08h", 32'h0000_0013); // nop
        $fdisplay(program_file, "%08h", 32'h0050_0093); // addi x1, x0, 5
        $fdisplay(program_file, "%08h", 32'h0020_8123); // example store
        $fdisplay(program_file, "%08h", 32'h0000_006F); // jal x0, 0
        $fclose(program_file);

        // Reload after creating the file, avoiding dependence on initial-block order.
        #1;
        $readmemh("program.mem", dut.memory);

        // Aligned byte addresses select consecutive instruction words.
        check_instruction(32'h0000_0000, 32'h0000_0013, "fetch word at PC 0");
        check_instruction(32'h0000_0004, 32'h0050_0093, "fetch word at PC 4");
        check_instruction(32'h0000_0008, 32'h0020_8123, "fetch word at PC 8");
        check_instruction(32'h0000_000C, 32'h0000_006F, "fetch word at PC 12");

        // PC[1:0] does not affect the word index selected by PC[31:2].
        check_instruction(32'h0000_0007, 32'h0050_0093,
                          "PC lower bits are ignored for word addressing");

        // The first word beyond the four-entry memory is invalid.
        check_unknown_instruction(32'h0000_0010, "out-of-range fetch");
        check_unknown_instruction(32'hxxxx_xxxx, "unknown PC fetch");

        if (failures == 0)
            $display("ALL INSTRUCTION MEMORY TESTS PASSED");
        else
            $display("INSTRUCTION MEMORY TESTBENCH FAILED: %0d failure(s)",
                     failures);

        $finish;
    end
endmodule
