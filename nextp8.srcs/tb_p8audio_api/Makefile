# Makefile for tb_p8audio_api using Vivado xsim
#
# Usage:
#   make          - Compile and run simulation
#   make clean    - Remove generated files
#   make wave     - Open waveform viewer (after simulation)

# Paths
SRC_DIR = ../sources_1
TB_DIR = .

# Source files
SRCS = $(SRC_DIR)/fp_ops.sv \
       $(SRC_DIR)/p8sfx_core_mux.sv \
       $(SRC_DIR)/p8audio.sv \
       $(SRC_DIR)/dma_arbiter.v \
       $(TB_DIR)/tb_test_framework_pkg.sv \
       $(TB_DIR)/tb_p8audio_api.sv

# Simulation parameters
TOP = tb_p8audio_api
SNAPSHOT = tb_p8audio_api_snap
TIMEOUT ?= 60

# xsim commands
XVLOG = xvlog
XELAB = xelab
XSIM = xsim

# Build directory
WORK_DIR = xsim.dir

.PHONY: all sim run clean wave help

all: sim

# Compile Verilog sources
compile: $(SRCS)
	@echo "=== Compiling Verilog sources ==="
	$(XVLOG) --sv $(SRCS)
	@echo ""

# Elaborate design
elaborate: compile
	@echo "=== Elaborating design ==="
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
	@echo "Makefile for tb_p8audio_api - P8 Audio API Testbench"
	@echo ""
	@echo "Targets:"
	@echo "  make          - Compile and run simulation"
	@echo "  make sim      - Same as 'make'"
	@echo "  make run      - Run simulation (skip recompile)"
	@echo "  make wave     - Open waveform viewer"
	@echo "  make clean    - Remove generated files"
	@echo "  make help     - Show this help message"
	@echo ""
	@echo "Options:"
	@echo "  TIMEOUT=<sec> - Simulation timeout (default: 60)"
