`timescale 1ns/1ps
`include "rv32i_defs.vh"

// Instruction decoder + immediate generator (ID stage)
module decoder (
    input      [31:0] instr,
    output reg [31:0] imm,
    output reg [3:0]  alu_ctrl,
    output reg        reg_write,
    output reg        mem_read,    // load
    output reg        mem_write,   // store
    output reg        alu_b_imm,   // ALU operand B = immediate
    output reg        a_pc,        // ALU operand A = PC   (AUIPC)
    output reg        a_zero,      // ALU operand A = 0    (LUI)
    output reg        is_branch,
    output reg        is_jal,
    output reg        is_jalr,
    output reg        uses_rs1,
    output reg        uses_rs2
);
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_IMM    = 7'b0010011;
    localparam OP_REG    = 7'b0110011;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire       alt    = instr[30];   // SUB / SRA select

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

    always @(*) begin
        // defaults = NOP
        imm = 32'd0;  alu_ctrl = `ALU_ADD;
        reg_write = 0; mem_read = 0; mem_write = 0;
        alu_b_imm = 0; a_pc = 0; a_zero = 0;
        is_branch = 0; is_jal = 0; is_jalr = 0;
        uses_rs1 = 0;  uses_rs2 = 0;

        case (opcode)
            OP_LUI:    begin imm = imm_u; reg_write = 1; alu_b_imm = 1; a_zero = 1; end
            OP_AUIPC:  begin imm = imm_u; reg_write = 1; alu_b_imm = 1; a_pc = 1; end
            OP_JAL:    begin imm = imm_j; reg_write = 1; is_jal = 1; end
            OP_JALR:   begin imm = imm_i; reg_write = 1; is_jalr = 1; uses_rs1 = 1; end
            OP_BRANCH: begin imm = imm_b; is_branch = 1; uses_rs1 = 1; uses_rs2 = 1; end
            OP_LOAD:   begin imm = imm_i; reg_write = 1; mem_read = 1;
                             alu_b_imm = 1; uses_rs1 = 1; end
            OP_STORE:  begin imm = imm_s; mem_write = 1;
                             alu_b_imm = 1; uses_rs1 = 1; uses_rs2 = 1; end
            OP_IMM: begin
                imm = imm_i; reg_write = 1; alu_b_imm = 1; uses_rs1 = 1;
                case (funct3)
                    3'b000: alu_ctrl = `ALU_ADD;
                    3'b010: alu_ctrl = `ALU_SLT;
                    3'b011: alu_ctrl = `ALU_SLTU;
                    3'b100: alu_ctrl = `ALU_XOR;
                    3'b110: alu_ctrl = `ALU_OR;
                    3'b111: alu_ctrl = `ALU_AND;
                    3'b001: alu_ctrl = `ALU_SLL;
                    3'b101: alu_ctrl = alt ? `ALU_SRA : `ALU_SRL;
                endcase
            end
            OP_REG: begin
                reg_write = 1; uses_rs1 = 1; uses_rs2 = 1;
                case (funct3)
                    3'b000: alu_ctrl = alt ? `ALU_SUB : `ALU_ADD;
                    3'b001: alu_ctrl = `ALU_SLL;
                    3'b010: alu_ctrl = `ALU_SLT;
                    3'b011: alu_ctrl = `ALU_SLTU;
                    3'b100: alu_ctrl = `ALU_XOR;
                    3'b101: alu_ctrl = alt ? `ALU_SRA : `ALU_SRL;
                    3'b110: alu_ctrl = `ALU_OR;
                    3'b111: alu_ctrl = `ALU_AND;
                endcase
            end
            default: ; // FENCE / ECALL / unknown -> treated as NOP
        endcase
    end
endmodule
