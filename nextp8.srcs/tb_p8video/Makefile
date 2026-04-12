# Makefile for p8video_tb - P8 video module testbench
#
# Usage:
#   make              - Compile and run all simulations
#   make sim_xform_0  - Run only SCREEN_TRANSFORM=0 test
#   make sim_overlay  - Run only ENABLE_OVERLAY=1 test
#   make clean        - Remove generated files
#   make wave         - Open waveform viewer (after simulation)

# Paths
SRC_DIR = ../sources_1
IP_GEN_DIR = ../../nextp8.gen/sources_1/ip
IP_DIR = $(SRC_DIR)/ip
TB_DIR = .

# IP Core simulation files
IP_VRAM_MAIN = $(IP_GEN_DIR)/vram_main_1/vram_main_sim_netlist.v
IP_VRAM_OVERLAY = $(IP_GEN_DIR)/vram_overlay_1/vram_overlay_sim_netlist.v

# P8 video module (VHDL)
P8VIDEO_SRCS = $(SRC_DIR)/p8video.vhd

# Testbench (SystemVerilog)
TB_SRCS = $(TB_DIR)/p8video_tb.sv

# All source files
ALL_SRCS = $(P8VIDEO_SRCS) $(TB_SRCS)

# Simulation parameters
TOP = p8video_tb
SNAPSHOT = p8video_tb_snap
TIMEOUT ?= 60

# Screen transform modes to test
XFORM_MODES = 0 1 2 3 5 6 7 129 130 131 133 134 135

# xsim commands
XVLOG = xvlog
XVHDL = xvhdl
XELAB = xelab
XSIM = xsim

# Elaboration flags common to all targets
ELAB_FLAGS = -debug typical --timescale 1ns/1ps \
	-L unisims_ver -L unimacro_ver -L secureip \
	-L blk_mem_gen_v8_4_11 -L xpm

# Build directory
WORK_DIR = xsim.dir

XFORM_ELAB_TARGETS = $(foreach m,$(XFORM_MODES),elaborate_xform_$(m))
XFORM_SIM_TARGETS  = $(foreach m,$(XFORM_MODES),sim_xform_$(m))

.PHONY: all sim run clean wave help compile_vhdl compile_ip compile_sv \
	$(XFORM_ELAB_TARGETS) $(XFORM_SIM_TARGETS) \
	elaborate_overlay sim_overlay

all: sim

# Compile VHDL sources
compile_vhdl:
	@echo "=== Compiling VHDL sources ==="
	$(XVHDL) $(P8VIDEO_SRCS)
	@echo ""

# Compile IP cores (Verilog)
compile_ip:
	@echo "=== Compiling IP cores ==="
	$(XVLOG) $(IP_VRAM_MAIN)
	$(XVLOG) $(IP_VRAM_OVERLAY)
	@echo ""

# Compile SystemVerilog testbench
compile_sv: compile_vhdl compile_ip
	@echo "=== Compiling SystemVerilog testbench ==="
	$(XVLOG) --sv $(TB_SRCS)
	@echo ""

# ---------------------------------------------------------------------------
# Per-transform elaborate and simulate targets (generated)
# ---------------------------------------------------------------------------
define XFORM_RULES

elaborate_xform_$(1): compile_sv
	@echo "=== Elaborating (SCREEN_TRANSFORM=$(1)) ==="
	$$(XELAB) $$(TOP) -s $$(SNAPSHOT)_xform_$(1) $$(ELAB_FLAGS) \
		-generic_top "ENABLE_OVERLAY=0" \
		-generic_top "SCREEN_TRANSFORM=$(1)" \
		glbl
	@echo ""

sim_xform_$(1): elaborate_xform_$(1)
	@echo "=== Sim SCREEN_TRANSFORM=$(1) (timeout: $$(TIMEOUT)s) ==="
	timeout $$(TIMEOUT) $$(XSIM) $$(SNAPSHOT)_xform_$(1) -runall
	@echo ""

endef

$(foreach mode,$(XFORM_MODES),$(eval $(call XFORM_RULES,$(mode))))

# ---------------------------------------------------------------------------
# Overlay target (ENABLE_OVERLAY=1, SCREEN_TRANSFORM=0)
# ---------------------------------------------------------------------------
elaborate_overlay: compile_sv
	@echo "=== Elaborating (ENABLE_OVERLAY=1) ==="
	$(XELAB) $(TOP) -s $(SNAPSHOT)_overlay $(ELAB_FLAGS) \
		-generic_top "ENABLE_OVERLAY=1" \
		glbl
	@echo ""

sim_overlay: elaborate_overlay
	@echo "=== Sim ENABLE_OVERLAY=1 (timeout: $(TIMEOUT)s) ==="
	timeout $(TIMEOUT) $(XSIM) $(SNAPSHOT)_overlay -runall
	@echo ""

# ---------------------------------------------------------------------------
# Run all simulations
# ---------------------------------------------------------------------------
sim: $(XFORM_SIM_TARGETS) sim_overlay
	@echo "=== All simulations complete ==="

# Run default transform only (quick check)
run:
	@echo "=== Running SCREEN_TRANSFORM=0 (assuming already compiled) ==="
	timeout $(TIMEOUT) $(XSIM) $(SNAPSHOT)_xform_0 -runall

# Open waveform viewer
wave:
	@if [ -f $(SNAPSHOT)_xform_0.wdb ]; then \
		echo "=== Opening waveform viewer ==="; \
		$(XSIM) --gui $(SNAPSHOT)_xform_0.wdb & \
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
	@echo "Makefile for p8video_tb - P8 Video Module Testbench"
	@echo ""
	@echo "Targets:"
	@echo "  make              - Compile and run all simulations"
	@echo "  make sim          - Same as 'make'"
	@echo "  make sim_xform_N  - Run SCREEN_TRANSFORM=N test only"
	@echo "  make sim_overlay  - Run ENABLE_OVERLAY=1 test only"
	@echo "  make run          - Run xform_0 simulation (skip recompile)"
	@echo "  make wave         - Open waveform viewer"
	@echo "  make clean        - Remove all generated files"
	@echo "  make help         - Show this help message"
	@echo ""
	@echo "Screen transform modes: $(XFORM_MODES)"
