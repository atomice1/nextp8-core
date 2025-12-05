//================================================================
// loader_tb.sv
// Loader Testbench
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
//==============================================================

module loader_tb ();

//Clock - 50 MHz (20 ns period)
reg clock_50_i = 0;
always #10 clock_50_i = ~clock_50_i;

// Reset signal for SD card model
reg reset = 1;
initial begin
    reset = 1;
    repeat(10) @(posedge clock_50_i);
    reset = 0;
end

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

// SD Card SPI Model
sdspi_model #(
    .LGMEMSZ(20),              // 1 MB card
    .CARDIMAGE("sdcard.img"),
    .CCS(1),                   // SDHC mode (block addressing)
    .DEBUG(1)                  // Enable debug output
) sd_card (
    .clk(clock_50_i),
    .reset(reset),
    .spi_cs_n(sd_cs0_n_o),
    .spi_clk(sd_sclk_o),
    .spi_mosi(sd_mosi_o),
    .spi_miso(sd_miso_i)
);

wire [5:0] post_code;

assign post_code = postcode_o;

parameter POST_TARGET = 25;

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
        for (int i = 0; i < uart_rx_count - 1; i = i + 1) begin
            uart_rx_buffer[i] <= uart_rx_buffer[i + 1];
        end
        uart_rx_buffer[13] <= uart_rx_data;
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
                mem[addr_i][15:7] <= data_in_i[15:7];
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
        $display("Loading loader.mem...");
        $readmemh("loader.mem", mem);
    end

endmodule
