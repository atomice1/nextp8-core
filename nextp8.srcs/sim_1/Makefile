# Makefile for exec_tb - Full nextp8_top execution testbench
# 
# Usage:
#   make          - Compile and run simulation
#   make clean    - Remove generated files
#   make wave     - Open waveform viewer (after simulation)

# Paths
SRC_DIR = ../sources_1
IMPORTS_DIR = $(SRC_DIR)/imports/Sinclair\ QL/src
IP_GEN_DIR = ../../nextp8.gen/sources_1/ip
TB_DIR = new

# Verilog source files
VERILOG_SOURCES = \
	$(SRC_DIR)/nextp8_top.v \
	$(SRC_DIR)/dma_arbiter.v \
	$(IMPORTS_DIR)/hdmi/encoder.v \
	$(IMPORTS_DIR)/hdmi/hdmidataencoder.v \
	$(IMPORTS_DIR)/hdmi/hdmi.v \
	$(IMPORTS_DIR)/keyboard.v \
	$(IMPORTS_DIR)/mkeyboard.v \
	$(TB_DIR)/exec_tb.v

# IP core simulation files (generated)
IP_SOURCES = \
	$(IP_GEN_DIR)/pll_1/pll_sim_netlist.v \
	$(IP_GEN_DIR)/pll_hdmi_1/pll_hdmi_sim_netlist.v \
	$(IP_GEN_DIR)/vram_1/sim/vram.v

# SystemVerilog source files
SYSTEMVERILOG_SOURCES = \
	$(IMPORTS_DIR)/hdmi/hdmidelay.sv \
	$(SRC_DIR)/p8audio.sv \
	$(SRC_DIR)/p8sfx_core_mux.sv

# VHDL source files
VHDL_SOURCES = \
	$(SRC_DIR)/p8video.vhd \
	$(SRC_DIR)/ps2_read_keyboard.vhd \
	$(IMPORTS_DIR)/dac.vhd \
	$(IMPORTS_DIR)/hdmi_out_xilinx.vhd \
	$(IMPORTS_DIR)/i2c.vhd \
	$(IMPORTS_DIR)/ps2_in.vhd \
	$(IMPORTS_DIR)/spi.vhd \
	$(IMPORTS_DIR)/uart.vhd \
	$(IMPORTS_DIR)/TG68K.C-master/TG68K_Pack.vhd \
	$(IMPORTS_DIR)/TG68K.C-master/TG68K_ALU.vhd \
	$(IMPORTS_DIR)/TG68K.C-master/TG68KdotC_Kernel.vhd

# Simulation parameters
TOP = exec_tb
SNAPSHOT = exec_tb_snap
TIMEOUT ?= 60
POST_TARGET ?= 3

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
	$(XVHDL) $(VHDL_SOURCES)
	@echo ""

# Compile Verilog sources
compile_verilog: compile_vhdl
	@echo "=== Compiling Verilog/SystemVerilog sources ==="
	$(XVLOG) $(IP_SOURCES) $(VERILOG_SOURCES)
	$(XVLOG) --sv $(SYSTEMVERILOG_SOURCES)
	@echo ""

# Elaborate design
elaborate: compile_verilog
	@echo "=== Elaborating design ==="
	$(XELAB) $(TOP) -s $(SNAPSHOT) -debug typical \
		--timescale 1ns/1ps \
		-L unisims_ver -L unimacro_ver -L secureip \
		-L blk_mem_gen_v8_4_11 -L xpm \
		-generic_top "POST_TARGET=$(POST_TARGET)" \
		glbl
	@echo ""

# Run simulation
sim: elaborate
	@echo "=== Running simulation (timeout: $(TIMEOUT)s, POST_TARGET=$(POST_TARGET)) ==="
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
	@echo "Makefile for exec_tb - Full nextp8_top Execution Testbench"
	@echo ""
	@echo "Targets:"
	@echo "  make          - Compile and run simulation"
	@echo "  make sim      - Same as 'make'"
	@echo "  make run      - Run simulation (skip recompile)"
	@echo "  make wave     - Open waveform viewer"
	@echo "  make clean    - Remove all generated files"
	@echo "  make help     - Show this help message"
	@echo ""
	@echo "Options:"
	@echo "  TIMEOUT=<sec>      - Simulation timeout in seconds (default: 60)"
	@echo "  POST_TARGET=<code> - Target POST code for success (default: 3)"
	@echo ""
	@echo "Examples:"
	@echo "  make                          # Run with defaults"
	@echo "  make sim TIMEOUT=120          # Run with 120 second timeout"
	@echo "  make sim POST_TARGET=5        # Run until POST code 5"
	@echo ""
	@echo "This testbench instantiates the full nextp8_top module"
	@echo "with simulated external interfaces (SRAM, PS2, SD card, etc.)"
	@echo "Exits successfully when POST code reaches POST_TARGET."
