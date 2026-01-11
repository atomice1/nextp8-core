.PHONY: all sim wave clean

# Vivado installation
VIVADO_DIR ?= /home/chris/Xilinx/2025.1/Vivado
VIVADO_BIN := $(VIVADO_DIR)/bin

# Simulation settings
XVHDL := $(VIVADO_BIN)/xvhdl
XVLOG := $(VIVADO_BIN)/xvlog
XELAB := $(VIVADO_BIN)/xelab
XSIM := $(VIVADO_BIN)/xsim

# Timeouts
SIM_TIMEOUT ?= 60

# Design files
VHDL_FILES =

VERILOG_FILES =

SV_FILES = \
	../../../sources_1/ps2_interface.sv \
	../../ps2_interface_device.sv \
	../../ps2_sniffer.sv \
	tb_ps2_interface_comms.sv

all: sim

sim: compile run

compile: $(SV_FILES)
	@echo "=== Compiling SystemVerilog sources ==="
	$(XVLOG) --sv $(SV_FILES)
	@echo ""
	@echo "=== Elaborating design ==="
	$(XELAB) tb_ps2_interface_comms -s tb_ps2_interface_comms_snap -debug typical \
		--timescale 1ns/1ns
	@echo ""

run:
	@echo "=== Running simulation (timeout=$(SIM_TIMEOUT)s) ==="
	$(XSIM) tb_ps2_interface_comms_snap -runall

wave: compile
	@echo "=== Opening waveform viewer ==="
	$(XSIM) tb_ps2_interface_comms_snap -gui &

clean:
	@echo "Cleaning up generated files..."
	rm -rf xsim.dir xsim.jou xsim.log xelab.log xelab.pb xvhdl.log xvhdl.pb xvlog.log xvlog.pb *.wdb *.vcd

.PHONY: help
help:
	@echo "PS/2 Interface Comms Test Makefile"
	@echo "Usage:"
	@echo "  make sim		 - Compile and run simulation"
	@echo "  make wave		- Open waveform viewer"
	@echo "  make clean	   - Remove generated files"
