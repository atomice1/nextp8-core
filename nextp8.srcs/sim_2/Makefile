# Makefile for p8video_tb - P8 video module testbench
# 
# Usage:
#   make          - Compile and run simulation
#   make clean    - Remove generated files
#   make wave     - Open waveform viewer (after simulation)

# Paths
SRC_DIR = ../sources_1
IP_DIR = $(SRC_DIR)/ip
TB_DIR = new

# IP Core (vram - video RAM)
# Note: vram is an IP core that needs to be generated first
IP_CORES = $(IP_DIR)/vram_2/vram.xci

# P8 video module (VHDL)
P8VIDEO_SRCS = $(SRC_DIR)/p8video.vhd

# Testbench (SystemVerilog)
TB_SRCS = $(TB_DIR)/p8video_tb.sv

# All source files
ALL_SRCS = $(P8VIDEO_SRCS) $(TB_SRCS)

# Simulation parameters
TOP = p8video_tb
SNAPSHOT = p8video_tb_snap
TIMEOUT ?= 30

# xsim commands
XVLOG = xvlog
XVHDL = xvhdl
XELAB = xelab
XSIM = xsim

# Build directory
WORK_DIR = xsim.dir

.PHONY: all sim run clean wave help

all: sim

# Compile VHDL sources
compile_vhdl:
	@echo "=== Compiling VHDL sources ==="
	$(XVHDL) $(P8VIDEO_SRCS)
	@echo ""

# Compile SystemVerilog testbench
compile_sv: compile_vhdl
	@echo "=== Compiling SystemVerilog testbench ==="
	$(XVLOG) --sv $(TB_SRCS)
	@echo ""

# Elaborate design
elaborate: compile_sv
	@echo "=== Elaborating design ==="
	@echo "NOTE: This testbench requires the vram IP core to be generated"
	@echo "      If you see errors about missing 'vram', generate it in Vivado GUI first"
	$(XELAB) $(TOP) -s $(SNAPSHOT) -debug typical
	@echo ""

# Run simulation
sim: elaborate
	@echo "=== Running simulation (timeout: $(TIMEOUT)s) ==="
	@timeout $(TIMEOUT) $(XSIM) $(SNAPSHOT) -runall || \
		(if [ $$? -eq 124 ]; then \
			echo "ERROR: Simulation timed out after $(TIMEOUT) seconds"; \
			exit 1; \
		else \
			exit $$?; \
		fi)
	@echo ""
	@echo "=== Simulation complete ==="

# Alternative: just run (if already compiled)
run:
	@echo "=== Running simulation (assuming already compiled) ==="
	@timeout $(TIMEOUT) $(XSIM) $(SNAPSHOT) -runall || \
		(if [ $$? -eq 124 ]; then \
			echo "ERROR: Simulation timed out after $(TIMEOUT) seconds"; \
			exit 1; \
		else \
			exit $$?; \
		fi)

# Open waveform viewer
wave:
	@if [ -f $(SNAPSHOT).wdb ]; then \
		echo "=== Opening waveform viewer ==="; \
		$(XSIM) --gui $(SNAPSHOT).wdb & \
	else \
		echo "ERROR: No waveform database found. Run simulation first."; \
	fi

# Clean generated files
clean:
	@echo "=== Cleaning generated files ==="
	rm -rf $(WORK_DIR)
	rm -rf .Xil
	rm -f *.jou *.log *.pb
	rm -f *.wdb
	rm -f xsim.ini
	@echo "Clean complete"

# Help target
help:
	@echo "Makefile for p8video_tb - P8 Video Module Testbench"
	@echo ""
	@echo "Targets:"
	@echo "  make          - Compile and run simulation"
	@echo "  make sim      - Same as 'make'"
	@echo "  make run      - Run simulation (skip recompile)"
	@echo "  make wave     - Open waveform viewer"
	@echo "  make clean    - Remove all generated files"
	@echo "  make help     - Show this help message"
	@echo ""
	@echo "This testbench tests the p8video module with a simulated vram"
	@echo "It fills the video memory with a test pattern and checks the output"
