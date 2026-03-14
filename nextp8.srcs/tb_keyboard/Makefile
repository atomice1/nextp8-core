# Makefile for tb_keyboard - Keyboard device model standalone testbench
#
# Usage:
#   make		  - Compile and run simulation
#   make clean	- Remove generated files
#   make wave	 - Open waveform viewer (after simulation)

# Paths
SRC_DIR = ../sources_1
TB_DIR = .

# SystemVerilog source files
SYSTEMVERILOG_SOURCES = \
	$(SRC_DIR)/hdmi/hdmidelay.sv \
	$(SRC_DIR)/p8audio.sv \
	$(SRC_DIR)/fp_ops.sv \
	$(SRC_DIR)/p8sfx_core_mux.sv \
	$(SRC_DIR)/keyboard.sv \
	$(SRC_DIR)/ps2_interface.sv \
	../models/keyboard_device.sv \
	../models/ps2_interface_device.sv \
	../models/ps2_sniffer.sv \
	../models/sram_simple.sv \
	tb_keyboard.sv

# Simulation parameters
TOP = tb_keyboard
SNAPSHOT = tb_keyboard_snap
TIMEOUT ?= 100

# xsim commands
XVHDL = xvhdl
XVLOG = xvlog
XELAB = xelab
XSIM = xsim

# Build directory
WORK_DIR = xsim.dir

.PHONY: all sim run clean wave help

all: sim

# Compile SystemVerilog sources
compile_sv:
	@echo "=== Compiling SystemVerilog sources ==="
	$(XVLOG) --sv $(SYSTEMVERILOG_SOURCES)
	@echo ""

# Elaborate design
elaborate: compile_sv
	@echo "=== Elaborating design ==="
	$(XELAB) $(TOP) -s $(SNAPSHOT) -debug typical \
		--timescale 1ns/1ns \
		-L unisims_ver -L unimacro_ver -L secureip
	@echo ""

# Run simulation
sim: elaborate
	@echo "=== Running simulation (timeout=$(TIMEOUT)s) ==="
	@timeout $(TIMEOUT) $(XSIM) $(SNAPSHOT) -runall || \
		if [ $$? -eq 124 ]; then \
			echo "ERROR: Simulation timed out after $(TIMEOUT) seconds"; \
			exit 1; \
		else \
			exit $$?; \
		fi
	@echo ""
	@echo "=== Simulation complete ==="

# Run simulation without recompiling
run:
	@echo "=== Running simulation ==="
	@timeout $(TIMEOUT) $(XSIM) $(SNAPSHOT) -runall
	@echo ""

# Open waveform viewer
wave:
	@echo "=== Opening waveform viewer ==="
	$(XSIM) $(SNAPSHOT) --gui &
	@echo ""

# Clean generated files
clean:
	@echo "=== Cleaning generated files ==="
	rm -rf $(WORK_DIR)
	rm -rf .Xil
	rm -f *.jou *.log *.pb
	rm -f *.wdb
	@echo "Clean complete"

# Help
help:
	@echo "Makefile for tb_keyboard - Keyboard device model standalone testbench"
	@echo ""
	@echo "Targets:"
	@echo "  make		  - Compile and run simulation"
	@echo "  make sim	  - Compile and run simulation"
	@echo "  make run	  - Run simulation (skip recompile)"
	@echo "  make wave	 - Open waveform viewer"
	@echo "  make clean	- Remove all generated files"
	@echo "  make help	 - Show this help message"
	@echo ""
	@echo "Options:"
	@echo "  TIMEOUT=N	 - Set simulation timeout in seconds (default: 100)"
	@echo ""
	@echo "Examples:"
	@echo "  make					# Run with defaults"
	@echo "  make sim TIMEOUT=120	# Run with 120 second timeout"
	@echo ""
	@echo "This testbench tests:"
	@echo "  - PS/2 keyboard device model (keyboard_device.sv)"
	@echo "  - PS/2 interface in DEVICE mode (ps2_interface.sv)"
	@echo "  - Scan code queueing and transmission"

