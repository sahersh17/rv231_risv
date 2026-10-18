`timescale 1ns/1ps
// Load-use hazard detection.
// If the instruction in EX is a load whose destination is needed by the
// instruction in ID, stall IF/ID for one cycle and insert a bubble into EX.
module hazard_unit (
    input        id_ex_mem_read,
    input [4:0]  id_ex_rd,
    input [4:0]  if_id_rs1,
    input [4:0]  if_id_rs2,
    input        uses_rs1,
    input        uses_rs2,
    output       stall
);
    assign stall = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                   ((uses_rs1 && id_ex_rd == if_id_rs1) ||
                    (uses_rs2 && id_ex_rd == if_id_rs2));
endmodule
