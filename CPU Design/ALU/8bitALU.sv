module ALU (
    input [7:0] A,       // 8-bit input A
    input [7:0] B,       // 8-bit input B
    input [2:0] ALU_Sel, // ALU operation select
    output reg [7:0] ALU_Out, // 8-bit ALU output
    output reg CarryOut  // Carry out flag
);

always @(*) begin
    case(ALU_Sel)
        3'b000: {CarryOut, ALU_Out} = A + B;  // ADD
        3'b001: {CarryOut, ALU_Out} = A - B;  // SUB
        3'b010: ALU_Out = A & B;              // AND
        3'b011: ALU_Out = A | B;              // OR
        3'b100: ALU_Out = A ^ B;              // XOR
        // Additional operations
        default: ALU_Out = 8'b00000000;       // Default case
    endcase
end

endmodule
