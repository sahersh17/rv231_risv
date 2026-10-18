`timescale 1ns/1ps
// Self-checking testbench: runs sw/test.hex until the program parks in its
// halt loop (jump-to-self), then checks registers + memory and reports CPI.
module tb_soc;
    reg  clk = 0;
    reg  rst = 1;
    wire retire;

    soc_top #(.IMEM_FILE("sw/test.hex")) dut (.clk(clk), .rst(rst), .retire(retire));

    always #5 clk = ~clk;

    integer cycles = 0, instrs = 0, errors = 0, stalls = 0, flushes = 0;
    reg     halted = 0;

    // performance counters (sampled just before each rising edge)
    always @(posedge clk) if (!rst && !halted) begin
        cycles <= cycles + 1;
        if (dut.u_core.id_ex_valid) instrs  <= instrs + 1;
        if (dut.u_core.stall)       stalls  <= stalls + 1;
        if (dut.u_core.redirect)    flushes <= flushes + 1;
        // jump-to-self => program finished
        if (dut.u_core.redirect && dut.u_core.redirect_pc == dut.u_core.id_ex_pc)
            halted <= 1;
    end

    task check_reg(input [4:0] r, input [31:0] expected);
        reg [31:0] got;
        begin
            got = dut.u_core.u_rf.regs[r];
            if (got !== expected) begin
                $display("  FAIL  x%0d = 0x%08h  (expected 0x%08h)", r, got, expected);
                errors = errors + 1;
            end
        end
    endtask

    task check_mem(input integer w, input [31:0] expected);
        begin
            if (dut.dmem[w] !== expected) begin
                $display("  FAIL  dmem[%0d] = 0x%08h  (expected 0x%08h)", w, dut.dmem[w], expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim.vcd");
        $dumpvars(0, tb_soc);
        repeat (3) @(posedge clk);
        rst = 0;

        // timeout guard
        fork
            begin wait (halted); end
            begin repeat (2000) @(posedge clk); $display("TIMEOUT: program never halted"); errors = errors + 1; end
        join_any
        repeat (6) @(posedge clk);       // let the pipeline drain

        $display("---- checking results ----");
        check_reg(1,  32'd5);
        check_reg(2,  32'd10);
        check_reg(3,  32'd15);
        check_reg(4,  32'd5);
        check_reg(5,  32'd10);
        check_reg(6,  32'd15);
        check_reg(7,  32'd5);
        check_reg(8,  32'd80);
        check_reg(9,  32'd20);
        check_reg(10, 32'hFFFFFFF0);
        check_reg(11, 32'hFFFFFFFC);
        check_reg(12, 32'd1);
        check_reg(13, 32'd0);
        check_reg(14, 32'h12345678);
        check_reg(15, 32'h12345678);
        check_reg(16, 32'h1234567D);
        check_reg(17, 32'h00000078);
        check_reg(18, 32'h00000012);
        check_reg(19, 32'hFFFFFFF0);
        check_reg(20, 32'h000000F0);
        check_reg(21, 32'hFFFFFFF0);
        check_reg(22, 32'h0000FFF0);
        check_reg(23, 32'd55);
        check_reg(24, 32'd11);
        check_reg(25, 32'd11);
        check_reg(26, 32'h00000084);   // JAL return address
        check_reg(27, 32'd99);
        check_reg(28, 32'd7);          // 123 would mean a flush bug
        check_reg(29, 32'h00000098);   // AUIPC
        check_reg(30, 32'd1);
        check_reg(31, 32'd0);          // non-zero => flush bug / wrong branch
        check_reg(0,  32'd0);          // x0 hard-wired to zero
        check_mem(0,  32'h12345678);
        check_mem(1,  32'h000000F0);
        check_mem(2,  32'h0000FFF0);

        $display("---- performance ----");
        $display("  cycles        : %0d", cycles);
        $display("  instructions  : %0d", instrs);
        $display("  load-use stalls: %0d", stalls);
        $display("  flush events  : %0d", flushes);
        $display("  CPI           : %0d.%02d", (cycles*100/instrs)/100, (cycles*100/instrs)%100);

        if (errors == 0) $display("\n*** ALL TESTS PASSED ***\n");
        else             $display("\n*** %0d TEST(S) FAILED ***\n", errors);
        $finish;
    end
endmodule
