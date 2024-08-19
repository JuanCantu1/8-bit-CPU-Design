module RegisterFile (
    input [2:0] read_reg1,    // Read register 1 address
    input [2:0] read_reg2,    // Read register 2 address
    input [2:0] write_reg,    // Write register address
    input [7:0] write_data,   // Data to write
    input write_enable,       // Write enable signal
    output [7:0] read_data1,  // Data output 1
    output [7:0] read_data2,  // Data output 2
    input clk                 // Clock signal
);

    // 8 registers, each 8 bits wide
    reg [7:0] registers [7:0];

    // Read data from registers
    assign read_data1 = registers[read_reg1];
    assign read_data2 = registers[read_reg2];

    // Write data to register on clock edge if write_enable is high
    always @(posedge clk) begin
        if (write_enable)
            registers[write_reg] <= write_data;
    end

endmodule
