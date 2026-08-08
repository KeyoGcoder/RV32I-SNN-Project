`timescale 1ns/1ps

// Self-checking testbench for the program counter module.
module tb_pc;
    reg         clk;
    reg         reset;
    reg         enable;
    reg  [31:0] next_pc;
    wire [31:0] pc_out;
    integer     failures;

    pc dut (
        .clk     (clk),
        .reset   (reset),
        .enable  (enable),
        .next_pc (next_pc),
        .pc_out  (pc_out)
    );

    // Generate a 100 MHz clock.
    always #5 clk = ~clk;

    // Drive a rising edge, then verify the registered PC value.
    task check_pc;
        input [31:0] expected_pc;
        input [8*48-1:0] test_name;
        begin
            @(posedge clk);
            #1;
            if (pc_out !== expected_pc) begin
                $display("FAIL: %0s. Expected %h, got %h", test_name,
                         expected_pc, pc_out);
                failures = failures + 1;
            end else begin
                $display("PASS: %0s", test_name);
            end
        end
    endtask

    initial begin
        clk      = 1'b0;
        reset    = 1'b0;
        enable   = 1'b0;
        next_pc  = 32'b0;
        failures = 0;

        // Reset must initialize the PC to zero, irrespective of its input.
        reset   = 1'b1;
        enable  = 1'b1;
        next_pc = 32'hDEAD_BEEF;
        check_pc(32'h0000_0000, "reset initializes PC to zero");

        // With reset inactive, enable loads the supplied next-PC address.
        reset   = 1'b0;
        enable  = 1'b1;
        next_pc = 32'h0000_1000;
        check_pc(32'h0000_1000, "enable updates PC");

        // When disabled, the PC must retain its previous value.
        enable  = 1'b0;
        next_pc = 32'h0000_2000;
        check_pc(32'h0000_1000, "disable holds PC constant");

        // Verify several consecutive enabled updates.
        enable  = 1'b1;
        next_pc = 32'h0000_1004;
        check_pc(32'h0000_1004, "first sequential update");
        next_pc = 32'h0000_1008;
        check_pc(32'h0000_1008, "second sequential update");
        next_pc = 32'h0000_100C;
        check_pc(32'h0000_100C, "third sequential update");

        if (failures == 0)
            $display("ALL PC TESTS PASSED");
        else
            $display("PC TESTBENCH FAILED: %0d failure(s)", failures);

        $finish;
    end
endmodule
