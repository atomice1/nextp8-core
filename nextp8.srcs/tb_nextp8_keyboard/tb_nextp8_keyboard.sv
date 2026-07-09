//////////////////////////////////////////////////////////////////////////////////
// tb_nextp8_keyboard.sv
// Keyboard matrix and latching keyboard testbench
// Copyright (C) 2026 Chris January
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ns

module tb_nextp8_keyboard ();

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

// Track initialization state
reg [7:0] init_byte_count = 0;
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

// Matrix keyboard
wire [7:0] keyb_row_o;
reg [6:0] keyb_col_i;

// Track which membrane keys are pressed: membrane_pressed[row][col]
reg [6:0] membrane_pressed [0:7];

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
    .MEM_FILE("keyboard_test_rom.mem")
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

// Initialize membrane keyboard state
initial begin
    integer r;
    for (r = 0; r < 8; r = r + 1) begin
        membrane_pressed[r] = 7'b1111111; // All keys released (high)
    end
end

// Simulate membrane keyboard matrix scanning
// When a row is driven low, set corresponding column low if key is pressed
always @* begin
    automatic integer r;
    automatic reg[6:0] col = 7'b1111111; // Default: all columns high (no keys)

    for (r = 0; r < 8; r = r + 1) begin
        if (keyb_row_o[r] == 1'b0) begin // This row is being scanned
            col = col & membrane_pressed[r]; // Update columns based on pressed keys
        end
    end
    keyb_col_i <= col;
end

// Monitor postcode for test progress
reg [5:0] last_postcode = 6'd0;
integer heartbeat_counter2 = 0;
always @(posedge clock_50_i) begin
    if (postcode_o != last_postcode) begin
        last_postcode <= postcode_o;
        $display("Time %t: POST CODE = %d (ps2_clk_io=%b ps2_data_io=%b)", $time, postcode_o, ps2_clk_io, ps2_data_io);

        // Test success
        if (postcode_o == 6'd40) begin
            $display("*************************************");
            $display("*** KEYBOARD TEST PASSED! ***");
            $display("*************************************");
            #1000;
            $finish(0);
        end

        // Test failure
        if (postcode_o >= 6'd50) begin
            $display("*************************************");
            $display("*** KEYBOARD TEST FAILED! ***");
            $display("*************************************");
            #1000;
            $finish(1);
        end
    end
end

// PS/2 keyboard stimulus using keyboard_device model
wire kbd_clk_out;
wire kbd_data_out;

// Connect device outputs to bus (open-drain)
assign ps2_clk_io = (kbd_clk_out === 1'b0) ? 1'b0 : 1'bz;
assign ps2_data_io = (kbd_data_out === 1'b0) ? 1'b0 : 1'bz;

// PS/2 protocol sniffer (both host and device tristate)
ps2_sniffer #(
    .HOST_IS_TRISTATE(1),      // nextp8 uses tristate ps2_clk_io/ps2_data_io
    .DEVICE_IS_TRISTATE(0)     // keyboard_device uses separate in/out
) sniffer (
    // Host side (tristate): monitor shared bus
    .host_ps2_clk_in_i(ps2_clk_io),
    .host_ps2_data_in_i(ps2_data_io),

    // Device side (non-tristate): monitor shared bus and device outputs
    .device_ps2_clk_in_i(ps2_clk_io),
    .device_ps2_data_in_i(ps2_data_io),
    .device_ps2_clk_out_i(kbd_clk_out),
    .device_ps2_data_out_i(kbd_data_out)
);

// Hold device model in reset briefly to start from a known state
reg kbd_reset = 1'b1;
initial begin
    #1000;
    kbd_reset = 1'b0;
end

keyboard_device #(
    .CLOCK_DIV(5000)    // 50MHz / 10kHz = 5000
) kbd_model (
    .clk(clock_50_i),
    .reset(kbd_reset),
    .ps2_clk_in(ps2_clk_io),
    .ps2_data_in(ps2_data_io),
    .ps2_clk_out(kbd_clk_out),
    .ps2_data_out(kbd_data_out)
);

// Task to send a PS/2 byte using keyboard model
task ps2_send_byte;
    input [7:0] data;
    begin
        kbd_model.send_scancode(data);
        // Wait for transmission to complete (50000 cycles @ 50MHz = 1ms)
        repeat(50000) @(posedge clock_50_i);
    end
endtask

// Task to wait for and verify initialization sequence
// Waits for keyboard module's init_state to reach INIT_DONE before allowing scancodes
task verify_init_sequence;
    begin
        $display("======================================");
        $display("=== Waiting for Init Sequence ===");
        $display("======================================");

        // Wait for keyboard module initialization to complete
        // The keyboard module ignores RX data until init_state == INIT_DONE
        wait(nextp8.keyboard.init_state == 5'd16);  // 5'd16 = INIT_DONE
        $display("Time %t: ✓ Keyboard initialization complete (init_state=%0d)", $time, nextp8.keyboard.init_state);

        init_complete = 1;
        $display("======================================");
        $display("=== Init Sequence Verified! ===");
        $display("======================================");

        #10000; // Delay before allowing key presses
    end
endtask

// Task to press a PS/2 key
task ps2_press_key;
    input [7:0] scancode;
    begin
        if (!init_complete) begin
            $display("ERROR: Attempted to send key before init complete!");
            $finish(1);
        end
        $display("Time %t: PS/2 pressing key scancode 0x%h", $time, scancode);
        ps2_send_byte(scancode);
        #1000; // 1us delay
    end
endtask

// Task to release a PS/2 key
task ps2_release_key;
    input [7:0] scancode;
    begin
        if (!init_complete) begin
            $display("ERROR: Attempted to send key before init complete!");
            $finish(1);
        end
        $display("Time %t: PS/2 releasing key scancode 0x%h", $time, scancode);
        ps2_send_byte(8'hF0); // Break code
        ps2_send_byte(scancode);
        #1000;
    end
endtask

// Task to press a membrane keyboard key
// Row: 0-7, Col: 0-6
task membrane_press_key;
    input [2:0] row;
    input [2:0] col;
    begin
        $display("Time %t: Membrane pressing key row=%d col=%d", $time, row, col);
        membrane_pressed[row][col] = 1'b0; // Mark key as pressed (active low)
        #1000;
    end
endtask

// Task to release a membrane keyboard key
task membrane_release_key;
    input [2:0] row;
    input [2:0] col;
    begin
        $display("Time %t: Membrane releasing key row=%d col=%d", $time, row, col);
        membrane_pressed[row][col] = 1'b1; // Mark key as released (high)
        #1000;
    end
endtask

// Keyboard test stimulus
initial begin
    $display("======================================");
    $display("=== KEYBOARD TESTBENCH STARTING ===");
    $display("======================================");

    // Wait for system to boot and keyboard init to start
    wait(postcode_o >= 6'd6);
    #100000; // 100us settle after POST code 6

    // First, verify the initialization sequence
    verify_init_sequence();

    // Wait for POST code 7 (waiting for first key)
    wait(postcode_o == 6'd7);
    $display("Time %t: ROM waiting for TEST_KEY_1 (USB HID 0x04 = A key, PS/2 0x1C)", $time);
    #10000; // 10us delay

    // Press TEST_KEY_1 (USB HID 0x04 = A key, PS/2 scancode 0x1C)
    ps2_press_key(8'h1C);

    // Wait for POST code 10 (waiting for key release)
    wait(postcode_o == 6'd10);
    $display("Time %t: ROM detected key, waiting for release", $time);
    #10000;

    // Release TEST_KEY_1
    ps2_release_key(8'h1C);

    // Wait for POST code 13 (waiting for second key)
    wait(postcode_o == 6'd13);
    $display("Time %t: ROM waiting for TEST_KEY_2 (USB HID 0x07 = D key, PS/2 0x23)", $time);
    #10000;

    // Press TEST_KEY_2 (USB HID 0x07 = D key, PS/2 scancode 0x23) via membrane keyboard
    // Map scancode to membrane position (example: row 1, col 2)
    membrane_press_key(3'd1, 3'd2);

    // Wait for POST code 14
    wait(postcode_o == 6'd14);
    $display("Time %t: ROM detected second key", $time);
    #10000;

    // Release TEST_KEY_2
    membrane_release_key(3'd1, 3'd2);

    // Wait for POST code 22 (new: queue cleared by ROM)
    wait(postcode_o == 6'd22);
    $display("Time %t: ROM cleared event queue", $time);

    // Wait for POST code 23 (new: empty queue returns 0)
    wait(postcode_o == 6'd23);
    $display("Time %t: ROM verified empty queue returns 0", $time);

    // Press TEST_KEY_1 to trigger press event
    ps2_press_key(8'h1C);
    #1000;

    // Wait for POST code 24 (new: key detected in regular matrix for queue test)
    wait(postcode_o == 6'd24);
    $display("Time %t: ROM detected key for queue test", $time);

    // Wait for POST code 25 (new: key press event received)
    wait(postcode_o == 6'd25);
    $display("Time %t: ROM received key press event", $time);

    // Release TEST_KEY_1 to trigger release event
    ps2_release_key(8'h1C);
    #1000;

    // Wait for POST code 27 (new: key released from regular matrix)
    wait(postcode_o == 6'd27);
    $display("Time %t: ROM waiting for key release event", $time);

    // Wait for POST code 28 (new: key release event received)
    wait(postcode_o == 6'd28);
    $display("Time %t: ROM received key release event", $time);

    // Wait for POST code 30 (new: waiting for key press to add to queue)
    wait(postcode_o == 6'd30);
    $display("Time %t: ROM waiting for key press to add to queue", $time);

    // Press a key to add to queue
    membrane_press_key(3'd3, 3'd1);
    #1000;

    // Wait for POST code 31 (new: key press detected)
    wait(postcode_o == 6'd31);
    $display("Time %t: ROM detected key press", $time);

    // Wait for POST code 32 (new: event in queue verified)
    wait(postcode_o == 6'd32);
    $display("Time %t: ROM verified event in queue", $time);

    // Wait for POST code 34 (new: queue clear verified)
    wait(postcode_o == 6'd34);
    $display("Time %t: ROM verified queue cleared", $time);

    // Wait for POST code 35 (new: latched key cleared)
    wait(postcode_o == 6'd35);
    $display("Time %t: ROM latched key cleared", $time);

    // Wait for test completion (POST 40 = success with new event queue tests)
    wait(postcode_o == 6'd40 || postcode_o >= 6'd50);
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
