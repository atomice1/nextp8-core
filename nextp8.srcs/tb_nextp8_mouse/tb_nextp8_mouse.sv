//////////////////////////////////////////////////////////////////////////////////
// tb_nextp8_mouse.sv
// Mouse integration and latching mouse testbench
// Copyright (C) 2026 Chris January
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ns

module tb_nextp8_mouse ();

//Clock - 50 MHz (20 ns period, toggle every 10ns)
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

// PS2 - bidirectional ports with open-drain behavior
// tri1 = tri-state with implicit pull-up
tri1 ps2_clk_io;
tri1 ps2_data_io;
tri1 ps2_pin6_io;
tri1 ps2_pin2_io;

reg init_complete = 0;

// SD Card
wire sd_cs0_n_o;
wire sd_cs1_n_o;
wire sd_sclk_o;
wire sd_mosi_o;
wire sd_miso_i = 1'b1;

// Flash
wire flash_cs_n_o;
wire flash_sclk_o;
wire flash_mosi_o;
wire flash_miso_i;
wire flash_wp_o;
wire flash_hold_o;

// Joystick
wire joyp1_i = 1'b1;
wire joyp2_i = 1'b1;
wire joyp3_i = 1'b1;
wire joyp4_i = 1'b1;
wire joyp6_i = 1'b1;
wire joyp7_o;
wire joyp9_i = 1'b1;
wire joysel_o;

// Audio
wire audioext_l_o;
wire audioext_r_o;
wire audioint_o;

// K7
wire ear_port_i;
wire mic_port_o;

// Buttons
wire btn_divmmc_n_i = 1'b1;
wire btn_multiface_n_i = 1'b1;
wire btn_reset_n_i = 1'b1;

// Matrix keyboard (not used for mouse test)
wire [7:0] keyb_row_o;
reg [6:0] keyb_col_i = 7'h7F;  // All keys released

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

wire sram_clk_i;
assign sram_clk_i = clock_50_i;

wire read_en_i;
wire write_en_i;
wire [20:0] addr_i;
wire lb_i;
wire ub_i;
wire [15:0] data_in_i;
wire [15:0] data_out_o;

sram_simple #(
    .MEM_FILE("mouse_test_rom.mem")
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

nextp8 #(
    .SIM(1)  // Enable simulation mode for fast delays
) nextp8(
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

    // Matrix keyboard (not used for mouse test)
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

// Monitor postcode changes
initial begin
    forever begin
        @(posedge postcode_o or negedge postcode_o)
        $display("Time %t: POST CODE = %d", $time, postcode_o);
    end
end

// PS/2 mouse stimulus using mouse_device model
wire mouse_clk_out;
wire mouse_data_out;

// Connect device outputs to bus (open-drain) - MOUSE uses pin6 (CLK) and pin2 (DATA)
assign ps2_pin6_io = (mouse_clk_out === 1'b0) ? 1'b0 : 1'bz;
assign ps2_pin2_io = (mouse_data_out === 1'b0) ? 1'b0 : 1'bz;

// Hold device model in reset briefly to start from a known state
reg mouse_reset = 1'b1;
initial begin
    #1000;
    mouse_reset = 1'b0;
end

mouse_device #(
    .CLOCK_DIV(5000)    // 50MHz / 10kHz = 5000
) mouse_model (
    .clk(clock_50_i),
    .reset(mouse_reset),
    .ps2_clk_in(ps2_pin6_io),
    .ps2_data_in(ps2_pin2_io),
    .ps2_clk_out(mouse_clk_out),
    .ps2_data_out(mouse_data_out),
    .intellimouse_capable(1'b1)  // Enable Intellimouse support
);

// Instantiate PS/2 protocol sniffer (both host and device tristate)
ps2_sniffer #(
    .HOST_IS_TRISTATE(1),      // nextp8 uses tristate ps2_clk_io/ps2_data_io
    .DEVICE_IS_TRISTATE(0)    // mouse_device uses separate in/out
) sniffer (
    // Host side (tristate) - Mouse on pin6/pin2
    .host_ps2_clk_in_i(ps2_pin6_io),
    .host_ps2_data_in_i(ps2_pin2_io),

    // Device side (non-tristate)
    .device_ps2_clk_in_i(ps2_pin6_io),
    .device_ps2_data_in_i(ps2_pin2_io),
    .device_ps2_clk_out_i(mouse_clk_out),
    .device_ps2_data_out_i(mouse_data_out)
);

// Task to send a PS/2 mouse movement packet
task send_mouse_movement;
    input logic left_btn;
    input logic right_btn;
    input logic middle_btn;
    input signed [8:0] x_movement;
    input signed [8:0] y_movement;
    input signed [3:0] z_movement;  // Scroll wheel (default 0)
    begin
        if (!init_complete) begin
            $display("ERROR: Attempted to send mouse packet before init complete!");
            $finish(1);
        end
        mouse_model.send_movement_packet(left_btn, right_btn, middle_btn, x_movement, y_movement, z_movement);
        // Wait for transmission to complete
        // 4-byte packet: 4 bytes × 11 bits × ~10μs/bit at 10kHz PS/2 clock = ~440μs
        // Add margin for queuing and processing
        #500000; // 500μs
    end
endtask

// Task to wait for and verify initialization sequence
// Waits for mouse module's init_state to reach INIT_DONE before allowing mouse packets
task verify_mouse_init;
    begin
        $display("======================================");
        $display("=== Waiting for Init Sequence ===");
        $display("======================================");

        // Wait for mouse module initialization to complete
        // The mouse module ignores RX data until init_state == INIT_DONE
        wait(nextp8.mouse_inst.init_state == 5'd24);  // 5'd24 = INIT_DONE
        $display("Time %t: ✓ Mouse initialization complete (init_state=%0d)", $time, nextp8.mouse_inst.init_state);

        init_complete = 1;
        $display("======================================");
        $display("=== Init Sequence Verified! ===");
        $display("======================================");

        #10000; // Delay before allowing mouse packets
    end
endtask

// Test stimulus for mouse functionality
initial begin
    $display("======================================");
    $display("=== MOUSE TESTBENCH STARTING ===");
    $display("======================================");

    // Wait for system to boot and mouse init to complete
    #15000000; // 15ms - enough for 10ms init delay + transmission

    // First, verify the initialization sequence
    verify_mouse_init();

    // Wait for POST code indicating mouse test ready
    $display("Time %t: Waiting for POST code 7 (waiting for TEST_1)", $time);
    wait(postcode_o == 6'd7);
    $display("Time %t: ROM waiting for mouse movement TEST_1", $time);
    #10000; // 10us delay

    // Send first mouse movement (X=+10, Y=+5, no buttons)
    $display("Time %t: Sending mouse movement: X=+10, Y=+5", $time);
    send_mouse_movement(1'b0, 1'b0, 1'b0, 9'sd10, 9'sd5, 4'sd0);

    // Wait for POST code 10 (movement detected)
    wait(postcode_o == 6'd10);
    $display("Time %t: ROM detected movement", $time);
    #10000;

    // Wait for POST code 12 (waiting for TEST_2)
    wait(postcode_o == 6'd12);
    $display("Time %t: ROM waiting for mouse button TEST_2", $time);
    #10000;

    // Send mouse packet with left button pressed (X=+5, Y=-3, left button)
    $display("Time %t: Sending mouse movement with left button: X=+5, Y=-3", $time);
    send_mouse_movement(1'b1, 1'b0, 1'b0, 9'sd5, -9'sd3, 4'sd0);

    // Wait for POST code 13 (button detected)
    wait(postcode_o == 6'd13);
    $display("Time %t: ROM detected left button press", $time);
    #100000; // Wait 100μs for button state to stabilize

    // Send mouse packet with no buttons (release button for ROM to detect release)
    $display("Time %t: Releasing mouse button and moving: X=-2, Y=+2", $time);
    send_mouse_movement(1'b0, 1'b0, 1'b0, -9'sd2, 9'sd2, 4'sd0);

    // Wait for POST code 14 (button released)
    wait(postcode_o == 6'd14);
    $display("Time %t: ROM detected left button release", $time);
    #10000;

    // Wait for POST code 20 (waiting for TEST_3 - right button)
    wait(postcode_o == 6'd20);
    $display("Time %t: ROM waiting for right button TEST_3", $time);
    #100000; // Wait 100μs before sending

    // Send mouse packet with right button pressed
    $display("Time %t: Sending mouse movement with right button: X=+1, Y=+1", $time);
    send_mouse_movement(1'b0, 1'b1, 1'b0, 9'sd1, 9'sd1, 4'sd0);

    // Wait for POST code 21 (button detected)
    wait(postcode_o == 6'd21);
    $display("Time %t: ROM detected right button press", $time);
    #100000; // Wait 100μs for button state to stabilize
    // Send mouse packet with right button pressed
    $display("Time %t: Sending mouse movement with right button: X=+1, Y=+1", $time);
    send_mouse_movement(1'b0, 1'b1, 1'b0, 9'sd1, 9'sd1, 4'sd0);
    #10000;

    // Send mouse packet with no buttons (release right button)
    $display("Time %t: Releasing right button", $time);
    send_mouse_movement(1'b0, 1'b0, 1'b0, 9'sd0, 9'sd0, 4'sd0);

    // Wait for POST code 30 (all tests passed)
    wait(postcode_o == 6'd30);
    $display("Time %t: All mouse tests passed!", $time);
    #10000;
    $finish(0);
end

// Monitor test results
always @(posedge clock_50_i) begin
    if (postcode_o >= 6'd50) begin
        // Test failure
        wait(postcode_o >= 6'd50);
        $display("Time %t: POST CODE = %d", $time, postcode_o);

        // Test failure
        if (postcode_o >= 6'd50) begin
            $display("*************************************");
            $display("*** MOUSE TEST FAILED! ***");
            $display("*************************************");
            #1000;
            $finish(1);
        end
    end
end

// Timeout
initial begin
    #100000000; // 100ms timeout
    $display("******************************");
    $display("*** TIMEOUT - TEST FAILED! ***");
    $display("******************************");
    $finish(1);
end

endmodule
