# Makefile for tb_ps2_interface_device using Vivado xsim
# Tests ps2_interface in DEVICE mode
#
# Usage:
#   make		  - Compile and run simulation (tb_ps2_interface_device.vhd)
#   make clean	- Remove generated files
#   make wave	 - Open waveform viewer (after simulation)
#
# Paths
SRC_DIR = ../sources_1
TB_DIR = .

# Source files (hierarchy: ps2_interface_device <- tb)
SRCS = ../../ps2_interface_device.sv \
	../../ps2_sniffer.sv \
	$(TB_DIR)/tb_ps2_interface_device.sv

# Simulation parameters
TOP = tb_ps2_interface_device
SNAPSHOT = tb_ps2_interface_device_snap
TIMEOUT ?= 30

# xsim commands
XVHDL = xvhdl
XELAB = xelab
XSIM = xsim

# Build directory
WORK_DIR = xsim.dir

.PHONY: all sim run clean wave help ref

all: sim

# Compile SystemVerilog sources
compile: $(SRCS)
	@echo "=== Compiling SystemVerilog sources ==="
	xvlog --sv $(SRCS)
	@echo ""

# Elaborate design
elaborate: compile
	@echo "=== Elaborating design ==="
	$(XELAB) -L work $(TOP) -s $(SNAPSHOT) -debug typical
	@echo ""

# Run simulation
sim: elaborate
	@echo "=== Running simulation (timeout: $(TIMEOUT)s) ==="
	@timeout $(TIMEOUT) $(XSIM) $(SNAPSHOT) -onfinish quit -runall || \
		(if [ $$? -eq 124 ]; then \
			echo "ERROR: Simulation timed out after $(TIMEOUT) seconds"; \
			exit 1; \
		fi; \
		exit $$?)
	@echo "=== Simulation complete ==="

# Alternative: just run (if already compiled)
run:
	@echo "=== Running simulation (assuming already compiled) ==="
	@timeout $(TIMEOUT) $(XSIM) $(SNAPSHOT) -onfinish quit -runall || \
		(if [ $$? -eq 124 ]; then \
			echo "ERROR: Simulation timed out after $(TIMEOUT) seconds"; \
			exit 1; \
		fi; \
		exit $$?) \
	fi

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
	@echo "Makefile for tb_ps2_interface_device - PS/2 DEVICE Mode Testbench"
	@echo ""
	@echo "Targets:"
	@echo "  make		  - Compile and run simulation (default)"
	@echo "  make sim	  - Same as 'make'"
	@echo "  make run	  - Run simulation (skip recompile)"
	@echo "  make wave	 - Open waveform viewer"
	@echo "  make clean	- Remove all generated files"
	@echo "  make help	 - Show this help message"
	@echo ""
