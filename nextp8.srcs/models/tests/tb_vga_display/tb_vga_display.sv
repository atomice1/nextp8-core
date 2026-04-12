// Testbench for VGA Display Model
// Tests p8video VGA output by writing pixels to VRAM and validating display

`timescale 1ns/1ps

module tb_vga_display;

    // PICO-8 color palette (12-bit RGB, 4 bits per channel)
    reg [11:0] pico8_palette [0:15];

    initial begin
        // Standard 16 colors (0-15)
        pico8_palette[0]  = 12'h000; // 000000 black
        pico8_palette[1]  = 12'h125; // 1D2B53 dark-blue
        pico8_palette[2]  = 12'h725; // 7E2553 dark-purple
        pico8_palette[3]  = 12'h085; // 008751 dark-green
        pico8_palette[4]  = 12'ha53; // AB5236 brown
        pico8_palette[5]  = 12'h554; // 5F574F dark-grey
        pico8_palette[6]  = 12'hccc; // C2C3C7 light-grey
        pico8_palette[7]  = 12'hffe; // FFF1E8 white
        pico8_palette[8]  = 12'hf04; // FF004D red
        pico8_palette[9]  = 12'hfa3; // FFA300 orange
        pico8_palette[10] = 12'hfe2; // FFEC27 yellow
        pico8_palette[11] = 12'h0e3; // 00E436 green (upper 4 bits: 0,E,3)
        pico8_palette[12] = 12'h2af; // 29ADFF blue
        pico8_palette[13] = 12'h879; // 83769C indigo
        pico8_palette[14] = 12'hf7a; // FF77A8 pink
        pico8_palette[15] = 12'hfca; // FFCCAA peach
    end

    // Clock and reset
    reg clock_50_i;
    reg reset;

    // Generated clocks (normally from PLL, here we generate them directly)
    reg mclk;
    reg clk65;        // 64.71 MHz VGA pixel clock
    reg clk_video = 0;    // 10.78 MHz = clk65 / 6

    // VRAM signals (port A on mclk, port B on clk_video)
    reg [12:0] vaddr1_main;
    reg [1:0] vw1_main;
    reg [15:0] vdin1_main;
    wire [15:0] vdout1_main;
    wire [12:0] vaddr2_main;
    wire [15:0] vdout2_main;

    // Video buffer control
    reg vfrontreq = 1'b0;
    wire vfront;

    // Overlay control (disabled for this test)
    reg [7:0] overlay_ctrl_sys = 8'h00;

    // Video output signals
    wire [7:0] video_r, video_g, video_b;
    wire video_hs, video_vs;
    wire iblank;

    // Pixel readback interface
    reg [9:0] pixel_x;
    reg [9:0] pixel_y;
    wire [3:0] pixel_r;
    wire [3:0] pixel_g;
    wire [3:0] pixel_b;

    // VRAM instance
    vram vram_main (
        .clka(mclk),
        .wea(vw1_main),
        .addra(vaddr1_main),
        .dina(vdin1_main),
        .douta(vdout1_main),
        .clkb(clk_video),
        .web(2'b00),
        .addrb(vaddr2_main),
        .dinb(16'd0),
        .doutb(vdout2_main)
    );

    // p8video instance
    p8video p8video (
        // Clock and reset
        .mclk(mclk),
        .clk_video(clk_video),
        .reset_sys(reset),
        .reset_video(reset),

        // MMIO palette interface (tied off - not used in this test)
        .address(3'b000),
        .din(16'd0),
        .dout(),
        .nUDS(1'b1),
        .nLDS(1'b1),
        .write_en(1'b0),
        .read_en(1'b0),
        .pal_sel(1'b0),

        // Overlay control (disabled)
        .overlay_enable(overlay_ctrl_sys[6]),
        .overlay_key_colour(overlay_ctrl_sys[3:0]),

        // Screen transform (normal mode)
        .screen_transform(8'd0),

        // VRAM interface
        .vaddress_main(vaddr2_main),
        .vdin_main(vdout2_main),
        .vaddress_overlay(),  // Not used
        .vdin_overlay(16'd0),

        // Double buffering
        .vfronto(vfront),
        .vfrontreq(vfrontreq),

        // Video output
        .VSB(video_vs),
        .HS(video_hs),
        .iblank(iblank),
        .VR(video_r),
        .VG(video_g),
        .VB(video_b)
    );

    // VGA Display Model
    vga_display_model display (
        .vgaclk_i(clk65),
        .rgb_r_i(video_r[7:4]),
        .rgb_g_i(video_g[7:4]),
        .rgb_b_i(video_b[7:4]),
        .hsync_i(video_hs),
        .vsync_i(video_vs),
        .x_i(pixel_x),
        .y_i(pixel_y),
        .rgb_r_o(pixel_r),
        .rgb_g_o(pixel_g),
        .rgb_b_o(pixel_b)
    );

    // Clock generation
    // 50 MHz reference clock
    initial begin
        clock_50_i = 0;
        forever #10 clock_50_i = ~clock_50_i;
    end

    // mclk: 28 MHz (35.7ns period)
    initial begin
        mclk = 0;
        forever #17.857 mclk = ~mclk;
    end

    // clk65: 64.71 MHz VGA pixel clock (15.426ns period)
    initial begin
        clk65 = 0;
        forever #7.713 clk65 = ~clk65;
    end

    // clk_video: clk65 / 6 = 10.78 MHz (92.554ns period)
    // Phase-locked to clk65 for upscaling
    reg [2:0] clk_div_counter = 0;
    always @(posedge clk65) begin
        if (clk_div_counter == 2) begin
            clk_div_counter <= 0;
            clk_video <= ~clk_video;
        end else begin
            clk_div_counter <= clk_div_counter + 1;
        end
    end

    // Task to write palette-indexed pixel to back buffer VRAM
    // PICO-8 screen is 128x128 pixels, 4 bits per pixel (2 pixels per byte)
    // Back buffer VRAM: 8KB, addressed as 4K x 16-bit words
    // Address calculation: (y * 128 + x) / 4 (4 pixels per 16-bit word)
    // Uses VRAM port A interface via mclk
    task write_pixel;
        input [6:0] x;  // 0..127
        input [6:0] y;  // 0..127
        input [3:0] color_index;  // 0..15 palette index
        reg [12:0] word_addr;  // 13-bit word address into VRAM (0-8191)
        reg [11:0] base_addr;  // 12-bit base address within buffer
        reg [15:0] read_data;
        reg [15:0] write_data;
        integer pixel_in_word;
        begin
            // Calculate base address within buffer: (y * 128 + x) / 4
            base_addr = ((y * 128 + x) >> 2);

            // Select back buffer half based on vfront
            // Back buffer address = {~vfront, base_addr[11:0]}
            word_addr = {~vfront, base_addr};

            // Determine which nibble in the 16-bit word (0-3)
            pixel_in_word = (y * 128 + x) & 2'b11;

            // Read current word from VRAM (read-modify-write)
            vaddr1_main = word_addr;
            vw1_main = 2'b00;  // Read mode
            @(posedge mclk);
            @(posedge mclk);  // Wait for read data
            read_data = vdout1_main;

            // Modify the appropriate nibble
            // Must match p8video's pixel reading order (see p8video.vhd lines 343-354)
            write_data = read_data;
            case (pixel_in_word)
                0: write_data[11:8]  = color_index;  // px mod 4 = 0
                1: write_data[15:12] = color_index;  // px mod 4 = 1
                2: write_data[3:0]   = color_index;  // px mod 4 = 2
                3: write_data[7:4]   = color_index;  // px mod 4 = 3
            endcase

            // Write back to VRAM
            vaddr1_main = word_addr;
            vdin1_main = write_data;
            vw1_main = 2'b11;  // Write both bytes
            @(posedge mclk);
            @(posedge mclk);

            // Read it back to verify
            vaddr1_main = word_addr;
            vw1_main = 2'b00;  // Read mode
            @(posedge mclk);
            @(posedge mclk);
            if (vdout1_main !== write_data) begin
                $display("ERROR: VRAM write verification failed at pixel (%0d,%0d), address %0h: expected %0h, got %0h",
                         x, y, word_addr, write_data, vdout1_main);
                $stop;
            end

            // Return to idle state
            vaddr1_main = 13'd0;
            vdin1_main = 16'd0;
            vw1_main = 2'b00;
            @(posedge mclk);
        end
    endtask

    // Task to toggle vfrontreq (flip front/back buffers)
    task flip_buffer;
        begin
            $display("Flipping video buffers (toggling vfrontreq)...");
            vfrontreq = ~vfrontreq;
        end
    endtask

    // Task to read pixel from display and compare with expected palette color
    // PICO-8 screen is 128×128, scaled 6× to 768×768, centered horizontally on 1024×768 VGA
    // Horizontal offset: (1024 - 768) / 2 = 128 pixels
    // Vertical offset: (768 - 768) / 2 = 0 pixels
    // PICO-8 pixel (px, py) maps to VGA pixel (128 + px*6, py*6)
    task check_pixel;
        input [6:0] pico_x;  // PICO-8 X coordinate (0..127)
        input [6:0] pico_y;  // PICO-8 Y coordinate (0..127)
        input [3:0] expected_palette_idx;
        reg [11:0] expected_rgb;
        reg [11:0] actual_rgb;
        integer vga_x, vga_y;
        begin
            // Map PICO-8 coordinates to VGA coordinates
            // PICO-8 128×128 scaled 6× = 768×768, centered in 1024×768
            // Horizontal centering: (1024-768)/2 = 128 pixel offset
            vga_x = 128 + (pico_x * 6);
            vga_y = pico_y * 6;

            pixel_x = vga_x;
            pixel_y = vga_y;
            #1; // Wait for combinatorial readback

            expected_rgb = pico8_palette[expected_palette_idx];
            actual_rgb = {pixel_r, pixel_g, pixel_b};

            if (actual_rgb !== expected_rgb) begin
                $display("ERROR at PICO-8 pixel (%0d,%0d) [VGA (%0d,%0d)]: expected palette[%0d]=%03h, got %03h",
                         pico_x, pico_y, vga_x, vga_y, expected_palette_idx, expected_rgb, actual_rgb);

                // Scan around the expected location to find where the pixel actually is
                $display("Scanning for expected color %03h in VGA region [%0d:%0d, %0d:%0d]...",
                         expected_rgb, vga_x-36, vga_x+36, vga_y-36, vga_y+36);
                for (integer scan_y = vga_y - 36; scan_y <= vga_y + 36; scan_y = scan_y + 6) begin
                    for (integer scan_x = vga_x - 36; scan_x <= vga_x + 36; scan_x = scan_x + 6) begin
                        if (scan_x >= 0 && scan_x < 1024 && scan_y >= 0 && scan_y < 768) begin
                            pixel_x = scan_x;
                            pixel_y = scan_y;
                            #1;
                            if ({pixel_r, pixel_g, pixel_b} == expected_rgb) begin
                                $display("  *** Found expected color at VGA (%0d,%0d), offset from expected: dx=%0d dy=%0d",
                                         scan_x, scan_y, scan_x - vga_x, scan_y - vga_y);
                            end
                        end
                    end
                end

                $stop;
            end else begin
                $display("PASS: PICO-8 pixel (%0d,%0d) [VGA (%0d,%0d)] = palette[%0d] = %03h",
                         pico_x, pico_y, vga_x, vga_y, expected_palette_idx, actual_rgb);
            end
        end
    endtask

    // Task to wait for vsync edge (end of frame)
    task wait_vsync;
        reg vsync_prev;
        begin
            vsync_prev = video_vs;
            @(posedge clk_video);
            while (video_vs == vsync_prev) @(posedge clk_video);
            // Wait for falling edge
            while (video_vs) @(posedge clk_video);
            while (!video_vs) @(posedge clk_video);
            $display("Frame complete (vsync detected)");
        end
    endtask

    // Task to write PPM file
    task write_ppm;
        input [256*8-1:0] filename;
        integer file;
        integer x, y;
        reg [3:0] r, g, b;
        begin
            file = $fopen(filename, "w");
            if (file == 0) begin
                $display("ERROR: Could not open file %s", filename);
                $stop;
            end

            // PPM header (1024x768)
            $fwrite(file, "P3\n1024 768\n15\n");

            // Write pixel data
            for (y = 0; y < 768; y = y + 1) begin
                for (x = 0; x < 1024; x = x + 1) begin
                    pixel_x = x;
                    pixel_y = y;
                    #1; // Wait for combinatorial readback
                    $fwrite(file, "%0d %0d %0d ", pixel_r, pixel_g, pixel_b);
                end
                $fwrite(file, "\n");
            end

            $fclose(file);
            $display("Wrote PPM file: %s", filename);
        end
    endtask

    // Main test sequence
    initial begin
        $display("=== VGA Display Model Testbench ===");

        // Initialize signals
        reset = 1;
        vaddr1_main = 13'd0;
        vw1_main = 2'b00;
        vdin1_main = 16'd0;

        // Release reset after a while
        #200;
        reset = 0;
        #100;

        // Write test pattern to back buffer VRAM
        $display("Writing test pattern to back buffer VRAM...");

        // Draw horizontal color bars (16 rows of 8 pixels each)
        for (integer c = 0; c < 16; c = c + 1) begin
            for (integer y = c * 8; y < (c + 1) * 8; y = y + 1) begin
                for (integer x = 0; x < 128; x = x + 1) begin
                    write_pixel(x, y, c);
                end
            end
        end

        // Draw some specific test pixels
        write_pixel(0, 0, 7);    // White at top-left
        write_pixel(127, 0, 8);  // Red at top-right
        write_pixel(0, 127, 11); // Green at bottom-left
        write_pixel(127, 127, 12); // Blue at bottom-right

        // Flip buffers to make back buffer visible
        flip_buffer();

        $display("Waiting for VGA frames...");
        wait_vsync();
        wait_vsync(); // Wait for a complete frame to be rendered

        // Check that vfront matches vfrontreq
        if (vfront !== vfrontreq) begin
            $display("ERROR: vfront (%b) does not match vfrontreq (%b)", vfront, vfrontreq);
            $stop;
        end

        // Write PPM output
        $display("Writing PPM file...");
        write_ppm("vga_output.ppm");

        // Validate some pixels
        $display("Validating pixel colors...");
        check_pixel(0, 0, 7);      // White
        check_pixel(127, 0, 8);    // Red
        check_pixel(0, 127, 11);   // Green
        check_pixel(127, 127, 12); // Blue

        // Check color bars
        check_pixel(64, 4, 0);   // Black bar
        check_pixel(64, 12, 1);  // Dark-blue bar
        check_pixel(64, 20, 2);  // Dark-purple bar
        check_pixel(64, 116, 14); // Pink bar

        $display("=== TEST PASSED ===");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #50_000_000; // 50ms at 1ns timescale
        $display("ERROR: Simulation timeout");
        $stop;
    end

endmodule
