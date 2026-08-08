`timescale 1ns/1ps

// Self-checking testbench for RV32I immediate decoding.
module tb_immediate_generator;
    reg  [31:0] instruction;
    wire [31:0] immediate;
    reg  [12:0] branch_offset;
    reg  [20:0] jump_offset;
    integer     failures;

    immediate_generator dut (
        .instruction (instruction),
        .immediate   (immediate)
    );

    // Apply an instruction and compare its combinational immediate output.
    task check_immediate;
        input [31:0] test_instruction;
        input [31:0] expected_immediate;
        input [8*56-1:0] test_name;
        begin
            instruction = test_instruction;
            #1;
            if (immediate !== expected_immediate) begin
                $display("FAIL: %0s. Expected %h, got %h", test_name,
                         expected_immediate, immediate);
                failures = failures + 1;
            end else begin
                $display("PASS: %0s", test_name);
            end
        end
    endtask

    initial begin
        instruction   = 32'b0;
        branch_offset = 13'b0;
        jump_offset   = 21'b0;
        failures      = 0;

        // I-type: positive and negative signed 12-bit operands.
        check_immediate({12'h07F, 5'd0, 3'b111, 5'd1, 7'b0010011},
                        32'h0000_007F, "I-type ANDI positive immediate");
        check_immediate({12'hFF8, 5'd0, 3'b000, 5'd1, 7'b0010011},
                        32'hFFFF_FFF8, "I-type ADDI negative immediate");
        check_immediate({12'h014, 5'd0, 3'b010, 5'd2, 7'b0000011},
                        32'h0000_0014, "I-type LW immediate");
        check_immediate({12'hFFC, 5'd1, 3'b000, 5'd0, 7'b1100111},
                        32'hFFFF_FFFC, "I-type JALR immediate");

        // S-type: store offsets use non-contiguous signed immediate bits.
        check_immediate({7'b0000000, 5'd2, 5'd1, 3'b010, 5'b10100,
                         7'b0100011}, 32'h0000_0014,
                        "S-type SW positive offset");
        check_immediate({7'b1111111, 5'd2, 5'd1, 3'b010, 5'b10000,
                         7'b0100011}, 32'hFFFF_FFF0,
                        "S-type SW negative offset");

        // B-type: offsets include an implied low zero bit and are sign-extended.
        branch_offset = 13'h0010;
        check_immediate({branch_offset[12], branch_offset[10:5], 5'd2, 5'd1,
                         3'b000, branch_offset[4:1], branch_offset[11],
                         7'b1100011}, {{19{branch_offset[12]}}, branch_offset},
                        "B-type BEQ positive branch offset");
        branch_offset = 13'h1FFC;
        check_immediate({branch_offset[12], branch_offset[10:5], 5'd2, 5'd1,
                         3'b001, branch_offset[4:1], branch_offset[11],
                         7'b1100011}, {{19{branch_offset[12]}}, branch_offset},
                        "B-type BNE negative branch offset");

        // U-type: no sign extension is needed; the upper 20 bits are retained.
        check_immediate({20'h12345, 5'd1, 7'b0110111}, 32'h1234_5000,
                        "U-type LUI upper immediate");
        check_immediate({20'hFFFFF, 5'd2, 7'b0010111}, 32'hFFFF_F000,
                        "U-type AUIPC upper immediate");

        // J-type: jump offsets are signed, rearranged, and have bit zero clear.
        jump_offset = 21'h00800;
        check_immediate({jump_offset[20], jump_offset[10:1], jump_offset[11],
                         jump_offset[19:12], 5'd1, 7'b1101111},
                        {{11{jump_offset[20]}}, jump_offset},
                        "J-type JAL positive jump offset");
        jump_offset = 21'h1FFFFC;
        check_immediate({jump_offset[20], jump_offset[10:1], jump_offset[11],
                         jump_offset[19:12], 5'd1, 7'b1101111},
                        {{11{jump_offset[20]}}, jump_offset},
                        "J-type JAL negative jump offset");

        // An opcode outside the supported RV32I groups must decode to zero.
        check_immediate(32'h0000_000F, 32'h0000_0000,
                        "unsupported opcode returns zero");

        if (failures == 0)
            $display("PASS: ALL IMMEDIATE GENERATOR TESTS PASSED");
        else
            $display("FAIL: IMMEDIATE GENERATOR TESTBENCH HAS %0d FAILURE(S)",
                     failures);

        $finish;
    end
endmodule
