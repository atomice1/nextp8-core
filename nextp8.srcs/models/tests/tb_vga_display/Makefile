# Makefile for tb_vga_display using Vivado xsim
# Tests VGA output from nextp8_top with vga_display_model
#
# Usage:
#   make          - Compile and run simulation
#   make clean    - Remove generated files
#   make wave     - Open waveform viewer (after simulation)
#
# Paths
SRC_DIR = ../../../sources_1
IP_GEN_DIR = ../../../../nextp8.gen/sources_1/ip
MODELS_DIR = ../..
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
	$(IP_GEN_DIR)/vram_main_1/vram_main_sim_netlist.v \
	$(IP_GEN_DIR)/vram_overlay_1/vram_overlay_sim_netlist.v

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
	$(TB_DIR)/tb_vga_display.sv

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
TOP = tb_vga_display
SNAPSHOT = tb_vga_display_snap
TIMEOUT ?= 300

# xsim commands
XVHDL = xvhdl
XVLOG = xvlog
XELAB = xelab
XSIM = xsim

# Build directory
WORK_DIR = xsim.dir

.PHONY: all sim run clean wave help

all: sim

# Compile VHDL sources
compile_vhdl: $(VHDL_SOURCES)
	@echo "=== Compiling VHDL sources ==="
	@$(XVHDL) --work work $(VHDL_SOURCES)
	@echo ""

# Compile Verilog sources
compile_verilog: compile_vhdl $(VERILOG_SOURCES)
	@echo "=== Compiling Verilog sources ==="
	@$(XVLOG) --work work $(VERILOG_SOURCES)
	@echo ""

# Compile IP simulation netlists
compile_ip: compile_verilog $(IP_SOURCES)
	@echo "=== Compiling IP simulation netlists ==="
	@for ip in $(IP_SOURCES); do \
		if [ -f "$$ip" ]; then \
			$(XVLOG) --work work "$$ip" || exit 1; \
		else \
			echo "WARNING: IP source not found: $$ip"; \
			echo "Run 'make regenerate-ip' from project root to generate IP simulation files."; \
		fi; \
	done
	@echo ""

# Compile SystemVerilog sources
compile_sv: compile_ip $(SYSTEMVERILOG_SOURCES)
	@echo "=== Compiling SystemVerilog sources ==="
	@$(XVLOG) --sv $(SYSTEMVERILOG_SOURCES)
	@echo ""

# Elaborate design
elaborate: compile_sv
	@echo "=== Elaborating design ==="
	@$(XELAB) $(TOP) -s $(SNAPSHOT) -debug typical \
		--timescale 1ns/1ps \
		-L unisims_ver -L unimacro_ver -L secureip \
		-L blk_mem_gen_v8_4_11 -L xpm \
		glbl
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
	@if [ -f vga_output.ppm ]; then \
		echo "SUCCESS: Generated vga_output.ppm"; \
	fi

# Alternative: just run (if already compiled)
run:
	@echo "=== Running simulation (assuming already compiled) ==="
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
	rm -f vga_output.ppm
	@echo "Clean complete"

# Help target
help:
	@echo "Makefile for tb_vga_display - VGA Display Model Testbench"
	@echo ""
	@echo "Targets:"
	@echo "  make          - Compile and run simulation (default)"
	@echo "  make sim      - Same as 'make'"
	@echo "  make run      - Run simulation (skip recompile)"
	@echo "  make wave     - Open waveform viewer"
	@echo "  make clean    - Remove all generated files"
	@echo "  make help     - Show this help message"
	@echo ""
	@echo "Output:"
	@echo "  vga_output.ppm - PPM image file of VGA display buffer"
	@echo ""
