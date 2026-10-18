`timescale 1ns/1ps
// Simple SoC wrapper: rv32i_core + 4 KB instruction ROM + 4 KB data RAM.
// Memories are modelled behaviourally (async read) for simulation.
module soc_top #(
    parameter IMEM_FILE = "sw/test.hex"
) (
    input  clk,
    input  rst,
    output retire
);
    wire [31:0] imem_addr, imem_rdata;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wstrb;

    rv32i_core u_core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_wstrb(dmem_wstrb), .dmem_rdata(dmem_rdata),
        .retire(retire)
    );

    // ---- instruction memory (1024 words) ----
    reg [31:0] imem [0:1023];
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) imem[i] = 32'h0000_0013;  // NOP fill
        $readmemh(IMEM_FILE, imem);
    end
    assign imem_rdata = imem[imem_addr[11:2]];

    // ---- data memory (1024 words, byte-enable write) ----
    reg [31:0] dmem [0:1023];
    initial for (i = 0; i < 1024; i = i + 1) dmem[i] = 32'd0;

    wire [9:0]  daddr = dmem_addr[11:2];
    wire [31:0] cur   = dmem[daddr];
    wire [31:0] merged = {
        dmem_wstrb[3] ? dmem_wdata[31:24] : cur[31:24],
        dmem_wstrb[2] ? dmem_wdata[23:16] : cur[23:16],
        dmem_wstrb[1] ? dmem_wdata[15:8]  : cur[15:8],
        dmem_wstrb[0] ? dmem_wdata[7:0]   : cur[7:0]
    };
    always @(posedge clk)
        if (|dmem_wstrb) dmem[daddr] <= merged;

    assign dmem_rdata = cur;
endmodule
