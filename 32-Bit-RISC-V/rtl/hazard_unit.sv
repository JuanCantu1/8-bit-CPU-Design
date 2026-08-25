// hazard_unit.sv
// Load-use hazard detection — the only stall forwarding can't eliminate.
// Every other RAW hazard is resolved by forwarding_unit (EX/MEM, MEM/WB
// -> EX) plus an ID-stage MEM/WB bypass in the core; only a load
// immediately followed by a dependent instruction still needs a 1-cycle
// stall, since the loaded value genuinely isn't available (dmem hasn't
// been read yet) until one cycle after the ALU-result producers are.
//
// `load_ex` should be tied to the EX-stage instruction's
// `result_src == RESULT_MEM` — a perfect proxy for "is a load" per
// control_unit's encoding, so no separate mem_read field is needed here.

module hazard_unit (
  input  logic [4:0] rs1_id,
  input  logic [4:0] rs2_id,
  input  logic       load_ex,
  input  logic [4:0] rd_ex,
  output logic       stall
);

  assign stall = load_ex && (rd_ex != 5'd0) && ((rd_ex == rs1_id) || (rd_ex == rs2_id));

endmodule : hazard_unit
