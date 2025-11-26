## ============================================================================
## nextp8 Timing Constraints
## ============================================================================
## Clock Architecture:
##   PLL1 (pll):        50 MHz input
##                      ├─ clk_out1 (clk_sys):    11 MHz      (system bus)
##                      ├─ clk_out2 (clk325):     32.35 MHz   (PLL2 input)
##                      └─ clk_out3 (mclk):       30.56 MHz   (CPU/memory)
##
##   PLL2 (pll_hdmi):   32.35 MHz input from PLL1
##                      ├─ clk_out1 (clk65):      64.71 MHz   (VGA pixel clock)
##                      ├─ clk_out2 (clk_tmds):   323.53 MHz  (HDMI TMDS clock)
##                      └─ clk_out3 (clk_video):  10.78 MHz   (video timing)
##
##   Generated Clocks:
##                      ├─ clk_cpu:     30.56 MHz (from mclk, separate domain)
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

## CPU clock: same as mclk (30.56 MHz) but buffered separately for CPU domain
create_generated_clock -name clk_cpu \
    -source [get_pins nextp8_inst/pll/clk_out3] \
    -divide_by 1 \
    [get_pins nextp8_inst/BUFG_inst2/O]

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


## Reset counter outputs drive many domains - false path to avoid over-constraining
set_false_path -from [get_pins {nextp8_inst/reset_cnt_reg[*]/C}]

## Video palette CDC: toggle-based handshake from clk_sys to clk_video
## Max delay = ~1 video clock period (31ns at 32.35 MHz)
set_max_delay -from [get_pins {nextp8_inst/p8video/palette_update_toggle_sys_reg/C}] \
              -to [get_pins {nextp8_inst/p8video/palette_update_toggle_video_reg/D}] \
              -datapath_only 31.0

## Palette data CDC from clk_sys to clk_video
set_max_delay -from [get_pins -hier -filter {NAME =~ */screen_palette*_sys*}] -to [get_pins -hier -filter {NAME =~ */palette*_video_reg*}] 20.0

## Palette transfers use multi-cycle paths (data stable for multiple cycles)
set_false_path -from [get_cells {nextp8_inst/p8video/screen_palette0_sys_reg[*][*]}] \
               -to [get_cells {nextp8_inst/p8video/palette0_video_reg[*]}]
set_false_path -from [get_cells {nextp8_inst/p8video/screen_palette1_sys_reg[*][*]}] \
               -to [get_cells {nextp8_inst/p8video/palette1_video_reg[*]}]

## VGA frontend request CDC from clk_sys to clk_video  
set_max_delay -from [get_pins {nextp8_inst/vfrontreq_reg/C}] \
              -to [get_pins {nextp8_inst/p8video/vfrontreq_q_reg/D}] \
              -datapath_only 31.0

## VGA frontend acknowledge CDC from clk_video to clk_sys
set_max_delay -from [get_pins {nextp8_inst/p8video/vfront_reg/C}] \
              -to [get_pins {nextp8_inst/p8video/vfronto_q_reg/D}] \
              -datapath_only 33.0

## HDMI InfoFrame data CDC from clk_sys to clk_tmds
set_false_path -from [get_cells nextp8_inst/da_memory_reg*] -to [get_cells nextp8_inst/da_data_tmds_*_reg[*]]


## Input/Output Delays
## These define the board-level timing requirements for external interfaces

## Button inputs on 50 MHz clock
set_input_delay -clock [get_clocks clock_50_i] -max 10.0 [get_ports btn_*]

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

## Audio DAC outputs (PWM-style, on clk_sys 11 MHz, board RC filter)
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -max 22.0 [get_ports {audioext_l_o audioext_r_o}]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -min 0.0 [get_ports {audioext_l_o audioext_r_o}]


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

## External SRAM interface (on clk_cpu 30.56 MHz)
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -max 10.0 [get_ports ram_addr_o[*]]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -min 0.0 [get_ports ram_addr_o[*]]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -max 10.0 [get_ports {ram_cs_n_o ram_lb_n_o ram_ub_n_o ram_oe_n_o ram_we_n_o}]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -min 0.0 [get_ports {ram_cs_n_o ram_lb_n_o ram_ub_n_o ram_oe_n_o ram_we_n_o}]

## SRAM data is bidirectional
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -max 10.0 [get_ports ram_data_io[*]]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -min 0.0 [get_ports ram_data_io[*]]

set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -max 15.0 [get_ports ram_data_io[*]]
set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out3]] -min 0.0 [get_ports ram_data_io[*]]

## I2C bus for RTC (on clk_sys 11 MHz, slow protocol, relaxed timing)
set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -max 50.0 [get_ports {i2c_scl_io i2c_sda_io}]
set_input_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -min 0.0 [get_ports {i2c_scl_io i2c_sda_io}]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -max 50.0 [get_ports {i2c_scl_io i2c_sda_io}]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]] -min 0.0 [get_ports {i2c_scl_io i2c_sda_io}]

## Joystick select signal (on joy_clock ~168 Hz, very relaxed timing)
set_output_delay -clock [get_clocks joy_clock] -max 200.0 [get_ports {joysel_o}]
set_output_delay -clock [get_clocks joy_clock] -min 0.0 [get_ports {joysel_o}]

## Accelerometer I2C (on 50 MHz clock)
set_input_delay -clock [get_clocks clock_50_i] -max 20.0 [get_ports accel_io[*]]
set_input_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports accel_io[*]]
set_output_delay -clock [get_clocks clock_50_i] -max 20.0 [get_ports accel_io[*]]
set_output_delay -clock [get_clocks clock_50_i] -min 0.0 [get_ports accel_io[*]]

## VGA outputs (on clk65 64.71 MHz pixel clock)
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pl2/clk_out1]] -max 5.0 [get_ports {rgb_r_o[*] rgb_g_o[*] rgb_b_o[*] hsync_o vsync_o}]
set_output_delay -clock [get_clocks -of_objects [get_pins nextp8_inst/pl2/clk_out1]] -min 0.0 [get_ports {rgb_r_o[*] rgb_g_o[*] rgb_b_o[*] hsync_o vsync_o}]


## Clock Domain Crossing False Paths
## These are paths between different PLLs or async clock domains with proper CDC

## PLL2 internal crossing: clk_video (10.78 MHz) ↔ clk65 (64.71 MHz)
## Same PLL but intentionally async - handled with CDC in design
set_false_path -from [get_clocks clk_out3_pll_hdmi] -to [get_clocks clk_out1_pll_hdmi]
set_false_path -from [get_clocks clk_out1_pll_hdmi] -to [get_clocks clk_out3_pll_hdmi]

## Async input paths: buttons with synchronizers
set_false_path -from [get_ports btn_*] -to [get_pins -hierarchical *sync*/D]

## Reset button to clock domains (async, has debounce and sync)
set_false_path -from [get_ports btn_reset_n_i] -to [get_clocks clk_cpu]
set_false_path -from [get_ports btn_reset_n_i] -to [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]]

## PS/2 keyboard inputs (async, handled by keyboard controller)
set_false_path -from [get_ports {ps2_data_io ps2_pin2_io ps2_clk_io ps2_pin6_io}] -to [get_clocks -of_objects [get_pins nextp8_inst/pll/clk_out1]]

## ESP32 UART (async serial, has CDC in UART module)
set_false_path -from [get_ports esp_rx_i]
set_false_path -to [get_ports esp_tx_o]

## NextPi accelerator GPIO (async)
set_false_path -from [get_ports accel_io[*]]
set_false_path -to [get_ports accel_io[*]]

## Joystick clock domain (very slow, async)
set_false_path -from [get_clocks joy_clock]
set_false_path -to [get_clocks joy_clock]


## Video BRAM to output register paths
## BRAM outputs are async to video clock, captured in registers
set_false_path -from [get_cells -hierarchical -filter {NAME =~ *vram* && PRIMITIVE_TYPE =~ BMEM.*}] -to [get_cells nextp8_inst/p8video/VR_reg*]
set_false_path -from [get_cells -hierarchical -filter {NAME =~ *vram* && PRIMITIVE_TYPE =~ BMEM.*}] -to [get_cells nextp8_inst/p8video/VG_reg*]
set_false_path -from [get_cells -hierarchical -filter {NAME =~ *vram* && PRIMITIVE_TYPE =~ BMEM.*}] -to [get_cells nextp8_inst/p8video/VB_reg*]

## Palette to video output path (data stable across multiple clocks)
set_false_path -from [get_cells nextp8_inst/p8video/screen_palette*_sys_reg[*][*]] -to [get_cells nextp8_inst/p8video/V*_reg[*]]

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

## PS/2 keyboard parameter sync (quasi-static control)
set_false_path -from [get_cells nextp8_inst/params_reg[0]] -to [get_cells {nextp8_inst/keyboard/ps2_keyboard/ps2*_sync_reg[0]}]


## Inter-PLL clock domain crossings
## PLL1 (pll): 50MHz input → 11MHz (clk_out1), 32.35MHz (clk_out2), 30.56MHz (clk_out3)
## PLL2 (pl2/pll_hdmi): 32.35MHz input → 64.71MHz (clk_out1), 323.53MHz (clk_out2), 10.78MHz (clk_out3)
## These PLLs have no phase relationship despite PLL2 using PLL1's output as input
## All crossings use proper CDC synchronizers in RTL

## mclk (30.56 MHz) ↔ clk_video (10.78 MHz): different PLLs
set_false_path -from [get_clocks clk_out3_pll] -to [get_clocks clk_out3_pll_hdmi]
set_false_path -from [get_clocks clk_out3_pll_hdmi] -to [get_clocks clk_out3_pll]

## mclk (30.56 MHz) ↔ clk65 (64.71 MHz): different PLLs
set_false_path -from [get_clocks clk_out3_pll] -to [get_clocks clk_out1_pll_hdmi]
set_false_path -from [get_clocks clk_out1_pll_hdmi] -to [get_clocks clk_out3_pll]

## clk325 (32.35 MHz) ↔ clk65 (64.71 MHz): different PLLs
set_false_path -from [get_clocks clk_out2_pll] -to [get_clocks clk_out1_pll_hdmi]
set_false_path -from [get_clocks clk_out1_pll_hdmi] -to [get_clocks clk_out2_pll]

## clk325 (32.35 MHz) ↔ clk_tmds (323.53 MHz): different PLLs
set_false_path -from [get_clocks clk_out2_pll] -to [get_clocks clk_out2_pll_hdmi]
set_false_path -from [get_clocks clk_out2_pll_hdmi] -to [get_clocks clk_out2_pll]

## clk325 (32.35 MHz) ↔ clk_video (10.78 MHz): different PLLs
set_false_path -from [get_clocks clk_out2_pll] -to [get_clocks clk_out3_pll_hdmi]
set_false_path -from [get_clocks clk_out3_pll_hdmi] -to [get_clocks clk_out2_pll]

## clk_sys (11 MHz) ↔ clk_tmds (323.53 MHz): different PLLs, audio outputs
set_false_path -from [get_clocks clk_out1_pll] -to [get_clocks clk_out2_pll_hdmi]
set_false_path -from [get_clocks clk_out2_pll_hdmi] -to [get_clocks clk_out1_pll]

## clk_sys (11 MHz) ↔ clk_video (10.78 MHz): different PLLs
set_false_path -from [get_clocks clk_out1_pll] -to [get_clocks clk_out3_pll_hdmi]
set_false_path -from [get_clocks clk_out3_pll_hdmi] -to [get_clocks clk_out1_pll]

## VRAM address to BRAM (async path, address stable before read)
set_false_path -from [get_cells nextp8_inst/p8video/vaddress_reg*] -to [get_cells nextp8_inst/vram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop*ram.r/prim_noinit.ram/DEVICE_7SERIES.NO_BMM_INFO.TRUE_DP.SIMPLE_PRIM36.ram*]

