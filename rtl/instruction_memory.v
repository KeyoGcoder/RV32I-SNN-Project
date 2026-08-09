module instruction_memory #(
    parameter MEM_DEPTH = 256
) (
    input wire [31:0] pc,
    output reg [31:0] instruction
);

reg [31:0] memory [0:MEM_DEPTH-1];

initial begin
    $readmemh("C:/Users/Asus/Documents/RV32I_SNN_Project/RISC_V_SNN/program.mem", memory);

    $display("========================================");
    $display("PROGRAM MEM LOADED");
    $display("memory[0]  = %h", memory[0]);
    $display("memory[1]  = %h", memory[1]);
    $display("memory[10] = %h", memory[10]);
    $display("========================================");
end

always @(*) begin
    if (pc[31:2] < MEM_DEPTH)
        instruction = memory[pc[31:2]];
    else
        instruction = 32'hxxxxxxxx;
end

endmodule