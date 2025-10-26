# Makefile for tb_ps2_read_keyboard using Vivado xsim
# 
# Usage:
#   make          - Compile and run simulation (tb_ps2_read_keyboard.vhd)
#   make clean    - Remove generated files
#   make wave     - Open waveform viewer (after simulation)
#
# Paths
SRC_DIR = ../sources_1
TB_DIR = .

# Source files (hierarchy: ps2_read_keyboard <- tb)
SRCS = $(SRC_DIR)/ps2_read_keyboard.vhd \
       $(TB_DIR)/tb_ps2_read_keyboard.vhd
#SRCS = $(SRC_DIR)/imports/Sinclair\ QL/src/ps2_intf.vhd \
#       $(TB_DIR)/tb_ps2_read_keyboard.vhd

# Simulation parameters
TOP = tb_ps2_read_keyboard
SNAPSHOT = tb_ps2_read_keyboard_snap

# xsim commands
XVHDL = xvhdl
XELAB = xelab
XSIM = xsim

# Build directory
WORK_DIR = xsim.dir

.PHONY: all sim run clean wave help ref

all: sim

# Compile Verilog sources
compile: $(SRCS)
	@echo "=== Compiling VHDL sources ==="
	$(XVHDL) $(SRCS)
	@echo ""

# Elaborate design
elaborate: compile
	@echo "=== Elaborating design ==="
	$(XELAB) -L work $(TOP) -s $(SNAPSHOT) -debug typical
	@echo ""

# Run simulation
sim: elaborate
	@echo "=== Running simulation ==="
	$(XSIM) $(SNAPSHOT) -runall
	@echo ""
	@echo "=== Simulation complete ==="

# Alternative: just run (if already compiled)
run:
	@echo "=== Running simulation (assuming already compiled) ==="
	$(XSIM) $(SNAPSHOT) -runall

# Open waveform viewer
wave:
	@if [ -f $(SNAPSHOT).wdb ]; then \
		echo "=== Opening waveform viewer ==="; \
		$(XSIM) --gui $(SNAPSHOT).wdb & \
	else \
		echo "ERROR: No waveform database found. Run simulation first with waveform capture enabled."; \
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
	@echo "Makefile for tb_p8audio_sfx - PICO-8 Audio SFX Testbench"
	@echo ""
	@echo "Targets:"
	@echo "  make          - Compile and run simulation (default cart)"
	@echo "  make sim      - Same as 'make'"
	@echo "  make run      - Run simulation (skip recompile)"
	@echo "  make wave     - Open waveform viewer"
	@echo "  make clean    - Remove all generated files"
	@echo "  make help     - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make                              # Run with default cart"
	@echo "  make clean && make                # Clean rebuild"
