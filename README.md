# 5-Stage Pipelined RV32I Core (Verilog, Yosys-synthesizable)

A classic IF-ID-EX-MEM-WB RISC-V core with data forwarding, load-use
hazard stalls, and branch/jump flushing. Self-checking testbench, a
dependency-free Python assembler, and Yosys synthesis scripts included.

```
        +----+   +----+   +----+   +-----+   +----+
  PC -> | IF |-->| ID |-->| EX |-->| MEM |-->| WB |--> regfile
        +----+   +----+   +----+   +-----+   +----+
                    ^        ^  ^                |
                    |        |  +---- forwarding-+  (EX/MEM, MEM/WB -> EX)
              hazard unit    +--- branch / jump resolved here -> flush IF, ID
              (load-use stall)
```

## Features
- Full RV32I integer ISA: ALU ops, LUI/AUIPC, JAL/JALR, 6 branch types,
  LB/LH/LW/LBU/LHU, SB/SH/SW (byte-strobe stores)
- Forwarding: EX/MEM -> EX and MEM/WB -> EX (+ register-file write bypass)
- Load-use hazard: 1-cycle stall + bubble insertion
- Control hazard: branches resolved in EX, static predict-not-taken, 2-cycle flush
- FENCE / ECALL / CSR instructions are treated as NOPs (not implemented)

## Layout
```
rtl/   alu.v decoder.v regfile.v hazard_unit.v forwarding_unit.v
       rv32i_core.v (top of the CPU)  soc_top.v (core + RAM/ROM for simulation)
tb/    tb_soc.v        self-checking testbench (registers + memory + CPI)
sw/    asm.py test.s   tiny assembler + directed test program
synth.ys synth_ice40.ys   Yosys scripts
```

## Run it (Windows-friendly, no `make` needed)
Install the OSS CAD Suite and open its environment shell, then:
```
python sw\asm.py sw\test.s sw\test.hex
iverilog -g2012 -Irtl -o sim.vvp rtl\alu.v rtl\decoder.v rtl\regfile.v rtl\hazard_unit.v rtl\forwarding_unit.v rtl\rv32i_core.v rtl\soc_top.v tb\tb_soc.v
vvp sim.vvp
gtkwave sim.vcd
yosys -s synth.ys
yosys -s synth_ice40.ys
```
(With `make` available: `make sim`, `make synth`, `make synth_ice40`.)

## Results (Yosys 0.33, Icarus 12)
| Metric | Value |
|---|---|
| Directed test | 35 register + memory checks, all pass |
| CPI on directed test | 1.46 (71 instr, 104 cycles; branch-heavy test, 16 flushes, 1 load-use stall) |
| Generic gate-level (AND/NAND/OR/NOR/XOR/XNOR/MUX + FFs) | 6,935 cells, of which 1,429 flip-flops (1,024 are the register file) |
| Longest topological path | 73 gate levels (structural estimate, not timing) |
| iCE40 mapping | 1,438 LUT4, 308 carry, 383 FFs, 4 BRAM |

## Ideas to extend it
1. Formal verification with SymbiYosys / riscv-formal
2. Branch predictor (BTB or 2-bit counters) - measure CPI before/after
3. Direct-mapped I-cache / D-cache with hit-rate counters
4. Synchronous-read memories so it maps cleanly to FPGA BRAM
5. OpenSTA / OpenROAD with Sky130 for real timing and area
