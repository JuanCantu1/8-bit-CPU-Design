module tb_RegisterFile();

    reg [2:0] read_reg1, read_reg2, write_reg;
    reg [7:0] write_data;
    reg write_enable, clk;
    wire [7:0] read_data1, read_data2;

    RegisterFile uut (
        .read_reg1(read_reg1),
        .read_reg2(read_reg2),
        .write_reg(write_reg),
        .write_data(write_data),
        .write_enable(write_enable),
        .read_data1(read_data1),
        .read_data2(read_data2),
        .clk(clk)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        // Initialize values
        write_enable = 0;
        read_reg1 = 3'b000;
        read_reg2 = 3'b001;
        write_reg = 3'b000;
        write_data = 8'hFF;

        // Write to register 0
        #10 write_enable = 1;
        #10 write_reg = 3'b000; write_data = 8'hA5; #10;
        #10 write_reg = 3'b001; write_data = 8'h5A; #10;
        write_enable = 0;

        // Read from register 0 and 1
        #10 read_reg1 = 3'b000; read_reg2 = 3'b001; #10;

        $stop;
    end

endmodule

/*module tb_RegisterFile();

    reg [2:0] read_reg1, read_reg2, write_reg;
    reg [7:0] write_data;
    reg write_enable, clk;
    wire [7:0] read_data1, read_data2;

    RegisterFile uut (
        .read_reg1(read_reg1),
        .read_reg2(read_reg2),
        .write_reg(write_reg),
        .write_data(write_data),
        .write_enable(write_enable),
        .read_data1(read_data1),
        .read_data2(read_data2),
        .clk(clk)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        // Initialize values
        write_enable = 0;
        read_reg1 = 3'b000;
        read_reg2 = 3'b001;
        write_reg = 3'b000;
        write_data = 8'hFF;

        // Write to register 0
        #10 write_enable = 1;
        #10 write_reg = 3'b000; write_data = 8'hA5; #10;
        write_enable = 0;

        // Read from register 0
        #10 read_reg1 = 3'b000; // should output 0xA5 in read_data1
        #10 read_reg2 = 3'b001; // should output whatever is in register 1 (default is 0)

        #10 $stop;
    end

endmodule
*/