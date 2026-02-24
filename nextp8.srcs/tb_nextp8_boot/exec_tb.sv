//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2025 Chris January
//////////////////////////////////////////////////////////////////////////////////

module exec_tb #(
    parameter string MEM_FILE = "hello_test_rom.mem",
    parameter integer POST_TARGET = 10
) ();

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
    .MEM_FILE(MEM_FILE),
    .VERBOSE(0)
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

reg pc_monitor_enabled = 0;
reg prev_valid = 1'b0;
reg [31:0] prev_pc = 32'd0;
reg [31:0] prev_d0 = 32'd0;
reg [31:0] prev_d1 = 32'd0;
reg [31:0] prev_d2 = 32'd0;
reg [31:0] prev_d3 = 32'd0;
reg [31:0] prev_d4 = 32'd0;
reg [31:0] prev_d5 = 32'd0;
reg [31:0] prev_d6 = 32'd0;
reg [31:0] prev_d7 = 32'd0;
reg [31:0] prev_a0 = 32'd0;
reg [31:0] prev_a1 = 32'd0;
reg [31:0] prev_a2 = 32'd0;
reg [31:0] prev_a3 = 32'd0;
reg [31:0] prev_a4 = 32'd0;
reg [31:0] prev_a5 = 32'd0;
reg [31:0] prev_a6 = 32'd0;
reg [31:0] prev_a7 = 32'd0;

reg pending_wb_valid [0:15];
reg [31:0] pending_wb_data [0:15];
integer pending_i;

// Latch writeback signals for one cycle to allow settling
reg [3:0]  wb_addr_r;
reg [31:0] wb_data_r;
reg        wb_en_r;
reg        wb_en_r_prev;  // For edge detection

// Tracking for 0xffd0a write diagnostics
localparam [23:0] ADDR_FFD0A = 24'h0ffd0a;

localparam [23:0] ADDR_UART_DATA = 24'h800032;
wire uart_data_write = nextp8.cpu_wr && (nextp8.cpu_addr[23:1] == ADDR_UART_DATA[23:1]);

wire [31:0] cpu_pc_cur = nextp8.tg68k_exe_pc;
wire [31:0] cpu_d0 = nextp8.tg68k_d0;
wire [31:0] cpu_d1 = nextp8.tg68k_d1;
wire [31:0] cpu_d2 = nextp8.tg68k_d2;
wire [31:0] cpu_d3 = nextp8.tg68k_d3;
wire [31:0] cpu_d4 = nextp8.tg68k_d4;
wire [31:0] cpu_d5 = nextp8.tg68k_d5;
wire [31:0] cpu_d6 = nextp8.tg68k_d6;
wire [31:0] cpu_d7 = nextp8.tg68k_d7;
wire [31:0] cpu_a0 = nextp8.tg68k_a0;
wire [31:0] cpu_a1 = nextp8.tg68k_a1;
wire [31:0] cpu_a2 = nextp8.tg68k_a2;
wire [31:0] cpu_a3 = nextp8.tg68k_a3;
wire [31:0] cpu_a4 = nextp8.tg68k_a4;
wire [31:0] cpu_a5 = nextp8.tg68k_a5;
wire [31:0] cpu_a6 = nextp8.tg68k_a6;
wire [31:0] cpu_a7 = nextp8.tg68k_a7;
wire tg68k_wb_en = nextp8.tg68k_wb_en;
wire [3:0] tg68k_wb_addr = nextp8.tg68k_wb_addr;
wire [31:0] tg68k_wb_data = nextp8.tg68k_wb_data;

/*

PC=0xffc2->0xffc6 D0=0x0 D1=0x0 D2=0x0 D3=0x0 D4=0x0 D5=0x0 D6=0x0 D7=0x0 A0=0x80000c A1=0x0 A2=0x0 A3=0x0 A4=0x0 A5=0x0 A6=0x0 A7=0xffdec->0xffde8
PC=0xffc2->0xffc6 D0=0x0 D1=0x0 D2=0x0 D3=0x0 D4=0x0 D5=0x0 D6=0x0 D7=0x0 A0=0x80000c->0xffde8 A1=0x0 A2=0x0 A3=0x0 A4=0x0 A5=0x0 A6=0x0 A7=0xffdec->0xffde8
*/

function automatic [31:0] post_reg(input integer idx, input logic [31:0] cur_val);
    // Check pending writebacks that are now stable (from previous cycle)
    if (pending_wb_valid[idx] === 1'b1) begin
        post_reg = pending_wb_data[idx];
    end else begin
        post_reg = cur_val;
    end
endfunction

function string change_to_str(input logic [31:0] old_val, input logic [31:0] new_val);
    if (old_val == new_val) begin
        change_to_str = $sformatf("0x%0x", new_val);
    end else begin
        change_to_str = $sformatf("0x%0x->0x%0x", old_val, new_val);
    end
endfunction
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
        /*if (uart_rx_data == 8'h0a) begin
            uart_newline_count <= uart_newline_count + 1;
            if (uart_newline_count == 1 && !pc_monitor_enabled) begin
                $monitor("[$monitor] time=%0t PC=0x%x", $time, cpu_pc);
                pc_monitor_enabled <= 1;
            end
        end*/
        uart_rx_count <= uart_rx_count + 1;
        uart_data_read <= 1;
    end
end
`ifdef FOOBAR
always @(posedge nextp8.mclk) begin
    if (!pc_monitor_enabled /* && uart_data_write && nextp8.cpu_dout[7:0] == 8'h0a */) begin
        $display("[$time=%0t] Detected UART write of newline character - enabling PC monitoring - PC=0x%x", $time, cpu_pc_cur);
        pc_monitor_enabled <= 1'b1;
        prev_pc <= cpu_pc_cur;
        prev_d0 <= cpu_d0;
        prev_d1 <= cpu_d1;
        prev_d2 <= cpu_d2;
        prev_d3 <= cpu_d3;
        prev_d4 <= cpu_d4;
        prev_d5 <= cpu_d5;
        prev_d6 <= cpu_d6;
        prev_d7 <= cpu_d7;
        prev_a0 <= cpu_a0;
        prev_a1 <= cpu_a1;
        prev_a2 <= cpu_a2;
        prev_a3 <= cpu_a3;
        prev_a4 <= cpu_a4;
        prev_a5 <= cpu_a5;
        prev_a6 <= cpu_a6;
        prev_a7 <= cpu_a7;
        prev_valid <= 1'b1;
    end

    // Capture writeback signals into latches to allow settling
    wb_en_r <= tg68k_wb_en;
    wb_addr_r <= tg68k_wb_addr;
    wb_data_r <= tg68k_wb_data;

    if (pc_monitor_enabled) begin
        // Store settled values into pending array ONLY on edge of wb_en (0->1 transition)
        // to avoid storing the same writeback multiple times
        if ((wb_en_r === 1'b1) && (wb_en_r_prev === 1'b0) && !$isunknown(wb_addr_r)) begin
            pending_wb_valid[wb_addr_r] <= 1'b1;
            pending_wb_data[wb_addr_r] <= wb_data_r;
        end
        wb_en_r_prev <= wb_en_r;

        if (cpu_pc_cur !== prev_pc) begin
            if (prev_valid) begin
                $display(
                    "PC=%s D0=%s D1=%s D2=%s D3=%s D4=%s D5=%s D6=%s D7=%s A0=%s A1=%s A2=%s A3=%s A4=%s A5=%s A6=%s A7=%s",
                    change_to_str(prev_pc, cpu_pc_cur),
                    change_to_str(prev_d0, post_reg(0, cpu_d0)),
                    change_to_str(prev_d1, post_reg(1, cpu_d1)),
                    change_to_str(prev_d2, post_reg(2, cpu_d2)),
                    change_to_str(prev_d3, post_reg(3, cpu_d3)),
                    change_to_str(prev_d4, post_reg(4, cpu_d4)),
                    change_to_str(prev_d5, post_reg(5, cpu_d5)),
                    change_to_str(prev_d6, post_reg(6, cpu_d6)),
                    change_to_str(prev_d7, post_reg(7, cpu_d7)),
                    change_to_str(prev_a0, post_reg(8, cpu_a0)),
                    change_to_str(prev_a1, post_reg(9, cpu_a1)),
                    change_to_str(prev_a2, post_reg(10, cpu_a2)),
                    change_to_str(prev_a3, post_reg(11, cpu_a3)),
                    change_to_str(prev_a4, post_reg(12, cpu_a4)),
                    change_to_str(prev_a5, post_reg(13, cpu_a5)),
                    change_to_str(prev_a6, post_reg(14, cpu_a6)),
                    change_to_str(prev_a7, post_reg(15, cpu_a7))
                );
            end
            // Clear pending writebacks after displaying (they've been applied)
            for (pending_i = 0; pending_i < 16; pending_i = pending_i + 1) begin
                pending_wb_valid[pending_i] <= 1'b0;
            end
            prev_pc <= cpu_pc_cur;
            prev_d0 <= post_reg(0, cpu_d0);
            prev_d1 <= post_reg(1, cpu_d1);
            prev_d2 <= post_reg(2, cpu_d2);
            prev_d3 <= post_reg(3, cpu_d3);
            prev_d4 <= post_reg(4, cpu_d4);
            prev_d5 <= post_reg(5, cpu_d5);
            prev_d6 <= post_reg(6, cpu_d6);
            prev_d7 <= post_reg(7, cpu_d7);
            prev_a0 <= post_reg(8, cpu_a0);
            prev_a1 <= post_reg(9, cpu_a1);
            prev_a2 <= post_reg(10, cpu_a2);
            prev_a3 <= post_reg(11, cpu_a3);
            prev_a4 <= post_reg(12, cpu_a4);
            prev_a5 <= post_reg(13, cpu_a5);
            prev_a6 <= post_reg(14, cpu_a6);
            prev_a7 <= post_reg(15, cpu_a7);
            prev_valid <= 1'b1;
            for (pending_i = 0; pending_i < 16; pending_i = pending_i + 1) begin
                pending_wb_valid[pending_i] <= 1'b0;
            end
        end

        // Monitor memory writes (excludes instruction fetches)
        if (nextp8.cpu_wr && nextp8.estate == 3'b000) begin
            $display("MEM WR: addr=0x%0x data=0x%0x", nextp8.cpu_addr[23:0], nextp8.cpu_dout[15:0]);
        end

        // Monitor memory data reads (cpu_busstate == 2'b10 = read data, excludes 2'b00 = fetch)
        if (nextp8.cpu_rd && nextp8.cpu_busstate == 2'b10 && nextp8.estate == 3'b000) begin
            $display("MEM RD: addr=0x%0x data=0x%0x", nextp8.cpu_addr[23:0], nextp8.cpu_din[15:0]);
        end
    end
end
`endif
/*
// Monitor writes to address 0xffd0a with comprehensive diagnostics
// Note: ram_we_n_o and control signals toggle on negedge mclk, so detect write on negedge
reg [1:0] ffd0a_write_pending = 2'b0;
reg [15:0] ffd0a_write_data = 16'd0;
reg [1:0] ffd0a_write_byte_enables = 2'd0;
reg [20:0] sram_addr_word;

always @(negedge nextp8.mclk, posedge nextp8.sram_we_toggle_a, negedge nextp8.sram_we_toggle_a) begin
    // Detect write when it happens (negedge - first in the clock cycle)
    if (nextp8.cpu_wr && nextp8.cpu_addr[23:0] == ADDR_FFD0A) begin
        $display("WRITE 0xffd0a: PC=0x%0x data=0x%0x nUDS=%b nLDS=%b",
                 cpu_pc_cur, nextp8.cpu_dout[15:0], nextp8.cpu_ds[1], nextp8.cpu_ds[0]);
        $display("  CPU signals: cpu_mem=%b vid_mem=%b memio_rd=%b back_mem=%b",
                 nextp8.cpu_mem, nextp8.vid_mem, nextp8.memio_rd, nextp8.back_mem);
        $display("  State machine: estate=%b cpu_busstate=%b sys_wr=%b sram_access=%b",
                 nextp8.estate, nextp8.cpu_busstate, nextp8.sys_wr, nextp8.sram_access);
        $display("  SRAM WE control: sram_we_toggle_a=%b sram_we_toggle_b=%b sram_we_active=%b",
                 nextp8.sram_we_toggle_a, nextp8.sram_we_toggle_b, nextp8.sram_we_active);
        $display("  Address decode: cpu_ram=%b cpu_rom=%b", nextp8.cpu_ram, nextp8.cpu_rom);

        // Check SRAM control signals immediately (on same negedge)
        $display("  -> SRAM output signals (on negedge): ram_we_n=%b ram_cs_n=%b ram_lb_n=%b ram_ub_n=%b",
                 ram_we_n_o, ram_cs_n_o, ram_lb_n_o, ram_ub_n_o);
        sram_addr_word = (ADDR_FFD0A) >> 1;
        $display("  -> SRAM address: 0x%0x", sram_addr_word);

        if (nextp8.cpu_ds == 2'b11) begin
            $display("  -> ERROR: Both CPU byte strobes disabled (nUDS=1, nLDS=1) - write never reached SRAM control");
        end else begin
            if (ram_we_n_o == 1'b1) begin
                $display("  -> ERROR: SRAM write NOT enabled (ram_we_n=1) - nextp8_top logic failure!");
                $display("  -> Check: sram_access should be 1, sram_we_toggle signals should toggle");
            end else if (ram_cs_n_o == 1'b1) begin
                $display("  -> ERROR: SRAM chip NOT selected (ram_cs_n=1) - nextp8_top logic failure!");
            end else begin
                $display("  -> OK: SRAM write control signals were active - write entering SRAM");
            end
        end

        // Save write info for verification on posedge
        ffd0a_write_pending <= 2'b10;
        ffd0a_write_data <= nextp8.cpu_dout[15:0];
        ffd0a_write_byte_enables <= nextp8.cpu_ds;
    end
end*/

// On posedge, check if WE# and CS# complete the write cycle
/*always @(posedge nextp8.mclk, posedge nextp8.sram_we_toggle_b, negedge nextp8.sram_we_toggle_b) begin
    if (ffd0a_write_pending > 2'b00) begin
        $display("  [POSEDGE] After write: ram_we_n=%b ram_cs_n=%b ram_lb_n=%b ram_ub_n=%b",
                 ram_we_n_o, ram_cs_n_o, ram_lb_n_o, ram_ub_n_o);
        $display("  [POSEDGE] SRAM WE control: sram_we_toggle_a=%b sram_we_toggle_b=%b sram_we_active=%b",
                 nextp8.sram_we_toggle_a, nextp8.sram_we_toggle_b, nextp8.sram_we_active);


        // Check SRAM write completion condition: WE# HIGH, CS# LOW (rising edge of WE# while CS# asserted)
        if (ram_we_n_o == 1'b1 && ram_cs_n_o == 1'b0) begin
            $display("  [POSEDGE] ✓ Write cycle COMPLETE: WE# is HIGH, CS# is LOW - SRAM should have written!");
        end else if (ram_we_n_o == 1'b0 && ram_cs_n_o == 1'b0) begin
            $display("  [POSEDGE] ✗ Write cycle INCOMPLETE: WE# still LOW (0) - SRAM not triggered!");
        end else if (ram_we_n_o == 1'b1 && ram_cs_n_o == 1'b1) begin
            $display("  [POSEDGE] ✗ Write cycle ABORTED: CS# went HIGH before WE# - write cancelled!");
        end else begin
            $display("  [POSEDGE] ? Unknown state: WE#=%b CS#=%b", ram_we_n_o, ram_cs_n_o);
        end

        ffd0a_write_pending <= ffd0a_write_pending - 1;
    end
end*/

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
