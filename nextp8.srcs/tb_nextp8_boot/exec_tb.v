////////////////////////////////////////////////////////////////////////////////// 
// Copyright (C) 2025 Chris January  
//////////////////////////////////////////////////////////////////////////////////

module exec_tb ();

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
//wwire csync_o,

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

wire read_en1_i;
wire write_en1_i;
wire [19:0] addr1_i;
wire lb1_i;
wire ub1_i;
wire [15:0] data_in1_i;
wire [15:0] data_out1_o;

wire read_en2_i;
wire write_en2_i;
wire [19:0] addr2_i;
wire lb2_i;
wire ub2_i;
wire [15:0] data_in2_i;
wire [15:0] data_out2_o;

// SRAM model instance (IS61WV204816BLL-10BLI)
sram #(
    .MEM_FILE("hello_test_rom.mem")
) sram_inst (
    .addr(ram_addr_o),
    .dq(ram_data_io),
    .cs_n(ram_cs_n_o),
    .we_n(ram_we_n_o),
    .oe_n(ram_oe_n_o),
    .lb_n(ram_lb_n_o),
    .ub_n(ram_ub_n_o)
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

parameter POST_TARGET = 10;

// UART receiver using UART module instance
parameter EXPECTED_MSG = "Hello, world!\n";

reg [7:0] uart_rx_buffer[0:31];
integer uart_rx_count = 0;

// UART RX signals
wire uart_rx_r;            // Read strobe
wire uart_rx_ready;        // Data ready
wire uart_rx_data_ready;   // Data available
wire uart_rx_ra;           // Read acknowledge
wire [7:0] uart_rx_data;   // Received data

// UART control/status registers  
reg uart_rx_r_reg = 0;

// Instantiate UART module for reception
UART uart_rx_inst (
    .clk(nextp8.clk_sys),     // Use same 11MHz clock as system UART
    .reset(1'b0),
    .speed(15'd95),        // 115200 baud at 11MHz
    .rx(pi_uart_tx_o),     // Connect to DUT's TX output
    .tx(),                 // Not used
    .data_in(8'h00),       // Not used
    .data_out(uart_rx_data),
    .w(1'b0),              // Not transmitting
    .r(uart_rx_r_reg),     // Read strobe
    .ready(uart_rx_ready),
    .data_ready(uart_rx_data_ready),
    .wa(),                 // Not used
    .ra(uart_rx_ra)
);

// UART RX state machine - read bytes as they arrive
reg uart_data_read = 0;
always @(posedge nextp8.clk_sys) begin
    uart_rx_r_reg <= 0;
    
    if (uart_rx_data_ready && !uart_rx_ra) begin
        // Set read strobe
        uart_rx_r_reg <= 1;
        uart_data_read <= 0;
    end
    
    if (uart_rx_ra && !uart_data_read) begin
        // Read acknowledge - data has been captured
        uart_rx_buffer[uart_rx_count] <= uart_rx_data;
        if (uart_rx_data >= 32 && uart_rx_data < 127)
            $display("[$time=%0t] UART: Received byte 0x%02h ('%c')", $time, uart_rx_data, uart_rx_data);
        else
            $display("[$time=%0t] UART: Received byte 0x%02h", $time, uart_rx_data);
        uart_rx_count <= uart_rx_count + 1;
        uart_data_read <= 1;
    end
end

initial begin
    $monitor ("[$monitor] time=%0t POST=%0d (target=%0d)", $time, post_code, POST_TARGET);
end 

// Monitor POST code and UART output
always @(posedge clock_50_i) begin
    if (uart_rx_count == 14 && post_code == POST_TARGET) begin // "Hello, world!\n" = 14 characters
        if (uart_rx_buffer[0] == "H" && 
            uart_rx_buffer[1] == "e" &&
            uart_rx_buffer[2] == "l" &&
            uart_rx_buffer[3] == "l" &&
            uart_rx_buffer[4] == "o" &&
            uart_rx_buffer[5] == "," &&
            uart_rx_buffer[6] == " " &&
            uart_rx_buffer[7] == "w" &&
            uart_rx_buffer[8] == "o" &&
            uart_rx_buffer[9] == "r" &&
            uart_rx_buffer[10] == "l" &&
            uart_rx_buffer[11] == "d" &&
            uart_rx_buffer[12] == "!" &&
            uart_rx_buffer[13] == 8'd10) begin // \n = 10
            $display("=== SUCCESS: UART message matches! ===");
            $display("=== Boot sequence with UART test completed successfully ===");
            $finish(0);
        end else begin
            $display("=== FAILURE: UART message content mismatch ===");
            $finish(1);
        end
    end
end

endmodule
