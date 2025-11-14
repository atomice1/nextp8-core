# Makefile for sim_7: Waveform generation test bench
# Tests the waveform_gen task in p8sfx_core_mux.v

# Vivado simulator tools
XVLOG = xvlog
XELAB = xelab
XSIM = xsim

# Source files
SRCS = ../sources_1/p8sfx_core_mux.sv ./tb_waveform_gen.v

# Simulation snapshot name
SNAPSHOT = tb_waveform_gen_snap

# Top-level module
TOP = tb_waveform_gen

# Waveform configuration file (optional)
WCFG =

.PHONY: all compile elaborate sim run wave clean help

all: run

# Compile Verilog sources
compile:
	@echo "=== Compiling Verilog sources ==="
	$(XVLOG) --sv $(SRCS)

# Elaborate the design
elaborate: compile
	@echo "=== Elaborating design ==="
	$(XELAB) $(TOP) -s $(SNAPSHOT) -debug typical

# Run simulation
sim: elaborate
	@echo "=== Running waveform generation test ==="
	$(XSIM) $(SNAPSHOT) -runall

# Complete build and run
run: sim
	@echo "=== Simulation complete ==="

# Open waveform viewer (if WCFG is specified)
wave:
	@if [ -n "$(WCFG)" ]; then \
		echo "=== Opening waveform viewer ==="; \
		$(XSIM) $(SNAPSHOT) -gui -view $(WCFG); \
	else \
		echo "=== Opening waveform viewer (no config) ==="; \
		$(XSIM) $(SNAPSHOT) -gui; \
	fi

# Clean generated files
clean:
	@echo "=== Cleaning generated files ==="
	rm -rf xsim.dir .Xil *.jou *.log *.pb *.wdb *.wcfg

# Help target
help:
	@echo "Available targets:"
	@echo "  all      - Compile, elaborate, and run simulation (default)"
	@echo "  compile  - Compile Verilog sources"
	@echo "  elaborate- Elaborate the design"
	@echo "  sim      - Run simulation"
	@echo "  run      - Complete build and run"
	@echo "  wave     - Open waveform viewer"
	@echo "  clean    - Remove generated files"
	@echo "  help     - Show this help message"
