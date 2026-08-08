`timescale 1ns/1ps

// Self-checking testbench for the RV32I integer register file.
module tb_register_file;
    reg         clk;
    reg         reset;
    reg  [4:0]  rs1;
    reg  [4:0]  rs2;
    reg  [4:0]  rd;
    reg  [31:0] write_data;
    reg         write_enable;
    wire [31:0] read_data1;
    wire [31:0] read_data2;
    integer     failures;

    register_file dut (
        .clk          (clk),
        .reset        (reset),
        .rs1          (rs1),
        .rs2          (rs2),
        .rd           (rd),
        .write_data   (write_data),
        .write_enable (write_enable),
        .read_data1   (read_data1),
        .read_data2   (read_data2)
    );

    // Generate a 100 MHz clock for synchronous writes and reset.
    always #5 clk = ~clk;

    // Check both asynchronous read ports after their inputs have settled.
    task check_reads;
        input [4:0]  check_rs1;
        input [4:0]  check_rs2;
        input [31:0] expected_data1;
        input [31:0] expected_data2;
        input [8*56-1:0] test_name;
        begin
            rs1 = check_rs1;
            rs2 = check_rs2;
            #1;
            if ((read_data1 !== expected_data1) ||
                (read_data2 !== expected_data2)) begin
                $display("FAIL: %0s. Expected rs1=%h rs2=%h, got rs1=%h rs2=%h",
                         test_name, expected_data1, expected_data2,
                         read_data1, read_data2);
                failures = failures + 1;
            end else begin
                $display("PASS: %0s", test_name);
            end
        end
    endtask

    // Apply a synchronous write and verify the destination through a read port.
    task write_and_check;
        input [4:0]  destination;
        input [31:0] value;
        input [8*56-1:0] test_name;
        begin
            rd           = destination;
            write_data   = value;
            write_enable = 1'b1;
            @(posedge clk);
            #1;
            write_enable = 1'b0;
            check_reads(destination, 5'b0, value, 32'b0, test_name);
        end
    endtask

    initial begin
        clk          = 1'b0;
        reset        = 1'b0;
        rs1          = 5'b0;
        rs2          = 5'b0;
        rd           = 5'b0;
        write_data   = 32'b0;
        write_enable = 1'b0;
        failures     = 0;

        // Reset clears all writable registers on the active clock edge.
        reset        = 1'b1;
        rd           = 5'd7;
        write_data   = 32'hDEAD_BEEF;
        write_enable = 1'b1;
        @(posedge clk);
        #1;
        reset        = 1'b0;
        write_enable = 1'b0;
        check_reads(5'd1, 5'd31, 32'b0, 32'b0,
                    "synchronous reset clears x1 and x31");

        // Writes update their destination register after a clock edge.
        write_and_check(5'd5, 32'h1234_5678, "write updates x5");
        write_and_check(5'd12, 32'hCAFE_BABE, "write updates x12");

        // The two asynchronous ports must read separate registers at once.
        check_reads(5'd5, 5'd12, 32'h1234_5678, 32'hCAFE_BABE,
                    "simultaneous reads from x5 and x12");

        // A write request targeting x0 must have no observable effect.
        rd           = 5'd0;
        write_data   = 32'hFFFF_FFFF;
        write_enable = 1'b1;
        @(posedge clk);
        #1;
        write_enable = 1'b0;
        check_reads(5'd0, 5'd5, 32'b0, 32'h1234_5678,
                    "x0 ignores write requests");

        // Reading a destination after its completed write returns new data.
        write_and_check(5'd20, 32'h0BAD_F00D,
                        "read-after-write returns newly written data");

        if (failures == 0)
            $display("ALL REGISTER FILE TESTS PASSED");
        else
            $display("REGISTER FILE TESTBENCH FAILED: %0d failure(s)", failures);

        $finish;
    end
endmodule
