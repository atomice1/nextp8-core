//////////////////////////////////////////////////////////////////////////////////
// tb_keyboard.v
// Keyboard matrix and latching keyboard testbench
// Copyright (C) 2026 Chris January
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ns

module tb_keyboard ();

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

// PS2 - use reg drivers with wire for inout ports
reg ps2_clk_driver = 1'b1;
reg ps2_data_driver = 1'b1;
wire ps2_clk_io;
wire ps2_data_io;
assign ps2_clk_io = ps2_clk_driver;
assign ps2_data_io = ps2_data_driver;
wire ps2_pin6_io;
wire ps2_pin2_io;

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

sram sram(sram_clk_i,
    read_en_i,
    write_en_i,
    addr_i,
    lb_i,
    ub_i,
    data_in_i,
    data_out_o);

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
    integer r;
    reg[6:0] col = 7'b1111111; // Default: all columns high (no keys)

    for (r = 0; r < 8; r = r + 1) begin
        if (keyb_row_o[r] == 1'b0) begin // This row is being scanned
            col = col & membrane_pressed[r]; // Update columns based on pressed keys
        end
    end
    keyb_col_i <= col;
end

// Monitor postcode for test progress
reg [5:0] last_postcode = 6'd0;
always @(posedge clock_50_i) begin
    if (postcode_o != last_postcode) begin
        last_postcode <= postcode_o;
        $display("Time %t: POST CODE = %d", $time, postcode_o);

        // Test success
        if (postcode_o == 6'd25) begin
            $display("*************************************");
            $display("*** KEYBOARD TEST PASSED! ***");
            $display("*************************************");
            #1000;
            $finish;
        end

        // Test failure
        if (postcode_o >= 6'd50) begin
            $display("*************************************");
            $display("*** KEYBOARD TEST FAILED! ***");
            $display("*************************************");
            #1000;
            $finish;
        end
    end
end

// PS/2 keyboard stimulus
// Task to send a PS/2 byte (LSB first, with start, parity, stop bits)
task ps2_send_byte;
    input [7:0] data;
    integer i;
    reg parity;
    begin
        parity = 1'b1; // Odd parity

        // Calculate parity
        for (i = 0; i < 8; i = i + 1) begin
            parity = parity ^ data[i];
        end

        // Start bit
        ps2_data_driver = 1'b0;
        #1000; // ~1us per bit at 1MHz
        ps2_clk_driver = 1'b0;
        #1000;
        ps2_clk_driver = 1'b1;
        #1000;

        // Data bits (LSB first)
        for (i = 0; i < 8; i = i + 1) begin
            ps2_data_driver = data[i];
            #1000;
            ps2_clk_driver = 1'b0;
            #1000;
            ps2_clk_driver = 1'b1;
            #1000;
        end

        // Parity bit
        ps2_data_driver = parity;
        #1000;
        ps2_clk_driver = 1'b0;
        #1000;
        ps2_clk_driver = 1'b1;
        #1000;

        // Stop bit
        ps2_data_driver = 1'b1;
        #1000;
        ps2_clk_driver = 1'b0;
        #1000;
        ps2_clk_driver = 1'b1;
        #1000;
    end
endtask

// Task to press a PS/2 key
task ps2_press_key;
    input [7:0] scancode;
    begin
        $display("Time %t: PS/2 pressing key scancode 0x%h", $time, scancode);
        ps2_send_byte(scancode);
        #1000; // 1us delay
    end
endtask

// Task to release a PS/2 key
task ps2_release_key;
    input [7:0] scancode;
    begin
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

    // Wait for system to boot
    #15000; // 15us

    // Wait for POST code 7 (waiting for first key)
    wait(postcode_o == 6'd7);
    $display("Time %t: ROM waiting for TEST_KEY_1 (0x1C = A key)", $time);
    #10000; // 10us delay

    // Press TEST_KEY_1 (scancode 0x1C = A key)
    ps2_press_key(8'h1C);

    // Wait for POST code 10 (waiting for key release)
    wait(postcode_o == 6'd10);
    $display("Time %t: ROM detected key, waiting for release", $time);
    #10000;

    // Release TEST_KEY_1
    ps2_release_key(8'h1C);

    // Wait for POST code 13 (waiting for second key)
    wait(postcode_o == 6'd13);
    $display("Time %t: ROM waiting for TEST_KEY_2 (0x23 = D key)", $time);
    #10000;

    // Press TEST_KEY_2 (scancode 0x23 = D key) via membrane keyboard
    // Map scancode to membrane position (example: row 1, col 2)
    membrane_press_key(3'd1, 3'd2);

    // Wait for POST code 14
    wait(postcode_o == 6'd14);
    $display("Time %t: ROM detected second key", $time);
    #10000;

    // Release TEST_KEY_2
    membrane_release_key(3'd1, 3'd2);

    // Now wait for test completion
    wait(postcode_o == 6'd25 || postcode_o >= 6'd50);
end

// Timeout
initial begin
    #10000000; // 10ms timeout
    $display("******************************");
    $display("*** TIMEOUT - TEST FAILED! ***");
    $display("******************************");
    $finish;
end

endmodule

// SRAM behavioral model
module sram #(
    parameter ADDR_WIDTH = 21,
    parameter DATA_WIDTH = 16
) (
    input  wire                       clk_i,
    input  wire                       read_en_i,
    input  wire                       write_en_i,
    input  wire [ADDR_WIDTH-1:0]      addr_i,
    input  wire                       lb_i,
    input  wire                       ub_i,
    input  wire [DATA_WIDTH-1:0]      data_in_i,
    output reg  [DATA_WIDTH-1:0]      data_out_o
);

    // Declare the memory array
    reg [DATA_WIDTH-1:0] mem [2**ADDR_WIDTH-1:0];

    // Behavioral model for read and write
    always @(posedge clk_i) begin
        if (write_en_i) begin
            // Write operation
            if (lb_i)
                mem[addr_i][7:0] <= data_in_i[7:0];
            if (ub_i)
                mem[addr_i][15:8] <= data_in_i[15:8];
        end
    end

    // Read operation (combinational) - triggered by addr_i or read_en_i changes
    always @(addr_i or read_en_i or write_en_i) begin
        if (read_en_i && ~write_en_i) begin
            data_out_o = mem[addr_i];
        end else begin
            data_out_o = 16'h0000; // Drive zero when not reading
        end
    end

    integer i;
    initial begin
        $display("Loading keyboard test ROM...");
        $readmemh("keyboard_test_rom.mem", mem);
    end

endmodule
