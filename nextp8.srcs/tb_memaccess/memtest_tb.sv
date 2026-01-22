////////////////////////////////////////////////////////////////////////////////// 
// Copyright (C) 2025 Chris January  
// Memory access testbench for nextp8
//////////////////////////////////////////////////////////////////////////////////

module memtest_tb ();

//Clock - 50 MHz (20 ns period)
reg clock_50_i = 0;
always #10 clock_50_i = ~clock_50_i;

//SRAM
wire [20:0] ram_addr_o;
wire [15:0] ram_data_io;
wire ram_lb_n_o;
wire ram_ub_n_o;
wire ram_oe_n_o;
wire ram_we_n_o;
wire ram_cs_n_o;

// PS2
wire ps2_clk_io;
wire ps2_data_io;
wire ps2_pin6_io;
wire ps2_pin2_io;

// SD Card
wire sd_cs0_n_o;
wire sd_cs1_n_o;
wire sd_sclk_o;
wire sd_mosi_o;
wire sd_miso_i;

// Flash
wire flash_cs_n_o;
wire flash_sclk_o;
wire flash_mosi_o;
wire flash_miso_i;
wire flash_wp_o;
wire flash_hold_o;

// Joystick
wire joyp1_i;
wire joyp2_i;
wire joyp3_i;
wire joyp4_i;
wire joyp6_i;
wire joyp7_o;
wire joyp9_i;
wire joysel_o;

// Audio
wire audioext_l_o;
wire audioext_r_o;
wire audioint_o;

// K7
wire ear_port_i;
wire mic_port_o;

// Buttons
wire btn_divmmc_n_i;
wire btn_multiface_n_i;
wire btn_reset_n_i;

// Matrix keyboard
wire [7:0] keyb_row_o;
wire [6:0] keyb_col_i;

// Bus
wire bus_rst_n_io;
wire bus_clk35_o;
wire [15:0] bus_addr_o;
wire [7:0] bus_data_io;
wire bus_int_n_io;
wire bus_nmi_n_i;
wire bus_ramcs_i;
wire bus_romcs_i;
wire bus_wait_n_i;
wire bus_halt_n_o;
wire bus_iorq_n_o;
wire bus_m1_n_o;
wire bus_mreq_n_o;
wire bus_rd_n_io;
wire bus_wr_n_o;
wire bus_rfsh_n_o;
wire bus_busreq_n_i;
wire bus_busack_n_o;
wire bus_iorqula_n_i;
wire bus_y_o;
wire bus_p3_mtr_n_o;
wire bus_p3_drd_n_o;
wire bus_p3_dwr_n_o;

// VGA
wire [3:0] rgb_r_o;
wire [3:0] rgb_g_o;
wire [3:0] rgb_b_o;
wire hsync_o;
wire vsync_o;
wire vgaclk_o;
wire vgaclkn_o;

// HDMI
wire [3:0] hdmi_p_o;
wire [3:0] hdmi_n_o;

// I2C (RTC and HDMI)
wire i2c_scl_io;
wire i2c_sda_io;

// ESP
wire esp_rx_i = 1'b1;
wire esp_tx_o;

// Pi UART
wire pi_uart_rx_i = 1'b1;
wire pi_uart_tx_o;

// XADC Analog to Digital Conversion
wire XADC_VP;
wire XADC_VN;
wire XADC_15P;
wire XADC_15N;
wire XADC_7P;
wire XADC_7N;

// Postcode output
wire [5:0] postcode_o;

// SRAM controller signals
wire read_en_i;
wire write_en_i;
wire [20:0] addr_i;
wire lb_i;
wire ub_i;
wire [15:0] data_in_i;
wire [15:0] data_out_o;

sram_simple #(
    .MEM_FILE("memtest_rom.mem")
) sram (
    .read_en_i(read_en_i),
    .write_en_i(write_en_i),
    .addr_i(addr_i),
    .lb_i(lb_i),
    .ub_i(ub_i),
    .data_in_i(data_in_i),
    .data_out_o(data_out_o)
);

assign addr_i = ram_addr_o;
assign data_in_i = ~ram_we_n_o ? ram_data_io : 16'h0;
assign ram_data_io = ram_we_n_o ? data_out_o : 'bz;
assign lb_i = ~ram_lb_n_o;
assign ub_i = ~ram_ub_n_o;
assign read_en_i = ~ram_oe_n_o && ~ram_cs_n_o;
assign write_en_i = ~ram_we_n_o && ~ram_cs_n_o;

nextp8 nextp8(
    // Clock
    .clock_50_i(clock_50_i),
    
    //SRAM
    .ram_addr_o(ram_addr_o),
    .ram_data_io(ram_data_io),
    .ram_lb_n_o(ram_lb_n_o),
    .ram_ub_n_o(ram_ub_n_o),
    .ram_oe_n_o(ram_oe_n_o),
    .ram_we_n_o(ram_we_n_o),
    .ram_cs_n_o(ram_cs_n_o),

    // PS2
    .ps2_clk_io(ps2_clk_io),
    .ps2_data_io(ps2_data_io),
    .ps2_pin6_io(ps2_pin6_io),
    .ps2_pin2_io(ps2_pin2_io),

    // SD Card
    .sd_cs0_n_o(sd_cs0_n_o),
    .sd_cs1_n_o(sd_cs1_n_o),
    .sd_sclk_o(sd_sclk_o),
    .sd_mosi_o(sd_mosi_o),
    .sd_miso_i(sd_miso_i),

    // Joystick
    .joyp1_i(joyp1_i),
    .joyp2_i(joyp2_i),
    .joyp3_i(joyp3_i),
    .joyp4_i(joyp4_i),
    .joyp6_i(joyp6_i),
    .joyp7_o(joyp7_o),
    .joyp9_i(joyp9_i),
    .joysel_o(joysel_o),

    // Audio
    .audioext_l_o(audioext_l_o),
    .audioext_r_o(audioext_r_o),

    // K7
    .ear_port_i(ear_port_i),

    // Buttons
    .btn_divmmc_n_i(btn_divmmc_n_i),
    .btn_multiface_n_i(btn_multiface_n_i),
    .btn_reset_n_i(btn_reset_n_i),

    // Matrix keyboard
    .keyb_row_o(keyb_row_o),
    .keyb_col_i(keyb_col_i),

    // I2C (RTC and HDMI)
    .i2c_scl_io(i2c_scl_io),
    .i2c_sda_io(i2c_sda_io),

    // VGA
    .rgb_r_o(rgb_r_o),
    .rgb_g_o(rgb_g_o),
    .rgb_b_o(rgb_b_o),
    .hsync_o(hsync_o),
    .vsync_o(vsync_o),
    .vgaclk_o(vgaclk_o),
    .vgaclkn_o(vgaclkn_o),

    // HDMI
    .hdmi_p_o(hdmi_p_o),
    .hdmi_n_o(hdmi_n_o),

    // ESP
    .esp_rx_i(esp_rx_i),
    .esp_tx_o(esp_tx_o),

    // Pi UART
    .pi_uart_rx_i(pi_uart_rx_i),
    .pi_uart_tx_o(pi_uart_tx_o),

    // XADC
    .XADC_VP(XADC_VP),
    .XADC_VN(XADC_VN),
    .XADC_15P(XADC_15P),
    .XADC_15N(XADC_15N),
    .XADC_7P(XADC_7P),
    .XADC_7N(XADC_7N),

    // Postcode
    .postcode_o(postcode_o)
);

// POST code monitoring
reg [5:0] last_postcode = 6'd0;
reg [5:0] prev_postcode = 6'd0;
integer test_start_time = 0;
reg monitoring_post11 = 0;

// Debug monitoring for VRAM  
always @(posedge clock_50_i) begin
    prev_postcode <= nextp8.post_code_cpu;
    
    // Detect POST code change to 11
    if (nextp8.post_code_cpu == 6'd11 && prev_postcode != 6'd11) begin
        $display("[$time=%t] === STARTING PALETTE TEST MONITORING (POST=%d) ===", $time, nextp8.post_code_cpu);
        monitoring_post11 <= 1;
    end
    
    if (monitoring_post11) begin
        if (nextp8.cpu_busstate == 2'b11) begin // Write cycle
            $display("[$time=%t] WR: addr=0x%06x data=0x%04x pal_mem=%b", 
                     $time, nextp8.cpu_addr, nextp8.cpu_dout, nextp8.pal_mem);
        end
        if (nextp8.pal_mem) begin // Any palette access
            $display("[$time=%t] PAL: addr=0x%06x busstate=%b wr=%b rd=%b dout=0x%04x din=0x%04x pal_dout=0x%04x rdata=0x%04x estate=%b cpu_enable=%b", 
                     $time, nextp8.cpu_addr, nextp8.cpu_busstate, nextp8.cpu_wr, nextp8.cpu_rd,
                     nextp8.cpu_dout, nextp8.cpu_din, nextp8.pal_dout, nextp8.rdata, nextp8.estate, nextp8.cpu_enable);
        end
    end
    
    // Stop monitoring on failure
    if (nextp8.post_code_cpu == 6'd31) begin
        $display("[$time=%t] === STOPPING PALETTE TEST MONITORING (FAILURE) ===", $time);
        monitoring_post11 <= 0;
    end
    if (nextp8.back_mem && nextp8.cpu_rd) begin
        $display("[$time=%t] VRAM_BACK READ: addr=0x%06x estate=%b busstate=%b vfront=%b vaddr1_main=%b (0x%04x) vdout1_main=0x%04x cpu_din=0x%04x cpu_enable=%b", 
                 $time, nextp8.cpu_addr, nextp8.estate, nextp8.cpu_busstate, nextp8.vfront, nextp8.vaddr1_main, nextp8.vaddr1_main, nextp8.vdout1_main, nextp8.cpu_din, nextp8.cpu_enable);
    end
    if (nextp8.back_mem && (nextp8.cpu_busstate != 0)) begin
        $display("[$time=%t] VRAM_BACK WRITE: addr=0x%06x estate=%b busstate=%b cpu_wr=%b vfront=%b vaddr1_main=%b (0x%04x) vdin1_main=0x%04x vw1_main=0x%x cpu_dout=0x%04x cpu_ds=0x%x", 
                 $time, nextp8.cpu_addr, nextp8.estate, nextp8.cpu_busstate, nextp8.cpu_wr, nextp8.vfront, nextp8.vaddr1_main, nextp8.vaddr1_main, nextp8.vdin1_main, nextp8.vw1_main, nextp8.cpu_dout, nextp8.cpu_ds);
    end
    if (nextp8.front_mem && (nextp8.cpu_busstate != 0)) begin
        $display("[$time=%t] VRAM_FRONT WRITE: addr=0x%06x estate=%b busstate=%b cpu_wr=%b vfront=%b vaddr1_main=%b (0x%04x) vdin1_main=0x%04x vw1_main=0x%x cpu_dout=0x%04x", 
                 $time, nextp8.cpu_addr, nextp8.estate, nextp8.cpu_busstate, nextp8.cpu_wr, nextp8.vfront, nextp8.vaddr1_main, nextp8.vaddr1_main, nextp8.vdin1_main, nextp8.vw1_main, nextp8.cpu_dout);
    end
    // Debug palette RAM
    if (nextp8.pal_mem && nextp8.cpu_wr) begin
        $display("[$time=%t] PAL_RAM WRITE: addr=0x%06x estate=%b busstate=%b cpu_wr=%b cpu_dout=0x%04x pal_write_en=%b", 
                 $time, nextp8.cpu_addr, nextp8.estate, nextp8.cpu_busstate, nextp8.cpu_wr, nextp8.cpu_dout, nextp8.pal_write_en);
    end
    if (nextp8.pal_mem) begin
        $display("[$time=%t] PAL_RAM ACCESS: addr=0x%06x estate=%b busstate=%b cpu_rd=%b cpu_wr=%b pal_read_en=%b pal_dout=0x%04x rdata=0x%04x cpu_din=0x%04x cpu_enable=%b", 
                 $time, nextp8.cpu_addr, nextp8.estate, nextp8.cpu_busstate, nextp8.cpu_rd, nextp8.cpu_wr, nextp8.pal_read_en, nextp8.pal_dout, nextp8.rdata, nextp8.cpu_din, nextp8.cpu_enable);
    end
end

initial begin
    $display("=== Memory Access Testbench ===");
    $display("Testing all memory types with write-wait-read pattern");
end

always @(postcode_o) begin
    if (postcode_o != last_postcode) begin
        last_postcode = postcode_o;
        
        case (postcode_o)
            6'd1: $display("[$time=%t] POST=1: Waiting for PLL lock", $time);
            6'd2: $display("[$time=%t] POST=2: In reset", $time);
            6'd3: $display("[$time=%t] POST=3: Releasing CPU", $time);
            6'd4: begin
                $display("[$time=%t] POST=4: Starting memory tests", $time);
                test_start_time = $time;
            end
            6'd5: $display("[$time=%t] POST=5: Testing SRAM", $time);
            6'd6: $display("[$time=%t] POST=6: Testing MMIO debug register", $time);
            6'd7: $display("[$time=%t] POST=7: Testing VRAM back buffer", $time);
            6'd8: $display("[$time=%t] POST=8: Testing VRAM front buffer", $time);
            6'd9: $display("[$time=%t] POST=9: Testing VRAM overlay back", $time);
            6'd10: $display("[$time=%t] POST=10: Testing VRAM overlay front", $time);
            6'd11: $display("[$time=%t] POST=11: Testing palette RAM", $time);
            6'd12: $display("[$time=%t] POST=12: Testing digital audio RAM", $time);
            6'd13: begin
                $display("[$time=%t] POST=13: ALL TESTS PASSED!", $time);
                $display("=== SUCCESS: All memory types validated ===");
                $display("Total test time: %0d ns", $time - test_start_time);
                #1000;
                $finish;
            end
            // Failure codes (test POST + 20)
            6'd25: begin
                $display("[$time=%t] POST=25: FAILURE - SRAM test failed", $time);
                $display("=== FAILURE: SRAM read/write verification failed ===");
                #1000;
                $finish;
            end
            6'd26: begin
                $display("[$time=%t] POST=26: FAILURE - MMIO debug register test failed", $time);
                $display("=== FAILURE: MMIO read/write verification failed ===");
                #1000;
                $finish;
            end
            6'd27: begin
                $display("[$time=%t] POST=27: FAILURE - VRAM back buffer test failed", $time);
                $display("=== FAILURE: VRAM back buffer read/write verification failed ===");
                #1000;
                $finish;
            end
            6'd28: begin
                $display("[$time=%t] POST=28: FAILURE - VRAM front buffer test failed", $time);
                $display("=== FAILURE: VRAM front buffer read/write verification failed ===");
                #1000;
                $finish;
            end
            6'd29: begin
                $display("[$time=%t] POST=29: FAILURE - VRAM overlay back test failed", $time);
                $display("=== FAILURE: VRAM overlay back read/write verification failed ===");
                #1000;
                $finish;
            end
            6'd30: begin
                $display("[$time=%t] POST=30: FAILURE - VRAM overlay front test failed", $time);
                $display("=== FAILURE: VRAM overlay front read/write verification failed ===");
                #1000;
                $finish;
            end
            6'd31: begin
                $display("[$time=%t] POST=31: FAILURE - Palette RAM test failed", $time);
                $display("=== FAILURE: Palette RAM read/write verification failed ===");
                #1000;
                $finish;
            end
            6'd32: begin
                $display("[$time=%t] POST=32: FAILURE - Digital audio RAM test failed", $time);
                $display("=== FAILURE: Digital audio RAM read/write verification failed ===");
                #1000;
                $finish;
            end
            default: $display("[$time=%t] POST=%0d: Unknown state", $time, postcode_o);
        endcase
    end
end

// Timeout
initial begin
    #50000000; // 50ms timeout
    $display("ERROR: Test timeout at POST=%0d", postcode_o);
    $display("=== FAILURE: Test did not complete ===");
    $finish;
end

endmodule
