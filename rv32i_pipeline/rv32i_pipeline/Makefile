RTL = rtl/alu.v rtl/decoder.v rtl/regfile.v rtl/hazard_unit.v \
      rtl/forwarding_unit.v rtl/rv32i_core.v rtl/soc_top.v

all: asm sim synth

asm:            ## assemble the test program
	python sw/asm.py sw/test.s sw/test.hex

sim: asm        ## simulate with Icarus Verilog
	iverilog -g2012 -Irtl -o sim.vvp $(RTL) tb/tb_soc.v
	vvp sim.vvp

wave:           ## open waveforms in GTKWave
	gtkwave sim.vcd

synth:          ## generic Yosys synthesis (gate count, depth)
	yosys -q -l reports/yosys_generic.log -s synth.ys

synth_ice40:    ## FPGA-style mapping (LUT4 / FF counts)
	yosys -q -l reports/yosys_ice40.log -s synth_ice40.ys

clean:
	rm -f sim.vvp sim.vcd reports/*
