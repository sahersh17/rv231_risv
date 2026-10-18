`timescale 1ns/1ps
// ============================================================================
// 5-stage pipelined RV32I core  (IF -> ID -> EX -> MEM -> WB)
//
//  * Full RV32I user-level integer ISA (no CSRs / ECALL / FENCE: treated as NOP)
//  * Data forwarding  : EX/MEM -> EX and MEM/WB -> EX
//  * Load-use hazard  : 1-cycle stall
//  * Control hazard   : branches/jumps resolved in EX, 2-cycle flush penalty
//                       (static "predict not taken")
//  * Byte / half-word / word loads and stores via byte strobes
//  * Memories are external: async-read instruction port, async-read data port
// ============================================================================
module rv32i_core #(
    parameter RESET_PC = 32'h0000_0000
) (
    input         clk,
    input         rst,           // synchronous, active high

    // instruction memory (combinational read)
    output [31:0] imem_addr,
    input  [31:0] imem_rdata,

    // data memory (combinational read, synchronous byte-strobed write)
    output [31:0] dmem_addr,
    output [31:0] dmem_wdata,
    output [3:0]  dmem_wstrb,
    input  [31:0] dmem_rdata,

    output        retire         // 1 when a real instruction completes WB
);
    localparam NOP = 32'h0000_0013;   // addi x0, x0, 0

    // ------------------------------------------------------------------
    // Pipeline-wide control
    // ------------------------------------------------------------------
    wire        stall;           // load-use stall (from hazard unit)
    wire        redirect;        // taken branch / jump resolved in EX
    wire [31:0] redirect_pc;
