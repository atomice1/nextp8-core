## ============================================================================
## nextp8 Timing Constraints
## ============================================================================
## This file contains timing constraints for the nextp8 PICO-8 core.
## ============================================================================

## ----------------------------------------------------------------------------
## Generated Clocks
## ----------------------------------------------------------------------------
## Note: The PLL IP automatically creates generated clocks for CLKOUT0-5.
## Additional derived clocks are defined here, but some may not be visible
## during synthesis and should be applied during implementation instead.

## These generated clock definitions commented out as they reference design
## registers that may not be visible during synthesis. The timing engine
## will automatically propagate clock relationships through the design.
## If needed for implementation, these can be moved to an impl-only XDC file.

## clk2i: derived from mclk (CLKOUT5), divided by 3
# create_generated_clock -name clk2i -source [get_pins pll/clk_out5] -divide_by 3 [get_pins clk2i_reg/Q]

## clk_pcm_pulse: derived from clk22 (CLKOUT1), divided by 998 for 22.05 kHz audio sample rate
# create_generated_clock -name clk_pcm_pulse -source [get_pins pll/clk_out1] -divide_by 998 [get_pins clk_pcm_pulse_reg/Q]

## joy_clock: derived from clk2i, divided by 2048 for joystick polling
# create_generated_clock -name joy_clock -source [get_pins clk2i_reg/Q] -divide_by 2048 [get_pins {joy_clk_div_reg[11]/Q}]

## memio_go__0: derived from mclk (CLKOUT5), divided by 3
# create_generated_clock -name memio_go__0 -source [get_pins pll/clk_out5] -divide_by 3 [get_pins memio_go_reg/Q]

## Old audio clock divider constraints - commented out as implementation may have changed
## create_generated_clock -name {p8audio_inst/pcm_div_ff[0]} -source [get_pins clk_pcm_pulse_reg/Q] -divide_by 2 [get_pins {p8audio_inst/pcm_div_ff_reg[0]/Q}]
## create_generated_clock -name {p8audio_inst/pcm_div_ff[1]} -source [get_pins clk_pcm_pulse_reg/Q] -divide_by 2 [get_pins {p8audio_inst/pcm_div_ff_reg[1]/Q}]
## create_generated_clock -name {p8audio_inst/pcm_div_ff[2]} -source [get_pins clk_pcm_pulse_reg/Q] -divide_by 2 [get_pins {p8audio_inst/pcm_div_ff_reg[2]/Q}]
## create_generated_clock -name {p8audio_inst/pcm_div_ff[3]} -source [get_pins clk_pcm_pulse_reg/Q] -divide_by 2 [get_pins {p8audio_inst/pcm_div_ff_reg[3]/Q}]
## create_generated_clock -name clk_pcm_pulse_Gen -source [get_pins {p8audio_inst/phase_acc[0]_i_12__3/I2}] -divide_by 1 -add -master_clock clk_pcm_pulse [get_pins {p8audio_inst/phase_acc[0]_i_12__3/O}]
## create_generated_clock -name {p8audio_inst/pcm_div_ff[0]_Gen} -source [get_pins {p8audio_inst/phase_acc[0]_i_12__3/I0}] -divide_by 1 -add -master_clock p8audio_inst/pcm_div_ff[0] [get_pins {p8audio_inst/phase_acc[0]_i_12__3/O}]
## create_generated_clock -name clk_pcm_pulse_Gen_1 -source [get_pins {p8audio_inst/phase_acc[0]_i_12__4/I2}] -divide_by 1 -add -master_clock clk_pcm_pulse [get_pins {p8audio_inst/phase_acc[0]_i_12__4/O}]
## create_generated_clock -name {p8audio_inst/pcm_div_ff[1]_Gen} -source [get_pins {p8audio_inst/phase_acc[0]_i_12__4/I0}] -divide_by 1 -add -master_clock p8audio_inst/pcm_div_ff[1] [get_pins {p8audio_inst/phase_acc[0]_i_12__4/O}]
## create_generated_clock -name clk_pcm_pulse_Gen_2 -source [get_pins {p8audio_inst/phase_acc[0]_i_12__5/I2}] -divide_by 1 -add -master_clock clk_pcm_pulse [get_pins {p8audio_inst/phase_acc[0]_i_12__5/O}]
## create_generated_clock -name {p8audio_inst/pcm_div_ff[2]_Gen} -source [get_pins {p8audio_inst/phase_acc[0]_i_12__5/I0}] -divide_by 1 -add -master_clock p8audio_inst/pcm_div_ff[2] [get_pins {p8audio_inst/phase_acc[0]_i_12__5/O}]
## create_generated_clock -name clk_pcm_pulse_Gen_3 -source [get_pins {p8audio_inst/phase_acc[0]_i_12__6/I2}] -divide_by 1 -add -master_clock clk_pcm_pulse [get_pins {p8audio_inst/phase_acc[0]_i_12__6/O}]
## create_generated_clock -name {p8audio_inst/pcm_div_ff[3]_Gen} -source [get_pins {p8audio_inst/phase_acc[0]_i_12__6/I0}] -divide_by 1 -add -master_clock p8audio_inst/pcm_div_ff[3] [get_pins {p8audio_inst/phase_acc[0]_i_12__6/O}]

## ----------------------------------------------------------------------------
## Clock Groups - Asynchronous Domains
## ----------------------------------------------------------------------------
## The PLL IP cores automatically create generated clocks:
##   pll/clk_out1 - 22.00000 MHz (clk22 - system/CPU)
##   pll/clk_out2 - 11.00000 MHz (clk11 - peripherals)
##   pll/clk_out3 - 32.35294 MHz (clk325 - video base)
##   pll/clk_out4 - 32.35294 MHz inv (clk325n - qlsdpi)
##   pll/clk_out5 - 30.55556 MHz (mclk - memory)
##   pl2/clk_out1 - 64.70588 MHz (clk65 - pixel)
##   pl2/clk_out2 - 323.52940 MHz (clk1625 - TMDS)
##
## These domains are NOT synchronized - we use async CDC techniques

set_clock_groups -asynchronous \
    -group [get_clocks -of_objects [get_pins pll/clk_out1]] \
    -group [get_clocks -of_objects [get_pins pll/clk_out2]] \
    -group [get_clocks -of_objects [get_pins pll/clk_out3]] \
    -group [get_clocks -of_objects [get_pins pll/clk_out4]] \
    -group [get_clocks -of_objects [get_pins pll/clk_out5]] \
    -group [get_clocks -of_objects [get_pins pl2/clk_out1]] \
    -group [get_clocks -of_objects [get_pins pl2/clk_out2]]

## Old clock constraints from previous design - commented out as these clocks don't exist
## set_clock_groups -logically_exclusive -group [get_clocks -include_generated_clocks clk_pcm_pulse_Gen] -group [get_clocks -include_generated_clocks {p8audio_inst/pcm_div_ff[0]_Gen}]
## set_clock_groups -logically_exclusive -group [get_clocks -include_generated_clocks clk_pcm_pulse_Gen_1] -group [get_clocks -include_generated_clocks {p8audio_inst/pcm_div_ff[1]_Gen}]
## set_clock_groups -logically_exclusive -group [get_clocks -include_generated_clocks clk_pcm_pulse_Gen_2] -group [get_clocks -include_generated_clocks {p8audio_inst/pcm_div_ff[2]_Gen}]
## set_clock_groups -logically_exclusive -group [get_clocks -include_generated_clocks clk_pcm_pulse_Gen_3] -group [get_clocks -include_generated_clocks {p8audio_inst/pcm_div_ff[3]_Gen}]
## set_clock_groups -asynchronous -group [get_clocks clk_pcm_pulse] -group [get_clocks clk_out1_pll_hdmi]
## set_clock_groups -asynchronous -group [get_clocks joy_clock] -group [get_clocks memio_go__0]

## ----------------------------------------------------------------------------
## Clock Domain Crossing Constraints
## ----------------------------------------------------------------------------
## Max delay for signals crossing from system clock to video clocks
## Conservative value: 1.5× slower clock period = 1.5 × 45.45ns = 68ns

set_max_delay -from [get_clocks -of_objects [get_pins pll/clk_out1]] \
              -to [get_clocks -of_objects [get_pins pll/clk_out3]] \
              68.0

set_max_delay -from [get_clocks -of_objects [get_pins pll/clk_out1]] \
              -to [get_clocks -of_objects [get_pins pl2/clk_out1]] \
              68.0

## Max delay from video back to system
set_max_delay -from [get_clocks -of_objects [get_pins pll/clk_out3]] \
              -to [get_clocks -of_objects [get_pins pll/clk_out1]] \
              68.0

## Max delay for memory controller crossings
set_max_delay -from [get_clocks -of_objects [get_pins pll/clk_out1]] \
              -to [get_clocks -of_objects [get_pins pll/clk_out5]] \
              68.0

set_max_delay -from [get_clocks -of_objects [get_pins pll/clk_out5]] \
              -to [get_clocks -of_objects [get_pins pll/clk_out1]] \
              68.0

## ----------------------------------------------------------------------------
## Input/Output Delays
## ----------------------------------------------------------------------------
## External signals relative to the 50MHz input clock

## GPIO/Button inputs - allow 10ns for board routing
## Note: gpio_* ports currently not used in design, commented out
## set_input_delay -clock [get_clocks clock_50_i] -max 10.0 [get_ports gpio_*]
set_input_delay -clock [get_clocks clock_50_i] -max 10.0 [get_ports btn_*]

## UART - 115200 baud is ~8.68us per bit, timing not critical
## Note: uart_rx/uart_tx currently not used in design, commented out
## set_input_delay -clock [get_clocks clock_50_i] -max 20.0 [get_ports uart_rx]
## set_output_delay -clock [get_clocks clock_50_i] -max 20.0 [get_ports uart_tx]

## SD Card SPI - runs at ~400kHz during init, up to 25MHz high-speed mode
set_input_delay -clock [get_clocks clock_50_i] -max 30.0 [get_ports sd_miso_i]
set_input_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports sd_miso_i]
set_output_delay -clock [get_clocks clock_50_i] -max 30.0 [get_ports {sd_cs0_n_o sd_cs1_n_o sd_mosi_o sd_sclk_o}]

## Audio DAC - I2S, synchronous to audio clock (clk22)
set_output_delay -clock [get_clocks -of_objects [get_pins pll/clk_out1]] -max 22.0 [get_ports {audioext_l_o audioext_r_o}]
set_output_delay -clock [get_clocks -of_objects [get_pins pll/clk_out1]] -min 0.0 [get_ports {audioext_l_o audioext_r_o}]

## HDMI outputs - synchronous to TMDS serialization clock (323.53 MHz)
## These are driven by ODDR primitives, very tight timing
set_output_delay -clock [get_clocks -of_objects [get_pins pl2/clk_out2]] -max 3.0 [get_ports {hdmi_p_o[*] hdmi_n_o[*]}]
set_output_delay -clock [get_clocks -of_objects [get_pins pl2/clk_out2]] -min -1.0 [get_ports {hdmi_p_o[*] hdmi_n_o[*]}]

## Keyboard Matrix - Not timing critical (scanned at ~1kHz)
## Rows driven by FPGA, columns sensed with pullups
set_output_delay -clock [get_clocks clock_50_i] -max 15.0 [get_ports keyb_row_o[*]]
set_input_delay -clock [get_clocks clock_50_i] -max 15.0 [get_ports keyb_col_i[*]]
set_input_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports keyb_col_i[*]]

## External SRAM (Asynchronous) - Timing relative to memory clock (mclk)
## Typical async SRAM: 10ns access time, but we use 30.56MHz mclk = 32.7ns period
## Conservative constraints to allow for PCB routing and signal integrity

# SRAM outputs from FPGA (address, control signals)
set_output_delay -clock [get_clocks -of_objects [get_pins pll/clk_out5]] -max 10.0 [get_ports ram_addr_o[*]]
set_output_delay -clock [get_clocks -of_objects [get_pins pll/clk_out5]] -max 10.0 [get_ports {ram_cs_n_o ram_lb_n_o ram_ub_n_o ram_oe_n_o ram_we_n_o}]

# SRAM bidirectional data bus
# When writing (output from FPGA)
set_output_delay -clock [get_clocks -of_objects [get_pins pll/clk_out5]] -max 10.0 [get_ports ram_data_io[*]]
set_output_delay -clock [get_clocks -of_objects [get_pins pll/clk_out5]] -min 0.0 [get_ports ram_data_io[*]]

# When reading (input to FPGA) - allow for RAM access time
set_input_delay -clock [get_clocks -of_objects [get_pins pll/clk_out5]] -max 15.0 [get_ports ram_data_io[*]]
set_input_delay -clock [get_clocks -of_objects [get_pins pll/clk_out5]] -min 0.0 [get_ports ram_data_io[*]]

## Note: set_max_input_transition not supported in XDC constraint files
## Signal integrity should be handled via PCB design and termination
# set_max_input_transition 5.0 [get_ports ram_data_io[*]]

# ESP WiFi Module UART - Very relaxed timing (115200 baud = 8.68us/bit)
## UART is asynchronous, no tight timing requirements
set_input_delay -clock [get_clocks clock_50_i] -max 50.0 [get_ports esp_rx_i]
set_input_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports esp_rx_i]
set_output_delay -clock [get_clocks clock_50_i] -max 50.0 [get_ports esp_tx_o]
set_output_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports esp_tx_o]

## I2C Bus (SCL/SDA) - Very relaxed timing (typically 100-400 kHz)
## I2C is open-drain with pullups, no tight timing requirements
## Even at Fast-Mode Plus (1 MHz), bit time is 1000ns
set_input_delay -clock [get_clocks clock_50_i] -max 50.0 [get_ports {i2c_scl_io i2c_sda_io}]
set_input_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports {i2c_scl_io i2c_sda_io}]
set_output_delay -clock [get_clocks clock_50_i] -max 50.0 [get_ports {i2c_scl_io i2c_sda_io}]
set_output_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports {i2c_scl_io i2c_sda_io}]

## Note: set_max_input_transition not supported in XDC constraint files
## Signal integrity should be handled via PCB design and pullup resistors
# set_max_input_transition 10.0 [get_ports {i2c_scl_io i2c_sda_io}]

## Joystick interface (human input, not timing critical)
set_input_delay -clock [get_clocks clock_50_i] -max 15.0 [get_ports {joyp1_i joyp2_i joyp3_i joyp4_i joyp6_i joyp9_i}]
set_input_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports {joyp1_i joyp2_i joyp3_i joyp4_i joyp6_i joyp9_i}]
set_output_delay -clock [get_clocks clock_50_i] -max 15.0 [get_ports {joyp7_o joysel_o}]

## PS/2 interface (keyboard/mouse, 10-16 kHz clock, very slow)
set_input_delay -clock [get_clocks clock_50_i] -max 50.0 [get_ports {ps2_clk_io ps2_data_io ps2_pin2_io ps2_pin6_io}]
set_input_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports {ps2_clk_io ps2_data_io ps2_pin2_io ps2_pin6_io}]
set_output_delay -clock [get_clocks clock_50_i] -max 50.0 [get_ports {ps2_clk_io ps2_data_io ps2_pin2_io ps2_pin6_io}]

## Note: set_max_input_transition not supported in XDC constraint files
## Signal integrity should be handled via PCB design and pullup resistors
# set_max_input_transition 10.0 [get_ports {ps2_clk_io ps2_data_io ps2_pin2_io ps2_pin6_io}]

## Accelerator/Expansion bus GPIO - General purpose I/O, timing depends on usage
## Use relaxed constraints suitable for typical expansion cards
set_input_delay -clock [get_clocks clock_50_i] -max 20.0 [get_ports accel_io[*]]
set_input_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports accel_io[*]]
set_output_delay -clock [get_clocks clock_50_i] -max 20.0 [get_ports accel_io[*]]
set_output_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports accel_io[*]]

## RGB/VGA video outputs - synchronous to pixel clock (64.71 MHz)
## RGB data and sync signals, moderate timing requirements
set_output_delay -clock [get_clocks -of_objects [get_pins pl2/clk_out1]] -max 5.0 [get_ports {rgb_r_o[*] rgb_g_o[*] rgb_b_o[*] hsync_o vsync_o}]
set_output_delay -clock [get_clocks -of_objects [get_pins pl2/clk_out1]] -min 0.0 [get_ports {rgb_r_o[*] rgb_g_o[*] rgb_b_o[*] hsync_o vsync_o}]

## ----------------------------------------------------------------------------
## False Paths
## ----------------------------------------------------------------------------
## Async resets - don't analyze timing to reset pins
## Note: PRE pins not present in current design, only CLR used
# set_false_path -to [get_pins -hierarchical *rst*/PRE]
set_false_path -to [get_pins -hierarchical *rst*/CLR]

## Async inputs that go through synchronizers
set_false_path -from [get_ports btn_*] -to [get_pins -hierarchical *sync*/D]
## Note: gpio_* ports currently not used in design, commented out
# set_false_path -from [get_ports gpio_*] -to [get_pins -hierarchical *sync*/D]

## ============================================================================
## End of nextp8 Timing Constraints
## ============================================================================