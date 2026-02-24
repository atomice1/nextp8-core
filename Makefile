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
#   make regenerate-ips - Regenerate IP cores
#   make all        - Run full build flow (synth -> implement -> bitstream)
#   make test       - Run all testbenches
#   make clean      - Clean all generated files

# Project settings
PROJECT = nextp8-issue5
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
           nextp8.srcs/tb_p8audio_music \
           nextp8.srcs/tb_nextp8_p8audio \
           nextp8.srcs/tb_waveform_gen \
           nextp8.srcs/tb_memaccess \
           nextp8.srcs/tb_ps2_interface \
           nextp8.srcs/models/tests/tb_ps2_interface_device \
           nextp8.srcs/models/tests/test_ps2_interface_comms \
           nextp8.srcs/models/tests/tb_vga_display \
           nextp8.srcs/tb_keyboard \
           nextp8.srcs/tb_mouse \
           nextp8.srcs/tb_nextp8_keyboard \
           nextp8.srcs/tb_nextp8_mouse \
           nextp8.srcs/tb_i2c_rtc_test

# Output files
BITSTREAM = $(IMPL_DIR)/$(TOP_MODULE).bit
TIMING_RPT = timing_summary.rpt
UTIL_RPT = utilization.rpt

.PHONY: all help clean lint compile synth synthesis implement bitstream test test-quick test-slow test-all rengerate-ip

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
	@echo "  make regenerate-ip - Regenerate IP core simulation netlists"
	@echo "  make all        - Run complete build flow (default)"
	@echo ""
	@echo "Test Targets:"
	@echo "  make test                     - Run quick tests (alias for test-quick)"
	@echo "  make test-quick               - Run all quick tests (excludes slow tests)"
	@echo "  make test-slow                - Run only slow tests (loader + full audio)"
	@echo "  make test-all                 - Run all tests (quick + slow)"
	@echo "  make test-tb_nextp8_boot      - Run exec_tb (full system boot test)"
	@echo "  make test-tb_nextp8_loader    - Run tb_nextp8_loader (bootloader test) [SLOW]"
	@echo "  make test-tb_p8video          - Run p8video_tb (video module test)"
	@echo "  make test-tb_p8audio_sfx      - Run tb_p8audio_sfx (audio SFX test, full)"
	@echo "  make test-tb_p8audio_sfx-quick - Run tb_p8audio_sfx (audio SFX test, SFX 8 only)"
	@echo "  make test-tb_ps2_keyboard     - Run tb_ps2_read_keyboard (PS/2 test)"
	@echo "  make test-tb_p8audio_music    - Run tb_p8audio_music (audio music test)"
	@echo "  make test-tb_nextp8_p8audio   - Run tb_nextp8_p8audio (integrated audio test)"
	@echo "  make test-tb_waveform_gen     - Run tb_waveform_gen (waveform generation test)"
	@echo "  make test-tb_memaccess        - Run tb_memaccess (memory access validation)"
	@echo "  make test-tb_i2c_rtc          - Run i2c_rtc_tb (I2C RTC readback test)"
	@echo "  make test-tb_ps2_interface    - Run tb_ps2_interface (PS/2 HOST mode)"
	@echo "  make test-tb_ps2_interface_device - Run tb_ps2_interface_device (PS/2 DEVICE mode)"
	@echo "  make test-ps2_interface_comms - Run test_ps2_interface_comms (ps2_interface communication test)"
	@echo "  make test-keyboard_device     - Run test_keyboard_device (keyboard device model test)"
	@echo "  make test-mouse_device        - Run test_mouse_device (mouse device model test)"
	@echo "  make test-tb_keyboard         - Run tb_keyboard (keyboard peripheral)"
	@echo "  make test-tb_mouse            - Run tb_mouse (mouse peripheral)"
	@echo "  make test-tb_nextp8_keyboard  - Run tb_nextp8_keyboard (keyboard system integration)"
	@echo "  make test-tb_nextp8_mouse     - Run tb_nextp8_mouse (mouse system integration)"
	@echo "  make test-tb_vga_display      - Run tb_vga_display (VGA display model test)"
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

# IP regeneration target
regenerate-ip:
	@echo "=== Regenerating IP simulation netlists ==="
	$(VIVADO_BATCH) -source $(SCRIPTS_DIR)/regenerate_ip.tcl
	@echo ""
	@echo "IP regeneration complete. Simulation netlists generated."


# Test targets
# test is an alias for test-quick (fast tests for typical development)
test: test-quick

# test-quick runs all quick tests (excludes slow tests)
test-quick: test-tb_nextp8_boot test-tb_p8video test-tb_p8audio_sfx-quick test-tb_p8audio_music test-tb_nextp8_p8audio test-tb_waveform_gen test-tb_ps2_interface test-tb_ps2_interface_device test-ps2_interface_comms test-keyboard_device test-mouse_device test-tb_keyboard test-tb_mouse test-tb_i2c_rtc
	@echo "=== Quick tests complete ==="

# test-slow runs only slow tests
test-slow: test-tb_nextp8_loader test-tb_p8audio_sfx test-tb_nextp8_keyboard test-tb_nextp8_mouse
	@echo "=== Slow tests complete ==="

# test-all runs all tests (quick + slow)
test-all: test-quick test-slow
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
	@echo "=== Running tb_p8audio_sfx: tb_p8audio_sfx (audio SFX test - FULL) ==="
	@$(MAKE) -C nextp8.srcs/tb_p8audio_sfx QUICK=0 || (echo "ERROR: tb_p8audio_sfx failed"; exit 1)
	@echo ""

test-tb_p8audio_sfx-quick:
	@echo "=== Running tb_p8audio_sfx: tb_p8audio_sfx (audio SFX test - QUICK: SFX 8 only) ==="
	@$(MAKE) -C nextp8.srcs/tb_p8audio_sfx QUICK=1 || (echo "ERROR: tb_p8audio_sfx failed"; exit 1)
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

test-tb_i2c_rtc:
	@echo "=== Running tb_i2c_rtc: i2c_rtc_tb (I2C RTC readback test) ==="
	@$(MAKE) -C nextp8.srcs/tb_i2c_rtc_test || (echo "ERROR: tb_i2c_rtc failed"; exit 1)
	@echo ""

test-tb_ps2_interface:
	@echo "=== Running tb_ps2_interface: tb_ps2_interface (PS/2 HOST mode test) ==="
	@$(MAKE) -C nextp8.srcs/tb_ps2_interface || (echo "ERROR: tb_ps2_interface failed"; exit 1)
	@echo ""

test-tb_ps2_interface_device:
	@echo "=== Running tb_ps2_interface_device: tb_ps2_interface_device (PS/2 DEVICE mode test) ==="
	@$(MAKE) -C nextp8.srcs/models/tests/tb_ps2_interface_device || (echo "ERROR: tb_ps2_interface_device failed"; exit 1)
	@echo ""

test-ps2_interface_comms:
	@echo "=== Running test_ps2_interface_comms: ps2_interface communication test ==="
	@$(MAKE) -C nextp8.srcs/models/tests/test_ps2_interface_comms || (echo "ERROR: test_ps2_interface_comms failed"; exit 1)
	@echo ""

test-keyboard_device:
	@echo "=== Running test_keyboard_device: keyboard_device model test ==="
	@$(MAKE) -C nextp8.srcs/models/tests/test_keyboard || (echo "ERROR: test_keyboard_device failed"; exit 1)
	@echo ""

test-mouse_device:
	@echo "=== Running test_mouse_device: mouse_device model test ==="
	@$(MAKE) -C nextp8.srcs/models/tests/test_mouse || (echo "ERROR: test_mouse_device failed"; exit 1)
	@echo ""

test-tb_keyboard:
	@echo "=== Running tb_keyboard: tb_keyboard (keyboard peripheral test) ==="
	@$(MAKE) -C nextp8.srcs/tb_keyboard || (echo "ERROR: tb_keyboard failed"; exit 1)
	@echo ""

test-tb_mouse:
	@echo "=== Running tb_mouse: tb_mouse (mouse peripheral test) ==="
	@$(MAKE) -C nextp8.srcs/tb_mouse || (echo "ERROR: tb_mouse failed"; exit 1)
	@echo ""

test-tb_nextp8_keyboard:
	@echo "=== Running tb_nextp8_keyboard: tb_nextp8_keyboard (keyboard system integration test) ==="
	@$(MAKE) -C nextp8.srcs/tb_nextp8_keyboard || (echo "ERROR: tb_nextp8_keyboard failed"; exit 1)
	@echo ""

test-tb_nextp8_mouse:
	@echo "=== Running tb_nextp8_mouse: tb_nextp8_mouse (mouse system integration test) ==="
	@$(MAKE) -C nextp8.srcs/tb_nextp8_mouse || (echo "ERROR: tb_nextp8_mouse failed"; exit 1)
	@echo ""
test-tb_vga_display:
	@echo "=== Running tb_vga_display: tb_vga_display (VGA display model test) ==="
	@$(MAKE) -C nextp8.srcs/models/tests/tb_vga_display || (echo "ERROR: tb_vga_display failed"; exit 1)
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
.PHONY: tests synthesis syn impl test-memaccess
tests: test
syn: synth
impl: implement
test-memaccess: test-tb_memaccess
