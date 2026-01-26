////////////////////////////////////////////////////////////////////////////////// 
// Copyright (C) 2026 Chris January
// I2C RTC Test - Testbench for DS1307 RTC date reading
//////////////////////////////////////////////////////////////////////////////////

module i2c_rtc_tb ();

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

// Drive button inputs (active low, so 1 = not pressed)
assign btn_divmmc_n_i = 1'b1;
assign btn_multiface_n_i = 1'b1;
assign btn_reset_n_i = 1'b1;  // Not in reset

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

wire [15:0] sram_data_out;

// Simple SRAM model wiring: derive enables from active-low control lines
assign ram_data_io = (~ram_cs_n_o && ~ram_oe_n_o && ram_we_n_o) ? sram_data_out : 16'hzzzz;

sram_simple #(
    .MEM_FILE("rtc_test_rom.mem")
) sram_inst (
    .read_en_i(~ram_cs_n_o & ~ram_oe_n_o & ram_we_n_o),
    .write_en_i(~ram_cs_n_o & ~ram_we_n_o),
    .addr_i(ram_addr_o),
    .lb_i(~ram_lb_n_o),
    .ub_i(~ram_ub_n_o),
    .data_in_i(ram_data_io),
    .data_out_o(sram_data_out)
);

// DS1307 RTC device model
wire ds1307_scl_out;
wire ds1307_sda_out;

ds1307_device ds1307_inst (
    .i2c_scl_in(i2c_scl_io),
    .i2c_sda_in(i2c_sda_io),
    .i2c_scl_out(ds1307_scl_out),
    .i2c_sda_out(ds1307_sda_out)
);

// Pull-up resistors for I2C (required for open-drain)
// NOTE: pullup() doesn't work in Vivado xsim, use weak drive strength instead
assign (weak1, weak0) i2c_scl_io = 1'b1;
assign (weak1, weak0) i2c_sda_io = 1'b1;

// Open-drain driver for DS1307: drive low when out=0, release when out=1
assign i2c_scl_io = (ds1307_scl_out == 1'b0) ? 1'b0 : 1'bz;
assign i2c_sda_io = (ds1307_sda_out == 1'b0) ? 1'b0 : 1'bz;

// I2C Protocol Sniffer
// Monitor traffic between nextp8 I2C master and DS1307 slave
i2c_sniffer #(
    .MASTER_IS_TRISTATE(1'b1),  // nextp8 uses tristate I2C
    .SLAVE_IS_TRISTATE(1'b0),   // DS1307 uses tristate I2C
    .VERBOSE(1'b0),             // Set to 1 for detailed bit-level output
    .I2C_MODE(0)                // 0=Standard 100kHz (DS1307 speed)
) i2c_sniffer_inst (
    // Master (nextp8) signals - both in and out are the shared bus
    .master_i2c_scl_in_i(i2c_scl_io),
    .master_i2c_sda_in_i(i2c_sda_io),
    .master_i2c_scl_out_i(),
    .master_i2c_sda_out_i(),
    
    // Slave (DS1307) signals - in monitors bus, out shows drive state
    .slave_i2c_scl_in_i(i2c_scl_io),
    .slave_i2c_sda_in_i(i2c_sda_io),
    .slave_i2c_scl_out_i(ds1307_scl_out),
    .slave_i2c_sda_out_i(ds1307_sda_out)
);

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

    // XADC Analog to Digital Conversion
    .XADC_VP(XADC_VP),
    .XADC_VN(XADC_VN),
    .XADC_15P(XADC_15P),
    .XADC_15N(XADC_15N),
    .XADC_7P(XADC_7P),
    .XADC_7N(XADC_7N),

    // Postcode output
    .postcode_o(postcode_o)
);

wire [5:0] post_code;
assign post_code = postcode_o;

parameter POST_TARGET1 = 8;  // Success post code 1
parameter POST_TARGET2 = 15;  // Success post code 2

// Expected date value: 0x24122025 for 2025-12-24 (Christmas Eve 2025)
parameter EXPECTED_DATE = 32'h24122025;

// Debug register monitor
reg [31:0] debug_reg;
reg debug_reg_written = 0;

// Monitor writes to debug register at 0x800062
// Need to watch the internal signals or memory writes
// For now, we'll monitor the completion via POST code

initial begin
    $display("=== I2C RTC Test Starting ===");
    $display("Expected date: 0x%08x (2025-12-25)", EXPECTED_DATE);
    $monitor("[$monitor] time=%0t POST=%0d (target=%0d)", $time, post_code, POST_TARGET2);
end 

// Timeout - fail if we don't complete in reasonable time
initial begin
    #50000000;  // 50ms timeout
    $display("=== TIMEOUT: Test did not complete ===");
    $finish(1);
end

// Monitor POST code
always @(posedge clock_50_i) begin
    if (post_code == POST_TARGET1) begin
        // Success POST code reached
        // Now we need to read the debug register value
        // The debug register is at 0x800062 in the memory map
        // We'll give it a few cycles to ensure the write completes
        #1000;
        
        // Read the debug register from nextp8 internal state
        // In a real testbench, we'd probe the internal registers
        // For now, check the POST code reached
        if (nextp8.debug_reg !== EXPECTED_DATE) begin
            $error("RTC date mismatch: got 0x%08x expected 0x%08x", nextp8.debug_reg, EXPECTED_DATE);
            i2c_sniffer_inst.print_statistics();
            $finish(1);
        end
        $display("Debug register (0x800062) matched expected value 0x%08x", EXPECTED_DATE);
    end else if (post_code == POST_TARGET2) begin
        #1000;
        
        if (nextp8.debug_reg !== EXPECTED_DATE) begin
            $error("RTC date mismatch: got 0x%08x expected 0x%08x", nextp8.debug_reg, EXPECTED_DATE);
            i2c_sniffer_inst.print_statistics();
            $finish(1);
        end
        $display("=== SUCCESS: POST code %0d reached ===", POST_TARGET2);
        $display("=== RTC date reading test completed successfully ===");
        $display("Debug register (0x800062) matched expected value 0x%08x", EXPECTED_DATE);
        
        $finish(0);
    end else if (post_code == 16) begin
        // Error POST code
        $display("=== FAILURE: Error POST code reached ===");
        i2c_sniffer_inst.print_statistics();
        $finish(1);
    end
end

endmodule
