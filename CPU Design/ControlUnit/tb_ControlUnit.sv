module tb_ControlUnit;

    // Testbench signals
    logic [3:0] tb_opcode;
    logic [1:0] tb_alu_op;
    logic tb_mem_read, tb_mem_write, tb_reg_write, tb_jump;

    // Instantiate the ControlUnit module
    ControlUnit cu (
        .opcode(tb_opcode),
        .alu_op(tb_alu_op),
        .mem_read(tb_mem_read),
        .mem_write(tb_mem_write),
        .reg_write(tb_reg_write),
        .jump(tb_jump)
    );

    // Test procedure
    initial begin
        // Test ADD instruction (opcode: 0001)
        tb_opcode = 4'b0001;
        #10;
        assert(tb_alu_op == 2'b00 && tb_reg_write == 1 && !tb_mem_read && !tb_mem_write && !tb_jump)
            else $fatal("Test failed for ADD instruction.");

        // Test SUB instruction (opcode: 0010)
        tb_opcode = 4'b0010;
        #10;
        assert(tb_alu_op == 2'b01 && tb_reg_write == 1 && !tb_mem_read && !tb_mem_write && !tb_jump)
            else $fatal("Test failed for SUB instruction.");

        // Test LOAD instruction (opcode: 0110)
        tb_opcode = 4'b0110;
        #10;
        assert(tb_alu_op == 2'b10 && tb_reg_write == 1 && tb_mem_read && !tb_mem_write && !tb_jump)
            else $fatal("Test failed for LOAD instruction.");

        // Test STORE instruction (opcode: 0111)
        tb_opcode = 4'b0111;
        #10;
        assert(tb_alu_op == 2'b11 && !tb_reg_write && !tb_mem_read && tb_mem_write && !tb_jump)
            else $fatal("Test failed for STORE instruction.");

        // Test JUMP instruction (opcode: 1111)
        tb_opcode = 4'b1111;
        #10;
        assert(!tb_reg_write && !tb_mem_read && !tb_mem_write && tb_jump)
            else $fatal("Test failed for JUMP instruction.");

        // Finish simulation
        $finish;
    end

endmodule
