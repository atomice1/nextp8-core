//================================================================
// tb_nextp8_p8audio.v
//
// Copyright (C) 2025 Chris January
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//================================================================
`timescale 1ns/1ps

module tb_nextp8_p8audio;
    //====================
    // Clock
    //====================
    reg clock_50_i = 1'b0;
    always #10 clock_50_i = ~clock_50_i; // 50 MHz

    //====================
    // SRAM interface signals
    //====================
    wire [19:0] ram_addr_o;
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
    wire btn_divmmc_n_i = 1'b1;
    wire btn_multiface_n_i = 1'b1;
    wire btn_reset_n_i = 1'b1;

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

    // VGA
    wire [2:0] rgb_r_o;
    wire [2:0] rgb_g_o;
    wire [2:0] rgb_b_o;
    wire hsync_o;
    wire vsync_o;

    // HDMI
    wire [3:0] hdmi_p_o;
    wire [3:0] hdmi_n_o;

    // I2C (RTC and HDMI)
    wire i2c_scl_io;
    wire i2c_sda_io;

    // ESP
    wire esp_gpio0_io;
    wire esp_gpio2_io;
    wire esp_rx_i;
    wire esp_tx_o;
    wire esp_rtr_n_i;
    wire esp_cts_n_o;

    // PI GPIO
    wire [27:0] accel_io;

    // XADC Analog to Digital Conversion
    wire XADC_VP;
    wire XADC_VN;
    wire XADC_15P;
    wire XADC_15N;
    wire XADC_7P;
    wire XADC_7N;
    wire adc_control_o;

    // Vacant pins
    wire extras_o;
    wire extras_2_io;
    wire extras_3_io;

    //====================
    // SRAM model
    //====================
    wire read_en_i;
    wire write_en_i;
    wire [19:0] addr_i;
    wire lb_i;
    wire ub_i;
    wire [15:0] data_in_i;
    wire [15:0] data_out_o;
    wire sram_clk_i;

    assign sram_clk_i = clock_50_i;

    sram sram_inst(
        .clk_i(sram_clk_i),
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
    assign ram_data_io = ram_we_n_o ? data_out_o : 16'bz;
    assign lb_i = ~ram_lb_n_o;
    assign ub_i = ~ram_ub_n_o;
    assign read_en_i = ~ram_oe_n_o && ~ram_cs_n_o;
    assign write_en_i = ~ram_we_n_o && ~ram_cs_n_o;

    //====================
    // DUT: nextp8_top
    //====================
    nextp8 nextp8_inst(
        // Clock
        .clock_50_i(clock_50_i),
        
        //SRAM (AS7C34096)
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

        // Flash
        .flash_cs_n_o(flash_cs_n_o),
        .flash_sclk_o(flash_sclk_o),
        .flash_mosi_o(flash_mosi_o),
        .flash_miso_i(flash_miso_i),
        .flash_wp_o(flash_wp_o),
        .flash_hold_o(flash_hold_o),

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
        .audioint_o(audioint_o),

        // K7
        .ear_port_i(ear_port_i),
        .mic_port_o(mic_port_o),

        // Buttons
        .btn_divmmc_n_i(btn_divmmc_n_i),
        .btn_multiface_n_i(btn_multiface_n_i),
        .btn_reset_n_i(btn_reset_n_i),

        // Matrix keyboard
        .keyb_row_o(keyb_row_o),
        .keyb_col_i(keyb_col_i),

        // Bus
        .bus_rst_n_io(bus_rst_n_io),
        .bus_clk35_o(bus_clk35_o),
        .bus_addr_o(bus_addr_o),
        .bus_data_io(bus_data_io),
        .bus_int_n_io(bus_int_n_io),
        .bus_nmi_n_i(bus_nmi_n_i),
        .bus_ramcs_i(bus_ramcs_i),
        .bus_romcs_i(bus_romcs_i),
        .bus_wait_n_i(bus_wait_n_i),
        .bus_halt_n_o(bus_halt_n_o),
        .bus_iorq_n_o(bus_iorq_n_o),
        .bus_m1_n_o(bus_m1_n_o),
        .bus_mreq_n_o(bus_mreq_n_o),
        .bus_rd_n_io(bus_rd_n_io),
        .bus_wr_n_o(bus_wr_n_o),
        .bus_rfsh_n_o(bus_rfsh_n_o),
        .bus_busreq_n_i(bus_busreq_n_i),
        .bus_busack_n_o(bus_busack_n_o),
        .bus_iorqula_n_i(bus_iorqula_n_i),
        .bus_y_o(bus_y_o),

        // VGA
        .rgb_r_o(rgb_r_o),
        .rgb_g_o(rgb_g_o),
        .rgb_b_o(rgb_b_o),
        .hsync_o(hsync_o),
        .vsync_o(vsync_o),

        // HDMI
        .hdmi_p_o(hdmi_p_o),
        .hdmi_n_o(hdmi_n_o),

        // I2C (RTC and HDMI)
        .i2c_scl_io(i2c_scl_io),
        .i2c_sda_io(i2c_sda_io),

        // ESP
        .esp_gpio0_io(esp_gpio0_io),
        .esp_gpio2_io(esp_gpio2_io),
        .esp_rx_i(esp_rx_i),
        .esp_tx_o(esp_tx_o),
        .esp_rtr_n_i(esp_rtr_n_i),
        .esp_cts_n_o(esp_cts_n_o),

        // PI GPIO
        .accel_io(accel_io),

        // XADC Analog to Digital Conversion
        .XADC_VP(XADC_VP),
        .XADC_VN(XADC_VN),
        .XADC_15P(XADC_15P),
        .XADC_15N(XADC_15N),
        .XADC_7P(XADC_7P),
        .XADC_7N(XADC_7N),
        .adc_control_o(adc_control_o),

        // Vacant pins
        .extras_o(extras_o),
        .extras_2_io(extras_2_io),
        .extras_3_io(extras_3_io)
    );

    //====================
    // Monitor post_code from GPIO
    //====================
    wire [5:0] post_code;
    assign post_code = accel_io[27:22];

    //====================
    // PCM capture from p8audio
    //====================
    wire signed [15:0] pcm_out;
    // Extract PCM output from nextp8 p8audio instance
    assign pcm_out = nextp8_inst.p8audio_inst.pcm_out;

    //====================
    // WAV file writing
    //====================
    localparam integer WAV_SR = 22050; // Sample rate

    task wav_write_header(input integer f, input integer num_samples);
        integer bytes, br;
        begin
            bytes = num_samples * 2; // 16-bit samples
            br = WAV_SR * 2;
            $fwrite(f, "RIFF");
            $fwrite(f, "%c%c%c%c", (bytes+36)&255, ((bytes+36)>>8)&255, ((bytes+36)>>16)&255, ((bytes+36)>>24)&255);
            $fwrite(f, "WAVEfmt ");
            $fwrite(f, "%c%c%c%c", 16,0,0,0); // PCM chunk size
            $fwrite(f, "%c%c", 1,0);          // PCM format
            $fwrite(f, "%c%c", 1,0);          // channels=1
            $fwrite(f, "%c%c%c%c", WAV_SR&255,(WAV_SR>>8)&255,(WAV_SR>>16)&255,(WAV_SR>>24)&255);
            $fwrite(f, "%c%c%c%c", br&255,(br>>8)&255,(br>>16)&255,(br>>24)&255);
            $fwrite(f, "%c%c", 2,0);          // block align
            $fwrite(f, "%c%c", 16,0);         // bits per sample
            $fwrite(f, "data");
            $fwrite(f, "%c%c%c%c", bytes&255,(bytes>>8)&255,(bytes>>16)&255,(bytes>>24)&255);
        end
    endtask

    //====================
    // Test sequence
    //====================
    integer wav_file;
    integer sample_count;
    localparam integer TEST_DURATION_SAMPLES = 44100; // 2 seconds at 22050 Hz

    initial begin
        // Wait for system to come out of reset
        #10000;
        $display("[%0t] System initialized, post_code=%d", $time, post_code);
        
        // Open WAV file for PCM capture
        wav_file = $fopen("tb_nextp8_p8audio_out.wav", "wb");
        wav_write_header(wav_file, TEST_DURATION_SAMPLES);
        
        // Capture PCM samples at ~22.05 kHz
        // Monitor the clk_pcm_pulse signal from nextp8_inst
        sample_count = 0;
        while (sample_count < TEST_DURATION_SAMPLES) begin
            @(posedge nextp8_inst.clk_pcm_pulse);
            // Write little-endian PCM samples as bytes
            $fwrite(wav_file, "%c%c", pcm_out[7:0], pcm_out[15:8]);
            sample_count = sample_count + 1;
            
            // Display progress every 1000 samples
            if (sample_count % 1000 == 0) begin
                $display("Captured %0d samples, post_code=%d", sample_count, post_code);
            end
        end
        
        $fclose(wav_file);
        $display("Wrote tb_nextp8_p8audio_out.wav (%0d samples)", TEST_DURATION_SAMPLES);
        $finish;
    end

    // Monitor post code changes
    always @(post_code) begin
        $display("[$monitor] time=%0t post_code=%d", $time, post_code);
    end

endmodule

//====================
// SRAM model (from sim_1)
//====================
module sram #(
    parameter ADDR_WIDTH = 20,
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

    // Read operation (combinational)
    always @(*) begin
        if (read_en_i && ~write_en_i) begin
            data_out_o = mem[addr_i];
        end else begin
            data_out_o = 'bz; // High impedance
        end
    end

    integer i;
    initial begin
        // Initialize memory to zero
        for (i=0; i<(2**ADDR_WIDTH); i=i+1) begin
            mem[i] = 16'h0000;
        end
        
        // Load ROM from .mem file if it exists
        $display("Loading p8audio test ROM...");
        $readmemh("p8audio_test_rom.mem", mem);
        $display("ROM loaded");
    end

endmodule
