module tb_InstructionMemory;

    // Testbench signals
    logic [7:0] tb_pc;
    logic [15:0] tb_instruction;

    // Instantiate the InstructionMemory module
    InstructionMemory imem (
        .pc(tb_pc),
        .instruction(tb_instruction)
    );

    // Clock generation (if needed for other modules, not required here)
    // always #5 clk = ~clk;

    // Test procedure
    initial begin
        // Initialize signals
        tb_pc = 8'b00000000;  // Start with address 0

        // Wait for some time
        #10;
        
        // Check instruction at address 0
        if (tb_instruction !== 16'b0001000100100011) 
            $display("Error: Expected instruction 0001_0001_0010_0011, but got %b", tb_instruction);
        else 
            $display("Instruction at address 0 is correct: %b", tb_instruction);

        // Move to address 1
        tb_pc = 8'b00000001;
        #10;
        
        // Check instruction at address 1
        if (tb_instruction !== 16'b0010000100010100) 
            $display("Error: Expected instruction 0010_0001_0001_0100, but got %b", tb_instruction);
        else 
            $display("Instruction at address 1 is correct: %b", tb_instruction);

        // Move to address 2
        tb_pc = 8'b00000010;
        #10;
        
        // Check instruction at address 2
        if (tb_instruction !== 16'b0110000100000100) 
            $display("Error: Expected instruction 0110_0001_0000_0100, but got %b", tb_instruction);
        else 
            $display("Instruction at address 2 is correct: %b", tb_instruction);

        // Move to address 3
        tb_pc = 8'b00000011;
        #10;
        
        // Check instruction at address 3
        if (tb_instruction !== 16'b0111000100001000) 
            $display("Error: Expected instruction 0111_0001_0000_1000, but got %b", tb_instruction);
        else 
            $display("Instruction at address 3 is correct: %b", tb_instruction);

        // Move to address 4
        tb_pc = 8'b00000100;
        #10;
        
        // Check instruction at address 4
        if (tb_instruction !== 16'b1111000000000000) 
            $display("Error: Expected instruction 1111_0000_0000_0000, but got %b", tb_instruction);
        else 
            $display("Instruction at address 4 is correct: %b", tb_instruction);

        // Finish simulation
        $finish;
    end

endmodule
