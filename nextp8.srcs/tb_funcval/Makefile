# Makefile for tb_funcval using Vivado xsim
# FuncVal testbench for nextp8 functional validation
#
# Usage:
#   make ROM_FILE=test.mem  - Compile and run simulation with ROM file
#   make clean              - Remove generated files
#   make wave               - Open waveform viewer (after simulation)
#
# Required parameter:
#   ROM_FILE - Path to .mem file to load into SRAM

# Paths
SRC_DIR = ../sources_1
IP_GEN_DIR = ../../nextp8.gen/sources_1/ip
MODELS_DIR = ../models
TB_DIR = .

# Project root (two levels up from tb_funcval)
PROJECT_DIR = $(abspath ../..)
REGEN_TCL   = $(PROJECT_DIR)/scripts/regenerate_ip.tcl

# IP source .xci files (inputs to Vivado IP generation).
# The generated netlists use _1 suffixes; the .xci sources use _2.
IP_XCI_DIR = $(abspath ../sources_1/ip)
IP_XCI_SOURCES = \
	$(IP_XCI_DIR)/pll_2/pll.xci \
	$(IP_XCI_DIR)/pll_hdmi_2/pll_hdmi.xci \
	$(IP_XCI_DIR)/vram_2/vram.xci

# Check that ROM_FILE is provided (not needed for wave/clean/help targets)
ifeq ($(filter wave clean help generate-ip,$(MAKECMDGOALS)),)
ifndef ROM_FILE
$(error ROM_FILE parameter is required. Usage: make ROM_FILE=test.mem)
endif
endif

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
	$(SRC_DIR)/fp_ops.sv \
	$(SRC_DIR)/p8sfx_core_mux.sv \
	$(SRC_DIR)/ps2_interface.sv \
	$(SRC_DIR)/keyboard.sv \
	$(SRC_DIR)/mouse.sv \
	$(MODELS_DIR)/sram.sv \
	$(MODELS_DIR)/vga_display_model.sv \
	$(MODELS_DIR)/ps2_interface_device.sv \
	$(MODELS_DIR)/ds1307_device.sv \
	$(MODELS_DIR)/keyboard_device.sv \
	$(MODELS_DIR)/mouse_device.sv \
	$(TB_DIR)/../tb_nextp8_loader/spi_slave.sv \
	$(TB_DIR)/../tb_nextp8_loader/sdspi_model.sv \
	$(TB_DIR)/tb_funcval.sv

# VHDL source files
VHDL_SOURCES = \
	$(SRC_DIR)/nextp8_top_issue5.vhd \
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
TOP = tb_funcval
SNAPSHOT = tb_funcval_snap
TIMEOUT ?= 300

# Optional SD card image (passed via SDCARD_IMAGE make variable or env var)
SDCARD_IMAGE ?=
ifdef SDCARD_IMAGE
EXTRA_GENERIC = --generic_top "SDCARD_IMAGE=$(SDCARD_IMAGE)"
else
EXTRA_GENERIC =
endif

# xsim commands
XVHDL = xvhdl
XVLOG = xvlog
XELAB = xelab
XSIM = xsim
XVLOG_FLAGS = -d SIMULATION
XSIM_EXTRA_ARGS ?=
# Use 'all' for full signal capture (required for $dumpvars / wave viewer).
# Override with DEBUG_LEVEL=typical for faster sims that don't need waveforms.
DEBUG_LEVEL ?= all

# Build directory
WORK_DIR = xsim.dir

.PHONY: all sim run clean wave help generate-ip

all: sim

# Generate IP simulation netlists using Vivado batch mode.
# '&:' is a grouped-target rule (GNU Make 4.3+): the single recipe produces
# all listed targets, so Vivado runs only once even when all files are missing.
# Dependencies are the .xci source files, so a change to any xci triggers regen.
$(IP_SOURCES) &: $(IP_XCI_SOURCES) $(REGEN_TCL)
	@echo "=== Generating IP simulation netlists ==="
	cd $(PROJECT_DIR) && vivado -mode batch -source scripts/regenerate_ip.tcl -nojournal -nolog

generate-ip: $(IP_SOURCES)

# Compile VHDL sources
compile_vhdl: $(VHDL_SOURCES)
	@echo "=== Compiling VHDL sources ==="
	@$(XVHDL) --work work $(VHDL_SOURCES)
	@echo ""

# Compile Verilog sources
compile_verilog: compile_vhdl $(VERILOG_SOURCES)
	@echo "=== Compiling Verilog sources ==="
	@$(XVLOG) $(XVLOG_FLAGS) --work work $(VERILOG_SOURCES)
	@echo ""

# Compile IP simulation netlists
compile_ip: compile_verilog $(IP_SOURCES)
	@echo "=== Compiling IP simulation netlists ==="
	@for ip in $(IP_SOURCES); do \
		$(XVLOG) $(XVLOG_FLAGS) --work work "$$ip" || exit 1; \
	done
	@echo ""

# Compile SystemVerilog sources
compile_sv: compile_ip $(SYSTEMVERILOG_SOURCES)
	@echo "=== Compiling SystemVerilog sources ==="
	@$(XVLOG) $(XVLOG_FLAGS) --sv $(SYSTEMVERILOG_SOURCES)
	@echo ""

# Elaborate design
elaborate: compile_sv
	@echo "=== Elaborating design ==="
	@$(XELAB) $(TOP) -s $(SNAPSHOT) -debug $(DEBUG_LEVEL) \
		--timescale 1ns/1ps \
		--generic_top "ROM_FILE=$(ROM_FILE)" \
		$(EXTRA_GENERIC) \
		-L unisims_ver -L unimacro_ver -L secureip \
		-L blk_mem_gen_v8_4_11 -L xpm \
		glbl
	@echo ""

# Wave-capture TCL batch script (used when DUMP_WAVES is requested)
SIM_TCL ?= $(TB_DIR)/sim_waves.tcl

# If XSIM_WAVES=1, use tclbatch (logs all signals); otherwise use -runall.
ifneq ($(XSIM_WAVES),1)
SIM_RUN_ARGS = -onfinish quit -runall
else
SIM_RUN_ARGS = -tclbatch $(SIM_TCL)
endif

# Run simulation
sim: elaborate
	@echo "=== Running simulation (timeout: $(TIMEOUT)s) ==="
	@echo "ROM_FILE: $(ROM_FILE)"
	@timeout $(TIMEOUT) $(XSIM) $(SNAPSHOT) $(SIM_RUN_ARGS) $(XSIM_EXTRA_ARGS) || \
		(if [ $$? -eq 124 ]; then \
			echo "ERROR: Simulation timed out after $(TIMEOUT) seconds"; \
			exit 1; \
		fi; \
		exit $$?)
	@echo "=== Simulation complete ==="

# Alternative: just run (if already compiled)
run:
	@echo "=== Running simulation (assuming already compiled) ==="
	@echo "ROM_FILE: $(ROM_FILE)"
	@timeout $(TIMEOUT) $(XSIM) $(SNAPSHOT) -onfinish quit -runall || \
		(if [ $$? -eq 124 ]; then \
			echo "ERROR: Simulation timed out after $(TIMEOUT) seconds"; \
			exit 1; \
		fi; \
		exit $$?)

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
	@echo "Makefile for tb_funcval - FuncVal Testbench for nextp8"
	@echo ""
	@echo "Targets:"
	@echo "  make ROM_FILE=<file>  - Compile and run simulation with ROM file (required)"
	@echo "  make run              - Run simulation (skip recompile)"
	@echo "  make wave             - Open waveform viewer"
	@echo "  make clean            - Remove all generated files"
	@echo "  make help             - Show this help message"
	@echo ""
	@echo "Required Parameters:"
	@echo "  ROM_FILE - Path to .mem file to initialize SRAM"
	@echo ""
	@echo "Example:"
	@echo "  make ROM_FILE=../test_rom.mem"
	@echo ""

