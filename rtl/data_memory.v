// Word-addressable RV32I data memory. Each entry stores one 32-bit word;
// address bits [1:0] are ignored when selecting an entry.
module data_memory #(
    parameter MEM_DEPTH = 256
) (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] address,
    input  wire [31:0] write_data,
    input  wire        mem_read,
    input  wire        mem_write,
    output reg  [31:0] read_data
);

    reg [31:0] memory [0:MEM_DEPTH-1];
    integer i;

    // Reset synchronously clears every word. Otherwise, a write occurs only
    // on a rising clock edge when enabled and within the memory address range.
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < MEM_DEPTH; i = i + 1)
                memory[i] <= 32'b0;
        end else if (mem_write && (address[31:2] < MEM_DEPTH)) begin
            memory[address[31:2]] <= write_data;
        end
    end

    // Reads are combinational. Disabled or out-of-range reads return zero.
    // No assignment in this block changes memory contents.
    always @(*) begin
        if (mem_read && (address[31:2] < MEM_DEPTH))
            read_data = memory[address[31:2]];
        else
            read_data = 32'b0;
    end

endmodule
