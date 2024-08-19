module DataMemory (
    input logic clk,
    input logic [7:0] address,
    input logic [15:0] write_data,
    input logic mem_read,
    input logic mem_write,
    output logic [15:0] read_data
);

    // 256 x 16-bit RAM
    logic [15:0] ram [0:255];

    // Read operation
    assign read_data = (mem_read) ? ram[address] : 16'bz;

    // Write operation
    always @(posedge clk) begin
        if (mem_write) begin
            ram[address] <= write_data;
        end
    end

endmodule
