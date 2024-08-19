module InstructionMemory (
    input logic [7:0] pc,          // Program counter input
    output logic [15:0] instruction // Output instruction
);

    // 256 x 16-bit ROM
    logic [15:0] rom [0:255]; 

    initial begin
        // Load ROM with instructions
        rom[0] = 16'b0001000100100011;  // ADD R1, R2, R3
        rom[1] = 16'b0010000100010100;  // SUB R1, R1, R4
        rom[2] = 16'b0110000100000100;  // LOAD R1, 0x04
        rom[3] = 16'b0111000100001000;  // STORE R1, 0x08
        rom[4] = 16'b1111000000000000;  // JMP to address 0x00
        // ...
    end

    // Output the instruction based on the program counter
    assign instruction = rom[pc];

endmodule
