`timescale 1ns/1ps

// Self-checking testbench for word-addressable RV32I data memory.
module tb_data_memory;
    reg         clk;
    reg         reset;
    reg  [31:0] address;
    reg  [31:0] write_data;
    reg         mem_read;
    reg         mem_write;
    wire [31:0] read_data;
    integer     failures;

    // A four-word instance provides compact tests of the range boundary.
    data_memory #(
        .MEM_DEPTH(4)
    ) dut (
        .clk        (clk),
        .reset      (reset),
        .address    (address),
        .write_data (write_data),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .read_data  (read_data)
    );

    // Generate a 100 MHz clock for reset and memory writes.
    always #5 clk = ~clk;

    // Check a combinational read at the supplied byte address.
    task check_read;
        input [31:0] test_address;
        input [31:0] expected_data;
        input [8*56-1:0] test_name;
        begin
            address  = test_address;
            mem_read = 1'b1;
            #1;
            if (read_data !== expected_data) begin
                $display("FAIL: %0s. Expected %h, got %h", test_name,
                         expected_data, read_data);
                failures = failures + 1;
            end else begin
                $display("PASS: %0s", test_name);
            end
        end
    endtask

    // Perform a synchronous write. The caller can subsequently read the word.
    task write_word;
        input [31:0] test_address;
        input [31:0] test_data;
        begin
            address    = test_address;
            write_data = test_data;
            mem_write  = 1'b1;
            @(posedge clk);
            #1;
            mem_write  = 1'b0;
        end
    endtask

    initial begin
        clk        = 1'b0;
        reset      = 1'b0;
        address    = 32'b0;
        write_data = 32'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        failures   = 0;

        // Reset clears every memory word synchronously.
        reset = 1'b1;
        @(posedge clk);
        #1;
        reset = 1'b0;
        check_read(32'h0000_0000, 32'b0, "reset clears first word");
        check_read(32'h0000_000C, 32'b0, "reset clears highest word");

        // Verify a single write followed by an asynchronous read.
        mem_read = 1'b0;
        write_word(32'h0000_0000, 32'h1234_5678);
        check_read(32'h0000_0000, 32'h1234_5678, "single write and read-after-write");

        // Multiple independent writes preserve each word's data.
        mem_read = 1'b0;
        write_word(32'h0000_0004, 32'hCAFE_BABE);
        write_word(32'h0000_000C, 32'h0BAD_F00D);
        check_read(32'h0000_0004, 32'hCAFE_BABE, "multiple writes word one");
        check_read(32'h0000_000C, 32'h0BAD_F00D, "highest valid address write");

        // Address low bits do not change the selected 32-bit word.
        mem_read = 1'b0;
        write_word(32'h0000_0005, 32'h55AA_55AA);
        check_read(32'h0000_0004, 32'h55AA_55AA, "word alignment ignores address low bits");

        // A disabled write must leave the addressed word unchanged.
        address    = 32'h0000_0008;
        write_data = 32'hDEAD_BEEF;
        mem_write  = 1'b0;
        @(posedge clk);
        #1;
        check_read(32'h0000_0008, 32'b0, "mem_write disabled");

        // A disabled read must return zero without changing stored data.
        address  = 32'h0000_0000;
        mem_read = 1'b0;
        #1;
        if (read_data !== 32'b0) begin
            $display("FAIL: mem_read disabled. Expected zero, got %h", read_data);
            failures = failures + 1;
        end else begin
            $display("PASS: mem_read disabled");
        end
        check_read(32'h0000_0000, 32'h1234_5678,
                   "disabled read does not corrupt memory");

        // Out-of-range writes are ignored and reads return zero.
        mem_read = 1'b0;
        write_word(32'h0000_0010, 32'hFFFF_FFFF);
        check_read(32'h0000_0010, 32'b0, "out-of-range read returns zero");
        check_read(32'h0000_000C, 32'h0BAD_F00D,
                   "out-of-range write does not corrupt memory");

        // During a valid simultaneous read/write, the old word is observed
        // before the clock edge and the new word is observed after the edge.
        address    = 32'h0000_0008;
        write_data = 32'hA5A5_A5A5;
        mem_read   = 1'b1;
        mem_write  = 1'b1;
        #1;
        if (read_data !== 32'b0) begin
            $display("FAIL: simultaneous read/write before edge. Expected zero, got %h",
                     read_data);
            failures = failures + 1;
        end else begin
            $display("PASS: simultaneous read/write before edge");
        end
        @(posedge clk);
        #1;
        mem_write = 1'b0;
        if (read_data !== 32'hA5A5_A5A5) begin
            $display("FAIL: simultaneous read/write after edge. Expected A5A5_A5A5, got %h",
                     read_data);
            failures = failures + 1;
        end else begin
            $display("PASS: simultaneous read/write after edge");
        end

        if (failures == 0)
            $display("PASS: ALL DATA MEMORY TESTS PASSED");
        else
            $display("FAIL: DATA MEMORY TESTBENCH HAS %0d FAILURE(S)", failures);

        $finish;
    end
endmodule
