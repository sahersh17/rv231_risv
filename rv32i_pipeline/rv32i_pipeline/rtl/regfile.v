`timescale 1ns/1ps
// 32x32 register file: 2 async read ports, 1 sync write port.
// Write-through bypass: a read in the same cycle as a write to the
// same register returns the new value (resolves the WB->ID hazard).
module regfile (
    input         clk,
    input         we,
    input  [4:0]  waddr,
    input  [31:0] wdata,
    input  [4:0]  raddr1,
    input  [4:0]  raddr2,
    output [31:0] rdata1,
    output [31:0] rdata2
);
    reg [31:0] regs [0:31];
    integer i;
    initial for (i = 0; i < 32; i = i + 1) regs[i] = 32'd0;

    always @(posedge clk)
        if (we && waddr != 5'd0) regs[waddr] <= wdata;

    assign rdata1 = (raddr1 == 5'd0)        ? 32'd0 :
                    (we && waddr == raddr1) ? wdata : regs[raddr1];
    assign rdata2 = (raddr2 == 5'd0)        ? 32'd0 :
                    (we && waddr == raddr2) ? wdata : regs[raddr2];
endmodule
