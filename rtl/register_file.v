// RV32I integer register file: 32 registers, each 32 bits wide.
// x0 is architecturally hard-wired to zero.
module register_file (
    input  wire        clk,
    input  wire        reset,
    input  wire [4:0]  rs1,
    input  wire [4:0]  rs2,
    input  wire [4:0]  rd,
    input  wire [31:0] write_data,
    input  wire        write_enable,
    output wire [31:0] read_data1,
    output wire [31:0] read_data2
);

    reg [31:0] registers [0:31];
    integer i;

    // Synchronous reset clears x1 through x31. A write occurs only when
    // enabled and its destination is not x0, so writes to x0 are ignored.
    always @(posedge clk) begin
        if (reset) begin
            registers[0] <= 32'b0;
            for (i = 1; i < 32; i = i + 1)
                registers[i] <= 32'b0;
        end else begin
            registers[0] <= 32'b0;
            if (write_enable && (rd != 5'b0))
                registers[rd] <= write_data;
        end
    end

    // The independent asynchronous read ports return x0 as zero regardless
    // of the internal storage value, preserving the RV32I x0 invariant.
    assign read_data1 = (rs1 == 5'b0) ? 32'b0 : registers[rs1];
    assign read_data2 = (rs2 == 5'b0) ? 32'b0 : registers[rs2];

endmodule
