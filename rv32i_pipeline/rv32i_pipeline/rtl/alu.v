`timescale 1ns/1ps
`include "rv32i_defs.vh"

// 32-bit ALU for RV32I
module alu (
    input      [31:0] a,
    input      [31:0] b,
    input      [3:0]  ctrl,
    output reg [31:0] y
);
    always @(*) begin
        case (ctrl)
            `ALU_ADD:  y = a + b;
            `ALU_SUB:  y = a - b;
            `ALU_SLL:  y = a << b[4:0];
            `ALU_SLT:  y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            `ALU_SLTU: y = (a < b) ? 32'd1 : 32'd0;
            `ALU_XOR:  y = a ^ b;
            `ALU_SRL:  y = a >> b[4:0];
            `ALU_SRA:  y = $signed(a) >>> b[4:0];
            `ALU_OR:   y = a | b;
            `ALU_AND:  y = a & b;
            default:   y = 32'd0;
        endcase
    end
endmodule
