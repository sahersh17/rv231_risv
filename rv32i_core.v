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
// ------------------------------------------------------------------
    // IF stage
    // ------------------------------------------------------------------
    reg [31:0] pc;
    assign imem_addr = pc;

    always @(posedge clk) begin
        if (rst)           pc <= RESET_PC;
        else if (redirect) pc <= redirect_pc;
        else if (!stall)   pc <= pc + 32'd4;
    end

    // IF/ID register
    reg [31:0] if_id_pc, if_id_instr;
    reg        if_id_valid;

    always @(posedge clk) begin
        if (rst || redirect) begin
            if_id_pc    <= 32'd0;
            if_id_instr <= NOP;
            if_id_valid <= 1'b0;
        end else if (!stall) begin
            if_id_pc    <= pc;
            if_id_instr <= imem_rdata;
            if_id_valid <= 1'b1;
        end
    end
// ------------------------------------------------------------------
    // ID stage
    // ------------------------------------------------------------------
    wire [4:0] id_rs1 = if_id_instr[19:15];
    wire [4:0] id_rs2 = if_id_instr[24:20];
    wire [4:0] id_rd  = if_id_instr[11:7];
    wire [2:0] id_funct3 = if_id_instr[14:12];

    wire [31:0] id_imm;
    wire [3:0]  id_alu_ctrl;
    wire        id_reg_write, id_mem_read, id_mem_write, id_alu_b_imm;
    wire        id_a_pc, id_a_zero, id_is_branch, id_is_jal, id_is_jalr;
    wire        id_uses_rs1, id_uses_rs2;

    decoder u_dec (
        .instr(if_id_instr), .imm(id_imm), .alu_ctrl(id_alu_ctrl),
        .reg_write(id_reg_write), .mem_read(id_mem_read), .mem_write(id_mem_write),
        .alu_b_imm(id_alu_b_imm), .a_pc(id_a_pc), .a_zero(id_a_zero),
        .is_branch(id_is_branch), .is_jal(id_is_jal), .is_jalr(id_is_jalr),
        .uses_rs1(id_uses_rs1), .uses_rs2(id_uses_rs2)
    );

    // write-back wires (declared here, driven in WB stage)
    wire        wb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    wire [31:0] id_rs1_val, id_rs2_val;

    regfile u_rf (
        .clk(clk), .we(wb_reg_write), .waddr(wb_rd), .wdata(wb_data),
        .raddr1(id_rs1), .raddr2(id_rs2),
        .rdata1(id_rs1_val), .rdata2(id_rs2_val)
    );

    // ID/EX register
    reg [31:0] id_ex_pc, id_ex_rs1_val, id_ex_rs2_val, id_ex_imm;
    reg [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    reg [2:0]  id_ex_funct3;
    reg [3:0]  id_ex_alu_ctrl;
    reg        id_ex_reg_write, id_ex_mem_read, id_ex_mem_write, id_ex_alu_b_imm;
    reg        id_ex_a_pc, id_ex_a_zero, id_ex_is_branch, id_ex_is_jal, id_ex_is_jalr;
    reg        id_ex_valid;

    hazard_unit u_haz (
        .id_ex_mem_read(id_ex_mem_read), .id_ex_rd(id_ex_rd),
        .if_id_rs1(id_rs1), .if_id_rs2(id_rs2),
        .uses_rs1(id_uses_rs1), .uses_rs2(id_uses_rs2),
        .stall(stall)
    );

    always @(posedge clk) begin
        if (rst || redirect || stall) begin
            // insert a bubble
            id_ex_pc <= 32'd0; id_ex_rs1_val <= 32'd0; id_ex_rs2_val <= 32'd0;
            id_ex_imm <= 32'd0;
            id_ex_rs1 <= 5'd0; id_ex_rs2 <= 5'd0; id_ex_rd <= 5'd0;
            id_ex_funct3 <= 3'd0; id_ex_alu_ctrl <= 4'd0;
            id_ex_reg_write <= 0; id_ex_mem_read <= 0; id_ex_mem_write <= 0;
            id_ex_alu_b_imm <= 0; id_ex_a_pc <= 0; id_ex_a_zero <= 0;
            id_ex_is_branch <= 0; id_ex_is_jal <= 0; id_ex_is_jalr <= 0;
            id_ex_valid <= 0;
        end else begin
            id_ex_pc <= if_id_pc;
            id_ex_rs1_val <= id_rs1_val;  id_ex_rs2_val <= id_rs2_val;
            id_ex_imm <= id_imm;
            id_ex_rs1 <= id_rs1;  id_ex_rs2 <= id_rs2;  id_ex_rd <= id_rd;
            id_ex_funct3 <= id_funct3;
            id_ex_alu_ctrl <= id_alu_ctrl;
            id_ex_reg_write <= id_reg_write;  id_ex_mem_read <= id_mem_read;
            id_ex_mem_write <= id_mem_write;  id_ex_alu_b_imm <= id_alu_b_imm;
            id_ex_a_pc <= id_a_pc;  id_ex_a_zero <= id_a_zero;
            id_ex_is_branch <= id_is_branch;
            id_ex_is_jal <= id_is_jal;  id_ex_is_jalr <= id_is_jalr;
            id_ex_valid <= if_id_valid;
        end
    end

