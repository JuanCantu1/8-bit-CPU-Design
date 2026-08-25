// dmem.sv
// Byte-addressable data memory. Combinational read (width/sign selected by
// funct3, same encoding as LOAD/STORE), synchronous write. Little-endian,
// matching RV32I.

module dmem
  import riscv_pkg::*;
#(
  parameter int DEPTH_BYTES = 1024
) (
  input  logic             clk,
  input  logic [XLEN-1:0]  addr,
  input  logic [XLEN-1:0]  write_data,
  input  logic             mem_write,
  input  logic [2:0]       funct3,
  output logic [XLEN-1:0]  read_data
);

  logic [7:0] mem [0:DEPTH_BYTES-1];

  always_comb begin
    case (funct3)
      3'b000:  read_data = {{24{mem[addr][7]}}, mem[addr]};                     // LB
      3'b001:  read_data = {{16{mem[addr+1][7]}}, mem[addr+1], mem[addr]};      // LH
      3'b010:  read_data = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};  // LW
      3'b100:  read_data = {24'b0, mem[addr]};                                  // LBU
      3'b101:  read_data = {16'b0, mem[addr+1], mem[addr]};                     // LHU
      default: read_data = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
    endcase
  end

  always_ff @(posedge clk) begin
    if (mem_write) begin
      case (funct3)
        3'b000: begin // SB
          mem[addr] <= write_data[7:0];
        end
        3'b001: begin // SH
          mem[addr]   <= write_data[7:0];
          mem[addr+1] <= write_data[15:8];
        end
        3'b010: begin // SW
          mem[addr]   <= write_data[7:0];
          mem[addr+1] <= write_data[15:8];
          mem[addr+2] <= write_data[23:16];
          mem[addr+3] <= write_data[31:24];
        end
        default: ;
      endcase
    end
  end

endmodule : dmem
