module tb_ALU();

    reg [7:0] A, B;
    reg [2:0] ALU_Sel;
    wire [7:0] ALU_Out;
    wire CarryOut;

    ALU uut (
        .A(A),
        .B(B),
        .ALU_Sel(ALU_Sel),
        .ALU_Out(ALU_Out),
        .CarryOut(CarryOut)
    );

    initial begin
        // Test ADD
        A = 8'h15; B = 8'h0A; ALU_Sel = 3'b000; #10;
        // Test SUB
        A = 8'h15; B = 8'h0A; ALU_Sel = 3'b001; #10;
        // Test AND
        A = 8'hF0; B = 8'h0F; ALU_Sel = 3'b010; #10;
        // Test OR
        A = 8'hF0; B = 8'h0F; ALU_Sel = 3'b011; #10;
        // Test XOR
        A = 8'hFF; B = 8'h0F; ALU_Sel = 3'b100; #10;
        
        // Test ADD with Carryout
        A = 8'hff; B = 8'hff; ALU_Sel = 3'b000; #10;

        $stop;
    end

endmodule
