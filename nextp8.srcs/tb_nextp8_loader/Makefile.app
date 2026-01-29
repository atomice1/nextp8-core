# Makefile for building hello test application for RAM
# Uses hello_test_ram.ld linker script (RAM at 0x20000)

# Paths
TB_DIR = .

# Toolchain
TOOLCHAIN = m68k-elf-
CPP = $(TOOLCHAIN)cpp
AS = $(TOOLCHAIN)as
LD = $(TOOLCHAIN)ld
OBJCOPY = $(TOOLCHAIN)objcopy
OBJDUMP = $(TOOLCHAIN)objdump

# Flags
CPPFLAGS = -I../../include
ASFLAGS = -m68000
LDFLAGS = -T $(TB_DIR)/hello_test_ram.ld

# Files
SRC = hello_test.s
PREPROCESSED = hello_test.i
OBJ = hello_test.o
ELF = hello_test.elf
BIN = nextp8.bin
LST = hello_test.lst

.PHONY: all clean

all: $(BIN)

# Preprocess assembly source to expand #include directives
$(PREPROCESSED): $(SRC)
	$(CPP) $(CPPFLAGS) $< -o $@

# Assemble preprocessed source
$(OBJ): $(PREPROCESSED)
	$(AS) $(ASFLAGS) -o $@ $<

# Link with RAM linker script
$(ELF): $(OBJ)
	$(LD) $(LDFLAGS) -o $@ $(OBJ)

# Create binary
$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@
	@echo "Application binary created: $@"
	@echo "Size: $$(stat -c%s $(BIN)) bytes"

# Create listing
$(LST): $(ELF)
	$(OBJDUMP) -d $< > $@

clean:
	rm -f $(PREPROCESSED) $(OBJ) $(ELF) $(BIN) $(LST)

help:
	@echo "Makefile targets:"
	@echo "  make all (default) - Build application binary for RAM"
	@echo "  make clean         - Remove generated files"
	@echo ""
	@echo "Generated files:"
	@echo "  $(BIN)  - Application binary for SD card"
	@echo "  $(LST)  - Disassembly listing"
