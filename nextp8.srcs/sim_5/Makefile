# Makefile for tb_p8audio_music using Vivado xsim
# 
# Usage:
#   make          - Compile and run simulation with default cart (tb_p8audio_music.p8)
#   make CART=path/to/cart.p8 - Run with custom cart
#   make clean    - Remove generated files
#   make wave     - Open waveform viewer (after simulation)

# Paths
SRC_DIR = ../sources_1
TB_DIR = .

# Source files (hierarchy: p8sfx_core <- p8sfx_voice <- p8audio <- tb)
SRCS = $(SRC_DIR)/p8sfx_core.v \
       $(SRC_DIR)/p8sfx_voice.v \
       $(SRC_DIR)/p8audio.v \
       $(SRC_DIR)/dma_arbiter.v \
       $(TB_DIR)/tb_p8audio_music.sv

# Default cart file for testing
CART ?= tb_p8audio_music.p8

# Simulation parameters
TOP = tb_p8audio_music
SNAPSHOT = tb_p8audio_music_snap
TIMEOUT ?= 30

# xsim commands
XVLOG = xvlog
XELAB = xelab
XSIM = xsim

# PICO-8 command (adjust path if needed)
PICO8 ?= pico8

# Build directory
WORK_DIR = xsim.dir

.PHONY: all sim run clean wave help ref

all: sim

# Compile Verilog sources
compile: $(SRCS)
	@echo "=== Compiling Verilog sources ==="
	$(XVLOG) --sv $(SRCS)
	@echo ""

# Elaborate design
elaborate: compile
	@echo "=== Elaborating design ==="
	$(XELAB) $(TOP) -s $(SNAPSHOT) -debug typical
	@echo ""

# Run simulation
sim: elaborate
	@echo "=== Running simulation with cart: $(CART) (timeout: $(TIMEOUT)s) ==="
	@timeout $(TIMEOUT) $(XSIM) $(SNAPSHOT) -runall -testplusarg CART=$(CART) || \
		(if [ $$? -eq 124 ]; then \
			echo "ERROR: Simulation timed out after $(TIMEOUT) seconds"; \
			exit 1; \
		else \
			exit $$?; \
		fi)
	@echo ""
	@echo "=== Simulation complete ==="
	@echo "WAV files generated: tb_p8audio_music.wav"

# Alternative: just run (if already compiled)
run:
	@echo "=== Running simulation (assuming already compiled) ==="
	@timeout $(TIMEOUT) $(XSIM) $(SNAPSHOT) -runall -testplusarg CART=$(CART) || \
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
		echo "ERROR: No waveform database found. Run simulation first with waveform capture enabled."; \
	fi

# Export reference WAV files from PICO-8
ref:
	@echo "=== Exporting reference WAV files from PICO-8 ==="
	@if [ ! -f $(CART) ]; then \
		echo "ERROR: Cart file $(CART) not found."; \
		exit 1; \
	fi
	@echo "Exporting MUSIC from $(CART)..."
	echo $(PICO8) -x $(CART) -export "tb_p8audio_music_ref.wav"; \
	@echo "Reference WAV files exported: tb_p8audio_music_ref.wav"
	@echo ""

compare:
	@echo "=== Comparing audio output with reference ==="
	@if [ ! -f ../../scripts/compare_audio.py ]; then \
		echo "ERROR: compare_audio.py not found in ../../scripts/"; \
		exit 1; \
	fi
	python3 ../../scripts/compare_audio.py "tb_p8audio_music_ref.wav" "tb_p8audio_music.wav"
	@echo "Comparison complete. Check audio_comparison.png"

# Clean generated files
clean:
	@echo "=== Cleaning generated files ==="
	rm -rf $(WORK_DIR)
	rm -rf .Xil
	rm -f *.jou *.log *.pb
	rm -f *.wdb
	rm -f tb_p8audio_music*.wav
	rm -f audio_comparison.png
	rm -f xsim.ini
	@echo "Clean complete"

# Help target
help:
	@echo "Makefile for tb_p8audio_music - P8 Audio Music Testbench"
	@echo ""
	@echo "Targets:"
	@echo "  make          - Compile, elaborate, and run simulation"
	@echo "  make compile  - Compile all sources"
	@echo "  make elaborate- Elaborate the design"
	@echo "  make sim      - Run simulation"
	@echo "  make ref      - Export reference WAV files from PICO-8"
	@echo "  make compare  - Compare reference vs simulation output"
	@echo "  make wave     - Open waveform viewer"
	@echo "  make clean    - Remove generated files"
	@echo ""
	@echo "Options:"
	@echo "  CART=<path>   - Specify cart file (default: tb_p8audio_music.p8)"
	@echo "  PICO8=<path>  - Specify reference platform executable (default: pico8)"
	@echo ""
	@echo "Examples:"
	@echo "  make                              # Run with default cart"
	@echo "  make CART=../../carts/jelpi.p8    # Run with specific cart"
	@echo "  make ref                          # Export reference WAVs from PICO-8"
	@echo "  make clean && make                # Clean rebuild"
	@echo ""
	@echo "Output:"
	@echo "  tb_p8audio_music_out.wav - WAV file from simulation"
	@echo "  tb_p8audio_music_ref.wav - Reference WAV file from PICO-8"
