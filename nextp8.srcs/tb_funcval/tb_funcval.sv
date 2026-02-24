// FuncVal Testbench for nextp8
// Provides MMIO access to DUT pins and peripheral models for functional validation
//
// This testbench allows M68K test programs to control and observe all I/O pins
// via SRAM-mapped MMIO registers at addresses 0x300000-0x3FFFFF

`timescale 1ns/1ps

module tb_funcval;

    // Parameters
    parameter ROM_FILE = "";  // Must be specified on command line

    // Clock generation
    reg clock_200_i = 0;
    always #2.5 clock_200_i = ~clock_200_i;  // 200 MHz

    // Derived 50Mhz clock
    reg clock_50_i = 0;
    reg [2:0] clk_div = 0;
    always @(posedge clock_200_i) begin
        clk_div <= clk_div + 1;
        clock_50_i <= clk_div[2];
    end

    // Reset
    reg reset_n = 0;
    initial begin
        #100 reset_n = 1;
    end

    // =========================================================================
    // SRAM Model
    // =========================================================================

    wire [20:0] ram_addr;
    wire [15:0] ram_data;
    wire        ram_lb_n;
    wire        ram_ub_n;
    wire        ram_oe_n;
    wire        ram_we_n;
    wire        ram_cs_n;
    wire        mmio_selected;

    // Deselect SRAM when MMIO is selected so it doesn't fight the testbench on ram_data
    wire sram_cs_n_gated = ram_cs_n | mmio_selected;

    sram #(
        .ADDR_WIDTH(21),
        .DATA_WIDTH(16),
        .SPEED_GRADE(10),
        .VERBOSE(0),
        .MEM_FILE(ROM_FILE)
    ) sram_inst (
        .addr(ram_addr),
        .dq(ram_data),
        .cs_n(sram_cs_n_gated),
        .we_n(ram_we_n),
        .oe_n(ram_oe_n),
        .lb_n(ram_lb_n),
        .ub_n(ram_ub_n)
    );

    // Check that ROM_FILE was provided
    initial begin
        if (ROM_FILE == "") begin
            $display("ERROR: ROM_FILE parameter must be specified");
            $display("Usage: xsim tb_funcval -generic_top \"ROM_FILE=<filename.mem>\"");
            $fatal(1);
        end
        $display("=== FuncVal Testbench ===");
        $display("ROM_FILE: %s", ROM_FILE);
    end

    // =========================================================================
    // DUT Pin Signals (nextp8_top_issue5 ports)
    // =========================================================================

    // PS2
    wire ps2_clk;
    wire ps2_data;
    wire ps2_pin6;
    wire ps2_pin2;

    // SD Card
    wire sd_cs0_n;
    wire sd_cs1_n;
    wire sd_sclk;
    wire sd_mosi;
    wire sd_miso;  // Controlled via MMIO

    // Flash
    wire flash_cs_n;
    wire flash_sclk;
    wire flash_mosi;
    wire flash_miso;  // Controlled via MMIO
    wire flash_wp;
    wire flash_hold;

    // Joystick
    wire joyp1;  // Controlled via MMIO
    wire joyp2;  // Controlled via MMIO
    wire joyp3;  // Controlled via MMIO
    wire joyp4;  // Controlled via MMIO
    wire joyp6;  // Controlled via MMIO
    wire joyp7;
    wire joyp9;  // Controlled via MMIO
    wire joysel;

    // Audio
    wire audioext_l;
    wire audioext_r;
    wire audioint;

    // K7
    wire ear_port;  // Controlled via MMIO
    wire mic_port;

    // Buttons
    wire btn_divmmc_n;      // Controlled via MMIO
    wire btn_multiface_n;   // Controlled via MMIO
    wire btn_reset_n;       // Controlled via MMIO

    // Matrix keyboard
    wire [7:0] keyb_row;
    wire [6:0] keyb_col;  // Controlled via MMIO

    // Bus
    wire       bus_rst_n;
    wire       bus_clk35;
    wire [15:0] bus_addr;
    wire [7:0]  bus_data;
    wire       bus_int_in;       // Controlled via MMIO
    wire       bus_int_n;
    wire       bus_nmi_n;        // Controlled via MMIO
    wire       bus_ramcs;
    wire       bus_romcs;        // Controlled via MMIO
    wire       bus_wait_n;       // Controlled via MMIO
    wire       bus_halt_n;
    wire       bus_iorq_n;
    wire       bus_m1_n;
    wire       bus_mreq_n;
    wire       bus_rd_n;
    wire       bus_wr_n;
    wire       bus_rfsh_n;
    wire       bus_busreq_n;     // Controlled via MMIO
    wire       bus_busack_n;
    wire       bus_iorqula_n;    // Controlled via MMIO
    wire       bus_y;
    wire       bus_p3_mtr_n;
    wire       bus_p3_drd_n;
    wire       bus_p3_dwr_n;

    // VGA
    wire [3:0] rgb_r;
    wire [3:0] rgb_g;
    wire [3:0] rgb_b;
    wire       hsync;
    wire       vsync;
    wire       vgaclk;
    wire       vgaclkn;

    // HDMI
    wire [3:0] hdmi_p;
    wire [3:0] hdmi_n;

    // I2C (RTC and HDMI)
    wire i2c_scl;
    wire i2c_sda;

    // ESP
    wire esp_gpio0;
    wire esp_gpio2;
    wire esp_rx;          // Controlled via MMIO
    wire esp_tx;
    wire esp_cts_n;
    wire esp_rtr_n;       // Controlled via MMIO

    // PI GPIO
    wire [27:0] accel;

    // XADC
    wire XADC_VP;         // Controlled via MMIO
    wire XADC_VN;         // Controlled via MMIO
    wire XADC_15P;        // Controlled via MMIO
    wire XADC_15N;        // Controlled via MMIO
    wire XADC_7P;         // Controlled via MMIO
    wire XADC_7N;         // Controlled via MMIO
    wire adc_control;

    // Vacant pins
    wire extras;
    wire extras_2;
    wire extras_3;

    // =========================================================================
    // DUT: nextp8_top_issue5
    // =========================================================================

    nextp8_top_issue5 dut (
        // Clocks
        .clock_50_i(clock_50_i),

        // SRAM
        .ram_addr_o(ram_addr),
        .ram_data_io(ram_data),
        .ram_lb_n_o(ram_lb_n),
        .ram_ub_n_o(ram_ub_n),
        .ram_oe_n_o(ram_oe_n),
        .ram_we_n_o(ram_we_n),
        .ram_cs_n_o(ram_cs_n),

        // PS2
        .ps2_clk_io(ps2_clk),
        .ps2_data_io(ps2_data),
        .ps2_pin6_io(ps2_pin6),
        .ps2_pin2_io(ps2_pin2),

        // SD Card
        .sd_cs0_n_o(sd_cs0_n),
        .sd_cs1_n_o(sd_cs1_n),
        .sd_sclk_o(sd_sclk),
        .sd_mosi_o(sd_mosi),
        .sd_miso_i(sd_miso),

        // Flash
        .flash_cs_n_o(flash_cs_n),
        .flash_sclk_o(flash_sclk),
        .flash_mosi_o(flash_mosi),
        .flash_miso_i(flash_miso),
        .flash_wp_o(flash_wp),
        .flash_hold_o(flash_hold),

        // Joystick
        .joyp1_i(joyp1),
        .joyp2_i(joyp2),
        .joyp3_i(joyp3),
        .joyp4_i(joyp4),
        .joyp6_i(joyp6),
        .joyp7_o(joyp7),
        .joyp9_i(joyp9),
        .joysel_o(joysel),

        // Audio
        .audioext_l_o(audioext_l),
        .audioext_r_o(audioext_r),
        .audioint_o(audioint),

        // K7
        .ear_port_i(ear_port),
        .mic_port_o(mic_port),

        // Buttons
        .btn_divmmc_n_i(btn_divmmc_n),
        .btn_multiface_n_i(btn_multiface_n),
        .btn_reset_n_i(btn_reset_n),

        // Matrix keyboard
        .keyb_row_o(keyb_row),
        .keyb_col_i(keyb_col),

        // Bus
        .bus_rst_n_io(bus_rst_n),
        .bus_clk35_o(bus_clk35),
        .bus_addr_o(bus_addr),
        .bus_data_io(bus_data),
        .bus_int_in_i(bus_int_in),
        .bus_int_n_o(bus_int_n),
        .bus_nmi_n_i(bus_nmi_n),
        .bus_ramcs_io(bus_ramcs),
        .bus_romcs_i(bus_romcs),
        .bus_wait_n_i(bus_wait_n),
        .bus_halt_n_o(bus_halt_n),
        .bus_iorq_n_o(bus_iorq_n),
        .bus_m1_n_o(bus_m1_n),
        .bus_mreq_n_o(bus_mreq_n),
        .bus_rd_n_io(bus_rd_n),
        .bus_wr_n_o(bus_wr_n),
        .bus_rfsh_n_o(bus_rfsh_n),
        .bus_busreq_n_i(bus_busreq_n),
        .bus_busack_n_o(bus_busack_n),
        .bus_iorqula_n_i(bus_iorqula_n),
        .bus_y_o(bus_y),
        .bus_p3_mtr_n_o(bus_p3_mtr_n),
        .bus_p3_drd_n_o(bus_p3_drd_n),
        .bus_p3_dwr_n_o(bus_p3_dwr_n),

        // VGA
        .rgb_r_o(rgb_r),
        .rgb_g_o(rgb_g),
        .rgb_b_o(rgb_b),
        .hsync_o(hsync),
        .vsync_o(vsync),
        .vgaclk_o(vgaclk),
        .vgaclkn_o(vgaclkn),

        // HDMI
        .hdmi_p_o(hdmi_p),
        .hdmi_n_o(hdmi_n),

        // I2C
        .i2c_scl_io(i2c_scl),
        .i2c_sda_io(i2c_sda),

        // ESP
        .esp_gpio0_io(esp_gpio0),
        .esp_gpio2_io(esp_gpio2),
        .esp_rx_i(esp_rx),
        .esp_tx_o(esp_tx),
        .esp_cts_n_o(esp_cts_n),
        .esp_rtr_n_i(esp_rtr_n),

        // PI GPIO
        .accel_io(accel),

        // XADC
        .XADC_VP(XADC_VP),
        .XADC_VN(XADC_VN),
        .XADC_15P(XADC_15P),
        .XADC_15N(XADC_15N),
        .XADC_7P(XADC_7P),
        .XADC_7N(XADC_7N),
        .adc_control_o(adc_control),

        // Vacant pins
        .extras_o(extras),
        .extras_2_io(extras_2),
        .extras_3_io(extras_3)
    );

    // =========================================================================
    // Peripheral Models
    // =========================================================================

    // DS1307 RTC I2C Device
    logic i2c_scl_rtc_out, i2c_sda_rtc_out;

    ds1307_device rtc (
        .i2c_scl_in(i2c_scl),
        .i2c_sda_in(i2c_sda),
        .i2c_scl_out(i2c_scl_rtc_out),
        .i2c_sda_out(i2c_sda_rtc_out)
    );

    // PS/2 Keyboard Device
    logic ps2_clk_kb_out, ps2_data_kb_out;

    keyboard_device #(
        .CLOCK_DIV(5000)  // 50MHz / 10kHz = 5000
    ) keyboard (
        .clk(clock_50_i),
        .reset(~reset_n),
        .ps2_clk_in(ps2_clk),
        .ps2_data_in(ps2_data),
        .ps2_clk_out(ps2_clk_kb_out),
        .ps2_data_out(ps2_data_kb_out)
    );

    // PS/2 Mouse Device
    logic ps2_clk_mouse_out, ps2_data_mouse_out;

    mouse_device #(
        .CLOCK_DIV(5000)  // 50MHz / 10kHz = 5000
    ) mouse (
        .clk(clock_50_i),
        .reset(~reset_n),
        .intellimouse_capable(1'b1),
        .ps2_clk_in(ps2_pin6),
        .ps2_data_in(ps2_pin2),
        .ps2_clk_out(ps2_clk_mouse_out),
        .ps2_data_out(ps2_data_mouse_out)
    );

    // VGA Display Model
    logic [9:0] vga_pixel_x, vga_pixel_y;
    logic [3:0] vga_pixel_r, vga_pixel_g, vga_pixel_b;

    vga_display_model vga_model (
        .vgaclk_i(vgaclk),
        .rgb_r_i(rgb_r),
        .rgb_g_i(rgb_g),
        .rgb_b_i(rgb_b),
        .hsync_i(hsync),
        .vsync_i(vsync),
        .x_i(vga_pixel_x),
        .y_i(vga_pixel_y),
        .rgb_r_o(vga_pixel_r),
        .rgb_g_o(vga_pixel_g),
        .rgb_b_o(vga_pixel_b)
    );

    // Debug UART (connected to accel GPIO pins for debug terminal)
    logic       debug_uart_tx;
    logic       debug_uart_rx;  // Connected via assign statement
    logic       debug_uart_ready;
    logic       debug_uart_data_ready;
    wire        debug_uart_r;
    logic       debug_uart_w = 1'b0;
    logic       debug_uart_ra;
    logic       debug_uart_wa;
    logic [7:0] debug_uart_data_in = 8'h00;
    logic [7:0] debug_uart_data_out;

    UART debug_uart (
        .Tx(debug_uart_tx),
        .Rx(debug_uart_rx),
        .clk(clock_50_i),
        .reset(~reset_n),
        .r(debug_uart_r),
        .w(debug_uart_w),
        .data_ready(debug_uart_data_ready),
        .ready(debug_uart_ready),
        .ra(debug_uart_ra),
        .wa(debug_uart_wa),
        .data_in(debug_uart_data_in),
        .data_out(debug_uart_data_out),
        .speed(15'd434)  // 115200 baud @ 50MHz
    );

    // ESP UART
    logic       esp_uart_ready;
    logic       esp_uart_data_ready;
    logic       esp_uart_r = 1'b0;
    logic       esp_uart_w = 1'b0;
    logic       esp_uart_ra;
    logic       esp_uart_wa;
    logic [7:0] esp_uart_data_in = 8'h00;
    logic [7:0] esp_uart_data_out;

    UART esp_uart (
        .Tx(esp_rx),  // ESP's RX is UART's TX
        .Rx(esp_tx),  // ESP's TX is UART's RX
        .clk(clock_50_i),
        .reset(~reset_n),
        .r(esp_uart_r),
        .w(esp_uart_w),
        .data_ready(esp_uart_data_ready),
        .ready(esp_uart_ready),
        .ra(esp_uart_ra),
        .wa(esp_uart_wa),
        .data_in(esp_uart_data_in),
        .data_out(esp_uart_data_out),
        .speed(15'd434)  // 115200 baud @ 50MHz
    );

    // Wire up bidirectional PS/2 signals
    assign ps2_clk = (ps2_clk_kb_out == 1'b0 || ps2_clk_mouse_out == 1'b0) ? 1'b0 : 1'bz;
    assign ps2_data = (ps2_data_kb_out == 1'b0) ? 1'b0 : 1'bz;
    assign ps2_pin6 = (ps2_clk_mouse_out == 1'b0) ? 1'b0 : 1'bz;
    assign ps2_pin2 = (ps2_data_mouse_out == 1'b0) ? 1'b0 : 1'bz;

    // Wire up bidirectional I2C signals
    assign i2c_scl = (i2c_scl_rtc_out == 1'b0) ? 1'b0 : 1'bz;
    assign i2c_sda = (i2c_sda_rtc_out == 1'b0) ? 1'b0 : 1'bz;

    // Connect debug UART to Raspberry Pi GPIO pins
    assign accel[14] = debug_uart_tx;   // Pi GPIO 14 (TXD0) - UART TX to Pi RX
    assign debug_uart_rx = accel[15];   // Pi GPIO 15 (RXD0) - Pi TX to UART RX

    // =========================================================================
    // POST Code Monitor (GPIO accel[27:22])
    // =========================================================================

    wire [5:0] post_code = accel[27:22];
    reg  [5:0] post_code_last;

    always @(posedge clock_50_i) begin
        if (!reset_n) begin
            post_code_last <= 6'h3F;
        end else if (post_code !== post_code_last) begin
            post_code_last <= post_code;
            if (^post_code !== 1'bx) begin
                $display("POST: %0d", post_code);
            end
        end
    end

    // =========================================================================
    // Debug UART Output Monitor
    // =========================================================================

    reg debug_uart_r_reg = 0;
    reg debug_uart_data_read = 0;

    always @(posedge clock_50_i) begin
        debug_uart_r_reg <= 0;

        if (debug_uart_data_ready && !debug_uart_ra) begin
            // Set read strobe
            debug_uart_r_reg <= 1;
            debug_uart_data_read <= 0;
        end

        if (debug_uart_ra && !debug_uart_data_read) begin
            // Read acknowledge - data has been captured
            $write("%c", debug_uart_data_out);
            debug_uart_data_read <= 1;
        end
    end

    assign debug_uart_r = debug_uart_r_reg;

    // =========================================================================
    // SRAM Address Decoder for MMIO
    // =========================================================================

    // Extract SRAM address and control signals
    wire [20:0] sram_addr = ram_addr;  // Word address (A20:A0)
    wire        sram_we_n = ram_we_n;
    wire        sram_oe_n = ram_oe_n;
    wire        sram_ce_n = ram_cs_n;  // Chip select

    // MMIO address ranges (word-addressed, A20:A0)
    // Peripheral MMIO: 0x380000 - 0x38FFFF (0x1C0000 - 0x1C7FFF word addr)
    // VGA Framebuffer: 0x390000 - 0x392000 (0x1C8000 - 0x1CBFFF word addr) [128x128 downsampled]
    wire mmio_periph_selected = (sram_addr[20:15] == 6'b111000); // 0x1C0000-0x1C7FFF
    wire vga_fb_selected = (sram_addr >= 21'h1C8000) && (sram_addr < 21'h1CC000); // 0x1C8000-0x1CBFFF
    assign mmio_selected =  mmio_periph_selected || vga_fb_selected;

    // Generate write strobe (rising edge of WE# when MMIO is selected)
    reg sram_we_n_q;
    wire sram_we_strobe;
    always @(posedge clock_200_i) begin
        sram_we_n_q <= sram_we_n;
    end
    assign sram_we_strobe = !sram_we_n && sram_we_n_q && mmio_selected && !sram_ce_n;

    // MMIO data buses
    reg [15:0] sram_read_data;
    wire [15:0] sram_write_data = ram_data;  // Data from SRAM during writes

    // Intercept SRAM data bus for MMIO reads
    // When MMIO is selected and OE# is active, drive MMIO read data onto SRAM data bus
    assign ram_data = (!sram_oe_n && mmio_selected && !sram_ce_n) ? sram_read_data : 16'hZZZZ;

    // =========================================================================
    // Peripheral MMIO Block (0x380000 - 0x3890000)
    // Maps MMIO registers to peripheral model tasks
    // =========================================================================

    // Keyboard control registers (0x380000)
    reg [7:0] kb_scancode = 8'h00;     // 0x380001: Scancode to send
    reg kb_send_trigger = 1'b0;        // Write trigger flag

    // Mouse control registers (0x380020)
    reg mouse_left_btn = 1'b0;         // 0x380021[0]: Left button
    reg mouse_right_btn = 1'b0;        // 0x380021[1]: Right button
    reg mouse_middle_btn = 1'b0;       // 0x380021[2]: Middle button
    reg signed [8:0] mouse_x = 9'sd0;  // 0x380023: X movement (signed)
    reg signed [8:0] mouse_y = 9'sd0;  // 0x380025: Y movement (signed)
    reg signed [3:0] mouse_z = 4'sd0;  // 0x380027[3:0]: Scroll wheel (signed)
    reg mouse_send_trigger = 1'b0;     // Write trigger flag

    // Screenshot control register (0x380041)
    reg screenshot_trigger = 1'b0;     // 0x380041: Screenshot trigger
    integer screenshot_counter = 0;    // Screenshot counter for unique filenames

    // Trace control register (0x380043)
    reg trace_enable = 1'b0;

    // WAV recording control register (0x380045)
    reg wav_recording = 1'b0;          // 0x380045: WAV recording enable (1=start, 0=stop)
    integer wav_file = 0;              // WAV file handle
    integer wav_sample_count = 0;      // Number of samples recorded
    integer wav_counter = 0;           // WAV file counter for unique filenames

    // Joystick control registers (0x380061 - 0x380063)
    reg [7:0] joy0 = 8'h00;  // 0x380061: Joystick 0 state
    reg [7:0] joy1 = 8'h00;  // 0x380063: Joystick 1 state

    // Built-in keyboard matrix control registers (0x380080 - 0x380087)
    // Each register contains 8 bits (bits [7:0] map to keyboard matrix columns)
    // When a bit is written as 1, that key is pressed in the matrix
    // When a bit is written as 0, that key is released
    reg [7:0] keyboard_matrix [0:7];
    // 0x380080: Row 0 (Caps Shift, Z, X, C, V, reserved, Up arrow)
    // 0x380081: Row 1 (A, S, D, F, G, Caps Lock)
    // 0x380082: Row 2 (Q, W, E, R, T)
    // 0x380083: Row 3 (1, 2, 3, 4, 5, Break/ESC)
    // 0x380084: Row 4 (0, 9, 8, 7, 6, ;, ")
    // 0x380085: Row 5 (P, O, I, U, Y, comma, period)
    // 0x380086: Row 6 (Enter, L, K, J, H, Delete, Right arrow)
    // 0x380087: Row 7 (Space, Sym Shift, M, N, B, Left arrow, Down arrow)

    // Initialize keyboard_matrix array
    initial begin
        keyboard_matrix[0] = 8'h00;
        keyboard_matrix[1] = 8'h00;
        keyboard_matrix[2] = 8'h00;
        keyboard_matrix[3] = 8'h00;
        keyboard_matrix[4] = 8'h00;
        keyboard_matrix[5] = 8'h00;
        keyboard_matrix[6] = 8'h00;
        keyboard_matrix[7] = 8'h00;
    end

    // VGA framebuffer readback signals
    wire [11:0] vga_fb_pixel = {vga_pixel_r, vga_pixel_g, vga_pixel_b};  // 12-bit pixel value from VGA model

    // VGA framebuffer address decoder (0x390000 - 0x398000) [128x128 downsampled buffer]
    // Address format: 0x390000 + (y * 128 + x) * 2
    // Each pixel samples center of 6x6 VGA block at (x*6+3+128, y*6+3)
    // 128x128 = 16,384 pixels = 32,768 bytes (0x8000)
    // Note: vga_fb_selected wire is declared in main testbench
    wire [19:0] vga_fb_offset = sram_addr - 21'h1C8000;  // Pixel index in downsampled buffer (word address)
    wire [6:0] downsamp_x = vga_fb_offset % 128;  // X in downsampled space (0-127)
    wire [6:0] downsamp_y = vga_fb_offset / 128;  // Y in downsampled space (0-127)
    // Convert to VGA coordinates: sample at (x*6+3+128, y*6+3)
    assign vga_pixel_x = {2'b00, downsamp_x} * 10'd6 + 10'd131;  // 3 + 128 = 131
    assign vga_pixel_y = {2'b00, downsamp_y} * 10'd6 + 10'd3;

    // Peripheral MMIO Read Logic
    always @(*) begin
        if (vga_fb_selected) begin
            // VGA framebuffer readback
            sram_read_data = {4'h0, vga_fb_pixel};
        end else if (mmio_periph_selected) begin
            case (sram_addr)
                default: sram_read_data = 16'h0000;
            endcase
        end else begin
            sram_read_data = 16'h0000;
        end
    end

    // Peripheral MMIO Write Logic
    always @(posedge clock_200_i) begin
        // Clear trigger flags
        kb_send_trigger <= 1'b0;
        mouse_send_trigger <= 1'b0;
        screenshot_trigger <= 1'b0;

        if (sram_we_strobe && mmio_periph_selected) begin
            $display("MMIO Write: Addr=0x%06X, Data=0x%04X", sram_addr, sram_write_data);
            case (sram_addr)
                // Keyboard: Writing scancode triggers send_scancode task
                21'h1C0000: begin
                    kb_scancode <= sram_write_data[7:0];
                    kb_send_trigger <= 1'b1;
                end

                // Mouse button state
                21'h1C0010: begin
                    mouse_left_btn <= sram_write_data[0];
                    mouse_right_btn <= sram_write_data[1];
                    mouse_middle_btn <= sram_write_data[2];
                end

                // Mouse X movement
                21'h1C0011: begin
                    mouse_x <= sram_write_data[8:0];
                end

                // Mouse Y movement
                21'h1C0012: begin
                    mouse_y <= sram_write_data[8:0];
                end

                // Mouse Z scroll + trigger send
                21'h1C0013: begin
                    mouse_z <= sram_write_data[3:0];
                    mouse_send_trigger <= 1'b1;
                end

                // Screenshot trigger
                21'h1C0020: begin
                    screenshot_trigger <= 1'b1;
                end

                // Trace trigger
                21'h1C0021: begin
                    trace_enable <= sram_write_data[0];
                    $display("Trace %s", sram_write_data[0] ? "enabled" : "disabled");
                end

                // WAV recording control (1=start, 0=stop)
                21'h1C0022: begin
                    if (sram_write_data[0] && !wav_recording) begin
                        // Start recording: open new WAV file
                        wav_start_recording();
                        wav_recording <= 1'b1;
                    end else if (!sram_write_data[0] && wav_recording) begin
                        // Stop recording: close WAV file
                        wav_stop_recording();
                        wav_recording <= 1'b0;
                    end
                end

                // Joystick 0
                21'h1C0030: begin
                    joy0 <= sram_write_data[7:0];
                end

                // Joystick 1
                21'h1C0031: begin
                    joy1 <= sram_write_data[7:0];
                end

                // Built-in keyboard matrix (0x380080 - 0x380087)
                21'h1C0040: keyboard_matrix[0] <= sram_write_data[7:0];  // Row 0
                21'h1C0041: keyboard_matrix[1] <= sram_write_data[7:0];  // Row 1
                21'h1C0042: keyboard_matrix[2] <= sram_write_data[7:0];  // Row 2
                21'h1C0043: keyboard_matrix[3] <= sram_write_data[7:0];  // Row 3
                21'h1C0044: keyboard_matrix[4] <= sram_write_data[7:0];  // Row 4
                21'h1C0045: keyboard_matrix[5] <= sram_write_data[7:0];  // Row 5
                21'h1C0046: keyboard_matrix[6] <= sram_write_data[7:0];  // Row 6
                21'h1C0047: keyboard_matrix[7] <= sram_write_data[7:0];  // Row 7
            endcase
        end
    end

    // Invoke peripheral model tasks when triggers are set
    always @(posedge clock_200_i) begin
        if (kb_send_trigger) begin
            keyboard.send_scancode(kb_scancode);
        end

        if (mouse_send_trigger) begin
            mouse.send_movement_packet(
                mouse_left_btn,
                mouse_right_btn,
                mouse_middle_btn,
                mouse_x,
                mouse_y,
                mouse_z
            );
        end

        if (screenshot_trigger) begin
            screenshot_ppm();
        end
    end

    // =========================================================================
    // PCM Audio Capture from p8audio
    // =========================================================================

    wire signed [7:0] pcm_out;
    // Extract PCM output from DUT's p8audio instance
    assign pcm_out = dut.nextp8_inst.p8audio_inst.pcm_out;

    // PCM sample capture: triggered on clk_pcm rising edge when recording
    wire clk_pcm = dut.nextp8_inst.clk_pcm;

    always @(posedge clk_pcm) begin
        if (wav_recording && wav_file != 0) begin
            // Write 16-bit little-endian PCM sample (8-bit PCM in upper byte, 0 in lower)
            $fwrite(wav_file, "%c%c", 8'd0, pcm_out[7:0]);
            wav_sample_count = wav_sample_count + 1;
        end
    end

    // =========================================================================
    // WAV Recording Tasks
    // =========================================================================

    localparam integer WAV_SAMPLE_RATE = 22050;

    // Start WAV recording: open file and write header with placeholder size
    task wav_start_recording;
        string filename;
        begin
            $sformat(filename, "funcval_audio_%0d.wav", wav_counter);
            wav_counter = wav_counter + 1;
            wav_file = $fopen(filename, "wb");
            if (wav_file == 0) begin
                $display("ERROR: Could not open %s for WAV recording", filename);
                wav_recording = 1'b0;
            end else begin
                // Write WAV header with size=0 (will be updated on close)
                wav_write_header(wav_file, 0);
                wav_sample_count = 0;
                $display("Started WAV recording to %s", filename);
            end
        end
    endtask

    // Stop WAV recording: rewrite header with correct size and close file
    task wav_stop_recording;
        begin
            if (wav_file != 0) begin
                // Rewind and rewrite header with actual sample count
                $fseek(wav_file, 0, 0);  // Seek to beginning
                wav_write_header(wav_file, wav_sample_count);
                $fclose(wav_file);
                $display("Stopped WAV recording: %0d samples written", wav_sample_count);
                wav_file = 0;
            end
        end
    endtask

    // Write WAV file header (mono, 16-bit, 22050 Hz)
    task wav_write_header(input integer f, input integer n_samples);
        integer bytes, br;
        begin
            bytes = n_samples * 2;  // 16-bit mono
            br = WAV_SAMPLE_RATE * 2;  // bytes/sec
            // RIFF header
            $fwrite(f, "RIFF");
            $fwrite(f, "%c%c%c%c", (bytes+36)&255, ((bytes+36)>>8)&255, ((bytes+36)>>16)&255, ((bytes+36)>>24)&255);
            $fwrite(f, "WAVEfmt ");
            $fwrite(f, "%c%c%c%c", 16,0,0,0);  // PCM chunk size
            $fwrite(f, "%c%c", 1,0);           // PCM format
            $fwrite(f, "%c%c", 1,0);           // channels=1
            $fwrite(f, "%c%c%c%c", WAV_SAMPLE_RATE&255,(WAV_SAMPLE_RATE>>8)&255,(WAV_SAMPLE_RATE>>16)&255,(WAV_SAMPLE_RATE>>24)&255);
            $fwrite(f, "%c%c%c%c", br&255,(br>>8)&255,(br>>16)&255,(br>>24)&255);
            $fwrite(f, "%c%c", 2,0);           // block align
            $fwrite(f, "%c%c", 16,0);          // bits per sample
            $fwrite(f, "data");
            $fwrite(f, "%c%c%c%c", bytes&255,(bytes>>8)&255,(bytes>>16)&255,(bytes>>24)&255);
        end
    endtask

    // Screenshot task: Generate PPM file from VGA framebuffer
    task screenshot_ppm;
        integer fd;
        integer x, y;
        integer pixel;
        integer r, g, b;
        string filename;
        begin
            // Generate unique filename with counter
            $sformat(filename, "screenshot_%0d.ppm", screenshot_counter);
            screenshot_counter = screenshot_counter + 1;

            fd = $fopen(filename, "w");
            if (fd == 0) begin
                $display("ERROR: Could not open %s for writing", filename);
            end else begin
                // Write PPM header (P3 = ASCII RGB, easier to debug than P6 binary)
                $fwrite(fd, "P3\n");
                $fwrite(fd, "1024 768\n");  // nextp8 screen is 1024x768
                $fwrite(fd, "255\n");

                // Write pixel data
                for (y = 0; y < 768; y = y + 1) begin
                    for (x = 0; x < 1024; x = x + 1) begin
                        // Read pixel from VGA model
                        // VGA model exposes current pixel at cursor position
                        // We need to read from VRAM directly via back buffer
                        pixel = vga_model.pixel_buffer[y][x];

                        // Extract RGB from 12-bit pixel ({R[3:0], G[3:0], B[3:0]})
                        r = ((pixel >> 8) & 4'hF) * 17;  // Scale 4-bit to 8-bit
                        g = ((pixel >> 4) & 4'hF) * 17;
                        b = (pixel & 4'hF) * 17;

                        // Write RGB values
                        //$fwrite(fd, "%0x ", pixel);
                        $fwrite(fd, "%0d %0d %0d ", r, g, b);
                    end
                    $fwrite(fd, "\n");
                end

                $fclose(fd);
                $display("Screenshot saved to %s (1024x768 pixels)", filename);
            end
        end
    endtask

    assign joyp1 = joysel ? joy1[0] : joy0[0];
    assign joyp2 = joysel ? joy1[1] : joy0[1];
    assign joyp3 = joysel ? joy1[2] : joy0[2];
    assign joyp4 = joysel ? joy1[3] : joy0[3];
    assign joyp6 = joysel ? joy1[4] : joy0[4];
    assign joyp9 = joysel ? joy1[5] : joy0[5];

    // Built-in keyboard matrix: combinatorial multiplexer
    // keyb_row_o is active-low (one bit low, others high-Z)
    // Decode which row is active and return the corresponding columns
    wire [2:0] active_row;
    assign active_row = (~keyb_row[7]) ? 3'd7 :
                        (~keyb_row[6]) ? 3'd6 :
                        (~keyb_row[5]) ? 3'd5 :
                        (~keyb_row[4]) ? 3'd4 :
                        (~keyb_row[3]) ? 3'd3 :
                        (~keyb_row[2]) ? 3'd2 :
                        (~keyb_row[1]) ? 3'd1 :
                        (~keyb_row[0]) ? 3'd0 :
                        3'd0;  // No row active or invalid state

    // Return the selected row's columns (7 bits)
    assign keyb_col = keyboard_matrix[active_row][6:0];

    // =========================================================================
    // TG68K PC Monitor (uses address bus during instruction fetch)
    // =========================================================================

    wire [23:0] cpu_addr = dut.nextp8_inst.cpu_addr;
    wire [1:0]  cpu_busstate = dut.nextp8_inst.cpu_busstate;
    reg  [23:0] cpu_addr_last;

    always @(posedge clock_50_i) begin
        if (!reset_n) begin
            cpu_addr_last <= 24'hFFFFFF;
        end else if (trace_enable && cpu_busstate == 2'b00 && cpu_addr !== cpu_addr_last) begin
            cpu_addr_last <= cpu_addr;
            if (^cpu_addr !== 1'bx) begin
                $display("PC=%06h", cpu_addr);
            end
        end
    end

    // =========================================================================
    // Simulation Control
    // =========================================================================

    // Shutdown monitor: finish when CPU shutdown and UART buffers drained
    reg shutdown_detected = 0;
    integer uart_idle_counter = 0;

    always @(posedge clock_50_i) begin
        if (dut.nextp8_inst.cpu_shutdown && !shutdown_detected) begin
            shutdown_detected <= 1;
            uart_idle_counter <= 0;
        end

        if (shutdown_detected) begin
            // Finish when UART has drained
            if (uart_idle_counter >= 5000 && !debug_uart_data_ready) begin
                $display("CPU shutdown and UART buffers drained, simulation complete at time %t", $time);
                $finish;
            end
            if (debug_uart_data_ready) begin
                uart_idle_counter <= 0;  // Reset counter if new UART data arrives
            end else begin
                uart_idle_counter <= uart_idle_counter + 1;
            end
        end
    end

    // Timeout watchdog
    initial begin
        #1000000000;  // 1000 ms timeout
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
