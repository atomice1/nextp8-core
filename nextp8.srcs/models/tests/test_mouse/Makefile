# Makefile for mouse_device testbench
# Tests the PS/2 mouse device model in isolation

# Vivado tools
XVLOG = xvlog
XVHDL = xvhdl
XELAB = xelab
XSIM = xsim

# Directories
SRC_DIR = ../..
VHDL_SRC_DIR = ../../../sources_1

# Source files
SYSTEMVERILOG_SOURCES = $(SRC_DIR)/mouse_device.sv tb_mouse_device.sv
SV_SOURCES = $(SRC_DIR)/ps2_interface_device.sv $(VHDL_SRC_DIR)/ps2_interface.sv $(SRC_DIR)/ps2_sniffer.sv

# Testbench settings
TOP = tb_mouse_device
SNAPSHOT = $(TOP)_snap
TIMEOUT = 30

# Default target
.PHONY: all
all: sim

# Compile SystemVerilog sources
compile_sv:
	@echo "=== Compiling SystemVerilog sources ==="
	$(XVLOG) --sv $(SV_SOURCES) $(SYSTEMVERILOG_SOURCES)
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

# Open waveform viewer
wave: elaborate
	@echo "=== Opening waveform viewer ==="
	$(XSIM) $(SNAPSHOT) -gui
	@echo ""

# Clean generated files
.PHONY: clean
clean:
	@echo "=== Cleaning generated files ==="
	rm -rf xsim.dir
	rm -rf .Xil
	rm -f *.jou *.log *.pb
	rm -f *.wdb
	@echo "Clean complete"
	@echo ""

# Help target
.PHONY: help
help:
	@echo "Makefile for mouse_device testbench"
	@echo ""
	@echo "Targets:"
	@echo "  all		- Run simulation (default)"
	@echo "  sim		- Compile and run simulation"
	@echo "  wave	   - Open waveform viewer"
	@echo "  clean	  - Remove generated files"
	@echo "  help	   - Show this help message"
	@echo ""
	@echo "Source files:"
	@echo "  VHDL: $(VHDL_SOURCES)"
	@echo "  SystemVerilog: $(SYSTEMVERILOG_SOURCES)"
