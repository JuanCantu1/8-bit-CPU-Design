module CPU (
    input logic clk,
    input logic reset
);

    // Internal signals
    logic [7:0] pc, new_pc;
    logic [15:0] instruction;
    logic [2:0] read_reg1, read_reg2, write_reg;
    logic [7:0] read_data1, read_data2, write_data;
    logic reg_write;
    logic [2:0] alu_sel;
    logic [7:0] alu_out;
    logic carry_out;
    logic mem_read, mem_write, jump;
    logic [15:0] mem_write_data, mem_read_data;
    
    // Program Counter
    ProgramCounter PC (
        .clk(clk),
        .reset(reset),
        .load(jump),
        .new_addr(new_pc),
        .pc(pc)
    );

    // Instruction Memory
    InstructionMemory IM (
        .pc(pc),
        .instruction(instruction)
    );

    // Register File
    RegisterFile RF (
        .read_reg1(instruction[10:8]),
        .read_reg2(instruction[7:5]),
        .write_reg(instruction[4:2]),
        .write_data(write_data),
        .write_enable(reg_write),
        .read_data1(read_data1),
        .read_data2(read_data2),
        .clk(clk)
    );

    // ALU
    ALU alu (
        .A(read_data1),
        .B(read_data2),
        .ALU_Sel(alu_sel),
        .ALU_Out(alu_out),
        .CarryOut(carry_out)
    );

    // Control Unit
    ControlUnit CU (
        .opcode(instruction[15:12]),
        .alu_op(alu_sel),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .reg_write(reg_write),
        .jump(jump)
    );

    // Data Memory
    DataMemory DM (
        .clk(clk),
        .address(alu_out),
        .write_data(read_data2),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .read_data(mem_read_data)
    );

    // Example of connecting output back to the PC
    assign new_pc = pc + 8'b00000001;

endmodule
