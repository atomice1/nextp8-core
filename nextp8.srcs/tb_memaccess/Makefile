# Makefile for tb_memaccess - Memory access testbench
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
	$(SRC_DIR)/keyboard.v \
	$(SRC_DIR)/mkeyboard.v \
	memtest_tb.sv

# IP core simulation files (generated)
IP_SOURCES = \
	$(IP_GEN_DIR)/pll_1/pll_sim_netlist.v \
	$(IP_GEN_DIR)/pll_hdmi_1/pll_hdmi_sim_netlist.v \
	$(IP_GEN_DIR)/vram_1/vram_sim_netlist.v

# SystemVerilog source files
SYSTEMVERILOG_SOURCES = \
	$(SRC_DIR)/hdmi/hdmidelay.sv \
	$(SRC_DIR)/p8audio.sv \
	$(SRC_DIR)/p8sfx_core_mux.sv

# VHDL source files
VHDL_SOURCES = \
	$(SRC_DIR)/p8video.vhd \
	$(SRC_DIR)/ps2_read_keyboard.vhd \
	$(SRC_DIR)/dac.vhd \
	$(SRC_DIR)/hdmi_out_xilinx.vhd \
	$(SRC_DIR)/i2c.vhd \
	$(SRC_DIR)/ps2_in.vhd \
	$(SRC_DIR)/spi.vhd \
	$(SRC_DIR)/uart.vhd \
	$(SRC_DIR)/TG68K.C-master/TG68K_Pack.vhd \
	$(SRC_DIR)/TG68K.C-master/TG68K_ALU.vhd \
	$(SRC_DIR)/TG68K.C-master/TG68KdotC_Kernel.vhd

# Simulation parameters
TOP_MODULE = memtest_tb
SNAPSHOT = memtest_snapshot
WAVEFORM = memtest_tb.wdb

# Xilinx tool paths (should be in PATH)
XVHDL = xvhdl
XVLOG = xvlog
XELAB = xelab
XSIM = xsim

# Compiler flags
XVHDL_FLAGS = --work work
XVLOG_FLAGS = --work work
XELAB_FLAGS = --debug typical --snapshot $(SNAPSHOT) \
	--timescale 1ns/1ps \
	-L unisims_ver -L unimacro_ver -L secureip \
	-L blk_mem_gen_v8_4_11 -L xpm
XSIM_FLAGS = --runall

.PHONY: all compile run clean wave rom help

all: rom compile run

# ROM generation - delegated to Makefile.rom
rom:
	$(MAKE) -f Makefile.rom

# Compilation targets
compile: rom
	@echo "Compiling VHDL sources..."
	$(XVHDL) $(XVHDL_FLAGS) $(VHDL_SOURCES)
	@echo "Compiling Verilog sources..."
	$(XVLOG) $(XVLOG_FLAGS) $(VERILOG_SOURCES)
	@echo "Compiling SystemVerilog sources..."
	$(XVLOG) $(XVLOG_FLAGS) -sv $(SYSTEMVERILOG_SOURCES)
	@echo "Compiling IP cores..."
	$(XVLOG) $(XVLOG_FLAGS) $(IP_SOURCES)
	@echo "Elaborating design..."
	$(XELAB) $(XELAB_FLAGS) $(TOP_MODULE) glbl

run:
	@echo "Running simulation..."
	$(XSIM) $(SNAPSHOT) -runall 2>&1 | tee sim_output.txt
	@echo "=== Simulation complete ==="

wave:
	@echo "Opening waveform viewer..."
	$(XSIM) --gui $(SNAPSHOT)

clean:
	rm -rf xsim.dir
	rm -f *.jou *.log *.pb *.wdb
	rm -f sim_output.txt
	rm -f .Xil
	$(MAKE) -f Makefile.rom clean

.PHONY: help
help:
	@echo "Makefile for Memory Access Testbench"
	@echo ""
	@echo "Targets:"
	@echo "  all     - Build ROM, compile, and run simulation (default)"
	@echo "  rom     - Generate ROM file from assembly source"
	@echo "  compile - Compile HDL sources and elaborate design"
	@echo "  run     - Run simulation"
	@echo "  wave    - Open waveform viewer"
	@echo "  clean   - Remove generated files"
	@echo "  help    - Show this help message"
