module tb_DataMemory;

    // Testbench signals
    logic clk;
    logic [7:0] address;
    logic [15:0] write_data;
    logic mem_read, mem_write;
    logic [15:0] read_data;

    // Instantiate the DataMemory
    DataMemory uut (
        .clk(clk),
        .address(address),
        .write_data(write_data),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .read_data(read_data)
    );

    // Clock generation
    always #5 clk = ~clk;

    // Test procedure
    initial begin
        // Initialize signals
        clk = 0;
        address = 8'b0;
        write_data = 16'b0;
        mem_read = 0;
        mem_write = 0;

        // Test writing to memory
        #10;
        write_data = 16'hABCD; // Example data
        address = 8'h10;       // Example address
        mem_write = 1;
        #10; // Wait for write
        mem_write = 0;

        // Test reading from memory
        #10;
        address = 8'h10;       // Same address as write
        mem_read = 1;
        #10; // Wait for read
        mem_read = 0;

        // Check results
        if (read_data !== 16'hABCD) begin
            $display("Error: Read data mismatch. Expected 16'hABCD but got %h", read_data);
        end else begin
            $display("Read data match: %h", read_data);
        end

        // Finish simulation
        $finish;
    end

endmodule
