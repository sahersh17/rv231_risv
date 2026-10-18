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


// ------------------------------------------------------------------
    // EX stage
    // ------------------------------------------------------------------
    // EX/MEM and MEM/WB registers (declared early for forwarding)
    reg [31:0] ex_mem_alu_result, ex_mem_store_data;
    reg [4:0]  ex_mem_rd;
    reg [2:0]  ex_mem_funct3;
    reg        ex_mem_reg_write, ex_mem_mem_read, ex_mem_mem_write, ex_mem_valid;

    reg [31:0] mem_wb_alu_result, mem_wb_load_data;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_write, mem_wb_mem_read, mem_wb_valid;

    wire [1:0] fwd_a, fwd_b;
    forwarding_unit u_fwd (
        .id_ex_rs1(id_ex_rs1), .id_ex_rs2(id_ex_rs2),
        .ex_mem_reg_write(ex_mem_reg_write), .ex_mem_rd(ex_mem_rd),
        .mem_wb_reg_write(mem_wb_reg_write), .mem_wb_rd(mem_wb_rd),
        .fwd_a(fwd_a), .fwd_b(fwd_b)
    );

    reg [31:0] op_a, op_b;   // forwarded register operands
    always @(*) begin
        case (fwd_a)
            2'd1:    op_a = ex_mem_alu_result;
            2'd2:    op_a = wb_data;
            default: op_a = id_ex_rs1_val;
        endcase
        case (fwd_b)
            2'd1:    op_b = ex_mem_alu_result;
            2'd2:    op_b = wb_data;
            default: op_b = id_ex_rs2_val;
        endcase
    end

    wire [31:0] alu_in_a = id_ex_a_zero ? 32'd0 : (id_ex_a_pc ? id_ex_pc : op_a);
    wire [31:0] alu_in_b = id_ex_alu_b_imm ? id_ex_imm : op_b;
    wire [31:0] alu_out;

    alu u_alu (.a(alu_in_a), .b(alu_in_b), .ctrl(id_ex_alu_ctrl), .y(alu_out));

    // branch condition
    wire eq  = (op_a == op_b);
    wire lt  = ($signed(op_a) < $signed(op_b));
    wire ltu = (op_a < op_b);
    reg  branch_cond;
    always @(*) begin
        case (id_ex_funct3)
            3'b000:  branch_cond = eq;     // BEQ
            3'b001:  branch_cond = !eq;    // BNE
            3'b100:  branch_cond = lt;     // BLT
            3'b101:  branch_cond = !lt;    // BGE
            3'b110:  branch_cond = ltu;    // BLTU
            3'b111:  branch_cond = !ltu;   // BGEU
            default: branch_cond = 1'b0;
        endcase
    end

    wire        branch_taken = id_ex_is_branch & branch_cond;
    wire [31:0] pc_plus_imm  = id_ex_pc + id_ex_imm;                 // branch / JAL
    wire [31:0] jalr_target  = (op_a + id_ex_imm) & 32'hFFFF_FFFE;   // JALR

    assign redirect    = branch_taken | id_ex_is_jal | id_ex_is_jalr;
    assign redirect_pc = id_ex_is_jalr ? jalr_target : pc_plus_imm;

    // JAL/JALR write PC+4 to rd
    wire [31:0] ex_result = (id_ex_is_jal | id_ex_is_jalr) ? (id_ex_pc + 32'd4) : alu_out;

    // EX/MEM register
    always @(posedge clk) begin
        if (rst) begin
            ex_mem_alu_result <= 32'd0; ex_mem_store_data <= 32'd0;
            ex_mem_rd <= 5'd0; ex_mem_funct3 <= 3'd0;
            ex_mem_reg_write <= 0; ex_mem_mem_read <= 0; ex_mem_mem_write <= 0;
            ex_mem_valid <= 0;
        end else begin
            ex_mem_alu_result <= ex_result;
            ex_mem_store_data <= op_b;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_funct3     <= id_ex_funct3;
            ex_mem_reg_write  <= id_ex_reg_write;
            ex_mem_mem_read   <= id_ex_mem_read;
            ex_mem_mem_write  <= id_ex_mem_write;
            ex_mem_valid      <= id_ex_valid;
        end
    end

