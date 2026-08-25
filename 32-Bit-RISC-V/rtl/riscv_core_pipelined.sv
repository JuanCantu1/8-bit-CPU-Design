// riscv_core_pipelined.sv
// 5-stage RV32I pipeline: IF -> ID -> EX -> MEM -> WB, with forwarding.
//
// Three bypass paths resolve RAW hazards without stalling, all keyed off
// register-address comparisons (never trusting a value that was already
// computed from a possibly-stale read):
//   - EX/MEM -> EX and MEM/WB -> EX (forwarding_unit.sv): feed a
//     producer's result into the CURRENT EX stage's ALU operands instead
//     of the (possibly stale) value ID/EX latched from the register file.
//     EX/MEM takes priority when both match the same register (it's the
//     more recent write).
//   - MEM/WB -> ID (inline below, feeding id_ex_d.rs1_data/rs2_data):
//     needed because regfile.sv deliberately has no same-cycle
//     write-then-read bypass (see tb_regfile.sv's timing tests) — without
//     this, a producer landing exactly 2 instructions ahead of a consumer
//     would still read stale data in ID. It only ever needs to check
//     mem_wb_q, not ex_mem_q: any producer closer than that gets caught
//     by the EX-stage paths above one cycle later, when the consumer
//     itself reaches EX — see design-notes.md for the full trace of why
//     that ordering is self-correcting.
//
// The one hazard forwarding cannot close: a load's data isn't ready
// until MEM completes, one stage later than an ALU result. An
// immediately-following dependent instruction still needs hazard_unit's
// 1-cycle stall; forwarding then supplies the loaded value on the next
// cycle via the MEM/WB -> EX path once the load reaches WB.
//
// Branch/jump resolution happens in EX (same ALU-reuse reasoning as
// riscv_core_singlecycle: branches need a target adder separate from the
// ALU since the ALU is busy with the comparison, while JAL/JALR reuse the
// ALU directly), costing a fixed 2-bubble flush on every taken
// branch/jump. An earlier revision of this file moved BRANCH/JAL
// resolution to ID to cut that to 1 bubble — reverted after
// tb_full_program.sv measured it as a net throughput LOSS for loop-shaped
// code: forwarding already resolves a loop counter's 0-gap dependency
// into EX at zero stall cost, which ID-stage resolution can't reuse
// (EX-stage forwarding runs one stage too late for an ID-stage decision),
// so ID-resolution traded a cheap flush for an expensive stall on exactly
// the kind of code that hits it most. See design-notes.md "Measured
// throughput" and "Branch/control hazard handling (reverted)" for the
// full analysis.

module riscv_core_pipelined
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst_n
);

  // ==================================================================
  // IF stage
  // ==================================================================
  logic [XLEN-1:0] pc, pc_next, pc_plus4;
  logic [XLEN-1:0] if_instr;

  logic hazard_stall;
  logic pc_redirect_taken;
  logic [XLEN-1:0] pc_redirect_target;

  pc_reg pc_reg_inst (
    .clk     (clk),
    .rst_n   (rst_n),
    .pc_next (pc_next),
    .pc      (pc)
  );

  assign pc_plus4 = pc + 32'd4;

  always_comb begin
    if (pc_redirect_taken)   pc_next = pc_redirect_target;
    else if (hazard_stall)   pc_next = pc; // hold: refetch same instruction
    else                      pc_next = pc_plus4;
  end

  imem imem_inst (
    .addr  (pc),
    .instr (if_instr)
  );

  if_id_t if_id_d, if_id_q;
  assign if_id_d.valid    = 1'b1;
  assign if_id_d.pc       = pc;
  assign if_id_d.pc_plus4 = pc_plus4;
  assign if_id_d.instr    = if_instr;

  if_id_reg if_id_reg_inst (
    .clk   (clk),
    .rst_n (rst_n),
    .stall (hazard_stall),
    .flush (pc_redirect_taken),
    .d_in  (if_id_d),
    .q_out (if_id_q)
  );

  // ==================================================================
  // ID stage
  // ==================================================================
  logic [6:0]      id_opcode;
  logic [4:0]      id_rd, id_rs1, id_rs2;
  logic [2:0]      id_funct3;
  logic            id_funct7b5;
  logic [XLEN-1:0] id_imm_ext;
  imm_src_e        id_imm_src;

  decoder decoder_inst (
    .instr    (if_id_q.instr),
    .imm_src  (id_imm_src),
    .opcode   (id_opcode),
    .rd       (id_rd),
    .funct3   (id_funct3),
    .rs1      (id_rs1),
    .rs2      (id_rs2),
    .funct7b5 (id_funct7b5),
    .imm_ext  (id_imm_ext)
  );

  logic        id_reg_write, id_mem_read, id_mem_write, id_branch, id_jump;
  result_src_e id_result_src;
  alu_src_a_e  id_alu_src_a;
  alu_src_b_e  id_alu_src_b;
  alu_op_e     id_alu_op;

  control_unit control_unit_inst (
    .opcode     (id_opcode),
    .funct3     (id_funct3),
    .funct7b5   (id_funct7b5),
    .reg_write  (id_reg_write),
    .mem_read   (id_mem_read),
    .mem_write  (id_mem_write),
    .branch     (id_branch),
    .jump       (id_jump),
    .result_src (id_result_src),
    .alu_src_a  (id_alu_src_a),
    .alu_src_b  (id_alu_src_b),
    .imm_src    (id_imm_src),
    .alu_op     (id_alu_op)
  );

  logic [XLEN-1:0] id_rs1_data_raw, id_rs2_data_raw;
  logic [XLEN-1:0] wb_result;
  mem_wb_t         mem_wb_q;

  regfile regfile_inst (
    .clk      (clk),
    .rs1_addr (id_rs1),
    .rs2_addr (id_rs2),
    .rd_addr  (mem_wb_q.rd),
    .rd_data  (wb_result),
    .we       (mem_wb_q.reg_write),
    .rs1_data (id_rs1_data_raw),
    .rs2_data (id_rs2_data_raw)
  );

  // MEM/WB -> ID bypass: see file header. Only mem_wb_q can be stale-read
  // in ID (anything closer is still mid-computation and gets corrected by
  // EX-stage forwarding once the consumer itself reaches EX).
  logic [XLEN-1:0] id_rs1_data, id_rs2_data;

  always_comb begin
    if (mem_wb_q.reg_write && (mem_wb_q.rd != 5'd0) && (mem_wb_q.rd == id_rs1))
      id_rs1_data = wb_result;
    else
      id_rs1_data = id_rs1_data_raw;
  end

  always_comb begin
    if (mem_wb_q.reg_write && (mem_wb_q.rd != 5'd0) && (mem_wb_q.rd == id_rs2))
      id_rs2_data = wb_result;
    else
      id_rs2_data = id_rs2_data_raw;
  end

  id_ex_t id_ex_q;
  ex_mem_t ex_mem_q;

  logic id_ex_is_load;
  assign id_ex_is_load = (id_ex_q.result_src == RESULT_MEM);

  hazard_unit hazard_unit_inst (
    .rs1_id  (id_rs1),
    .rs2_id  (id_rs2),
    .load_ex (id_ex_is_load),
    .rd_ex   (id_ex_q.rd),
    .stall   (hazard_stall)
  );

  id_ex_t id_ex_d;
  assign id_ex_d.valid      = if_id_q.valid;
  assign id_ex_d.reg_write  = id_reg_write;
  assign id_ex_d.mem_write  = id_mem_write;
  assign id_ex_d.branch     = id_branch;
  assign id_ex_d.jump       = id_jump;
  assign id_ex_d.result_src = id_result_src;
  assign id_ex_d.alu_src_a  = id_alu_src_a;
  assign id_ex_d.alu_src_b  = id_alu_src_b;
  assign id_ex_d.alu_op     = id_alu_op;
  assign id_ex_d.funct3     = id_funct3;
  assign id_ex_d.rd         = id_rd;
  assign id_ex_d.rs1        = id_rs1;
  assign id_ex_d.rs2        = id_rs2;
  assign id_ex_d.rs1_data   = id_rs1_data;
  assign id_ex_d.rs2_data   = id_rs2_data;
  assign id_ex_d.imm_ext    = id_imm_ext;
  assign id_ex_d.pc         = if_id_q.pc;
  assign id_ex_d.pc_plus4   = if_id_q.pc_plus4;

  id_ex_reg id_ex_reg_inst (
    .clk   (clk),
    .rst_n (rst_n),
    .stall (hazard_stall),
    .flush (pc_redirect_taken),
    .d_in  (id_ex_d),
    .q_out (id_ex_q)
  );

  // ==================================================================
  // EX stage
  // ==================================================================
  fwd_sel_e forward_a, forward_b;

  forwarding_unit forwarding_unit_inst (
    .rs1_ex        (id_ex_q.rs1),
    .rs2_ex        (id_ex_q.rs2),
    .reg_write_mem (ex_mem_q.reg_write),
    .rd_mem        (ex_mem_q.rd),
    .reg_write_wb  (mem_wb_q.reg_write),
    .rd_wb         (mem_wb_q.rd),
    .forward_a     (forward_a),
    .forward_b     (forward_b)
  );

  logic [XLEN-1:0] ex_rs1_fwd, ex_rs2_fwd;

  always_comb begin
    case (forward_a)
      FWD_EX_MEM: ex_rs1_fwd = ex_mem_q.alu_result;
      FWD_MEM_WB: ex_rs1_fwd = wb_result;
      default:    ex_rs1_fwd = id_ex_q.rs1_data;
    endcase
  end

  always_comb begin
    case (forward_b)
      FWD_EX_MEM: ex_rs2_fwd = ex_mem_q.alu_result;
      FWD_MEM_WB: ex_rs2_fwd = wb_result;
      default:    ex_rs2_fwd = id_ex_q.rs2_data;
    endcase
  end

  logic [XLEN-1:0] ex_operand_a, ex_operand_b, ex_alu_result;
  logic            ex_alu_zero;

  always_comb begin
    case (id_ex_q.alu_src_a)
      SRCA_RS1:  ex_operand_a = ex_rs1_fwd;
      SRCA_PC:   ex_operand_a = id_ex_q.pc;
      SRCA_ZERO: ex_operand_a = '0;
      default:   ex_operand_a = ex_rs1_fwd;
    endcase
  end

  assign ex_operand_b = (id_ex_q.alu_src_b == SRCB_IMM) ? id_ex_q.imm_ext : ex_rs2_fwd;

  alu alu_inst (
    .operand_a (ex_operand_a),
    .operand_b (ex_operand_b),
    .alu_op    (id_ex_q.alu_op),
    .result    (ex_alu_result),
    .zero      (ex_alu_zero)
  );

  logic            ex_branch_taken;
  logic [XLEN-1:0] ex_branch_target, ex_jump_target;

  always_comb begin
    case (id_ex_q.funct3)
      3'b000:  ex_branch_taken = ex_alu_zero;        // BEQ
      3'b001:  ex_branch_taken = ~ex_alu_zero;       // BNE
      3'b100:  ex_branch_taken = ex_alu_result[0];   // BLT
      3'b101:  ex_branch_taken = ~ex_alu_result[0];  // BGE
      3'b110:  ex_branch_taken = ex_alu_result[0];   // BLTU
      3'b111:  ex_branch_taken = ~ex_alu_result[0];  // BGEU
      default: ex_branch_taken = 1'b0;
    endcase
  end

  assign ex_branch_target = id_ex_q.pc + id_ex_q.imm_ext;
  assign ex_jump_target   = {ex_alu_result[31:1], 1'b0};

  assign pc_redirect_taken  = id_ex_q.valid && (id_ex_q.jump || (id_ex_q.branch && ex_branch_taken));
  assign pc_redirect_target = id_ex_q.jump ? ex_jump_target : ex_branch_target;

  ex_mem_t ex_mem_d;
  assign ex_mem_d.valid      = id_ex_q.valid;
  assign ex_mem_d.reg_write  = id_ex_q.reg_write;
  assign ex_mem_d.mem_write  = id_ex_q.mem_write;
  assign ex_mem_d.result_src = id_ex_q.result_src;
  assign ex_mem_d.funct3     = id_ex_q.funct3;
  assign ex_mem_d.rd         = id_ex_q.rd;
  assign ex_mem_d.alu_result = ex_alu_result;
  assign ex_mem_d.rs2_data   = ex_rs2_fwd; // store data also needs forwarding
  assign ex_mem_d.pc_plus4   = id_ex_q.pc_plus4;

  ex_mem_reg ex_mem_reg_inst (
    .clk   (clk),
    .rst_n (rst_n),
    .d_in  (ex_mem_d),
    .q_out (ex_mem_q)
  );

  // ==================================================================
  // MEM stage
  // ==================================================================
  logic [XLEN-1:0] mem_read_data;

  dmem dmem_inst (
    .clk        (clk),
    .addr       (ex_mem_q.alu_result),
    .write_data (ex_mem_q.rs2_data),
    .mem_write  (ex_mem_q.mem_write),
    .funct3     (ex_mem_q.funct3),
    .read_data  (mem_read_data)
  );

  mem_wb_t mem_wb_d;
  assign mem_wb_d.valid         = ex_mem_q.valid;
  assign mem_wb_d.reg_write     = ex_mem_q.reg_write;
  assign mem_wb_d.result_src    = ex_mem_q.result_src;
  assign mem_wb_d.rd            = ex_mem_q.rd;
  assign mem_wb_d.alu_result    = ex_mem_q.alu_result;
  assign mem_wb_d.mem_read_data = mem_read_data;
  assign mem_wb_d.pc_plus4      = ex_mem_q.pc_plus4;

  mem_wb_reg mem_wb_reg_inst (
    .clk   (clk),
    .rst_n (rst_n),
    .d_in  (mem_wb_d),
    .q_out (mem_wb_q)
  );

  // ==================================================================
  // WB stage
  // ==================================================================
  always_comb begin
    case (mem_wb_q.result_src)
      RESULT_ALU: wb_result = mem_wb_q.alu_result;
      RESULT_MEM: wb_result = mem_wb_q.mem_read_data;
      RESULT_PC4: wb_result = mem_wb_q.pc_plus4;
      default:    wb_result = mem_wb_q.alu_result;
    endcase
  end

  // ==================================================================
  // Assertions (immediate — see design-notes.md "Assertions": this
  // Icarus build silently no-ops `assert property`/concurrent
  // assertions and doesn't support `bind`, so these are procedural
  // checks embedded directly in the RTL instead of a separate,
  // bound checker module).
  // ==================================================================

  // Snapshot invariants: reading multiple registered signals in the
  // active region of the same posedge gives a mutually-consistent view
  // of "state as of the end of the previous cycle" for all of them —
  // safe to check together, no same-edge race (see design-notes.md for
  // the full reasoning; validated against a deliberately-broken
  // regfile.sv write guard before trusting this pattern).
  always_ff @(posedge clk) begin
    if (rst_n) begin
      // Fetch always requests a word-aligned address.
      assert (pc[1:0] == 2'b00)
        else $error("PC misaligned: 0x%h", pc);

      // A bubble (valid=0) must never carry a write through the
      // pipeline — every control field on it is don't-care except
      // reg_write/mem_write, which must stay clear (see the if_id_t
      // comment in riscv_pkg.sv this assertion is checking against).
      assert (id_ex_q.valid || (!id_ex_q.reg_write && !id_ex_q.mem_write))
        else $error("bubble in id_ex_q asserted reg_write/mem_write");
      assert (ex_mem_q.valid || (!ex_mem_q.reg_write && !ex_mem_q.mem_write))
        else $error("bubble in ex_mem_q asserted reg_write/mem_write");
      assert (mem_wb_q.valid || !mem_wb_q.reg_write)
        else $error("bubble in mem_wb_q asserted reg_write");

      // A taken branch/jump redirect must always win the PC-next mux,
      // regardless of any same-cycle stall request (see the
      // stall-vs-flush priority note in the file header).
      assert (!pc_redirect_taken || (pc_next == pc_redirect_target))
        else $error("pc_redirect_taken did not win PC-next priority");

      // Never forward from a producer whose destination is x0 — the
      // "never forward when rd == x0" rule from design-notes.md's
      // hazard strategy, checked at the point of use rather than only
      // trusted from forwarding_unit's own rd!=0 guard.
      assert (forward_a != FWD_EX_MEM || ex_mem_q.rd != 5'd0)
        else $error("forward_a selected EX/MEM with rd==x0");
      assert (forward_a != FWD_MEM_WB || mem_wb_q.rd != 5'd0)
        else $error("forward_a selected MEM/WB with rd==x0");
      assert (forward_b != FWD_EX_MEM || ex_mem_q.rd != 5'd0)
        else $error("forward_b selected EX/MEM with rd==x0");
      assert (forward_b != FWD_MEM_WB || mem_wb_q.rd != 5'd0)
        else $error("forward_b selected MEM/WB with rd==x0");
    end
  end

  // Temporal invariant: a load-use stall this cycle must always produce
  // a bubble in id_ex_q the following cycle (id_ex_reg's stall input is
  // supposed to guarantee this). Hand-rolled one-cycle delay since
  // Icarus's concurrent assertions (which would normally express this
  // as `hazard_stall |=> !id_ex_q.valid`) don't actually evaluate.
  logic hazard_stall_prev;

  always_ff @(posedge clk) begin
    if (rst_n && hazard_stall_prev)
      assert (!id_ex_q.valid)
        else $error("hazard_stall was asserted last cycle but id_ex_q is not a bubble this cycle");
    hazard_stall_prev <= hazard_stall;
  end

endmodule : riscv_core_pipelined
