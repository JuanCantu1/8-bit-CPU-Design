// coverage_collector.sv
// Hand-rolled functional coverage model for riscv_core_pipelined.
//
// Icarus doesn't support `covergroup`/`coverpoint` at all — a scratch
// probe with a two-bin covergroup failed to even parse ("invalid module
// item" on the `covergroup` keyword). Associative arrays don't work
// either: `int arr[string]` and `int arr[int]` elaborate as bogus
// fixed-size arrays (indices silently truncated to garbage numbers) and
// `.num()` isn't a recognized method. So this reimplements the same
// methodology by hand: every coverpoint is a set of named `int unsigned`
// hit counters (one per bin), incremented by an explicit case/if
// classifier standing in for `bins {...}`, with a print_report() task
// that plays the role of a coverage report (`get_coverage()` isn't
// available either) — called explicitly by the testbench right before
// $finish, since Icarus also rejects task calls from inside a `final`
// block, which would otherwise have been the natural place to trigger
// it automatically. See design-notes.md "Functional coverage" for the
// full reasoning and for what this surfaced in the existing test suite.
//
// Test-only: never instantiated from synthesizable RTL. A testbench
// instantiates this alongside riscv_core_pipelined and wires it to the
// DUT's internal signals via hierarchical reference (confirmed working
// for reads, though not for drives, in this Icarus build) — see
// tb_coverage.sv.

module coverage_collector
  import riscv_pkg::*;
(
  input logic       clk,
  input logic       rst_n,

  // ID-stage decode. Opcode coverage samples here rather than off
  // id_ex_q because id_ex_t only carries already-decoded control fields,
  // not the raw opcode itself.
  input logic [6:0]  id_opcode,
  input logic        if_id_valid,
  input logic        hazard_stall,

  // EX-stage instruction + forwarding outcome
  input id_ex_t      id_ex_q,
  input fwd_sel_e    forward_a,
  input fwd_sel_e    forward_b,
  input logic        ex_branch_taken
);

  // ---- opcode coverage (9 bins) ----
  // Sampled once per instruction as it leaves ID: if_id_valid gates out
  // reset/empty cycles, !hazard_stall skips the held cycle of a load-use
  // stall so the same stalled instruction isn't counted twice (harmless
  // either way for a hit/miss bin, but this keeps counts meaningful).
  int unsigned cov_opc_load, cov_opc_op_imm, cov_opc_auipc, cov_opc_store,
               cov_opc_op, cov_opc_lui, cov_opc_branch, cov_opc_jalr, cov_opc_jal;

  // ---- ALU operation coverage (10 bins) ----
  int unsigned cov_alu_add, cov_alu_sub, cov_alu_and, cov_alu_or, cov_alu_xor,
               cov_alu_sll, cov_alu_srl, cov_alu_sra, cov_alu_slt, cov_alu_sltu;

  // ---- forwarding path coverage (4 bins) ----
  // Only EX/MEM and MEM/WB are tracked as "interesting" — FWD_NONE is
  // the default/majority case for any instruction with no nearby
  // producer, so it isn't a meaningful verification target the way
  // "did we actually exercise both bypass paths" is.
  int unsigned cov_fwd_a_exmem, cov_fwd_a_memwb, cov_fwd_b_exmem, cov_fwd_b_memwb;

  // ---- load-use hazard stall coverage (1 bin) ----
  int unsigned cov_hazard_stall;

  // ---- branch outcome coverage: 6 funct3 types x taken/not-taken (12 bins) ----
  int unsigned cov_beq_taken,  cov_beq_nottaken,  cov_bne_taken,  cov_bne_nottaken,
               cov_blt_taken,  cov_blt_nottaken,  cov_bge_taken,  cov_bge_nottaken,
               cov_bltu_taken, cov_bltu_nottaken, cov_bgeu_taken, cov_bgeu_nottaken;

  // ---- x0 special-case operand coverage (3 bins) ----
  // Gated on the instruction actually having a semantic rs1/rs2 per the
  // RV32I format (the decoder blind-slices rs1/rs2 bits out of every
  // instruction word regardless of format — see decoder.sv — so e.g.
  // LUI's "rs1 field" is meaningless immediate bits, not a real operand,
  // and must not count here).
  int unsigned cov_x0_as_rs1, cov_x0_as_rs2, cov_x0_as_rd_write;

  logic ex_has_rs1, ex_has_rs2;
  assign ex_has_rs1 = (id_ex_q.alu_src_a == SRCA_RS1);
  assign ex_has_rs2 = (id_ex_q.alu_src_b == SRCB_RS2) || id_ex_q.mem_write || id_ex_q.branch;

  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (if_id_valid && !hazard_stall) begin
        case (id_opcode)
          OPC_LOAD:   cov_opc_load   <= cov_opc_load   + 1;
          OPC_OP_IMM: cov_opc_op_imm <= cov_opc_op_imm + 1;
          OPC_AUIPC:  cov_opc_auipc  <= cov_opc_auipc  + 1;
          OPC_STORE:  cov_opc_store  <= cov_opc_store  + 1;
          OPC_OP:     cov_opc_op     <= cov_opc_op     + 1;
          OPC_LUI:    cov_opc_lui    <= cov_opc_lui    + 1;
          OPC_BRANCH: cov_opc_branch <= cov_opc_branch + 1;
          OPC_JALR:   cov_opc_jalr   <= cov_opc_jalr   + 1;
          OPC_JAL:    cov_opc_jal    <= cov_opc_jal    + 1;
          default: ; // unimplemented opcode (FENCE/ECALL/...) — not a coverage goal
        endcase
      end

      if (id_ex_q.valid) begin
        case (id_ex_q.alu_op)
          ALU_ADD:  cov_alu_add  <= cov_alu_add  + 1;
          ALU_SUB:  cov_alu_sub  <= cov_alu_sub  + 1;
          ALU_AND:  cov_alu_and  <= cov_alu_and  + 1;
          ALU_OR:   cov_alu_or   <= cov_alu_or   + 1;
          ALU_XOR:  cov_alu_xor  <= cov_alu_xor  + 1;
          ALU_SLL:  cov_alu_sll  <= cov_alu_sll  + 1;
          ALU_SRL:  cov_alu_srl  <= cov_alu_srl  + 1;
          ALU_SRA:  cov_alu_sra  <= cov_alu_sra  + 1;
          ALU_SLT:  cov_alu_slt  <= cov_alu_slt  + 1;
          ALU_SLTU: cov_alu_sltu <= cov_alu_sltu + 1;
          default: ;
        endcase

        if (forward_a == FWD_EX_MEM) cov_fwd_a_exmem <= cov_fwd_a_exmem + 1;
        if (forward_a == FWD_MEM_WB) cov_fwd_a_memwb <= cov_fwd_a_memwb + 1;
        if (forward_b == FWD_EX_MEM) cov_fwd_b_exmem <= cov_fwd_b_exmem + 1;
        if (forward_b == FWD_MEM_WB) cov_fwd_b_memwb <= cov_fwd_b_memwb + 1;

        if (ex_has_rs1 && id_ex_q.rs1 == 5'd0) cov_x0_as_rs1 <= cov_x0_as_rs1 + 1;
        if (ex_has_rs2 && id_ex_q.rs2 == 5'd0) cov_x0_as_rs2 <= cov_x0_as_rs2 + 1;
        if (id_ex_q.reg_write && id_ex_q.rd == 5'd0) cov_x0_as_rd_write <= cov_x0_as_rd_write + 1;

        if (id_ex_q.branch) begin
          case (id_ex_q.funct3)
            3'b000: if (ex_branch_taken) cov_beq_taken  <= cov_beq_taken  + 1;
                    else                 cov_beq_nottaken  <= cov_beq_nottaken  + 1;
            3'b001: if (ex_branch_taken) cov_bne_taken  <= cov_bne_taken  + 1;
                    else                 cov_bne_nottaken  <= cov_bne_nottaken  + 1;
            3'b100: if (ex_branch_taken) cov_blt_taken  <= cov_blt_taken  + 1;
                    else                 cov_blt_nottaken  <= cov_blt_nottaken  + 1;
            3'b101: if (ex_branch_taken) cov_bge_taken  <= cov_bge_taken  + 1;
                    else                 cov_bge_nottaken  <= cov_bge_nottaken  + 1;
            3'b110: if (ex_branch_taken) cov_bltu_taken <= cov_bltu_taken + 1;
                    else                 cov_bltu_nottaken <= cov_bltu_nottaken + 1;
            3'b111: if (ex_branch_taken) cov_bgeu_taken <= cov_bgeu_taken + 1;
                    else                 cov_bgeu_nottaken <= cov_bgeu_nottaken + 1;
            default: ;
          endcase
        end
      end

      if (hazard_stall) cov_hazard_stall <= cov_hazard_stall + 1;
    end
  end

  // ---- report ----
  int unsigned total_bins, hit_bins;

  task automatic report_bin(input string name, input int unsigned count);
    total_bins++;
    if (count > 0) hit_bins++;
    $display("  [%s] %-20s : %0d hit%s", count > 0 ? "x" : " ", name, count,
             count == 1 ? "" : "s");
  endtask

  task automatic print_report();
    total_bins = 0;
    hit_bins   = 0;

    $display("");
    $display("==================== functional coverage report ====================");
    $display("-- opcode coverage --");
    report_bin("OPC_LOAD",   cov_opc_load);
    report_bin("OPC_OP_IMM", cov_opc_op_imm);
    report_bin("OPC_AUIPC",  cov_opc_auipc);
    report_bin("OPC_STORE",  cov_opc_store);
    report_bin("OPC_OP",     cov_opc_op);
    report_bin("OPC_LUI",    cov_opc_lui);
    report_bin("OPC_BRANCH", cov_opc_branch);
    report_bin("OPC_JALR",   cov_opc_jalr);
    report_bin("OPC_JAL",    cov_opc_jal);

    $display("-- ALU op coverage --");
    report_bin("ALU_ADD",  cov_alu_add);
    report_bin("ALU_SUB",  cov_alu_sub);
    report_bin("ALU_AND",  cov_alu_and);
    report_bin("ALU_OR",   cov_alu_or);
    report_bin("ALU_XOR",  cov_alu_xor);
    report_bin("ALU_SLL",  cov_alu_sll);
    report_bin("ALU_SRL",  cov_alu_srl);
    report_bin("ALU_SRA",  cov_alu_sra);
    report_bin("ALU_SLT",  cov_alu_slt);
    report_bin("ALU_SLTU", cov_alu_sltu);

    $display("-- forwarding path coverage --");
    report_bin("forward_a=EX/MEM", cov_fwd_a_exmem);
    report_bin("forward_a=MEM/WB", cov_fwd_a_memwb);
    report_bin("forward_b=EX/MEM", cov_fwd_b_exmem);
    report_bin("forward_b=MEM/WB", cov_fwd_b_memwb);

    $display("-- hazard coverage --");
    report_bin("load-use stall", cov_hazard_stall);

    $display("-- branch outcome coverage (type x taken/not-taken) --");
    report_bin("BEQ  taken",     cov_beq_taken);
    report_bin("BEQ  not-taken", cov_beq_nottaken);
    report_bin("BNE  taken",     cov_bne_taken);
    report_bin("BNE  not-taken", cov_bne_nottaken);
    report_bin("BLT  taken",     cov_blt_taken);
    report_bin("BLT  not-taken", cov_blt_nottaken);
    report_bin("BGE  taken",     cov_bge_taken);
    report_bin("BGE  not-taken", cov_bge_nottaken);
    report_bin("BLTU taken",     cov_bltu_taken);
    report_bin("BLTU not-taken", cov_bltu_nottaken);
    report_bin("BGEU taken",     cov_bgeu_taken);
    report_bin("BGEU not-taken", cov_bgeu_nottaken);

    $display("-- x0 special-case operand coverage --");
    report_bin("x0 as rs1",        cov_x0_as_rs1);
    report_bin("x0 as rs2",        cov_x0_as_rs2);
    report_bin("x0 as rd (write)", cov_x0_as_rd_write);

    $display("-----------------------------------------------------------------------");
    $display("TOTAL: %0d / %0d bins hit (%0d%%)", hit_bins, total_bins,
              (hit_bins * 100) / total_bins);
    if (hit_bins == total_bins) $display("FULL FUNCTIONAL COVERAGE");
    else $display("COVERAGE GAPS REMAIN — see unmarked bins above");
    $display("=======================================================================");
  endtask

  // Not a `final` block: Icarus rejects task calls from inside `final`
  // ("final procedures cannot enable/call tasks"), so the testbench
  // calls print_report() explicitly right before $finish instead.

endmodule : coverage_collector
