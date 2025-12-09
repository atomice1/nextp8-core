# Top-level Makefile for nextp8-core project
# 
# This Makefile provides targets for building and testing the nextp8 FPGA design
# using Xilinx Vivado tools.
#
# Usage:
#   make help       - Show this help message
#   make lint       - Run syntax checking on all sources
#   make compile    - Compile/elaborate the design (syntax check)
#   make synth      - Run synthesis
#   make implement  - Run implementation (place and route)
#   make bitstream  - Generate bitstream (.bit file)
#   make all        - Run full build flow (synth -> implement -> bitstream)
#   make test       - Run all testbenches
#   make clean      - Clean all generated files

# Project settings
PROJECT = nextp8
PROJECT_FILE = $(PROJECT).xpr
PART = xc7a35tcsg324-2
TOP_MODULE = nextp8_top_issue5

# Vivado settings
VIVADO = vivado
VIVADO_BATCH = $(VIVADO) -mode batch -nojournal -nolog

# Build directories
BUILD_DIR = $(PROJECT).runs
SYNTH_DIR = $(BUILD_DIR)/synth_1
IMPL_DIR = $(BUILD_DIR)/impl_1

# Scripts directory
SCRIPTS_DIR = scripts

# Test bench directories
SIM_DIRS = nextp8.srcs/tb_nextp8_boot \
           nextp8.srcs/tb_nextp8_loader \
           nextp8.srcs/tb_p8video \
           nextp8.srcs/tb_p8audio_sfx \
           nextp8.srcs/tb_ps2_keyboard \
           nextp8.srcs/tb_p8audio_music \
           nextp8.srcs/tb_nextp8_p8audio \
           nextp8.srcs/tb_waveform_gen

# Output files
BITSTREAM = $(IMPL_DIR)/$(TOP_MODULE).bit
TIMING_RPT = timing_summary.rpt
UTIL_RPT = utilization.rpt

.PHONY: all help clean lint compile synth synthesis implement bitstream test

# Default target
all: bitstream

# Help message
help:
	@echo "nextp8-core Build System"
	@echo "========================"
	@echo ""
	@echo "Hardware Build Targets:"
	@echo "  make lint       - Run syntax/lint checking on all source files"
	@echo "  make compile    - Compile and elaborate design (syntax check)"
	@echo "  make synth      - Run Vivado synthesis"
	@echo "  make implement  - Run Vivado implementation (place and route)"
	@echo "  make bitstream  - Generate FPGA bitstream"
	@echo "  make all        - Run complete build flow (default)"
	@echo ""
	@echo "Test Targets:"
	@echo "  make test                     - Run all testbenches"
	@echo "  make test-tb_nextp8_boot      - Run exec_tb (full system boot test)"
	@echo "  make test-tb_nextp8_loader    - Run tb_nextp8_loader (bootloader test)"
	@echo "  make test-tb_p8video          - Run p8video_tb (video module test)"
	@echo "  make test-tb_p8audio_sfx      - Run tb_p8audio_sfx (audio SFX test)"
	@echo "  make test-tb_ps2_keyboard     - Run tb_ps2_read_keyboard (PS/2 test)"
	@echo "  make test-tb_p8audio_music    - Run tb_p8audio_music (audio music test)"
	@echo "  make test-tb_nextp8_p8audio   - Run tb_nextp8_p8audio (integrated audio test)"
	@echo "  make test-tb_waveform_gen     - Run tb_waveform_gen (waveform generation test)"
	@echo ""
	@echo "Utility Targets:"
	@echo "  make clean      - Remove all generated files"
	@echo "  make clean-test - Clean only testbench outputs"
	@echo "  make help       - Show this help message"
	@echo ""
	@echo "Project: $(PROJECT)"
	@echo "Part:    $(PART)"
	@echo "Top:     $(TOP_MODULE)"

# Lint target - syntax checking
lint:
	@echo "=== Running lint/syntax check ==="
	$(VIVADO_BATCH) -source $(SCRIPTS_DIR)/lint.tcl
	@echo ""

# Compile target - elaborate design for syntax checking
compile: lint
	@echo "=== Design syntax check completed ==="

# Synthesis
synth synthesis:
	@echo "=== Running Synthesis ==="
	$(VIVADO_BATCH) -source $(SCRIPTS_DIR)/synth.tcl
	@echo ""
	@echo "Synthesis complete. Check $(SYNTH_DIR) for results."

# Implementation
implement: synth
	@echo "=== Running Implementation ==="
	$(VIVADO_BATCH) -source $(SCRIPTS_DIR)/implement.tcl
	@echo ""
	@echo "Implementation complete. Check $(IMPL_DIR) for results."
	@echo "Timing report: $(TIMING_RPT)"
	@echo "Utilization report: $(UTIL_RPT)"

# Bitstream generation
bitstream: implement
	@echo "=== Generating Bitstream ==="
	$(VIVADO_BATCH) -source $(SCRIPTS_DIR)/bitstream.tcl
	@echo ""
	@if [ -f "$(BITSTREAM)" ]; then \
		echo "SUCCESS: Bitstream generated: $(BITSTREAM)"; \
	else \
		echo "ERROR: Bitstream file not found"; \
		exit 1; \
	fi

# Test targets
test: test-tb_nextp8_boot test-tb_nextp8_loader test-tb_p8video test-tb_p8audio_sfx test-tb_ps2_keyboard test-tb_p8audio_music test-tb_nextp8_p8audio test-tb_waveform_gen
	@echo "=== All tests complete ==="

test-tb_nextp8_boot:
	@echo "=== Running tb_nextp8_boot: exec_tb (full system boot test) ==="
	@$(MAKE) -C nextp8.srcs/tb_nextp8_boot || (echo "ERROR: tb_nextp8_boot failed"; exit 1)
	@echo ""

test-tb_nextp8_loader:
	@echo "=== Running tb_nextp8_loader: loader_tb (loader with SD card test) ==="
	@$(MAKE) -C nextp8.srcs/tb_nextp8_loader || (echo "ERROR: tb_nextp8_loader failed"; exit 1)
	@echo ""

test-tb_p8video:
	@echo "=== Running tb_p8video: p8video_tb (video module test) ==="
	@$(MAKE) -C nextp8.srcs/tb_p8video || (echo "ERROR: tb_p8video failed"; exit 1)
	@echo ""

test-tb_p8audio_sfx:
	@echo "=== Running tb_p8audio_sfx: tb_p8audio_sfx (audio SFX test) ==="
	@$(MAKE) -C nextp8.srcs/tb_p8audio_sfx || (echo "ERROR: tb_p8audio_sfx failed"; exit 1)
	@echo ""

test-tb_ps2_keyboard:
	@echo "=== Running tb_ps2_keyboard: tb_ps2_read_keyboard (PS/2 test) ==="
	@$(MAKE) -C nextp8.srcs/tb_ps2_keyboard || (echo "ERROR: tb_ps2_keyboard failed"; exit 1)
	@echo ""

test-tb_p8audio_music:
	@echo "=== Running tb_p8audio_music: tb_p8audio_music (audio music test) ==="
	@$(MAKE) -C nextp8.srcs/tb_p8audio_music || (echo "ERROR: tb_p8audio_music failed"; exit 1)
	@echo ""

test-tb_nextp8_p8audio:
	@echo "=== Running tb_nextp8_p8audio: tb_nextp8_p8audio (integrated audio test) ==="
	@$(MAKE) -C nextp8.srcs/tb_nextp8_p8audio || (echo "ERROR: tb_nextp8_p8audio failed"; exit 1)
	@echo ""

test-tb_waveform_gen:
	@echo "=== Running tb_waveform_gen: tb_waveform_gen (waveform generation test) ==="
	@$(MAKE) -C nextp8.srcs/tb_waveform_gen || (echo "ERROR: tb_waveform_gen failed"; exit 1)
	@echo ""

# Clean targets
clean-test:
	@echo "=== Cleaning testbench outputs ==="
	@for dir in $(SIM_DIRS); do \
		if [ -f $$dir/Makefile ]; then \
			echo "Cleaning $$dir..."; \
			$(MAKE) -C $$dir clean; \
		fi; \
	done
	@echo "Test clean complete"

clean: clean-test
	@echo "=== Cleaning all generated files ==="
	rm -rf $(BUILD_DIR)
	rm -rf $(PROJECT).cache
	rm -rf $(PROJECT).hw
	rm -rf $(PROJECT).ip_user_files
	rm -rf $(PROJECT).sim
	rm -rf .Xil
	rm -f *.jou *.log
	rm -f $(TIMING_RPT) $(UTIL_RPT)
	rm -f vivado*.backup.jou vivado*.backup.log
	@echo "Clean complete"

# Phony targets for common typos
.PHONY: tests synthesis syn impl
tests: test
syn: synth
impl: implement
