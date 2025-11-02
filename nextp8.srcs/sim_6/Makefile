# Makefile for sim_6: nextp8_top with p8audio integration test
# Usage:
#   make sim CART=path/to/cart.p8  # Compile and run simulation
#   make wave                       # Open waveform in Vivado
#   make clean                      # Remove generated files

# Default cart file
CART ?= tb_p8audio_sfx.p8

# Timeout for simulation (seconds)
TIMEOUT ?= 30

# Source files
SOURCES_DIR = ../sources_1
IMPORTS_DIR = $(SOURCES_DIR)/imports/Sinclair\ QL/src
IP_GEN_DIR = ../../nextp8.gen/sources_1/ip
SIM_DIR = .

# Verilog source files
VERILOG_SOURCES = \
	$(SOURCES_DIR)/nextp8_top.v \
	$(SOURCES_DIR)/p8audio.v \
	$(SOURCES_DIR)/p8sfx_core.v \
	$(SOURCES_DIR)/p8sfx_voice.v \
	$(SOURCES_DIR)/dma_arbiter.v \
	$(IMPORTS_DIR)/hdmi/encoder.v \
	$(IMPORTS_DIR)/hdmi/hdmidataencoder.v \
	$(IMPORTS_DIR)/hdmi/hdmi.v \
	$(IMPORTS_DIR)/keyboard.v \
	$(IMPORTS_DIR)/mkeyboard.v

# IP core simulation files (generated)
IP_SOURCES = \
	$(IP_GEN_DIR)/pll_1/pll_sim_netlist.v \
	$(IP_GEN_DIR)/pll_hdmi_1/pll_hdmi_sim_netlist.v \
	$(IP_GEN_DIR)/vram_1/sim/vram.v

# SystemVerilog source files
SYSTEMVERILOG_SOURCES = \
	$(IMPORTS_DIR)/hdmi/hdmidelay.sv

# VHDL source files
VHDL_SOURCES = \
	$(SOURCES_DIR)/p8video.vhd \
	$(SOURCES_DIR)/ps2_read_keyboard.vhd \
	$(IMPORTS_DIR)/dac.vhd \
	$(IMPORTS_DIR)/hdmi_out_xilinx.vhd \
	$(IMPORTS_DIR)/i2c.vhd \
	$(IMPORTS_DIR)/ps2_in.vhd \
	$(IMPORTS_DIR)/spi.vhd \
	$(IMPORTS_DIR)/uart.vhd \
	$(IMPORTS_DIR)/TG68K.C-master/TG68K_Pack.vhd \
	$(IMPORTS_DIR)/TG68K.C-master/TG68K_ALU.vhd \
	$(IMPORTS_DIR)/TG68K.C-master/TG68KdotC_Kernel.vhd \

TESTBENCH = $(SIM_DIR)/tb_nextp8_p8audio.sv

# Vivado xsim settings
XVLOG = xvlog
XVHDL = xvhdl
XELAB = xelab
XSIM = xsim

# Simulation top module
TOP = tb_nextp8_p8audio

# Default target
.PHONY: all
all: sim

# Compile and elaborate
.PHONY: compile
compile:
	@echo "Compiling sources..."
	$(XVLOG) --sv $(TESTBENCH)
	$(XVLOG) -d SIMULATION $(VERILOG_SOURCES)
	$(XVLOG) -d SIMULATION $(IP_SOURCES)
	$(XVLOG) --sv -d SIMULATION $(SYSTEMVERILOG_SOURCES)
	$(XVHDL) $(VHDL_SOURCES)
	@echo "Elaborating design..."
	$(XELAB) $(TOP) -s $(TOP)_snap -debug all \
		--timescale 1ns/1ps \
		-L unisims_ver -L unimacro_ver -L secureip \
		-L blk_mem_gen_v8_4_11 -L xpm \
		glbl

# Run simulation
.PHONY: sim
sim: compile
	@echo "Running simulation with CART=$(CART) (timeout: $(TIMEOUT)s)..."
	@timeout $(TIMEOUT) $(XSIM) $(TOP)_snap -runall -testplusarg CART=$(CART) || \
		(if [ $$? -eq 124 ]; then \
			echo "ERROR: Simulation timed out after $(TIMEOUT) seconds"; \
			exit 1; \
		else \
			exit $$?; \
		fi)

# Open waveform viewer
.PHONY: wave
wave:
	@if [ -f $(TOP)_snap.wdb ]; then \
		vivado -mode gui $(TOP)_snap.wdb; \
	else \
		echo "No waveform database found. Run 'make sim' first."; \
	fi

# Clean generated files
.PHONY: clean
clean:
	rm -rf xsim.dir
	rm -f xvlog.log xvlog.pb
	rm -f xelab.log xelab.pb
	rm -f xsim*.log xsim*.jou
	rm -f webtalk*.jou webtalk*.log
	rm -f *.wdb
	rm -f tb_nextp8_p8audio_out.wav
	rm -f .Xil

.PHONY: help
help:
	@echo "Makefile targets:"
	@echo "  make sim CART=file.p8  - Compile and run simulation"
	@echo "  make wave              - Open waveform in Vivado"
	@echo "  make clean             - Remove generated files"
	@echo ""
	@echo "Variables:"
	@echo "  CART                   - Path to cart file for testing (default: tb_p8audio_sfx.p8)"
