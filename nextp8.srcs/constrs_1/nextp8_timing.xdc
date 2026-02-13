## ============================================================================
## nextp8 Timing Constraints
## ============================================================================
## Clock Architecture:
##   PLL1 (pll):        50 MHz input
##                      ├─ clk_out1 (clk_sys):    11 MHz      (system bus)
##                      ├─ clk_out2 (clk325):     325 MHz     (PLL2 input)
##                      └─ clk_out3 (mclk):       30.56 MHz   (CPU/memory)
##
##   PLL2 (pll_hdmi):   325 MHz input from PLL1, VCO = 650 MHz
##                      ├─ clk_out1 (clk65):      65.0 MHz    (VGA pixel clock, VCO/10)
##                      └─ clk_out2 (clk_tmds):   325.0 MHz   (HDMI TMDS clock, VCO/2, exactly 5× clk65)
##
##   Generated Clocks:
##                      ├─ clk_video:   32.5 MHz (clk65 / 2, BUFGCE_DIV, exactly clk65/2)
##                      ├─ clk_pcm_8x:  354.8 kHz (audio 8× sample rate)
##                      ├─ clk_pcm:     44.35 kHz (audio sample rate)
##                      └─ joy_clock:   ~168 Hz   (joystick scanning)
##
## Clock Domain Strategy:
##   - PLL1 outputs are related but treated as separate domains (CDC used)
##   - PLL2 outputs are related but treated as separate domains (CDC used)
##   - PLL1 ↔ PLL2 crossings have no phase relationship (different PLLs)
##   - Audio clocks (clk_pcm*) are fractional dividers, fully async
##   - All clock crossings use proper CDC synchronizers in RTL
## ============================================================================

## Generated clocks for audio system
## clk_pcm_8x: 11 MHz / 31 = 354.839 kHz (16× audio sample rate)
## clk_pcm: 354.839 kHz / 8 = 44.355 kHz (2× audio sample rate)
create_generated_clock -name clk_pcm_8x \
    -source [get_pins nextp8_inst/pll/clk_out1] \
    -divide_by 31 \
    [get_pins nextp8_inst/BUFG_clk_pcm_8x/O]

create_generated_clock -name clk_pcm \
    -source [get_pins nextp8_inst/BUFG_clk_pcm_8x/O] \
    -divide_by 8 \
    [get_pins nextp8_inst/BUFG_clk_pcm/O]


## Joystick clock: very slow clock for joystick scanning (~168 Hz from 11 MHz)
create_generated_clock -name joy_clock \
    -source [get_pins nextp8_inst/BUFG_joy_clock/I] \
    -divide_by 65536 \
    -add -master_clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] \
    [get_pins nextp8_inst/BUFG_joy_clock/O]


## Audio clocks are asynchronous to all other clocks
## They derive from fractional divider, not phase-locked to main PLLs
set clk_pcm_8x_clocks [get_clocks -quiet clk_pcm_8x]
set clk_pcm_clocks [get_clocks -quiet clk_pcm]

set_clock_groups -asynchronous -quiet \
    -group $clk_pcm_8x_clocks \
    -group [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]]

set_clock_groups -asynchronous -quiet \
    -group $clk_pcm_8x_clocks \
    -group [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out2]]

set_clock_groups -asynchronous -quiet \
    -group $clk_pcm_8x_clocks \
    -group [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]]

set_clock_groups -asynchronous -quiet \
    -group $clk_pcm_8x_clocks \
    -group [get_clocks -of_objects [get_pins nextp8_inst/pl2/clk_out1]]

set_clock_groups -asynchronous -quiet \
    -group $clk_pcm_8x_clocks \
    -group [get_clocks -of_objects [get_pins nextp8_inst/pl2/clk_out2]]

set_clock_groups -asynchronous -quiet \
    -group $clk_pcm_8x_clocks \
    -group [get_clocks joy_clock]

set_clock_groups -asynchronous -quiet \
    -group $clk_pcm_8x_clocks \
    -group [get_clocks clock_50_i]

## clk_pcm also asynchronous to other domains
set_clock_groups -asynchronous -quiet \
    -group $clk_pcm_clocks \
    -group [get_clocks -of_objects [get_pins nextp8_inst/pl2/clk_out1]]

set_clock_groups -asynchronous -quiet \
    -group $clk_pcm_clocks \
    -group [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]]

set_clock_groups -asynchronous -quiet \
    -group $clk_pcm_clocks \
    -group [get_clocks -of_objects [get_pins nextp8_inst/pl2/clk_out1]]

## PLL1 clocks: clk_sys (clk_out1) and mclk (clk_out3) are asynchronous
## They have CDC synchronizers in the design, so treat as async domains
set_clock_groups -asynchronous -quiet \
    -group [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] \
    -group [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]]

## Reset counter outputs drive many domains - false path to avoid over-constraining
set_false_path -from [get_pins {nextp8_inst/reset_cnt_reg[*]/C}]

## Reset synchronizers for different clock domains (async reset paths)
set_false_path -from [get_pins nextp8_inst/reset_reg_reg*/C] -to [get_pins {nextp8_inst/reset65_d_reg/PRE nextp8_inst/reset65_q_reg/PRE}]

## CDC paths from clk_sys (11 MHz) to mclk (30.56 MHz) with ASYNC_REG synchronizers
## These are properly synchronized with 2-stage synchronizers
## Set max delay to 1 destination clock period (32.821ns for 30.56 MHz mclk)
set_max_delay -from [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] \
              -to [get_pins {nextp8_inst/qlsd_data_d_reg[*]/D nextp8_inst/ql_sd_ready_d_reg/D \
                             nextp8_inst/ql_sd_cs0_n_o_d_reg/D nextp8_inst/ql_sd_cs1_n_o_d_reg/D \
                             nextp8_inst/i2c_din_d_reg[*]/D \
                             nextp8_inst/esp_dout_d_reg[*]/D \
                             nextp8_inst/uart_dout_d_reg[*]/D \
                             nextp8_inst/da_start_sys_d_reg/D}] \
              -datapath_only 32.8

## CDC paths from mclk (30.56 MHz) to clk_sys (11 MHz) with ASYNC_REG synchronizers
## SD card, I2C, UART paths from mclk to clk_sys (all 2-stage synchronizers)
## Set max delay to 1 destination clock period (91.282ns for 11 MHz clk_sys)
set_max_delay -from [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] \
              -to [get_pins {nextp8_inst/qlsd_din_d_reg[*]/D nextp8_inst/qlsd_div_d_reg[*]/D nextp8_inst/ql_sd_w_d_reg/D \
                             nextp8_inst/i2c_dout_d_reg[*]/D nextp8_inst/i2c_rw_d_reg/D nextp8_inst/i2c_ena_d_reg/D \
                             nextp8_inst/esp_din_d_reg[*]/D nextp8_inst/esp_div_d_reg[*]/D nextp8_inst/esp_r_d_reg/D nextp8_inst/esp_w_d_reg/D \
                             nextp8_inst/uart_din_d_reg[*]/D nextp8_inst/uart_div_d_reg[*]/D nextp8_inst/uart_r_d_reg/D nextp8_inst/uart_w_d_reg/D}] \
              -datapath_only 91.3

## Video palette CDC: Direct transfer with ASYNC_REG synchronizers
## Palette data is quasi-static (only changes on palette writes from CPU)
## Use max_delay to allow ample time for clock domain crossing
## Max delay = 1 video clock period (~31ns at 32 MHz video clock)
set_max_delay -from [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] \
              -to [get_pins {nextp8_inst/p8video/palette0_video_reg[*]/D}] \
              -datapath_only 31.0
set_max_delay -from [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] \
              -to [get_pins {nextp8_inst/p8video/palette1_video_reg[*]/D}] \
              -datapath_only 31.0

## VGA frontend request CDC from clk_sys to clk_video  
set_max_delay -from [get_pins {nextp8_inst/vfrontreq_reg/C}] \
              -to [get_pins {nextp8_inst/p8video/vfrontreq_q_reg/D}] \
              -datapath_only 31.0

## VGA frontend acknowledge CDC from clk_video to clk_sys
set_max_delay -from [get_pins {nextp8_inst/p8video/vfront_reg/C}] \
              -to [get_pins {nextp8_inst/p8video/vfronto_q_reg/D}] \
              -datapath_only 33.0


## Input/Output Delays
## These define the board-level timing requirements for external interfaces

## Button inputs are asynchronous - constrained via false_path below, not input_delay

## ESP32 UART (115200 baud, async, on clk_sys 11 MHz)
set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -max 20.0 [get_ports esp_rx_i]
set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -min 0.0 [get_ports esp_rx_i]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -max 20.0 [get_ports esp_tx_o]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -min 0.0 [get_ports esp_tx_o]

## SD card SPI interface (on clk_sys 11 MHz)
set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -max 5.0 [get_ports sd_miso_i]
set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -min 0.0 [get_ports sd_miso_i]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -max 5.0 [get_ports {sd_cs0_n_o sd_cs1_n_o sd_mosi_o sd_sclk_o}]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -min 0.0 [get_ports {sd_cs0_n_o sd_cs1_n_o sd_mosi_o sd_sclk_o}]

## Audio DAC outputs (PWM-style, on clk65 64.71 MHz, board RC filter)
## Digital audio moved to clk65 domain for better timing
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pl2/clk_out1]] -max 5.0 [get_ports {audioext_l_o audioext_r_o}]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pl2/clk_out1]] -min 0.0 [get_ports {audioext_l_o audioext_r_o}]


## HDMI outputs: TMDS serializer has internal timing, max delay keeps routing reasonable
set_max_delay -to [get_ports {hdmi_p_o[*] hdmi_n_o[*]}] 8.0

## HDMI TMDS serializer: data sampled on clk_tmds (323 MHz), serialized on 10x that
## Multi-cycle path because data is stable for 2 clk_tmds cycles
set_multicycle_path -setup 2 -to [get_pins nextp8_inst/hdmiqout/g1[*].to_serial/D*] -from [get_clocks -of_objects [get_pins nextp8_inst/pl2/clk_out2]]
set_multicycle_path -hold 1 -to [get_pins nextp8_inst/hdmiqout/g1[*].to_serial/D*] -from [get_clocks -of_objects [get_pins nextp8_inst/pl2/clk_out2]]

## Keyboard matrix scanning (on clk_sys 11 MHz)
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -max 15.0 [get_ports keyb_row_o[*]]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -min 0.0 [get_ports keyb_row_o[*]]
set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -max 15.0 [get_ports keyb_col_i[*]]
set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -min 0.0 [get_ports keyb_col_i[*]]

## External SRAM interface (on mclk/clk_out3 30.56 MHz)
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -max 10.0 [get_ports ram_addr_o[*]]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -min 0.0 [get_ports ram_addr_o[*]]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -max 10.0 [get_ports {ram_cs_n_o ram_lb_n_o ram_ub_n_o ram_oe_n_o}]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -min 0.0 [get_ports {ram_cs_n_o ram_lb_n_o ram_ub_n_o ram_oe_n_o}]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -max 3.0 [get_ports ram_we_n_o]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -min 0.0 [get_ports ram_we_n_o]

## SRAM data is bidirectional
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -max 10.0 [get_ports ram_data_io[*]]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -min 0.0 [get_ports ram_data_io[*]]

set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -max 12.0 [get_ports ram_data_io[*]]
set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -min 0.0 [get_ports ram_data_io[*]]

## I2C bus for RTC (on clk_sys 11 MHz, slow protocol, relaxed timing)
set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -max 50.0 [get_ports {i2c_scl_io i2c_sda_io}]
set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -min 0.0 [get_ports {i2c_scl_io i2c_sda_io}]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -max 50.0 [get_ports {i2c_scl_io i2c_sda_io}]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -min 0.0 [get_ports {i2c_scl_io i2c_sda_io}]

## Joystick select signal (on joy_clock ~168 Hz, very relaxed timing)
set_output_delay -clock [get_clocks joy_clock] -max 200.0 [get_ports {joysel_o}]
set_output_delay -clock [get_clocks joy_clock] -min 0.0 [get_ports {joysel_o}]

## Accelerater I2C (on 50 MHz clock)
set_input_delay -clock [get_clocks clock_50_i] -max 20.0 [get_ports accel_io[*]]
set_input_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports accel_io[*]]
set_output_delay -clock [get_clocks clock_50_i] -max 20.0 [get_ports accel_io[*]]
set_output_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports accel_io[*]]

## VGA outputs (on clk65 64.71 MHz pixel clock)
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pl2/clk_out1]] -max 5.0 [get_ports {rgb_r_o[*] rgb_g_o[*] rgb_b_o[*] hsync_o vsync_o}]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pl2/clk_out1]] -min 0.0 [get_ports {rgb_r_o[*] rgb_g_o[*] rgb_b_o[*] hsync_o vsync_o}]

## VGA DAC clock outputs (direct clock forwarding from clk65)
set_max_delay -to [get_ports {vgaclk_o vgaclkn_o}] 5.0

## Pi UART output (async serial, on clk_sys)
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -max 20.0 [get_ports pi_uart_tx_o]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -min 0.0 [get_ports pi_uart_tx_o]

## Debug/diagnostic outputs (not timing critical)
set_false_path -to [get_ports {postcode_o[*] joyp7_o}]

## Clock Domain Crossing False Paths
## These are paths between different PLLs or async clock domains with proper CDC

## PLL2 internal crossing: clk_video (32.5 MHz) ↔ clk65 (65.0 MHz)
## Both from same PLL but treated as async domains - handled with CDC in design
set_false_path -from [get_clocks clk_out3_pll_hdmi] -to [get_clocks clk_out1_pll_hdmi]
set_false_path -from [get_clocks clk_out1_pll_hdmi] -to [get_clocks clk_out3_pll_hdmi]

## Async input paths: buttons with synchronizers
set_false_path -from [get_ports btn_*] -to [get_pins -hierarchical *sync*/D]

## Unused button inputs (divmmc, multiface): mark as unconstrained
set_false_path -from [get_ports {btn_divmmc_n_i btn_multiface_n_i}]

## Reset button to clock domains (async, has debounce and sync)
set_false_path -from [get_ports btn_reset_n_i] -to [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]]
set_false_path -from [get_ports btn_reset_n_i] -to [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]]

## Vsync interrupt: video_vs_mclk_q used as async clock for interrupt latch
## This is intentional edge-triggered interrupt logic with async reset
set_false_path -from [get_pins {nextp8_inst/video_vs_mclk_q_reg/C}] -to [get_pins {nextp8_inst/vsync_irq_reg/C}]
set_false_path -to [get_pins {nextp8_inst/vsync_irq_reg/CLR}]

## PS/2 keyboard (async bidirectional I/O, handled by keyboard controller)
## Input constraints: async protocol with synchronizers
set_false_path -from [get_ports {ps2_data_io ps2_pin2_io ps2_clk_io ps2_pin6_io}] -to [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]]

## Output constraints: async protocol, no timing requirements
set_false_path -to [get_ports {ps2_clk_io ps2_data_io ps2_pin2_io ps2_pin6_io}]

## ESP32 UART (async serial, has CDC in UART module)
set_false_path -from [get_ports esp_rx_i]
set_false_path -to [get_ports esp_tx_o]

## ESP32 flow control (async)
set_false_path -from [get_ports esp_rtr_n_i]

## NextPi accelerator GPIO (async)
set_false_path -from [get_ports accel_io[*]]
set_false_path -to [get_ports accel_io[*]]

## ZX Spectrum expansion bus signals (async to FPGA clocks)
set_false_path -from [get_ports {bus_busreq_n_i bus_int_in_i bus_iorqula_n_i bus_nmi_n_i bus_romcs_i bus_wait_n_i}]

## Joystick inputs (async, sampled at low frequency)
set_false_path -from [get_ports {joyp1_i joyp2_i joyp3_i joyp4_i joyp6_i joyp9_i}]

## Cassette/tape input (async audio signal)
set_false_path -from [get_ports ear_port_i]

## SPI flash input (self-timed by internal SPI controller)
set_false_path -from [get_ports flash_miso_i]

## Unused input ports (not connected in design)
set_false_path -from [get_ports {btn_divmmc_n_i btn_multiface_n_i}]
set_false_path -from [get_ports {XADC_VP XADC_VN XADC_15P XADC_15N XADC_7P XADC_7N}]

## Joystick clock domain (very slow, async)
set_false_path -from [get_clocks joy_clock]
set_false_path -to [get_clocks joy_clock]


## Video BRAM to output register paths
## BRAM outputs are async to video clock, captured in registers
set_false_path -from [get_cells -hierarchical -filter {NAME =~ *vram* && PRIMITIVE_TYPE =~ BMEM.*}] -to [get_cells nextp8_inst/p8video/VR_reg*]
set_false_path -from [get_cells -hierarchical -filter {NAME =~ *vram* && PRIMITIVE_TYPE =~ BMEM.*}] -to [get_cells nextp8_inst/p8video/VG_reg*]
set_false_path -from [get_cells -hierarchical -filter {NAME =~ *vram* && PRIMITIVE_TYPE =~ BMEM.*}] -to [get_cells nextp8_inst/p8video/VB_reg*]

## Multi-cycle path for palette lookup (4 video clocks setup, 3 hold)
## Palette data is stable for multiple pixel clocks during rendering
set_multicycle_path 4 -setup -from [get_cells nextp8_inst/p8video/palette*_video_reg[*]] -to [get_cells nextp8_inst/p8video/V*_reg[*]]
set_multicycle_path 3 -hold -from [get_cells nextp8_inst/p8video/palette*_video_reg[*]] -to [get_cells nextp8_inst/p8video/V*_reg[*]]


## Audio and InfoFrame CDC from clk_sys to clk_tmds for HDMI audio
## These are synchronized with multi-stage synchronizers in the design
set_false_path -from [get_cells nextp8_inst/da_playing_reg] -to [get_cells nextp8_inst/da_playing_tmds_?_reg]
set_false_path -from [get_cells nextp8_inst/da_mono_reg] -to [get_cells nextp8_inst/da_mono_tmds_?_reg]
set_false_path -from [get_cells {nextp8_inst/p8audio_pcm_out_sys_q_reg[*]}] -to [get_cells {nextp8_inst/p8audio_pcm_out_tmds_?_reg[*]}]
set_false_path -from [get_cells {nextp8_inst/p8audio_inst/pcm_out_reg[*]}] -to [get_cells {nextp8_inst/p8audio_pcm_out_tmds_?_reg[*]}]

## HDMI InfoFrame BRAM read from clk_tmds domain to clk_sys domain
## da_memory is dual-port BRAM: write port on clk_tmds/10, read port on clk_sys
## This is an asynchronous read - data stability is guaranteed by control logic
set_false_path -from [get_clocks clk_out3_pll] -to [get_pins {nextp8_inst/da_data_reg[*]/D}]

## PS/2 keyboard parameter sync (quasi-static control)
set_false_path -from [get_cells nextp8_inst/params_reg[0]] -to [get_cells {nextp8_inst/keyboard/ps2_keyboard/ps2*_sync_reg[0]}]


## Inter-PLL clock domain crossings
## PLL1 (pll): 50MHz input → 11MHz (clk_out1), 325MHz (clk_out2), 30.56MHz (clk_out3)
## PLL2 (pl2/pll_hdmi): 325MHz input → 65.0MHz (clk_out1), 325.0MHz (clk_out2)
## These PLLs have no phase relationship despite PLL2 using PLL1's output as input
## All crossings use proper CDC synchronizers in RTL

## mclk (30.56 MHz) ↔ clk_video (32.5 MHz): different PLLs
set_false_path -from [get_clocks clk_out3_pll] -to [get_clocks clk_out3_pll_hdmi]
set_false_path -from [get_clocks clk_out3_pll_hdmi] -to [get_clocks clk_out3_pll]

## mclk (30.56 MHz) ↔ clk65 (65.0 MHz): different PLLs
set_false_path -from [get_clocks clk_out3_pll] -to [get_clocks clk_out1_pll_hdmi]
set_false_path -from [get_clocks clk_out1_pll_hdmi] -to [get_clocks clk_out3_pll]

## clk325 (325 MHz) ↔ clk65 (65.0 MHz): same PLL, different dividers, treat as async
set_false_path -from [get_clocks clk_out2_pll] -to [get_clocks clk_out1_pll_hdmi]
set_false_path -from [get_clocks clk_out1_pll_hdmi] -to [get_clocks clk_out2_pll]

## clk325 (325 MHz) ↔ clk_tmds (325.0 MHz): different PLLs despite same frequency
set_false_path -from [get_clocks clk_out2_pll] -to [get_clocks clk_out2_pll_hdmi]
set_false_path -from [get_clocks clk_out2_pll_hdmi] -to [get_clocks clk_out2_pll]

## clk325 (325 MHz) ↔ clk_video (32.5 MHz): different PLLs
set_false_path -from [get_clocks clk_out2_pll] -to [get_clocks clk_out3_pll_hdmi]
set_false_path -from [get_clocks clk_out3_pll_hdmi] -to [get_clocks clk_out2_pll]

## clk_sys (11 MHz) ↔ clk_tmds (325.0 MHz): different PLLs, audio outputs
set_false_path -from [get_clocks clk_out1_pll] -to [get_clocks clk_out2_pll_hdmi]
set_false_path -from [get_clocks clk_out2_pll_hdmi] -to [get_clocks clk_out1_pll]

## clk_sys (11 MHz) ↔ clk_video (32.5 MHz): different PLLs
set_false_path -from [get_clocks clk_out1_pll] -to [get_clocks clk_out3_pll_hdmi]
set_false_path -from [get_clocks clk_out3_pll_hdmi] -to [get_clocks clk_out1_pll]

## VRAM address to BRAM (async path, address stable before read)
set_false_path -from [get_cells nextp8_inst/p8video/vaddress_reg*] -to [get_cells nextp8_inst/vram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop*ram.r/prim_noinit.ram/DEVICE_7SERIES.NO_BMM_INFO.TRUE_DP.SIMPLE_PRIM36.ram*]

