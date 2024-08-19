module ControlUnit (
    input logic [3:0] opcode,      // 4-bit opcode input
    output logic [1:0] alu_op,     // ALU operation control signals
    output logic mem_read, mem_write, reg_write, jump // Other control signals
);

    always @(*) begin
        case (opcode)
            4'b0001: begin // ADD
                alu_op = 2'b00; // ALU operation for ADD
                reg_write = 1;
                mem_read = 0; mem_write = 0; jump = 0;
            end
            4'b0010: begin // SUB
                alu_op = 2'b01; // ALU operation for SUB
                reg_write = 1;
                mem_read = 0; mem_write = 0; jump = 0;
            end
            4'b0110: begin // LOAD
                alu_op = 2'b10; // ALU operation for LOAD
                reg_write = 1;
                mem_read = 1; mem_write = 0; jump = 0;
            end
            4'b0111: begin // STORE
                alu_op = 2'b11; // ALU operation for STORE
                reg_write = 0;
                mem_read = 0; mem_write = 1; jump = 0;
            end
            4'b1111: begin // JUMP
                jump = 1;
                reg_write = 0; mem_read = 0; mem_write = 0;
            end
            default: begin
                // Default case to handle undefined instructions
                reg_write = 0;
                mem_read = 0; mem_write = 0; jump = 0;
            end
        endcase
    end

endmodule
