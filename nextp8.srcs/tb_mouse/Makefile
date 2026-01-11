# Makefile for tb_mouse testbench

HOST_SV = ../sources_1/ps2_interface.sv
DEVICE_SV = ../models/ps2_interface_device.sv
VERILOG_SOURCES = ../sources_1/mouse.sv
SV_SOURCES = ../models/mouse_device.sv ../models/ps2_sniffer.sv tb_mouse.sv

all: sim

compile:
	xvlog -sv $(HOST_SV) $(DEVICE_SV)
	xvlog -sv $(VERILOG_SOURCES) $(SV_SOURCES)

sim: compile
	xelab -debug all tb_mouse -s tb_mouse_snap
	xsim tb_mouse_snap -runall

clean:
	rm -rf xsim.dir
	rm -f *.jou *.log *.pb
	rm -f .Xil

.PHONY: all compile sim clean
