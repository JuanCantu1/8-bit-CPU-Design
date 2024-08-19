module tb_ProgramCounter();

    logic clk;
    logic reset;
    logic load;
    logic [7:0] new_addr;
    logic [7:0] pc;

    // Instantiate the Program Counter module
    ProgramCounter uut (
        .clk(clk),
        .reset(reset),
        .load(load),
        .new_addr(new_addr),
        .pc(pc)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10ns clock period
    end

    // Test procedure
    initial begin
        // Initial values
        reset = 0;
        load = 0;
        new_addr = 8'h00;

        // Apply reset
        #10 reset = 1;
        #10 reset = 0;

        // Let the PC increment a few times
        #50;

        // Load a new address
        new_addr = 8'h10;
        load = 1;
        #10 load = 0;

        // Let the PC increment again
        #50;

        $stop;
    end

endmodule
