module ProgramCounter (
    input logic clk,             // Clock signal
    input logic reset,           // Reset signal
    input logic load,            // Load signal for jumping
    input logic [7:0] new_addr,  // New address to load on jump/branch
    output logic [7:0] pc        // Current program counter value
);

    // Always block for PC update
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pc <= 8'b0;  // Reset the PC to 0
        end else if (load) begin
            pc <= new_addr;  // Load the new address
        end else begin
            pc <= pc + 1;  // Increment the PC
        end
    end

endmodule
