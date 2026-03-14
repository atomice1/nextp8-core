# Makefile for tb_nextp8_loader - nextp8_top loader testbench with SD card model
# 
# Usage:
#   make          - Compile and run simulation
#   make clean    - Remove generated files
#   make wave     - Open waveform viewer (after simulation)

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
	$(SRC_DIR)/fp_ops.sv \
	$(SRC_DIR)/p8sfx_core_mux.sv \
	$(SRC_DIR)/ps2_interface.sv \
	$(SRC_DIR)/keyboard.sv \
	$(SRC_DIR)/mouse.sv \
	$(TB_DIR)/spi_slave.sv \
	$(TB_DIR)/tb_nextp8_loader.sv \
	$(TB_DIR)/sdspi_model.sv \
	../models/sram_simple.sv

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
TOP = tb_nextp8_loader
SNAPSHOT = tb_nextp8_loader_snap
TIMEOUT ?= 7200

# Standalone SDSPI test parameters
SDSPI_TOP = tb_sdspi
SDSPI_SNAPSHOT = tb_sdspi_snap
SDSPI_TIMEOUT ?= 10

# xsim commands
XVLOG = xvlog
XVHDL = xvhdl
XELAB = xelab
XSIM = xsim

# Build directory
WORK_DIR = xsim.dir

# Python environment (shared venv at top level)
PYTHON3 = python3
VENV_DIR = ../../venv
VENV_PYTHON = $(VENV_DIR)/bin/python3
VENV_PIP = $(VENV_DIR)/bin/pip
REQUIREMENTS = ../../scripts/requirements.txt

.PHONY: all sim run clean wave help sdcard app test_sdspi sdspi_wave venv

all: app sdcard sim

# Create Python virtual environment
venv:
	@if [ ! -d "$(VENV_DIR)" ]; then \
		echo "=== Creating Python virtual environment ==="; \
		$(PYTHON3) -m venv $(VENV_DIR); \
		echo "=== Installing Python dependencies ==="; \
		$(VENV_PIP) install setuptools==81 ; \
		$(VENV_PIP) install -r $(REQUIREMENTS); \
		echo ""; \
	else \
		echo "Virtual environment already exists. Use 'make clean' to recreate."; \
	fi

# Build application binary
app:
	@echo "=== Building hello test application ==="
	@$(MAKE) -f Makefile.app
	@echo ""

# Create SD card image
sdcard: app venv
	@echo "=== Creating SD card image ==="
	@$(VENV_PYTHON) make-sdcard-image.py -o sdcard.img nextp8.bin
	@echo ""

# Note: loader.mem should be provided by user before running simulation

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

# Elaborate design with debug (for waveforms)
elaborate: compile_verilog
	@echo "=== Elaborating design (with debug) ==="
	$(XELAB) $(TOP) -s $(SNAPSHOT) -debug typical \
		--timescale 1ns/1ps \
		-L unisims_ver -L unimacro_ver -L secureip \
		-L blk_mem_gen_v8_4_11 -L xpm \
		glbl
	@echo ""

# Elaborate design fast (no debug/waveforms)
elaborate_fast: compile_verilog
	@echo "=== Elaborating design (fast mode - no waveforms) ==="
	$(XELAB) $(TOP) -s $(SNAPSHOT) -debug off \
		--timescale 1ns/1ps \
		-L unisims_ver -L unimacro_ver -L secureip \
		-L blk_mem_gen_v8_4_11 -L xpm \
		glbl
	@echo ""

# Run simulation (fast - no waveforms)
sim: elaborate_fast
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

# Run simulation with debug/waveforms enabled
sim_debug: elaborate
	@echo "=== Running simulation with debug (timeout: $(TIMEOUT)s) ==="
	@timeout $(TIMEOUT) $(XSIM) $(SNAPSHOT) -runall || \
		(if [ $$? -eq 124 ]; then \
			echo "ERROR: Simulation timed out after $(TIMEOUT) seconds"; \
			exit 1; \
		else \
			exit $$?; \
		fi)
	@echo ""
	@echo "=== Simulation complete (waveform saved to $(SNAPSHOT).wdb) ==="

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

# Standalone SDSPI testbench (simple SPI communication test)
test_sdspi: sdcard
	@echo "=== Compiling standalone SDSPI testbench ==="
	$(XVHDL) $(SRC_DIR)/spi.vhd
	$(XVLOG) --sv $(TB_DIR)/spi_slave.sv $(TB_DIR)/sdspi_model.sv $(TB_DIR)/tb_sdspi.sv
	@echo ""
	@echo "=== Elaborating SDSPI testbench ==="
	$(XELAB) $(SDSPI_TOP) -s $(SDSPI_SNAPSHOT) -debug typical --timescale 1ns/1ps
	@echo ""
	@echo "=== Running SDSPI testbench (timeout: $(SDSPI_TIMEOUT)s) ==="
	@timeout $(SDSPI_TIMEOUT) $(XSIM) $(SDSPI_SNAPSHOT) -runall || \
		(if [ $$? -eq 124 ]; then \
			echo "ERROR: SDSPI test timed out after $(SDSPI_TIMEOUT) seconds"; \
			exit 1; \
		else \
			exit $$?; \
		fi)
	@echo ""
	@echo "=== SDSPI test complete ==="

# Open SDSPI waveform viewer
sdspi_wave:
	@if [ -f $(SDSPI_SNAPSHOT).wdb ]; then \
		echo "=== Opening SDSPI waveform viewer ==="; \
		$(XSIM) --gui $(SDSPI_SNAPSHOT).wdb & \
	else \
		echo "ERROR: No SDSPI waveform database found. Run test_sdspi first."; \
	fi

# Test SPI slave module (simple loopback test)
test_spi_slave:
	@echo "=== Compiling SPI slave testbench ==="
	$(XVLOG) --sv $(TB_DIR)/spi_slave.sv $(TB_DIR)/tb_spi_slave.sv
	@echo ""
	@echo "=== Elaborating SPI slave testbench ==="
	$(XELAB) tb_spi_slave -s tb_spi_slave_snap -debug typical --timescale 1ns/1ps
	@echo ""
	@echo "=== Running SPI slave testbench ==="
	@timeout 5 $(XSIM) tb_spi_slave_snap -runall
	@echo ""
	@echo "=== SPI slave test complete ==="

# Help target
help:
	@echo "Makefile for tb_nextp8_loader - Bootloader Testbench with SD Card Model"
	@echo ""
	@echo "Targets:"
	@echo "  make          - Build app, create SD card image, and run simulation"
	@echo "  make app      - Build hello test application binary"
	@echo "  make venv     - Create Python virtual environment (done automatically)"
	@echo "  make sdcard   - Create SD card image with application"
	@echo "  make sim      - Compile and run simulation"
	@echo "  make run      - Run simulation (skip recompile)"
	@echo "  make wave     - Open waveform viewer"
	@echo "  make test_sdspi  - Run standalone SDSPI model test"
	@echo "  make sdspi_wave  - Open SDSPI test waveform viewer"
	@echo "  make clean    - Remove all generated files"
	@echo "  make help     - Show this help message"
	@echo ""
	@echo "Options:"
	@echo "  TIMEOUT=<sec>        - Full sim timeout in seconds (default: 3600)"
	@echo "  SDSPI_TIMEOUT=<sec>  - SDSPI test timeout in seconds (default: 10)"
	@echo ""
	@echo "Examples:"
	@echo "  make                          # Run with defaults"
	@echo "  make sim TIMEOUT=120          # Run with 120 second timeout"
	@echo "  make test_sdspi               # Test SDSPI model standalone"
	@echo ""
	@echo "This testbench instantiates the full nextp8_top module"
	@echo "with simulated external interfaces (SRAM, UART etc.)"
	@echo "Exits successfully when POST code reaches 25 and the expected UART is output."

# Clean generated files
clean:
	@echo "=== Cleaning testbench files ==="
	rm -rf $(WORK_DIR) *.jou *.log *.pb *.wdb *.ini
	rm -f sdcard.img
	@$(MAKE) -f Makefile.app clean
	@echo "Clean complete"
