# Makefile for tb_keyboard - Keyboard matrix and latching keyboard testbench
#
# Usage:
#   make		  - Compile and run simulation
#   make clean	- Remove generated files
#   make wave	 - Open waveform viewer (after simulation)

# Paths
SRC_DIR = ../sources_1
IP_GEN_DIR = ../../nextp8.gen/sources_1/ip
TB_DIR = .

# Verilog source files
VERILOG_SOURCES = \
	$(SRC_DIR)/nextp8_top.v \
	$(SRC_DIR)/dma_arbiter.v \
	$(SRC_DIR)/hdmi/encoder.v \
	$(SRC_DIR)/hdmi/hdmidataencoder.v \
	$(SRC_DIR)/hdmi/hdmi.v \
	$(SRC_DIR)/mkeyboard.v

# IP core simulation files (generated)
IP_SOURCES = \
	$(IP_GEN_DIR)/pll_1/pll_sim_netlist.v \
	$(IP_GEN_DIR)/pll_hdmi_1/pll_hdmi_sim_netlist.v \
	$(IP_GEN_DIR)/vram_1/vram_sim_netlist.v

# SystemVerilog source files
SYSTEMVERILOG_SOURCES = \
	$(SRC_DIR)/hdmi/hdmidelay.sv \
	$(SRC_DIR)/p8audio.sv \
	$(SRC_DIR)/p8sfx_core_mux.sv \
	$(SRC_DIR)/ps2_interface.sv \
	$(SRC_DIR)/keyboard.sv \
	$(SRC_DIR)/mouse.sv \
	$(SRC_DIR)/../models/ps2_interface_device.sv \
	$(SRC_DIR)/../models/keyboard_device.sv \
	$(SRC_DIR)/../models/ps2_sniffer.sv \
	../models/sram_simple.sv \
	tb_nextp8_keyboard.sv

# VHDL source files
VHDL_SOURCES = \
	$(SRC_DIR)/p8video.vhd \
	$(SRC_DIR)/dac.vhd \
	$(SRC_DIR)/hdmi_out_xilinx.vhd \
	$(SRC_DIR)/i2c.vhd \
	$(SRC_DIR)/spi.vhd \
	$(SRC_DIR)/uart.vhd \
	$(SRC_DIR)/TG68K.C-master/TG68K_Pack.vhd \
	$(SRC_DIR)/TG68K.C-master/TG68K_ALU.vhd \
	$(SRC_DIR)/TG68K.C-master/TG68KdotC_Kernel.vhd

# Simulation parameters
TOP = tb_nextp8_keyboard
SNAPSHOT = tb_nextp8_keyboard_snap
TIMEOUT ?= 1000

# xsim commands
XVLOG = xvlog
XVHDL = xvhdl
XELAB = xelab
XSIM = xsim

# Build directory
WORK_DIR = xsim.dir

.PHONY: all sim run clean wave help rom

all: rom sim

# Build ROM
rom:
	@echo "=== Building keyboard test ROM ==="
	@$(MAKE) -f Makefile.rom
	@echo ""

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
		glbl
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
	@$(MAKE) -f Makefile.rom clean
	@echo "Clean complete"

# Help
help:
	@echo "Makefile for tb_keyboard - Keyboard matrix and latching keyboard testbench"
	@echo ""
	@echo "Targets:"
	@echo "  make		  - Build ROM, compile, and run simulation"
	@echo "  make rom	  - Build keyboard test ROM"
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
	@echo "  - PS/2 keyboard matrix reading"
	@echo "  - Membrane keyboard matrix reading"
	@echo "  - Latching keyboard matrix (btnp support)"
	@echo "  - Selective key clearing via MMIO writes"
