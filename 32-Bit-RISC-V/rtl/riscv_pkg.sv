// riscv_pkg.sv
// Shared types and constants for the 32-bit RISC-V core.

package riscv_pkg;

  parameter int XLEN = 32;

  typedef enum logic [3:0] {
    ALU_ADD  = 4'b0000,
    ALU_SUB  = 4'b0001,
    ALU_AND  = 4'b0010,
    ALU_OR   = 4'b0011,
    ALU_XOR  = 4'b0100,
    ALU_SLL  = 4'b0101,
    ALU_SRL  = 4'b0110,
    ALU_SRA  = 4'b0111,
    ALU_SLT  = 4'b1000,
    ALU_SLTU = 4'b1001
  } alu_op_e;

  // RV32I base opcodes (instr[6:0]).
  parameter logic [6:0] OPC_LOAD   = 7'b0000011;
  parameter logic [6:0] OPC_OP_IMM = 7'b0010011;
  parameter logic [6:0] OPC_AUIPC  = 7'b0010111;
  parameter logic [6:0] OPC_STORE  = 7'b0100011;
  parameter logic [6:0] OPC_OP     = 7'b0110011;
  parameter logic [6:0] OPC_LUI    = 7'b0110111;
  parameter logic [6:0] OPC_BRANCH = 7'b1100011;
  parameter logic [6:0] OPC_JALR   = 7'b1100111;
  parameter logic [6:0] OPC_JAL    = 7'b1101111;

  // Writeback source select.
  typedef enum logic [1:0] {
    RESULT_ALU,
    RESULT_MEM,
    RESULT_PC4
  } result_src_e;

  // ALU operand-A select.
  typedef enum logic [1:0] {
    SRCA_RS1,
    SRCA_PC,
    SRCA_ZERO
  } alu_src_a_e;

  // ALU operand-B select.
  typedef enum logic {
    SRCB_RS2,
    SRCB_IMM
  } alu_src_b_e;

  // Immediate format select, per RV32I instruction encoding.
  typedef enum logic [2:0] {
    IMM_I,
    IMM_S,
    IMM_B,
    IMM_U,
    IMM_J
  } imm_src_e;

  // EX-stage forwarding source select (forwarding_unit.sv).
  typedef enum logic [1:0] {
    FWD_NONE,
    FWD_EX_MEM,
    FWD_MEM_WB
  } fwd_sel_e;

  // ---- 5-stage pipeline inter-stage register bundles ----
  // `valid` marks a bubble (inserted by a stall or a branch/jump flush)
  // vs. a real in-flight instruction; every control field on a bubble is
  // don't-care except reg_write/mem_write, which a bubble always clears.

  typedef struct packed {
    logic            valid;
    logic [XLEN-1:0] pc;
    logic [XLEN-1:0] pc_plus4;
    logic [XLEN-1:0] instr;
  } if_id_t;

  typedef struct packed {
    logic            valid;
    logic            reg_write;
    logic            mem_write;
    logic            branch;
    logic            jump;
    result_src_e     result_src;
    alu_src_a_e      alu_src_a;
    alu_src_b_e      alu_src_b;
    alu_op_e         alu_op;
    logic [2:0]      funct3;
    logic [4:0]      rd;
    logic [4:0]      rs1;
    logic [4:0]      rs2;
    logic [XLEN-1:0] rs1_data;
    logic [XLEN-1:0] rs2_data;
    logic [XLEN-1:0] imm_ext;
    logic [XLEN-1:0] pc;
    logic [XLEN-1:0] pc_plus4;
  } id_ex_t;

  typedef struct packed {
    logic            valid;
    logic            reg_write;
    logic            mem_write;
    result_src_e     result_src;
    logic [2:0]      funct3;
    logic [4:0]      rd;
    logic [XLEN-1:0] alu_result;
    logic [XLEN-1:0] rs2_data;
    logic [XLEN-1:0] pc_plus4;
  } ex_mem_t;

  typedef struct packed {
    logic            valid;
    logic            reg_write;
    result_src_e     result_src;
    logic [4:0]      rd;
    logic [XLEN-1:0] alu_result;
    logic [XLEN-1:0] mem_read_data;
    logic [XLEN-1:0] pc_plus4;
  } mem_wb_t;

endpackage : riscv_pkg