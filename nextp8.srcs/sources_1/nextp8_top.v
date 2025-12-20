//
// nextp8 core for the ZX Spectrum Next
//
// Copyright (C) 2025 Chris January
// Derived from the Sinclair QL for the ZX Spectrum Next - KS2
// Copyright (c) 2024 Theodoulos Liontakis (Leon)
// Copyright (c) 2020 Victor Trucco
// original MiST Port of Sinclair QL
// Copyright (c) 2015 Till Harbaum <till@harbaum.org>
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

`default_nettype none

 module nextp8
(
    // Clocks
    input  wire clock_50_i,

    //SRAM (IS61WV204816BLL-10BLI)
    output wire [20:0] ram_addr_o,
    inout  wire [15:0] ram_data_io,
    output wire        ram_lb_n_o,
    output wire        ram_ub_n_o,
    output wire        ram_oe_n_o,
    output wire        ram_we_n_o,
    output wire        ram_cs_n_o,
    // output wire [ 3:0] ram_ce_n_o,

    // PS2
    inout wire ps2_clk_io,
    inout wire ps2_data_io,
    inout wire ps2_pin6_io,
    inout wire ps2_pin2_io,

    // SD Card
    output wire sd_cs0_n_o,
    output wire sd_cs1_n_o,
    output wire sd_sclk_o,
    output wire sd_mosi_o,
    input  wire sd_miso_i,

    // Joystick
    input  wire joyp1_i,
    input  wire joyp2_i,
    input  wire joyp3_i,
    input  wire joyp4_i,
    input  wire joyp6_i,
    inout wire joyp7_o,
    input  wire joyp9_i,
    output wire joysel_o,

    // Audio
    output wire audioext_l_o,
    output wire audioext_r_o,

    // K7
    input  wire ear_port_i,

    // Buttons
    input  wire btn_divmmc_n_i,
    input  wire btn_multiface_n_i,
    input  wire btn_reset_n_i,

    // Matrix keyboard
    output wire [7:0] keyb_row_o,
    input  wire [6:0] keyb_col_i,

    // I2C (RTC and HDMI)
    inout  wire i2c_scl_io,
    inout  wire i2c_sda_io,

    // VGA
    output wire [3:0] rgb_r_o,
    output wire [3:0] rgb_g_o,
    output wire [3:0] rgb_b_o,
    output wire hsync_o,
    output wire vsync_o,
    output wire vgaclk_o,
    output wire vgaclkn_o,
    //output wire csync_o,

    // HDMI
    output wire [3:0] hdmi_p_o,
    output wire [3:0] hdmi_n_o,

    // ESP
    input  wire esp_rx_i,
    output wire esp_tx_o,

    // Pi UART (via GPIO pins 14/15)
    input  wire pi_uart_rx_i,
    output wire pi_uart_tx_o,

    // XADC Analog to Digital Conversion

    input wire XADC_VP,
    input wire  XADC_VN,

    input wire  XADC_15P,
    input wire  XADC_15N,

    input wire  XADC_7P,
    input wire  XADC_7N,

    // Postcode output
    output wire [5:0] postcode_o
);


//-------------- parameters --------------------

parameter API_VERSION = 8'h00;
parameter MAJOR_VERSION = 8'h00;
parameter MINOR_VERSION = 8'h01;
parameter PATCH_VERSION = 8'h00;
parameter VERSION = {API_VERSION, MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION};

reg [15:0] params = 16'd0;
reg [5:0] post_code_cpu = 6'd3;

// -------------------------------------------------------------------------
// -------------------------- clock generation -----------------------------
// -------------------------------------------------------------------------

wire pll_locked, clk_sys, clk325, clk_tmds, clk65, mclk, clk_video;

pll pll
(
    .clk_in1   ( clock_50_i ),
    .clk_out1  ( clk_sys ),    // 11 MHz
    .clk_out2  ( clk325 ),     // 325 MHz
    .clk_out3  ( mclk ),       // 30.56 MHz
    .locked    ( pll_locked )
);

pll_hdmi pl2
(
    .clk_in1   ( clk325 ),
    .clk_out1  ( clk65 ),      // 64.71 MHz pixel clock
    .clk_out2  ( clk_tmds ),   // 323.52940 MHz TMDS clock
    .clk_out3  ( clk_video )   // 10.78 MHz video clock (64.71 MHz / 6)
);


// ---------------------------------------------------------------------------------
// -------------------------------------- reset ------------------------------------
// ---------------------------------------------------------------------------------

// -------------------------------------- reset ------------------------------------
// Button debounce logic: require button to be stable for ~12ms at 11MHz (2^17 cycles)
parameter DEBOUNCE_CNT = 17'd131071;  // ~11.9ms at 11MHz
reg [16:0] debounce_cnt = 17'd0;
reg btn_reset_n_sync = 1'b1;
reg btn_reset_n_stable = 1'b1;

always @(posedge clk_sys) begin
    if (btn_reset_n_sync != btn_reset_n_i) begin
        // Button state changed, reset counter
        debounce_cnt <= 17'd0;
        btn_reset_n_sync <= btn_reset_n_i;
    end else if (debounce_cnt != DEBOUNCE_CNT) begin
        // Count up while button is stable
        debounce_cnt <= debounce_cnt + 17'd1;
    end else begin
        // Button has been stable for full debounce period
        btn_reset_n_stable <= btn_reset_n_sync;
    end
end

// Reset generation logic
parameter RESET_CNT = 15'h0003;
reg [14:0] reset_cnt = RESET_CNT;
reg reset_reg = 1'b1;

always @(posedge clk_sys) begin
    if (!pll_locked || !btn_reset_n_stable) begin
        reset_cnt <= RESET_CNT;
        reset_reg <= 1'b1;
    end else if(reset_cnt != 15'h0) begin
        reset_cnt <= reset_cnt - 15'h1;
        reset_reg <= 1'b1;
    end else begin
        reset_reg <= 1'b0;
    end
end

wire reset = reset_reg;

// Post code priority: system status overrides CPU value when active
wire [5:0] post_code;
assign post_code = !pll_locked ? 6'd1 :       // PLL not locked
                   reset ? 6'd2 :             // in reset
                   post_code_cpu;

// Export postcode to top-level wrapper
assign postcode_o = post_code;

wire [31:0] build_timestamp;
wire cfgclk;
wire data_valid;
USR_ACCESSE2 USR_ACCESS (
    .CFGCLK(cfgclk),
    .DATA(build_timestamp),
    .DATAVALID(data_valid)
);

// ---------------------------------------------------------------------------------
// -------------------------------------- CPU --------------------------------------
// ---------------------------------------------------------------------------------

wire [31:0] cpu_addr;
wire [1:0] cpu_ds;
wire [15:0] cpu_dout;
wire [2:0] cpu_ipl = 3'b111;
wire cpu_rw;
wire [1:0] cpu_busstate;
wire cpu_rd = (cpu_busstate == 2'b00) || (cpu_busstate == 2'b10);
wire cpu_wr = (cpu_busstate == 2'b11) && !cpu_rw;
wire cpu_idle = (cpu_busstate == 2'b01);

// address decoding
wire cpu_act = cpu_rd || cpu_wr;

wire cpu_ram = cpu_addr[23:22] == 2'b00;
wire cpu_rom = 1'b0;
wire cpu_mem = cpu_ram || cpu_rom;
wire memio_rd = cpu_act && (cpu_addr[23:20] == 4'b1000);
wire p8audio_mem = memio_rd && cpu_addr[8];                              // $800100 - $8001ff
wire vid_mem = cpu_act && (cpu_addr[23:15] ==  9'b110000000);            // $c00000 - $c07fff
wire back_mem  = cpu_addr[23:13] == 11'b11000000000;                     // $c00000 - $c01fff
wire front_mem = cpu_addr[23:13] == 11'b11000000001;                     // $c02000 - $c03fff
wire overlay_back_mem  = cpu_addr[23:13] == 11'b11000000010;             // $c04000 - $c05fff
wire overlay_front_mem = cpu_addr[23:13] == 11'b11000000011;             // $c06000 - $c07fff
wire pal_mem = cpu_act && (cpu_addr[23:6]  == 18'b110000001000000000);   // $c08000 - $c0803f
wire da_mem  = cpu_act && (cpu_addr[23:14] == 10'b1100000011);           // $c0c000 - $c0ffff

reg [15:0] rdata;
reg [15:0] memio_out;
wire [15:0] vdout1_main;
wire [15:0] vdout1_overlay;

// Palette interface signals
wire [15:0] pal_dout;
wire pal_write_en;
wire pal_read_en;
reg pal_sel = 1'b0;

// Palette control signals
assign pal_write_en = pal_mem && cpu_wr;
assign pal_read_en = pal_mem && cpu_rd;

// demultiplex the various data sources
wire [15:0] cpu_din =
    memio_rd?{ memio_out}:
    cpu_mem? rdata:
    (back_mem || front_mem)? {vdout1_main} :
    (overlay_back_mem || overlay_front_mem)? {vdout1_overlay} :
    16'hffff;

TG68KdotC_Kernel #(0,0,0,0,0,0,0,1)
tg68k (
    .clk            ( mclk              ),
    .nReset         ( ~reset         ),
    .clkena_in      ( cpu_enable     ),
    .data_in        ( cpu_din        ),
    .IPL            ( cpu_ipl        ),
    .IPL_autovector ( 1'b1           ),
    .berr           ( 1'b0           ),
    .clr_berr       ( ),                  //1'b0           ),
    .CPU            ( 2'b00          ),
    .addr_out       ( cpu_addr       ),
    .data_write     ( cpu_dout       ),
    .nUDS           ( cpu_ds[1]      ),
    .nLDS           ( cpu_ds[0]      ),
    .nWr            ( cpu_rw         ),
    .busstate       ( cpu_busstate   ), // 00-> fetch code 10->read data 11->write data 01->no memaccess
    .nResetOut      (                ),
    .FC             (                )
);


//-------------- audio port --------------------

wire audioL,audioR;
assign audioext_l_o = audioL;
assign audioext_r_o = audioR;

// Digital audio signals (declare before use)
reg da_playing=0;
reg da_mono=0;
reg [15:0] da_data=16'd0;
(* ASYNC_REG = "TRUE" *) reg da_start_sys_d, da_start_sys_q;

// P8 audio output (from p8audio module below)
wire signed [7:0] p8audio_pcm_out;

// DAC audio mixing in clk_sys domain (removed - now done in clk_tmds domain)
// wire [15:0] pcm_audio_L_dac, pcm_audio_R_dac;
// assign pcm_audio_L_dac = (da_playing ? (da_mono_q ? da_data_sys_q : {da_data_sys_q[7:0], 8'd0}) : 16'd0) +
//                          {p8audio_pcm_out_sys_q, 8'd0};
// assign pcm_audio_R_dac = (da_playing ? (da_mono_q ? da_data_sys_q : {da_data_sys_q[15:8], 8'd0}) : 16'd0) +
//                          {p8audio_pcm_out_sys_q, 8'd0};

// DAC audio mixing synchronized to clk_tmds
(* ASYNC_REG = "TRUE" *) reg [15:0] pcm_audio_L_dac_2pll_d, pcm_audio_L_dac_2pll_q;
(* ASYNC_REG = "TRUE" *) reg [15:0] pcm_audio_R_dac_2pll_d, pcm_audio_R_dac_2pll_q;

// Additional CDC synchronizers for audio mixing components (clk_sys -> clk_tmds)
(* ASYNC_REG = "TRUE" *) reg da_playing_tmds_d, da_playing_tmds_q;
(* ASYNC_REG = "TRUE" *) reg da_mono_tmds_d, da_mono_tmds_q;
(* ASYNC_REG = "TRUE" *) reg [15:0] da_data_tmds_d, da_data_tmds_q;
(* ASYNC_REG = "TRUE" *) reg signed [7:0] p8audio_pcm_out_tmds_d, p8audio_pcm_out_tmds_q;
(* ASYNC_REG = "TRUE" *) reg reset_tmds_d, reset_tmds_q;

// Audio mixing in clk_tmds domain with pipelined stages
wire [15:0] pcm_audio_L_tmds, pcm_audio_R_tmds;

// Stage 1: DA audio selection (combinatorial)
wire [15:0] da_audio_L_sel = da_playing_tmds_q ? (da_mono_tmds_q ? da_data_tmds_q : {da_data_tmds_q[7:0], 8'd0}) : 16'd0;
wire [15:0] da_audio_R_sel = da_playing_tmds_q ? (da_mono_tmds_q ? da_data_tmds_q : {da_data_tmds_q[15:8], 8'd0}) : 16'd0;

// Stage 2: P8 audio extension (combinatorial)
wire [15:0] p8_audio_L_ext = {p8audio_pcm_out_tmds_q, 8'd0};
wire [15:0] p8_audio_R_ext = {p8audio_pcm_out_tmds_q, 8'd0};

// Pipeline registers for audio mixing stages
reg [15:0] da_audio_L_tmds_reg, da_audio_R_tmds_reg;
reg [15:0] p8_audio_L_tmds_reg, p8_audio_R_tmds_reg;
reg [15:0] pcm_audio_L_tmds_reg, pcm_audio_R_tmds_reg;

always @(posedge clk_tmds) begin
    if (reset_tmds_q) begin
        pcm_audio_L_dac_2pll_d <= 16'd0;
        pcm_audio_L_dac_2pll_q <= 16'd0;
        pcm_audio_R_dac_2pll_d <= 16'd0;
        pcm_audio_R_dac_2pll_q <= 16'd0;

        da_playing_tmds_d <= 1'b0;
        da_playing_tmds_q <= 1'b0;
        da_mono_tmds_d <= 1'b0;
        da_mono_tmds_q <= 1'b0;
        da_data_tmds_d <= 16'd0;
        da_data_tmds_q <= 16'd0;
        p8audio_pcm_out_tmds_d <= 8'd0;
        p8audio_pcm_out_tmds_q <= 8'd0;

        // Pipeline registers for audio mixing
        da_audio_L_tmds_reg <= 16'd0;
        da_audio_R_tmds_reg <= 16'd0;
        p8_audio_L_tmds_reg <= 16'd0;
        p8_audio_R_tmds_reg <= 16'd0;
        pcm_audio_L_tmds_reg <= 16'd0;
        pcm_audio_R_tmds_reg <= 16'd0;
    end else begin
        // Pipeline the audio mixing stages to break combinatorial path
        da_audio_L_tmds_reg <= da_audio_L_sel;
        da_audio_R_tmds_reg <= da_audio_R_sel;
        p8_audio_L_tmds_reg <= p8_audio_L_ext;
        p8_audio_R_tmds_reg <= p8_audio_R_ext;
        pcm_audio_L_tmds_reg <= da_audio_L_tmds_reg + p8_audio_L_tmds_reg;
        pcm_audio_R_tmds_reg <= da_audio_R_tmds_reg + p8_audio_R_tmds_reg;

        // Synchronize the final mixed audio
        pcm_audio_L_dac_2pll_d <= pcm_audio_L_tmds_reg;
        pcm_audio_L_dac_2pll_q <= pcm_audio_L_dac_2pll_d;
        pcm_audio_R_dac_2pll_d <= pcm_audio_R_tmds_reg;
        pcm_audio_R_dac_2pll_q <= pcm_audio_R_dac_2pll_d;

        // Synchronize the audio mixing components
        da_playing_tmds_d <= da_playing;
        da_playing_tmds_q <= da_playing_tmds_d;
        da_mono_tmds_d <= da_mono;
        da_mono_tmds_q <= da_mono_tmds_d;
        da_data_tmds_d <= da_data;
        da_data_tmds_q <= da_data_tmds_d;
        p8audio_pcm_out_tmds_d <= p8audio_pcm_out;
        p8audio_pcm_out_tmds_q <= p8audio_pcm_out_tmds_d;
    end
end

dac #(11) audioDL
(
    .clk_i  (clk_tmds),
    .res_i  (reset),
    .dac_i  (pcm_audio_L_dac_2pll_q[15:4]),
    .dac_o  (audioL)
);

dac #(11) audioDR
(
    .clk_i  (clk_tmds),
    .res_i  (reset),
    .dac_i  (pcm_audio_R_dac_2pll_q[15:4]),
    .dac_o  (audioR)
);

//------------- Digital Audio --------------

reg da_read=1'b0;
// CDC synchronizers for da_data
(* ASYNC_REG = "TRUE" *) reg [15:0] da_data_d, da_data_q;
reg [12:0] da_address=13'd0;
reg [11:0] da_cnt=12'd0;
reg [11:0] da_period=12'd500;
// CDC synchronizers for da_period
(* ASYNC_REG = "TRUE" *) reg [11:0] da_period_sys_d, da_period_sys_q;
reg da_start=0;
// CDC synchronizers for da_playing
(* ASYNC_REG = "TRUE" *) reg da_playing_d, da_playing_q;
// CDC synchronizers for da_mono
(* ASYNC_REG = "TRUE" *) reg da_mono_d, da_mono_q;
reg [1:0] da_state=0;
(* ram_style = "block" *) reg [15:0] da_memory [0:8191];
reg [15:0] da_memory_cpu_rdata; // Registered BRAM read output for CPU access

always @(posedge clk_sys) begin
    da_data <= da_memory[da_address];
end

always @(posedge mclk) begin
    da_memory_cpu_rdata <= da_memory[cpu_addr[13:1]];

    if (da_mem && cpu_wr && estate == 3'b001) begin
        if (~cpu_ds[0]) da_memory[cpu_addr[13:1]][7:0] <= cpu_dout[7:0];
        if (~cpu_ds[1]) da_memory[cpu_addr[13:1]][15:8] <= cpu_dout[15:8];
    end
end

always @(posedge clk_sys)
begin
    if (da_cnt>12'd0) begin
        da_cnt<=da_cnt-12'd1;
    end else begin
        da_cnt<=da_period_sys_q;
        case (da_state)
        2'd0: begin
            if (da_playing) da_address<=da_address+13'd1;
            da_state<=3'd2;
            end
        2'd2: begin
            if (da_start_sys_q==1'b1 && da_address==13'd0) da_playing<=1'b1;
            if (da_start_sys_q==1'b0) begin da_playing<=1'b0; da_address<=13'd0; end
            da_state<=3'd0;
        end
        endcase
    end
end

//------------- P8 Audio --------------

// P8 Audio interface signals
wire [6:0]  p8audio_address;
wire [15:0] p8audio_din;
wire [15:0] p8audio_dout;
wire        p8audio_nUDS;
wire        p8audio_nLDS;
wire        p8audio_write_en;
wire        p8audio_read_en;
// p8audio_pcm_out already declared above

// P8 Audio DMA interface
wire [30:0] p8audio_dma_addr;
wire [15:0] p8audio_dma_rdata;
wire        p8audio_dma_req;
wire        p8audio_dma_ack;

// Latched DMA request/address (captured when req pulses, cleared when serviced)
// Both p8audio and nextp8_top FSM run on mclk - same clock domain
reg         p8audio_dma_req_latched;
reg  [30:0] p8audio_dma_addr_latched;

// P8 Audio MMIO signal assignments
assign p8audio_address  = cpu_addr[7:1];  // 7-bit word address from bits 7:1
assign p8audio_din      = cpu_dout;
assign p8audio_nUDS     = cpu_ds[1];
assign p8audio_nLDS     = cpu_ds[0];
assign p8audio_write_en = p8audio_mem && cpu_wr;
assign p8audio_read_en  = p8audio_mem && cpu_rd;

// P8 Audio module instantiation
p8audio p8audio_inst (
    // Clock and reset
    .mclk       (mclk),
    .clk_pcm    (clk_pcm),          // 22.05 kHz sample clock (proper clock)
    .clk_pcm_8x (clk_pcm_8x),       // 176.4 kHz time-mux clock (proper clock)
    .resetn     (~reset),           // Active-low reset

    // MMIO interface
    .address    (p8audio_address),
    .din        (p8audio_din),
    .dout       (p8audio_dout),
    .nUDS       (p8audio_nUDS),
    .nLDS       (p8audio_nLDS),
    .write_en   (p8audio_write_en),
    .read_en    (p8audio_read_en),

    // PCM output
    .pcm_out    (p8audio_pcm_out),

    // DMA interface
    .dma_addr   (p8audio_dma_addr),
    .dma_rdata  (p8audio_dma_rdata),
    .dma_req    (p8audio_dma_req),
    .dma_ack    (p8audio_dma_ack)
);

//------------- RTC -----------------

reg i2c_ena=1'b0, i2c_rw=1'b1;
wire i2c_busy, i2c_err;
wire [7:0] i2c_din;
// CDC synchronizers for i2c_din
(* ASYNC_REG = "TRUE" *) reg [7:0] i2c_din_d, i2c_din_q;
reg [7:0] i2c_dout;
reg [6:0] i2c_adr=7'b1101000; //DS1307 address

i2c_master #( .input_clk(11000000), .bus_clk(100000) )
rtc_i2c
(
    .clk      (clk_sys),                  ///system clock
    .reset_n  (!reset),                 //active low reset
    .ena       (i2c_ena_q),             //latch in command
    .addr      (i2c_adr),               //address of target slave
    .rw        (i2c_rw_q),              //'0' is write, '1' is read
    .data_wr   (i2c_dout_q),            //data to write to slave
    .busy      (i2c_busy),              //indicates transaction in progress
    .data_rd   (i2c_din),               //data read from slave
    .ack_error (i2c_err),               //flag if improper acknowledge from slave
    .sda       (i2c_sda_io),            //serial data output of i2c bus
    .scl       (i2c_scl_io)             //serial clock output of i2c bus
);

// ---------------------------------------------------------------------------------
// -------------------------------------- KBD --------------------------------------
// ---------------------------------------------------------------------------------

wire key_ms;
assign key_ms = params[0];  //keyboard or mouse at ps/2 port
wire ps2_key_clk, ps2_key_data;

// key_ms red from configuration at init :  0 = keyboard, 1 = mouse
assign ps2_key_clk =  key_ms ? ps2_pin6_io : ps2_clk_io;
assign ps2_key_data = key_ms ? ps2_pin2_io : ps2_data_io;

wire [255:0] ps2_kbd_matrix;
wire [255:0] meb_kbd_matrix;

keyboard keyboard (
    .reset    ( reset        ),
    .clk      ( clk_sys        ),

    .ps2_clk  ( ps2_key_clk  ),
    .ps2_data ( ps2_key_data ),

    .matrix   ( ps2_kbd_matrix  )
);

//------------------------------Membrane Keyboard---------------------

mkeyboard mkeyb (
.clk      ( clk_sys ),
.reset    ( reset ),
.rows_o   ( keyb_row_o ),
.cols_i   ( keyb_col_i ),
.omatrix  ( meb_kbd_matrix )
);
//-------------------------------------------------------------------

wire [63:0] kbd_matrix;

assign kbd_matrix = ps2_kbd_matrix | meb_kbd_matrix;

// CDC synchronizers for kbd_matrix
(* ASYNC_REG = "TRUE" *) reg [63:0] kbd_matrix_d, kbd_matrix_q;

// ----------- Joystick ---------------
// Generate ~84 Hz clock for joystick polling from clk_sys(11 MHz)
// Reset synchronizer for joy_clock domain (declare before use)
(* ASYNC_REG = "TRUE" *) reg reset_joy_d, reset_joy_q;

reg [15:0] joy_clk_div;
reg joy_clk_toggle = 1'b0;

always @(posedge clk_sys or posedge reset)
begin
    if (reset) begin
        joy_clk_div <= 16'd0;
        joy_clk_toggle <= 1'b0;
    end else begin
        joy_clk_div <= joy_clk_div + 16'd1;
        if (joy_clk_div == 16'hFFFF) begin
            joy_clk_toggle <= ~joy_clk_toggle;
        end
    end
end

wire joy_clock;
BUFG BUFG_joy_clock (.I(joy_clk_toggle), .O(joy_clock));

reg [7:0] js1 = 7'd0;
// CDC synchronizers for js1
(* ASYNC_REG = "TRUE" *) reg [7:0] js1_d, js1_q;
reg [7:0] js0 = 7'd0;
// CDC synchronizers for js0
(* ASYNC_REG = "TRUE" *) reg [7:0] js0_d, js0_q;
reg joys=0;
assign joyp7_o=1'bz;
assign joysel_o=joys;

always @(posedge joy_clock or posedge reset_joy_q)
begin
    if (reset_joy_q) begin
        js0 = 7'd0;
        js1 = 7'd0;
    end else begin
        joys=~joys;
        if (joys) begin
            js1[0]=~joyp1_i;  // up
            js1[1]=~joyp2_i;  // down
            js1[2]=~joyp3_i;  // left
            js1[3]=~joyp4_i;  // right
            js1[4]=~joyp6_i;  // button 1
            js1[5]=~joyp9_i;  // button 2
        end else begin
            js0[0]=~joyp1_i;  // up
            js0[1]=~joyp2_i;  // down
            js0[2]=~joyp3_i;  // left
            js0[3]=~joyp4_i;  // right
            js0[4]=~joyp6_i;  // button 1
            js0[5]=~joyp9_i;  // button 2
        end
    end
end

// ---------------------------------------------------------------------------------
// -------------------------------------- video ------------------------------------
// ---------------------------------------------------------------------------------

reg  [12:0] vaddr1_main;
wire [12:0] vaddr2_main;
wire [15:0] vdout2_main;
reg [15:0] vdin1_main;
reg [1:0] vw1_main = 2'b00;

reg  [12:0] vaddr1_overlay;
wire [12:0] vaddr2_overlay;
wire [15:0] vdout2_overlay;
reg [15:0] vdin1_overlay;
reg [1:0] vw1_overlay = 2'b00;

reg vfrontreq=1'b0;

// overlay control register (clk_sys)
reg [7:0] overlay_ctrl_sys = 8'h00;  // [6]=enable, [3:0]=key_colour
(* ASYNC_REG = "TRUE" *) reg [7:0] overlay_ctrl_video_d, overlay_ctrl_video_q; // (clk_video)


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

vram vram_overlay (
  .clka(mclk),
  .wea(vw1_overlay),
  .addra(vaddr1_overlay),
  .dina(vdin1_overlay),
  .douta(vdout1_overlay),
  .clkb(clk_video),
  .web(2'b00),
  .addrb(vaddr2_overlay),
  .dinb(16'd0),
  .doutb(vdout2_overlay)
);


wire [7:0] video_r, video_g, video_b;

wire video_hs, video_vs;
wire iblank;
wire vfront;

// Video CDC synchronizers (clk_video -> clk_sys for VGA outputs)
(* ASYNC_REG = "TRUE" *) reg [7:0] video_r_sys_d, video_r_sys_q;
(* ASYNC_REG = "TRUE" *) reg [7:0] video_g_sys_d, video_g_sys_q;
(* ASYNC_REG = "TRUE" *) reg [7:0] video_b_sys_d, video_b_sys_q;
(* ASYNC_REG = "TRUE" *) reg video_hs_sys_d, video_hs_sys_q;
(* ASYNC_REG = "TRUE" *) reg video_vs_sys_d, video_vs_sys_q;

// Video RAM data synchronizer (RAM clk_video domain -> p8video clk_video domain)
// The RAM has synchronous outputs with 1-cycle latency, so we register the data
// to provide stable input to p8video's DDR timing logic
(* ASYNC_REG = "TRUE" *) reg [15:0] vdout2_main_d, vdout2_main_q;
(* ASYNC_REG = "TRUE" *) reg [15:0] vdout2_overlay_d, vdout2_overlay_q;

always @(posedge clk_video) begin
    if (reset) begin
        vdout2_main_d <= 16'd0;
        vdout2_overlay_d <= 16'd0;
        vdout2_main_q <= 16'd0;
        vdout2_overlay_q <= 16'd0;
        overlay_ctrl_video_d <= 8'd0;
        overlay_ctrl_video_q <= 8'd0;
    end else begin
        vdout2_main_d <= vdout2_main;
        vdout2_main_q <= vdout2_main_d;
        vdout2_overlay_d <= vdout2_overlay;
        vdout2_overlay_q <= vdout2_overlay_d;
        overlay_ctrl_video_d <= overlay_ctrl_sys;
        overlay_ctrl_video_q <= overlay_ctrl_video_d;
    end
end

p8video p8video (
    // Clock and reset
    .mclk(mclk),
    .clk_video(clk_video),
    .reset(reset),                 // Async reset

    // MMIO palette interface (clk_sys domain)
    .address(cpu_addr[3:1]),
    .din(cpu_dout),
    .dout(pal_dout),
    .nUDS(cpu_ds[1]),
    .nLDS(cpu_ds[0]),
    .write_en(pal_write_en),
    .read_en(pal_read_en),
    .pal_sel(pal_sel),

    // Overlay control (clk_video domain, already CDC'd)
    .overlay_enable(overlay_ctrl_video_q[6]),
    .overlay_key_colour(overlay_ctrl_video_q[3:0]),

    // VRAM interface (clk_video domain)
    .vaddress_main(vaddr2_main),
    .vdin_main(vdout2_main_q),
    .vaddress_overlay(vaddr2_overlay),
    .vdin_overlay(vdout2_overlay_q),

    // Double buffering interface (clk_video domain)
    .vfronto(vfront),
    .vfrontreq(vfrontreq_video_q),

    // Video output signals (clk_video domain)
    .VSB(video_vs),
    .HS(video_hs),
    .iblank(iblank),
    .VR(video_r),
    .VG(video_g),
    .VB(video_b)
    );

// Video CDC synchronizers (clk_video -> clk_sys for VGA outputs)
always @(posedge mclk) begin
    video_r_sys_d <= video_r;
    video_r_sys_q <= video_r_sys_d;
    video_g_sys_d <= video_g;
    video_g_sys_q <= video_g_sys_d;
    video_b_sys_d <= video_b;
    video_b_sys_q <= video_b_sys_d;
    video_hs_sys_d <= video_hs;
    video_hs_sys_q <= video_hs_sys_d;
    video_vs_sys_d <= video_vs;
    video_vs_sys_q <= video_vs_sys_d;
end

assign vsync_o = video_vs_sys_q;
assign hsync_o = video_hs_sys_q;
//assign csync_o = vga_csync;

assign rgb_r_o = video_r_sys_q[7:4];
assign rgb_g_o = video_g_sys_q[7:4];
assign rgb_b_o = video_b_sys_q[7:4];

// VGA clocks to latch RGB data in external DACs
// vgaclk_o clocks ADV7125 (highest 4 bits), vgaclkn_o clocks 74ALVC574 (lowest 4 bits)
// Use pixel clock for synchronous data transfer
assign vgaclk_o = clk65;
assign vgaclkn_o = ~clk65;

// -------------------------------------------------------------------------
// ---------------------- Audio Subsystem Clocks ----------------------------
// -------------------------------------------------------------------------
// Generate 176.4 kHz (clk_pcm_8x) from 11 MHz using fractional-N divider
// For a toggled clock: need 2x target frequency for toggle rate
// Required toggle rate: 352,800 / 11,000,000 = 0.0320727272...
// Phase increment: 0.0320727272 × 2^32 = 137,751,328

reg [31:0] clk_pcm_8x_phase = 32'd0;
reg clk_pcm_8x_pulse = 1'b0;
reg clk_pcm_8x_div = 1'b0;

always @(posedge clk_sys or posedge reset)
begin
    if (reset) begin
        clk_pcm_8x_phase <= 32'd0;
        clk_pcm_8x_pulse <= 1'b0;
        clk_pcm_8x_div <= 1'b0;
    end else begin
        // Add fractional increment, pulse on overflow
        // Toggle rate = 2x desired clock frequency (352.8 kHz for 176.4 kHz clock)
        {clk_pcm_8x_pulse, clk_pcm_8x_phase} <= {1'b0, clk_pcm_8x_phase} + 33'd137751328;

        // Toggle clk_pcm_8x_div to create proper 50% duty cycle clock
        if (clk_pcm_8x_pulse) begin
            clk_pcm_8x_div <= ~clk_pcm_8x_div;
        end
    end
end

// Route clk_pcm_8x through global clock buffer
wire clk_pcm_8x;
BUFG BUFG_clk_pcm_8x (.I(clk_pcm_8x_div), .O(clk_pcm_8x));

// Derive clk_pcm from clk_pcm_8x at 1:8 ratio (22.05 kHz from 176.4 kHz)
// For toggled clock: need to toggle every 4 cycles to get 1:8 frequency division
reg [1:0] clk_pcm_div_counter = 2'd0;
reg clk_pcm_div = 1'b0;

always @(posedge clk_pcm_8x or posedge reset)
begin
    if (reset) begin
        clk_pcm_div_counter <= 2'd0;
        clk_pcm_div <= 1'b0;
    end else begin
        clk_pcm_div_counter <= clk_pcm_div_counter + 2'd1;

        // Toggle every 4 clk_pcm_8x cycles (when 2-bit counter wraps)
        // This creates 1:8 frequency division (4 toggles = 8 clk_pcm_8x edges)
        if (clk_pcm_div_counter == 2'd3) begin
            clk_pcm_div <= ~clk_pcm_div;
        end
    end
end

// Route clk_pcm through global clock buffer
wire clk_pcm;
BUFG BUFG_clk_pcm (.I(clk_pcm_div), .O(clk_pcm));

// -------------------------------------------------------------------------
// ---------------- Reset Synchronizers for CDC ---------------------------
// -------------------------------------------------------------------------

// Reset synchronizer for clk_pcm domain (async reset from clk_sys)
(* ASYNC_REG = "TRUE" *) reg reset_pcm_d, reset_pcm_q;
always @(posedge clk_pcm or posedge reset) begin
    if (reset) begin
        reset_pcm_d <= 1'b1;
        reset_pcm_q <= 1'b1;
    end else begin
        reset_pcm_d <= 1'b0;
        reset_pcm_q <= reset_pcm_d;
    end
end

// Reset synchronizer for mclk domain (async reset from clk_sys)
(* ASYNC_REG = "TRUE" *) reg reset_mclk_d, reset_mclk_q;
always @(posedge mclk or posedge reset) begin
    if (reset) begin
        reset_mclk_d <= 1'b1;
        reset_mclk_q <= 1'b1;
    end else begin
        reset_mclk_d <= 1'b0;
        reset_mclk_q <= reset_mclk_d;
    end
end

// Reset synchronizer for clk_video domain (async reset from clk_sys)
(* ASYNC_REG = "TRUE" *) reg reset_325_d, reset_325_q;
always @(posedge clk_video or posedge reset) begin
    if (reset) begin
        reset_325_d <= 1'b1;
        reset_325_q <= 1'b1;
    end else begin
        reset_325_d <= 1'b0;
        reset_325_q <= reset_325_d;
    end
end

// Reset synchronizer for clk_tmds domain (async reset from clk_sys)
always @(posedge clk_tmds or posedge reset) begin
    if (reset) begin
        reset_tmds_d <= 1'b1;
        reset_tmds_q <= 1'b1;
    end else begin
        reset_tmds_d <= 1'b0;
        reset_tmds_q <= reset_tmds_d;
    end
end

// Reset synchronizer for clk65 domain (async reset from clk_sys)
(* ASYNC_REG = "TRUE" *) reg reset_65_d, reset_65_q;
always @(posedge clk65 or posedge reset) begin
    if (reset) begin
        reset_65_d <= 1'b1;
        reset_65_q <= 1'b1;
    end else begin
        reset_65_d <= 1'b0;
        reset_65_q <= reset_65_d;
    end
end

// Reset synchronizer for joy_clock domain (async reset from clk_sys)
// reset_joy_d and reset_joy_q already declared above near joystick section
always @(posedge joy_clock or posedge reset) begin
    if (reset) begin
        reset_joy_d <= 1'b1;
        reset_joy_q <= 1'b1;
    end else begin
        reset_joy_d <= 1'b0;
        reset_joy_q <= reset_joy_d;
    end
end

// Reset synchronizer for clk_video domain (async reset from clk11)
(* ASYNC_REG = "TRUE" *) reg reset_video_d, reset_video_q;
always @(posedge clk_video or posedge reset) begin
    if (reset) begin
        reset_video_d <= 1'b1;
        reset_video_q <= 1'b1;
    end else begin
        reset_video_d <= 1'b0;
        reset_video_q <= reset_video_d;
    end
end

// -------------------------------------------------------------------------
// ---------------- vfrontreq synchronizer (mclk -> clk_video) -------------
// -------------------------------------------------------------------------
(* ASYNC_REG = "TRUE" *) reg vfrontreq_video_d, vfrontreq_video_q;

always @(posedge clk_video) begin
    if (reset) begin
        vfrontreq_video_d <= 1'b0;
        vfrontreq_video_q <= 1'b0;
    end else begin
        vfrontreq_video_d <= vfrontreq;
        vfrontreq_video_q <= vfrontreq_video_d;
    end
end

// -------------------------------------------------------------------------
// --------- memory/io access and rom initialization ----------
// -------------------------------------------------------------------------

reg [20:0] raddr;
reg ramce=1'b1;
reg [15:0] rdout;
reg memio_go=1'b0;
reg ramwe=1'b1;
reg ramoe=1'b1;
reg [1:0] rds;

wire [ 1:0] sys_ds   =  ~cpu_ds;
wire [15:0] sys_dout =  cpu_dout;
wire        sys_wr   =  (cpu_wr && cpu_ram);
wire        sys_oe   =  (cpu_rd && cpu_mem);

assign ram_addr_o = raddr;
assign ram_we_n_o = ramwe;
assign ram_cs_n_o = ramce;
assign ram_oe_n_o = ramoe;
assign ram_lb_n_o = rds[0];
assign ram_ub_n_o = rds[1];
assign ram_data_io = ramwe ? 16'bZZZZZZZZZZZZZZZZ : rdout;
reg [2:0] estate =3'b000;

// cpu_enable generation: combinational logic to avoid one-cycle delay
// Must be LOW when CPU is performing memory access (not idle)
// and we're in wait states (estate 001 or early in 000)
wire cpu_enable = pll_locked && ((estate == 3'b000 && cpu_idle) || estate == 3'b010);

// P8 Audio DMA arbiter signals (depend on estate)
// Acknowledge is a single-cycle pulse in state 3'b100 (after data latched in state 011)
assign p8audio_dma_ack = (estate == 3'b100);
assign p8audio_dma_rdata = rdata;

// P8 Audio DMA request capture - latch any request pulse until serviced
// Both p8audio and FSM run on mclk (same clock domain)
always @(posedge mclk) begin
    if (!pll_locked) begin
        p8audio_dma_req_latched <= 1'b0;
        p8audio_dma_addr_latched <= 31'd0;
    end else begin
        // Latch request when it goes high
        if (p8audio_dma_req) begin
            p8audio_dma_req_latched <= 1'b1;
            p8audio_dma_addr_latched <= p8audio_dma_addr;
        end
        // Clear latched request when FSM detects it in state 000
        // Non-blocking assignment ensures FSM sees old value before it changes
        else if (p8audio_dma_req_latched && (estate == 3'b000)) begin
            p8audio_dma_req_latched <= 1'b0;
            $display("[nextp8_top] time=%0t DMA request cleared (FSM picked up in state 000)", $time);
        end
    end
end

always @(posedge mclk)
begin
    if (pll_locked)
    begin
        case (estate)
        3'b000: begin
            // P8 Audio DMA has priority - if requesting, service it first
            if (p8audio_dma_req_latched) begin
                ramce <= 1'b0;
                ramoe <= 1'b0;  // Enable read
                ramwe <= 1'b1;  // DMA is read-only
                raddr <= p8audio_dma_addr_latched[20:0];  // DMA address (word-addressed)
                rds <= 2'b00;   // Both bytes enabled
                memio_go <= 1'b0;
                estate <= 3'b011;  // DMA state
            end else begin
                // Normal CPU access - latch address when busstate changes from idle
                ramce <= 1'b0;
                ramoe <= ~sys_oe;
                raddr <= cpu_addr[21:1];
                if (back_mem)
                    vaddr1_main <= {^vfront, cpu_addr[12:1]};
                else if (front_mem)
                    vaddr1_main <= {vfront, cpu_addr[12:1]};
                if (overlay_back_mem)
                    vaddr1_overlay <= {1'b0, cpu_addr[12:1]};
                else if (overlay_front_mem)
                    vaddr1_overlay <= {1'b1, cpu_addr[12:1]};
                if (cpu_addr[5:4] == 2'b00)
                    pal_sel <= ^vfront;
                else if (cpu_addr[5:4] == 2'b01)
                    pal_sel <= vfront;
                else
                    pal_sel <= cpu_addr[4];
                rds <= cpu_ds;
                memio_go<=1'b1;
                if (sys_wr) rdout<=cpu_dout; ramwe <= ~sys_wr;
                if (cpu_idle) begin
                    // CPU idle - cpu_enable automatically HIGH (combinational)
                    estate <= 3'b000;
                end else begin
                    // CPU starting memory access - cpu_enable automatically LOW (combinational)
                    estate <= 3'b001;
                end
            end
        end
        3'b001: begin
            // Memory access in progress - data propagating from SRAM/BRAM
            if (vid_mem) begin
                if (back_mem || front_mem) begin
                    vdin1_main <= cpu_dout;
                    vw1_main <= cpu_wr ? ~cpu_ds : 2'b00;
                end else if (overlay_back_mem || overlay_front_mem) begin
                    vdin1_overlay <= cpu_dout;
                    vw1_overlay <= cpu_wr ? ~cpu_ds : 2'b00;
                end
            end
            memio_go<=1'b0;
            if (!sys_wr) rdata <= ram_data_io;
            if (da_mem && !cpu_wr) begin
                 if (~cpu_ds[0]) rdata[7:0] <= da_memory_cpu_rdata[7:0];
                 if (~cpu_ds[1]) rdata[15:8] <= da_memory_cpu_rdata[15:8];
            end
            if (pal_mem) begin
                // Palette read/write now handled by p8video module via MMIO interface
                // Just latch the read data from p8video
                if (!cpu_wr) begin
                      rdata <= pal_dout;
                 end
            end
            // cpu_enable will automatically go HIGH in state 010 (combinational)
            // TG68K samples data_in on rising_edge(clk) when clkena_in='1'
            estate<=3'b010;
            end
        3'b010: begin
            // Data valid, CPU sampled on rising edge entering this state
            // Clean up and return to idle
            ramwe <= 1'b1;
            vw1_main <= 2'b00;
            vw1_overlay <= 2'b00;
            // Keep cpu_enable HIGH - state 000 will control it based on cpu_idle
            estate<=3'b000;
             end
        3'b011: begin
            // DMA read cycle - data is valid on ram_data_io, ack asserted
            rdata <= ram_data_io;
            ramce <= 1'b1;
            ramoe <= 1'b1;
            estate <= 3'b100;
        end
        3'b100: begin
            // Complete DMA cycle
            estate <= 3'b000;
        end
        endcase
    end
    else    begin estate <=3'b000; ramce<=1'b1; ramoe <= 1'b1; end
end

//-------------- user timer -----------------

reg [31:0] utimer_1mhz=0;
// CDC synchronizers for utimer_1mhz
(* ASYNC_REG = "TRUE" *) reg [31:0] utimer_1mhz_d, utimer_1mhz_q;
reg [31:0] utimer_1khz=0;
// CDC synchronizers for utimer_1khz
(* ASYNC_REG = "TRUE" *) reg [31:0] utimer_1khz_d, utimer_1khz_q;
reg [3:0]  utcnt_1mhz=0;
reg [13:0] utcnt_1khz=0;
always @(negedge clk_sys)
begin
    if (utcnt_1mhz<4'd10) utcnt_1mhz<=utcnt_1mhz+6'd1; else begin
        utimer_1mhz <= utimer_1mhz + 31'd1;
        utcnt_1mhz<=6'd0;
    end
    if (utcnt_1khz<15'd10999) utcnt_1khz<=utcnt_1khz+6'd1; else begin
        utimer_1khz <= utimer_1khz + 31'd1;
        utcnt_1khz<=15'd0;
    end
end

//------------------- ESP UART -----------------------------------------

reg  [7:0] esp_din;
wire [7:0] esp_dout;
// CDC synchronizers for esp_dout
(* ASYNC_REG = "TRUE" *) reg [7:0] esp_dout_d, esp_dout_q;
reg esp_r,esp_w=0;
wire esp_rd,esp_dr;
// CDC synchronizers for esp_rd, esp_dr
(* ASYNC_REG = "TRUE" *) reg esp_rd_d, esp_rd_q;
(* ASYNC_REG = "TRUE" *) reg esp_dr_d, esp_dr_q;
// New: ra and wa signals with CDC synchronizers
wire esp_ra, esp_wa;
(* ASYNC_REG = "TRUE" *) reg esp_ra_d, esp_ra_q;
(* ASYNC_REG = "TRUE" *) reg esp_wa_d, esp_wa_q;
reg  [14:0] esp_div=15'd95;  // 95 = 115200 bps

UART esp_uart (
        .Tx  (esp_tx_o),
        .Rx  (esp_rx_i),
        .clk (clk_sys),
        .reset (esp_reset_q),
        .r (esp_r_q),
        .w (esp_w_q),
        .data_ready (esp_dr),
        .ready (esp_rd),
        .ra (esp_ra),
        .wa (esp_wa),
        .data_in (esp_din_q),
        .data_out (esp_dout),
        .speed (esp_div_q) // 95 = 115200 bps
    );

//------------------- Pi UART -----------------------------------------

reg  [7:0] uart_din;
wire [7:0] uart_dout;
// CDC synchronizers for uart_dout
(* ASYNC_REG = "TRUE" *) reg [7:0] uart_dout_d, uart_dout_q;
reg uart_r, uart_w;
wire uart_rd,uart_dr;
// CDC synchronizers for uart_rd, uart_dr
(* ASYNC_REG = "TRUE" *) reg uart_rd_d, uart_rd_q;
(* ASYNC_REG = "TRUE" *) reg uart_dr_d, uart_dr_q;
// New: ra and wa signals with CDC synchronizers
wire uart_ra, uart_wa;
(* ASYNC_REG = "TRUE" *) reg uart_ra_d, uart_ra_q;
(* ASYNC_REG = "TRUE" *) reg uart_wa_d, uart_wa_q;
// CDC synchronizer for UART RX input (metastability protection)
(* ASYNC_REG = "TRUE" *) reg uart_rx_sync_d, uart_rx_sync_q;
reg  [14:0] uart_div=15'd95;  // 95 = 115200 bps

UART uart (
        .Tx  (pi_uart_tx_o),
        .Rx  (uart_rx_sync_q),
        .clk (clk_sys),
        .reset (uart_reset_q),
        .r (uart_r_q),
        .w (uart_w_q),
        .data_ready (uart_dr),
        .ready (uart_rd),
        .ra (uart_ra),
        .wa (uart_wa),
        .data_in (uart_din_q),
        .data_out (uart_dout),
        .speed (uart_div_q) // 95 = 115200 bps
    );

//------------- SD card -------------------------------------

wire ql_sd_ready;
reg ql_sd_cs0_n_o=1'b1;
reg ql_sd_cs1_n_o=1'b1;
// Declare CDC synchronized versions before use
(* ASYNC_REG = "TRUE" *) reg ql_sd_cs0_n_o_d, ql_sd_cs0_n_o_q;
(* ASYNC_REG = "TRUE" *) reg ql_sd_cs1_n_o_d, ql_sd_cs1_n_o_q;
reg [7:0] qlsd_din;
reg [7:0] qlsd_div = 8'd2;
reg ql_sd_w=1'b0;
wire [7:0] qlsd_data;
// CDC synchronizers for qlsd_data
(* ASYNC_REG = "TRUE" *) reg [7:0] qlsd_data_d, qlsd_data_q;

assign sd_cs0_n_o  =  ql_sd_cs0_n_o_q;
assign sd_cs1_n_o  =  ql_sd_cs1_n_o_q;

spi qlsdspi(
    .sclko    (sd_sclk_o),
    .mosi     (sd_mosi_o),
    .miso     (sd_miso_i),
    .clk      (clk_sys),
    .reset    (reset),
    .w          (ql_sd_w_q),
    .readyo   (ql_sd_ready),
    .data_in  (qlsd_din_q),
    .data_out (qlsd_data),
    .divider  (qlsd_div_q)
);

// -------------------------------------------------------------------------
// ---------------- CDC synchronizers for mclk -> clk_sys crossings --------
// -------------------------------------------------------------------------

// ESP UART synchronizers (mclk -> clk_sys)
(* ASYNC_REG = "TRUE" *) reg [7:0] esp_din_d, esp_din_q;
(* ASYNC_REG = "TRUE" *) reg esp_r_d, esp_r_q;
(* ASYNC_REG = "TRUE" *) reg esp_w_d, esp_w_q;
(* ASYNC_REG = "TRUE" *) reg [14:0] esp_div_d, esp_div_q;
// Reset synchronizer for ESP UART (mclk -> clk_sys)
(* ASYNC_REG = "TRUE" *) reg esp_reset_d, esp_reset_q;

// Pi UART synchronizers (mclk -> clk_sys)
(* ASYNC_REG = "TRUE" *) reg [7:0] uart_din_d, uart_din_q;
(* ASYNC_REG = "TRUE" *) reg uart_r_d, uart_r_q;
(* ASYNC_REG = "TRUE" *) reg uart_w_d, uart_w_q;
(* ASYNC_REG = "TRUE" *) reg [14:0] uart_div_d, uart_div_q;
// Reset synchronizer for UART (mclk -> clk_sys)
(* ASYNC_REG = "TRUE" *) reg uart_reset_d, uart_reset_q;

// I2C synchronizers (mclk -> clk_sys)
(* ASYNC_REG = "TRUE" *) reg [7:0] i2c_dout_d, i2c_dout_q;
(* ASYNC_REG = "TRUE" *) reg i2c_rw_d, i2c_rw_q;
(* ASYNC_REG = "TRUE" *) reg i2c_ena_d, i2c_ena_q;

// SD card synchronizers (mclk -> clk_sys)
(* ASYNC_REG = "TRUE" *) reg [7:0] qlsd_din_d, qlsd_din_q;
(* ASYNC_REG = "TRUE" *) reg ql_sd_w_d, ql_sd_w_q;
(* ASYNC_REG = "TRUE" *) reg [7:0] qlsd_div_d, qlsd_div_q;
// ql_sd_cs0_n_o_q and ql_sd_cs1_n_o_q already declared above near SD card section

// DA control synchronizers (mclk -> clk_sys)
// da_start_sys_d and da_start_sys_q already declared above near audio section

// P8 audio PCM synchronizer (clk_pcm -> clk_sys)
(* ASYNC_REG = "TRUE" *) reg signed [7:0] p8audio_pcm_out_sys_d, p8audio_pcm_out_sys_q;

// Synchronization logic in clk_sys domain
always @(posedge clk_sys) begin
    if (reset) begin
        // ESP UART
        esp_din_d <= 8'd0;
        esp_din_q <= 8'd0;
        esp_r_d <= 1'b0;
        esp_r_q <= 1'b0;
        esp_w_d <= 1'b0;
        esp_w_q <= 1'b0;
        esp_div_d <= 15'd95;
        esp_div_q <= 15'd95;
        esp_reset_d <= 1'b1;
        esp_reset_q <= 1'b1;

        // Pi UART
        uart_din_d <= 8'd0;
        uart_din_q <= 8'd0;
        uart_r_d <= 1'b0;
        uart_r_q <= 1'b0;
        uart_w_d <= 1'b0;
        uart_w_q <= 1'b0;
        uart_div_d <= 15'd95;
        uart_div_q <= 15'd95;
        uart_reset_d <= 1'b1;
        uart_reset_q <= 1'b1;
        uart_rx_sync_d <= 1'b1;
        uart_rx_sync_q <= 1'b1;

        // I2C
        i2c_dout_d <= 8'd0;
        i2c_dout_q <= 8'd0;
        i2c_rw_d <= 1'b1;
        i2c_rw_q <= 1'b1;
        i2c_ena_d <= 1'b0;
        i2c_ena_q <= 1'b0;

        // SD card
        qlsd_din_d <= 8'd0;
        qlsd_din_q <= 8'd0;
        ql_sd_w_d <= 1'b0;
        ql_sd_w_q <= 1'b0;
        qlsd_div_d <= 8'd2;
        qlsd_div_q <= 8'd2;
        ql_sd_cs0_n_o_d <= 1'b1;
        ql_sd_cs0_n_o_q <= 1'b1;
        ql_sd_cs1_n_o_d <= 1'b1;
        ql_sd_cs1_n_o_q <= 1'b1;

        // DA control
        da_start_sys_d <= 1'b0;
        da_start_sys_q <= 1'b0;

        // DA period
        da_period_sys_d <= 12'd500;
        da_period_sys_q <= 12'd500;

        // P8 audio PCM
        p8audio_pcm_out_sys_d <= 8'd0;
        p8audio_pcm_out_sys_q <= 8'd0;
    end else begin
        // ESP UART
        esp_din_d <= esp_din;
        esp_din_q <= esp_din_d;
        esp_r_d <= esp_r;
        esp_r_q <= esp_r_d;
        esp_w_d <= esp_w;
        esp_w_q <= esp_w_d;
        esp_div_d <= esp_div;
        esp_div_q <= esp_div_d;
        esp_reset_d <= reset;
        esp_reset_q <= esp_reset_d;

        // Pi UART
        uart_din_d <= uart_din;
        uart_din_q <= uart_din_d;
        uart_r_d <= uart_r;
        uart_r_q <= uart_r_d;
        uart_w_d <= uart_w;
        uart_w_q <= uart_w_d;
        uart_div_d <= uart_div;
        uart_div_q <= uart_div_d;
        uart_reset_d <= reset;
        uart_reset_q <= uart_reset_d;
        uart_rx_sync_d <= pi_uart_rx_i;
        uart_rx_sync_q <= uart_rx_sync_d;

        // I2C
        i2c_dout_d <= i2c_dout;
        i2c_dout_q <= i2c_dout_d;
        i2c_rw_d <= i2c_rw;
        i2c_rw_q <= i2c_rw_d;
        i2c_ena_d <= i2c_ena;
        i2c_ena_q <= i2c_ena_d;

        // SD card
        qlsd_din_d <= qlsd_din;
        qlsd_din_q <= qlsd_din_d;
        ql_sd_w_d <= ql_sd_w;
        ql_sd_w_q <= ql_sd_w_d;
        qlsd_div_d <= qlsd_div;
        qlsd_div_q <= qlsd_div_d;
        ql_sd_cs0_n_o_d <= ql_sd_cs0_n_o;
        ql_sd_cs0_n_o_q <= ql_sd_cs0_n_o_d;
        ql_sd_cs1_n_o_d <= ql_sd_cs1_n_o;
        ql_sd_cs1_n_o_q <= ql_sd_cs1_n_o_d;

        // DA control
        da_start_sys_d <= da_start;
        da_start_sys_q <= da_start_sys_d;

        // DA period
        da_period_sys_d <= da_period;
        da_period_sys_q <= da_period_sys_d;

        // P8 audio PCM
        p8audio_pcm_out_sys_d <= p8audio_pcm_out;
        p8audio_pcm_out_sys_q <= p8audio_pcm_out_sys_d;
    end
end

// -------------------------------------------------------------------------
// ---------------- CDC synchronizers for mclk -> clk_tmds crossings --
// -------------------------------------------------------------------------

// DA mono synchronizer (mclk -> clk_tmds)
(* ASYNC_REG = "TRUE" *) reg da_mono_audio_d, da_mono_audio_q;

always @(posedge clk_tmds) begin
    if (reset) begin
        da_mono_audio_d <= 1'b0;
        da_mono_audio_q <= 1'b0;
    end else begin
        da_mono_audio_d <= da_mono;
        da_mono_audio_q <= da_mono_audio_d;
    end
end

// -------------------------------------------------------------------------
// ---------------- CDC synchronizers for clk_sys -> mclk crossings --
// -------------------------------------------------------------------------

always @(posedge mclk)
begin
    kbd_matrix_d <= kbd_matrix;
    kbd_matrix_q <= kbd_matrix_d;
    i2c_din_d <= i2c_din;
    i2c_din_q <= i2c_din_d;
    da_data_d <= da_data;
    da_data_q <= da_data_d;
    da_playing_d <= da_playing;
    da_playing_q <= da_playing_d;
    da_mono_d <= da_mono;
    da_mono_q <= da_mono_d;
    esp_dout_d <= esp_dout;
    esp_dout_q <= esp_dout_d;
    esp_rd_d <= esp_rd;
    esp_rd_q <= esp_rd_d;
    esp_dr_d <= esp_dr;
    esp_dr_q <= esp_dr_d;
    esp_ra_d <= esp_ra;
    esp_ra_q <= esp_ra_d;
    esp_wa_d <= esp_wa;
    esp_wa_q <= esp_wa_d;
    uart_dout_d <= uart_dout;
    uart_dout_q <= uart_dout_d;
    uart_rd_d <= uart_rd;
    uart_rd_q <= uart_rd_d;
    uart_dr_d <= uart_dr;
    uart_dr_q <= uart_dr_d;
    uart_ra_d <= uart_ra;
    uart_ra_q <= uart_ra_d;
    uart_wa_d <= uart_wa;
    uart_wa_q <= uart_wa_d;
    utimer_1mhz_d <= utimer_1mhz;
    utimer_1mhz_q <= utimer_1mhz_d;
    utimer_1khz_d <= utimer_1khz;
    utimer_1khz_q <= utimer_1khz_d;
    qlsd_data_d <= qlsd_data;
    qlsd_data_q <= qlsd_data_d;
    js0_d <= js0;
    js0_q <= js0_d;
    js1_d <= js1;
    js1_q <= js1_d;
end

// -------------------------------------------------------------------------
// ---------------- Memory mapped ports ------------------------------------
// -------------------------------------------------------------------------

reg [15:0] utbuf_1mhz;
reg [15:0] utbuf_1khz;
reg [31:0] debug_reg;

always @(posedge mclk)
begin
    if (memio_go && memio_rd && cpu_rd) begin  // read memory mapped ports
        if (cpu_addr[8] == 1'b0) begin
            //--------------- QLSD --------------------------------------------------
            if (cpu_addr[6:1]==6'b000011 && cpu_rd ) memio_out <= {qlsd_data_q, qlsd_data_q }; //h800006
            if (cpu_addr[6:1]==6'b000100 && cpu_rd ) memio_out <= {7'd0, ql_sd_ready, 7'd0, ql_sd_ready}; //h800008
            // ------------ video ----------------------------------------------------
            if (cpu_addr[6:1]==6'b000111 && cpu_rd && !cpu_ds[1]) memio_out <= {7'b0, vfront, 7'b0, vfront}; //h80000E
            //--------------- overlay ----------------------------------
            if (cpu_addr[6:1]==6'b001000 && cpu_rd && !cpu_ds[1]) memio_out <= {overlay_ctrl_sys, overlay_ctrl_sys}; //h800010
            //--------------- Build Info --------------------------------------------------
            if (cpu_addr[6:1]==6'b001010 && cpu_rd) memio_out <= build_timestamp[31:16]; // h800014
            if (cpu_addr[6:1]==6'b001011 && cpu_rd) memio_out <= build_timestamp[15:0]; // h800016
            if (cpu_addr[6:1]==6'b001100 && cpu_rd) memio_out <= VERSION[31:16]; // h800018
            if (cpu_addr[6:1]==6'b001101 && cpu_rd) memio_out <= VERSION[15:0]; // h80001a
            //--------------- I2C --------------------------------------------------
            if (cpu_addr[6:1]==6'b010000 && cpu_rd ) memio_out <= {i2c_din_q,i2c_din_q}; //h800021
            if (cpu_addr[6:1]==6'b010001 && cpu_rd ) memio_out <= { 14'b0, i2c_err, i2c_busy }; //h800023
            //-------------- ESP UART ----------------------------------------------------------
            if (cpu_addr[6:1]==6'b010100 && cpu_rd && !cpu_ds[0]) memio_out <= {esp_dout_q,esp_dout_q}; //h800029
            if (cpu_addr[6:1]==6'b010100 && cpu_rd && !cpu_ds[1]) memio_out <= {4'b0,esp_wa_q,esp_ra_q,esp_rd_q,esp_dr_q, 4'b0,esp_wa_q,esp_ra_q,esp_rd_q,esp_dr_q}; //h800028
            //-------------- Pi UART ----------------------------------------------------------
            if (cpu_addr[6:1]==6'b010010 && cpu_rd && !cpu_ds[0]) memio_out <= {uart_dout_q,uart_dout_q}; //h800025
            if (cpu_addr[6:1]==6'b010010 && cpu_rd && !cpu_ds[1]) memio_out <= {4'b0,uart_wa_q,uart_ra_q,uart_rd_q,uart_dr_q, 4'b0,uart_wa_q,uart_ra_q,uart_rd_q,uart_dr_q}; //h800024
            //------------- User timers -------------------------
            if (cpu_addr[6:1]==6'b010111 && cpu_rd) memio_out <= utimer_1mhz_q[31:16]; utbuf_1mhz<=utimer_1mhz_q[15:0];  //h80002E
            if (cpu_addr[6:1]==6'b011000 && cpu_rd) memio_out <= utbuf_1mhz;  //h800030
            if (cpu_addr[6:1]==6'b011001 && cpu_rd) memio_out <= utimer_1khz_q[31:16]; utbuf_1khz<=utimer_1khz_q[15:0];  //h800032
            if (cpu_addr[6:1]==6'b011010 && cpu_rd) memio_out <= utbuf_1khz;  //h800034
            //------------- digital audio -----------------------------
            if (cpu_addr[6:1]==6'b011011 && cpu_rd) memio_out <= {3'd0,da_address}; //h800036
            //------------- keyboard ----------------------------- h800040-h80005f
            if (cpu_addr[6:5]==2'b10 && cpu_rd) memio_out <= {kbd_matrix_q[{cpu_addr[4:1], 1'b0}], kbd_matrix_q[{cpu_addr[4:1], 1'b1}]};
            //------------- joystick -----------------------------
            if (cpu_addr[6:1]==6'b110000 && cpu_rd) memio_out <= {js0_q, js1_q}; //h800060
        end else begin
            //------------- P8 Audio ----------------------------- h800100-h8001FF
            if (cpu_rd) memio_out <= p8audio_dout;
        end
    end
end

always @(negedge mclk) // write memory mapped ports
begin
    if (memio_go && memio_rd && cpu_wr) begin
        if (cpu_addr[8] == 1'b0) begin
            // ------------  ql-sd io -------------------------------------------------
            if (cpu_addr[6:1]==6'b000010 && cpu_wr ) qlsd_din <= cpu_dout[7:0];    //h800004
            if (cpu_addr[6:1]==6'b000000 && cpu_wr ) ql_sd_w <= cpu_dout[0];       //h800000
            if (cpu_addr[6:1]==6'b000001 && cpu_wr ) qlsd_div <= cpu_dout[7:0];    //h800002
            if (cpu_addr[6:1]==6'b000101 && cpu_wr ) begin ql_sd_cs0_n_o <= cpu_dout[0]; ql_sd_cs1_n_o <= cpu_dout[1]; end //h80000a
            //------------- post code -------------------------------------------------------
            if (cpu_addr[6:1]==6'b000110 && cpu_wr && !cpu_ds[1] ) post_code_cpu <= cpu_dout[5:0]; //h80000C
            // ------------ video ----------------------------------------------------
            if (cpu_addr[6:1]==6'b000111 && cpu_wr && !cpu_ds[1]) vfrontreq <= cpu_dout[0]; //h80000E
            //--------------- overlay ----------------------------------
            if (cpu_addr[6:1]==6'b001000 && cpu_wr && !cpu_ds[1]) overlay_ctrl_sys <= cpu_dout[15:8]; //h800010
            // ------------ parameters -------------------------------------------------------
            if (cpu_addr[6:1]==6'b001001 && cpu_wr && !cpu_ds[0]) params[7:0] <= cpu_dout[7:0]; //h800013  bit0=key_ms
            if (cpu_addr[6:1]==6'b001001 && cpu_wr && !cpu_ds[1]) params[15:8] <= cpu_dout[15:8]; //h800012
            //-------------- RTC -------------------------------------------------------
            if (cpu_addr[6:1]==6'b010000 && cpu_wr ) i2c_dout <= cpu_dout[7:0]; //h800021
            if (cpu_addr[6:1]==6'b010001 && cpu_wr ) begin i2c_rw <= cpu_dout[1];  i2c_ena <= cpu_dout[0]; end //h800023
            //-------------- UART ------------------------------------------------------
            if (cpu_addr[6:1]==6'b010010 && cpu_wr && !cpu_ds[1]) begin uart_r <= cpu_dout[9]; uart_w <= cpu_dout[8]; end //h800024
            if (cpu_addr[6:1]==6'b010010 && cpu_wr && !cpu_ds[0]) begin uart_din <= cpu_dout[7:0]; end //h800025
            // ---------- UART baud rate divider  ------------------------------------------------------
            if (cpu_addr[6:1]==6'b010011 && cpu_wr ) begin uart_div <= cpu_dout[14:0]; end //h800026
            //-------------- ESP UART ------------------------------------------------------
            if (cpu_addr[6:1]==6'b010100 && cpu_wr && !cpu_ds[1]) begin esp_r <= cpu_dout[9]; esp_w <= cpu_dout[8]; end //h800028
            if (cpu_addr[6:1]==6'b010100 && cpu_wr && !cpu_ds[0]) begin esp_din <= cpu_dout[7:0]; end //h800029
            // ---------- esp baud rate divider  ------------------------------------------------------
            if (cpu_addr[6:1]==6'b010101 && cpu_wr ) begin esp_div <= cpu_dout[14:0]; end //h80002a
            // --------------- digital audio -----------------------------------------------------------
            if (cpu_addr[6:1]==6'b011011 && cpu_wr ) begin da_start <= cpu_dout[0]; da_mono<= cpu_dout[8]; end //h800036
            if (cpu_addr[6:1]==6'b011100 && cpu_wr ) begin da_period <= cpu_dout[11:0]; end //h800038
            //------------------ debug ------------------------------
            if (cpu_addr[6:1]==6'b110001 && cpu_wr) begin
                debug_reg[31:16] <= cpu_dout; //h800062
                $display("Debug reg hi write: %h at time %t, debug reg is now %h", cpu_dout, $time, debug_reg);
            end
            if (cpu_addr[6:1]==6'b110010 && cpu_wr) begin
                debug_reg[15:0]  <= cpu_dout; //h800064
                $display("Debug reg lo write: %h at time %t, debug reg is now %h", cpu_dout, $time, debug_reg);
            end
        end
    end
end

//------------- HDMI -------------------------------------


wire [9:0] ored,ogreen,oblue;
wire [3:0] tmds_out_p,tmds_out_n;
wire [15:0] pcm_audio_L,pcm_audio_R;

// CDC synchronizers for video signals (p8video clk_video domain -> HDMI clk65 domain)
(* ASYNC_REG = "TRUE" *) reg [7:0] video_r_d, video_r_q;
(* ASYNC_REG = "TRUE" *) reg [7:0] video_g_d, video_g_q;
(* ASYNC_REG = "TRUE" *) reg [7:0] video_b_d, video_b_q;
(* ASYNC_REG = "TRUE" *) reg iblank_d, iblank_q;
(* ASYNC_REG = "TRUE" *) reg video_hs_d, video_hs_q;
(* ASYNC_REG = "TRUE" *) reg video_vs_d, video_vs_q;

// DA mono synchronizer (mclk -> clk65)
(* ASYNC_REG = "TRUE" *) reg da_mono_65_d, da_mono_65_q;

// P8 audio PCM synchronizers (clk_pcm -> clk_sys and clk_pcm -> clk65)
(* ASYNC_REG = "TRUE" *) reg signed [7:0] p8audio_pcm_out_65_d, p8audio_pcm_out_65_q;

always @(posedge clk65) begin
    video_r_d <= video_r;
    video_r_q <= video_r_d;
    video_g_d <= video_g;
    video_g_q <= video_g_d;
    video_b_d <= video_b;
    video_b_q <= video_b_d;
    iblank_d <= iblank;
    iblank_q <= iblank_d;
    video_hs_d <= video_hs;
    video_hs_q <= video_hs_d;
    video_vs_d <= video_vs;
    video_vs_q <= video_vs_d;

    // DA mono
    da_mono_65_d <= da_mono;
    da_mono_65_q <= da_mono_65_d;

    // P8 audio PCM
    p8audio_pcm_out_65_d <= p8audio_pcm_out;
    p8audio_pcm_out_65_q <= p8audio_pcm_out_65_d;
end

// Mix digital audio (da_playing) with P8 audio (p8audio_pcm_out)
// P8 audio is mono, send to both channels
assign pcm_audio_L = (da_playing_q ? (da_mono_65_q ? da_data_q : {da_data_q[7:0], 8'd0}) : 16'd0) +
                     {p8audio_pcm_out_65_q, 8'd0};
assign pcm_audio_R = (da_playing_q ? (da_mono_65_q ? da_data_q : {da_data_q[15:8], 8'd0}) : 16'd0) +
                     {p8audio_pcm_out_65_q, 8'd0};

hdmi_out_xilinx hdmiqout (
    .clock_pixel_i     (clk65),
    .clock_tmds_i      (clk_tmds),
    .red_i    (ored),
    .green_i    (ogreen),
    .blue_i    (oblue),
    .tmds_out_p (hdmi_p_o),
    .tmds_out_n (hdmi_n_o)
);

hdmi hdmi (
    .I_CLK_PIXEL (clk65),
    .I_R             ( video_r_q ),
    .I_G             ( video_g_q ),
    .I_B             ( video_b_q ),
    .I_BLANK            ( iblank_q ),
    .I_HSYNC            ( video_hs_q ),
    .I_VSYNC          ( video_vs_q ),
    .I_AUDIO_ENABLE ( 1'b1 ),
    .I_AUDIO_PCM_L   ( pcm_audio_L ),
    .I_AUDIO_PCM_R    ( pcm_audio_R ),
    .O_RED     (ored),
    .O_GREEN (ogreen),
    .O_BLUE    (oblue)
    );


//-------------- tube -----------------

wire [7:0] tube_stdout;
wire [7:0] tube_stderr;
assign tube_stdout = (memio_go && cpu_enable && cpu_wr && {cpu_addr[23:1], 1'b0} == 24'hfffffe && !cpu_ds[1]) ? cpu_dout[15:8] : 8'dz;
assign tube_stderr = (memio_go && cpu_enable && cpu_wr && {cpu_addr[23:1], 1'b0} == 24'hfffffe && !cpu_ds[0]) ? cpu_dout[7:0] : 8'dz;

endmodule



