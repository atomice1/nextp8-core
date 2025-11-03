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

    //SRAM (AS7C34096)
    output wire [19:0] ram_addr_o,
    inout  wire [15:0] ram_data_io,
    output wire        ram_lb_n_o,
    output wire        ram_ub_n_o,
    output wire        ram_oe_n_o,
    output wire        ram_we_n_o,
    output wire        ram_cs_n_o, // output wire [ 3:0] ram_ce_n_o,

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

    // Flash
    output wire flash_cs_n_o,
    output wire flash_sclk_o,
    output wire flash_mosi_o,
    input  wire flash_miso_i,
    output wire flash_wp_o,
    output wire flash_hold_o,

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
    output wire audioint_o,

    // K7
    input  wire ear_port_i,
    output wire mic_port_o,

    // Buttons
    input  wire btn_divmmc_n_i,
    input  wire btn_multiface_n_i,
    input  wire btn_reset_n_i,

    // Matrix keyboard
    output wire [7:0] keyb_row_o,
    input  wire [6:0] keyb_col_i,

    // Bus
    inout  wire bus_rst_n_io,
    output wire bus_clk35_o,
    output wire [15:0] bus_addr_o,
    inout  wire [7:0] bus_data_io,
    inout  wire bus_int_n_io,
    input  wire bus_nmi_n_i,
    input  wire bus_ramcs_i,
    input  wire bus_romcs_i,
    input  wire bus_wait_n_i,
    output wire bus_halt_n_o,
    output wire bus_iorq_n_o,
    output wire bus_m1_n_o,
    output wire bus_mreq_n_o,
    inout  wire bus_rd_n_io,
    output wire bus_wr_n_o,
    output wire bus_rfsh_n_o,
    input  wire bus_busreq_n_i,
    output wire bus_busack_n_o,
    input  wire bus_iorqula_n_i,
    output wire bus_y_o,

    // VGA
    output wire [2:0] rgb_r_o,
    output wire [2:0] rgb_g_o,
    output wire [2:0] rgb_b_o,
    output wire hsync_o,
    output wire vsync_o,
    //output wire csync_o,

    // HDMI
    output wire [3:0] hdmi_p_o,
    output wire [3:0] hdmi_n_o,

    // I2C (RTC and HDMI)
    inout  wire i2c_scl_io,
    inout  wire i2c_sda_io,

    // ESP
    inout  wire esp_gpio0_io,
    inout  wire esp_gpio2_io,
    input  wire esp_rx_i,
    output wire esp_tx_o,
    input  wire esp_rtr_n_i,
    output wire esp_cts_n_o,

    // PI GPIO
    inout  wire [27:0] accel_io,

    // XADC Analog to Digital Conversion

    input wire XADC_VP,
    input wire  XADC_VN,

    input wire  XADC_15P,
    input wire  XADC_15N,

    input wire  XADC_7P,
    input wire  XADC_7N,

    output wire  adc_control_o,


    // Vacant pins
    output  wire extras_o,
    inout   wire extras_2_io,
    inout   wire extras_3_io
);


//-------------- parameters --------------------

reg [15:0] params = 16'd0;
reg [5:0] post_code = 6'd0;


// -------------------------------------------------------------------------
// -------------------------- clock generation -----------------------------
// -------------------------------------------------------------------------

wire pll_locked, clk11, clk325, clk325n, clk1625, clk65, clk1625n, mclk,clk22;

pll pll
(
    .clk_in1   ( clock_50_i ),
    .clk_out1  ( clk22 ),
    .clk_out2  ( clk11 ),
	.clk_out3  ( clk325 ),
	.clk_out4  ( clk325n ),
	.clk_out5  ( mclk ),
    .locked    ( pll_locked )
);

pll_hdmi pl2
(
    .clk_in1  ( clk325 ),
	.clk_out1  ( clk65 ),
	.clk_out2  ( clk1625 ),
	.clk_out3  ( clk1625n )
);

reg [2:0] clock_div = 3'b000;
always @(posedge clk22)
begin
    clock_div = clock_div + 3'd1;
end

wire clk2;

BUFG  BUFG_inst2 (.I (clk2i), .O (clk2));

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

wire cpu_ram = cpu_addr[23:21] == 3'b000;
wire cpu_rom = 1'b0;
wire cpu_mem = cpu_ram || cpu_rom;
wire memio_rd = cpu_act && (cpu_addr[23:20] == 4'b1000);
wire p8audio_mem = memio_rd && cpu_addr[8];                              // $800100 - $8001ff
wire da_mem  = cpu_act && (cpu_addr[23:14] == 10'b1100000011);           // $c0c000 - $c0ffff
wire vid_mem = cpu_act && (cpu_addr[23:15] ==  9'b110000000);            // $c00000 - $c07fff
wire pal_mem = cpu_act && (cpu_addr[23:4]  == 20'b11000000100000000000); // $c08000 - $c0800f
wire back_mem  = cpu_addr[23:13] == 11'b11000000000;                     // $c00000 - $c01fff
wire front_mem = cpu_addr[23:13] == 11'b11000000001;                     // $c02000 - $c03fff
wire fb_mem    = cpu_addr[23:14] == 10'b1100000001;                      // $c04000 - $c07fff

reg [15:0] rdata;
reg [15:0] memio_out;
wire [15:0] vdout1;

// demultiplex the various data sources
wire [15:0] cpu_din =
	memio_rd?{ memio_out}:
    cpu_mem? rdata:
	vid_mem? {vdout1} :
	16'hffff;

reg cpu_enable;
reg [1:0] cpu_type=2'b00;

TG68KdotC_Kernel #(2,2,2,2,2,2,2,1)
tg68k (
    .clk            ( clk2           ),
    .nReset         ( ~reset         ),
    .clkena_in      ( cpu_enable     ),
    .data_in        ( cpu_din        ),
    .IPL            ( cpu_ipl        ),
    .IPL_autovector ( 1'b1           ),
    .berr           ( 1'b0           ),
    .clr_berr       ( ),                  //1'b0           ),
    .CPU            ( cpu_type       ),   // 00=68000  // 11=68020
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

dac #(11) audioDL
(
    .clk_i  (clk22),
    .res_i  (reset),
    .dac_i  (pcm_audio_L[15:4]),
    .dac_o  (audioL)
);

dac #(11) audioDR
(
    .clk_i  (clk22),
    .res_i  (reset),
    .dac_i  (pcm_audio_R[15:4]),
    .dac_o  (audioR)
);

//------------- Digital Audio --------------

reg da_read=1'b0;
reg [15:0] da_data=16'd0;
reg [12:0] da_address=13'd0;
reg [11:0] da_cnt=12'd0;
reg [11:0] da_period=12'd500;
reg da_start=0;
reg da_playing=0;
reg da_mono=0;
reg [1:0] da_state=0;
(* ram_style = "block" *) reg [15:0] da_memory [0:8191];

always @(posedge clk11)
begin
    if (da_cnt>12'd0) begin
        da_cnt<=da_cnt-12'd1;
    end else begin
        da_cnt<=da_period;
        case (da_state)
		2'd0: begin
            da_data=da_memory[da_address];
            if (da_playing) da_address<=da_address+13'd1;
            da_state<=3'd2;
            end
        2'd2: begin
            if (da_start==1'b1 && da_address==13'd0) da_playing<=1'b1;
            if (da_start==1'b0) begin da_playing<=1'b0; da_address<=13'd0; end
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
wire signed [15:0] p8audio_pcm_out;

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
    .clk_sys    (mclk),
    .clk_pcm    (clk_pcm_pulse),    // 22.05 kHz sample clock
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
reg [7:0] i2c_dout;
reg [6:0] i2c_adr=7'b1101000; //DS1307 address

i2c_master #( .input_clk(11000000), .bus_clk(100000) )
rtc_i2c
(
    .clk      (clk11),                  ///system clock
    .reset_n  (!reset),                 //active low reset
    .ena       (i2c_ena),               //latch in command
    .addr      (i2c_adr),               //address of target slave
    .rw        (i2c_rw),                //'0' is write, '1' is read
    .data_wr   (i2c_dout),              //data to write to slave
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
    .clk      ( clk11        ),

    .ps2_clk  ( ps2_key_clk  ),
    .ps2_data ( ps2_key_data ),

    .matrix   ( ps2_kbd_matrix  )
);

//------------------------------Membrane Keyboard---------------------

mkeyboard mkeyb (
.clk      ( clk11 ),
.reset    ( reset ),
.rows_o   ( keyb_row_o ),
.cols_i   ( keyb_col_i ),
.omatrix  ( meb_kbd_matrix )
);
//-------------------------------------------------------------------

wire [63:0] kbd_matrix;

assign kbd_matrix = ps2_kbd_matrix | meb_kbd_matrix;

// ----------- Joystick ---------------

reg [11:0] joy_clk_div;
always @(posedge clk2)
    joy_clk_div <= joy_clk_div + 12'd1;
wire joy_clock = joy_clk_div[11];

reg [7:0] js1 = 7'd0;
reg [7:0] js0 = 7'd0;
reg joys=0;
assign joyp7_o=1'bz;
assign joysel_o=joys;

always @(posedge joy_clock)
begin
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

// ---------------------------------------------------------------------------------
// -------------------------------------- video ------------------------------------
// ---------------------------------------------------------------------------------

reg  [12:0] vaddr1;
wire [12:0] vaddr2;
wire [15:0] vdout2;
reg [15:0] vdin1;
reg [15:0] vdin2=16'd0;
reg [1:0] vw1,vw2=2'b00;
reg vfrontreq=1'b0;


// dual bus video ram
vram vram (
  .clka(clk325),    // input clka
  .wea(vw1),       // input [0 : 0] wea
  .addra(vaddr1),   // input [12 : 0] addra
  .dina(vdin1),    // input [15 : 0] dina
  .douta(vdout1),   // output [15 : 0] douta
  .clkb(clk325),   // input clkb
  .web(2'b00),    // input [0 : 0] web
  .addrb(vaddr2), // input [12 : 0] addrb
  .dinb(vdin2),   // input [15 : 0] dinb
  .doutb(vdout2) // output [15 : 0] doutb
);


wire [7:0] video_r, video_g, video_b;

wire video_hs, video_vs;
wire iblank;
wire vfront;

(* ram_style = "block" *) reg [4:0] screen_palette0 [0:15];
(* ram_style = "block" *) reg [4:0] screen_palette1 [0:15];

reg [4:0] i;
initial begin
    for (i = 0; i < 16; i = i + 1) begin
        screen_palette0[i] = i;
        screen_palette1[i] = i;
    end
end

// Select active palette based on vfront
wire [79:0] screen_palette_active = vfront ? 
    {screen_palette0[0],  screen_palette0[1],  screen_palette0[2],  screen_palette0[3],
     screen_palette0[4],  screen_palette0[5],  screen_palette0[6],  screen_palette0[7],
     screen_palette0[8],  screen_palette0[9],  screen_palette0[10], screen_palette0[11],
     screen_palette0[12], screen_palette0[13], screen_palette0[14], screen_palette0[15]} :
    {screen_palette1[0],  screen_palette1[1],  screen_palette1[2],  screen_palette1[3],
     screen_palette1[4],  screen_palette1[5],  screen_palette1[6],  screen_palette1[7],
     screen_palette1[8],  screen_palette1[9],  screen_palette1[10], screen_palette1[11],
     screen_palette1[12], screen_palette1[13], screen_palette1[14], screen_palette1[15]};

p8video p8video (
	.clk325(clk325),
	.reset(reset),
	.vaddress(vaddr2),
	.vdin(vdout2),
    .vfronto(vfront),
    .vfrontreq(vfrontreq),
	.VSB(video_vs),
	.HS(video_hs),
	.iblank (iblank),
	.VR(video_r),
	.VG(video_g),
	.VB(video_b),
	.screen_palette(screen_palette_active)
	);

assign vsync_o = video_vs;
assign hsync_o = video_hs;
//assign csync_o = vga_csync;

assign rgb_r_o = video_r[7:5];
assign rgb_g_o = video_g[7:5];
assign rgb_b_o = video_b[7:5];

// ---------------------------------------------------------------------------------
// -------------------------------------- reset ------------------------------------
// ---------------------------------------------------------------------------------

// parameter RESET_CNT = 15'h7FFE;
parameter RESET_CNT = 15'h0003;

reg [14:0] reset_cnt = RESET_CNT;
wire reset = (reset_cnt != 15'h0);
always @(posedge clk2) begin
    if (!pll_locked  || !btn_reset_n_i)
        reset_cnt <= RESET_CNT;
    else if(reset_cnt != 15'h0)
        reset_cnt <= reset_cnt - 15'h1;
end

// -------------------------------------------------------------------------
// ---------------------- Audio Subsystem Clock (22.05 kHz) ----------------
// -------------------------------------------------------------------------
// Generate 22.05 kHz from 22 MHz using fractional-N divider (phase accumulator)
// Required ratio: 22,050 / 22,000,000 = 0.0010022727...
// Phase increment: 0.0010022727 × 2^32 = 4,304,728.585 ≈ 4,304,729

reg [31:0] clk_pcm_phase = 32'd0;
reg clk_pcm_pulse = 1'b0;

always @(posedge clk22 or posedge reset)
begin
    if (reset) begin
        clk_pcm_phase <= 32'd0;
        clk_pcm_pulse <= 1'b0;
    end else begin
        // Add fractional increment, pulse on overflow
        {clk_pcm_pulse, clk_pcm_phase} <= {1'b0, clk_pcm_phase} + 33'd4304729;
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

wire [24:0] sys_addr =  { 4'd0, cpu_addr[20:1]};
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
reg clk2i=1'b0;

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
			$display("[nextp8_top] time=%0t DMA request captured: addr=0x%05h, estate=%b", 
			         $time, p8audio_dma_addr[19:0], estate);
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
		if (!cpu_enable) post_code <= 6'd2;
		case (estate)
		3'b000: begin
			// P8 Audio DMA has priority - if requesting, service it first
			if (p8audio_dma_req_latched) begin
				$display("[nextp8_top] time=%0t DMA servicing in state 000: addr=0x%05h, setting up read", $time, p8audio_dma_addr_latched[19:0]);
				cpu_enable <= 1'b0;  // Stall CPU
				ramce <= 1'b0;
				ramoe <= 1'b0;  // Enable read
				ramwe <= 1'b1;  // DMA is read-only
				raddr <= p8audio_dma_addr_latched[19:0];  // DMA address (word-addressed)
				rds <= 2'b00;   // Both bytes enabled
				clk2i <= 1'b0;
				memio_go <= 1'b0;
				estate <= 3'b011;  // DMA state
			end else begin
				// Normal CPU access
				cpu_enable <= 1'b1;
				ramce <= 1'b0;
				ramoe <= ~sys_oe;
				raddr <= sys_addr[19:0];
				clk2i<=1'b0;
				if (back_mem)
					vaddr1 <= {^vfront, cpu_addr[12:1]};
				else if (front_mem)
					vaddr1 <= {vfront, cpu_addr[12:1]};
				else if (fb_mem)
					vaddr1 <= cpu_addr[13:1];
				rds <= cpu_ds;
				memio_go<=1'b0;
				if (cpu_idle) estate<=3'b010; else estate<=3'b001; //skip cycles when cpu idle
				if (sys_wr) rdout<=cpu_dout; ramwe <= ~sys_wr;
				estate<=3'b001;
			end
		end
		3'b001: begin
			if (vid_mem) begin vdin1=cpu_dout; vw1 <= cpu_wr ? ~cpu_ds : 2'b00; end
			memio_go<=1'b1;
			if (!sys_wr) rdata <= ram_data_io;
			if (da_mem) begin
			     if (cpu_wr) begin
			          if (~cpu_ds[0]) da_memory[cpu_addr[13:1]][7:0]<=cpu_dout[7:0];
			          if (~cpu_ds[1]) da_memory[cpu_addr[13:1]][15:8]<=cpu_dout[15:8];
			     end else begin
			          if (~cpu_ds[0]) rdata[7:0] <= da_memory[cpu_addr[13:1]][7:0];
			          if (~cpu_ds[1]) rdata[15:9] <= da_memory[cpu_addr[13:1]][15:8];
			     end
			end
			if (pal_mem) begin
                if (cpu_wr) begin
			          // Write to inactive palette (opposite of vfront)
			          if (~vfront) begin
			              if (~cpu_ds[0]) screen_palette1[{cpu_addr[3:1], 1'b1}]<={cpu_dout[7],  cpu_dout[3:0]};
			              if (~cpu_ds[1]) screen_palette1[{cpu_addr[3:1], 1'b0}]<={cpu_dout[15], cpu_dout[11:8]};
			          end else begin
			              if (~cpu_ds[0]) screen_palette0[{cpu_addr[3:1], 1'b1}]<={cpu_dout[7],  cpu_dout[3:0]};
			              if (~cpu_ds[1]) screen_palette0[{cpu_addr[3:1], 1'b0}]<={cpu_dout[15], cpu_dout[11:8]};
			          end
			     end else begin
			          // Read from inactive palette (opposite of vfront)
			          if (~vfront) begin
			              if (~cpu_ds[0]) rdata[7:0]  <= {screen_palette1[{cpu_addr[3:1], 1'b1}][4], 3'b000, screen_palette1[{cpu_addr[3:1], 1'b1}][3:0]};
			              if (~cpu_ds[1]) rdata[15:9] <= {screen_palette1[{cpu_addr[3:1], 1'b0}][4], 3'b000, screen_palette1[{cpu_addr[3:1], 1'b0}][3:0]};
			          end else begin
			              if (~cpu_ds[0]) rdata[7:0]  <= {screen_palette0[{cpu_addr[3:1], 1'b1}][4], 3'b000, screen_palette0[{cpu_addr[3:1], 1'b1}][3:0]};
			              if (~cpu_ds[1]) rdata[15:9] <= {screen_palette0[{cpu_addr[3:1], 1'b0}][4], 3'b000, screen_palette0[{cpu_addr[3:1], 1'b0}][3:0]};
			          end
			     end
			end
			estate<=3'b010;
			end
		3'b010: begin
		    clk2i<=1'b1;
			ramwe <= 1'b1; vw1 <= 2'b00;
		    estate<=3'b000;
			 end
		3'b011: begin
			// DMA read cycle - data is valid on ram_data_io, ack asserted
			$display("[nextp8_top] time=%0t State 011: raddr=0x%05h, ramce=%b, ramoe=%b, ramwe=%b, ram_data_io=0x%04h, ack=%b, addr=0x%05h", 
			         $time, raddr, ramce, ramoe, ramwe, ram_data_io, p8audio_dma_ack, p8audio_dma_addr[19:0]);
            rdata <= ram_data_io;
			ramce <= 1'b1;
			ramoe <= 1'b1;
			estate <= 3'b100;
		end
        3'b100: begin
			$display("[nextp8_top] time=%0t State 100: addr=0x%05h, ramce=%b, ramoe=%b, ramwe=%b, ram_data_io=0x%04h, ack=%b, addr=0x%05h", 
			         $time, raddr, ramce, ramoe, ramwe, ram_data_io, p8audio_dma_ack, p8audio_dma_addr[19:0]);
            // Complete DMA cycle
            estate <= 3'b000;
        end
/*        3'b101: begin
			$display("[nextp8_top] time=%0t State 101: addr=0x%05h, ramce=%b, ramoe=%b, ramwe=%b, ram_data_io=0x%04h, ack=%b, addr=0x%05h", 
			         $time, raddr, ramce, ramoe, ramwe, ram_data_io, p8audio_dma_ack, p8audio_dma_addr[19:0]);
            // Complete DMA cycle
            estate <= 3'b000;
        end*/
		endcase
	end
	else	begin cpu_enable <= 1'b0; estate <=3'b000; ramce<=1'b1; clk2i<=1'b0; ramoe <= 1'b1; post_code <= 6'd1; reset_cnt = RESET_CNT; end
end

//-------------- user timer -----------------

reg [31:0] utimer_1mhz=0;
reg [31:0] utimer_1khz=0;
reg [5:0]  utcnt_1mhz=0;
reg [14:0] utcnt_1khz=0;
always @(negedge clk22)
begin
    if (utcnt_1mhz<6'd21) utcnt_1mhz<=utcnt_1mhz+6'd1; else begin
        utimer_1mhz <= utimer_1mhz + 31'd1;
        utcnt_1mhz<=6'd0;
    end
    if (utcnt_1khz<15'd21999) utcnt_1khz<=utcnt_1khz+6'd1; else begin
        utimer_1khz <= utimer_1khz + 31'd1;
        utcnt_1khz<=15'd0;
    end
end

//------------------- ESP UART -----------------------------------------

reg  [7:0] esp_din;
wire [7:0] esp_dout;
reg esp_r,esp_w=0;
wire esp_rd,esp_dr;
reg  [14:0] esp_div=15'd191;  // 191 = 115200 bps

UART esp_uart (
		.Tx  (esp_tx_o),
		.Rx  (esp_rx_i),
		.clk (clk22),
		.reset (reset),
		.r (esp_r),
		.w (esp_w),
		.data_ready (esp_dr),
		.ready (esp_rd),
		.data_in (esp_din),
		.data_out (esp_dout),
		.speed (esp_div) // 191 = 115200 bps
	);

//------------- SD card -------------------------------------

wire ql_sd_ready;
reg ql_sd_cs0_n_o=1'b1;
reg ql_sd_cs1_n_o=1'b1;
reg [7:0] qlsd_din;
reg [7:0] qlsd_div = 8'd2;
reg ql_sd_w=1'b0;
wire [7:0] qlsd_data;

assign sd_cs0_n_o  =  ql_sd_cs0_n_o;
assign sd_cs1_n_o  =  ql_sd_cs1_n_o;

spi qlsdspi(
	.sclko    (sd_sclk_o),
	.mosi     (sd_mosi_o),
	.miso     (sd_miso_i),
	.clk      (clk325n),
	.reset    (reset),
	.w		  (ql_sd_w),
	.readyo   (ql_sd_ready),
	.data_in  (qlsd_din),
	.data_out (qlsd_data),
	.divider  (qlsd_div)
);

// -------------------------------------------------------------------------
// ---------------- Memory mapped ports ------------------------------------
// -------------------------------------------------------------------------

reg [15:0] utbuf_1mhz;
reg [15:0] utbuf_1khz;
reg [31:0] debug_reg;

always @(posedge memio_go)
begin
	if (memio_rd) begin  // read memory mapped ports
        if (cpu_addr[8] == 1'b0) begin
            // ------------ video ----------------------------------------------------
            if (cpu_addr[6:1]==6'b000111 && cpu_rd && !cpu_ds[1]) memio_out={7'b0, vfront, 7'b0, vfront}; //h80000E
            //--------------- QLSD --------------------------------------------------
            if (cpu_addr[6:1]==6'b000011 && cpu_rd ) memio_out <= {qlsd_data, qlsd_data }; //h800006
            if (cpu_addr[6:1]==6'b000100 && cpu_rd ) memio_out <= {7'd0, ql_sd_ready, 7'd0, ql_sd_ready}; //h800008
            //------------- RTC -------------------------------------------------------
            if (cpu_addr[6:1]==6'b010000 && cpu_rd ) memio_out <= {i2c_din,i2c_din}; //h800021
            if (cpu_addr[6:1]==6'b010001 && cpu_rd ) memio_out <= { 14'b0, i2c_err, i2c_busy }; //h800023
            //-------------- ESP UART ----------------------------------------------------------
            if (cpu_addr[6:1]==6'b010010 && cpu_rd && !cpu_ds[0]) memio_out <= {esp_dout,esp_dout}; //h800025
            if (cpu_addr[6:1]==6'b010010 && cpu_rd && !cpu_ds[1]) memio_out <= {6'b0,esp_rd,esp_dr, 6'b0,esp_rd,esp_dr}; //h800024
            //------------- User timers -------------------------
            if (cpu_addr[6:1]==6'b010111 && cpu_rd) memio_out <= utimer_1mhz[31:16]; utbuf_1mhz<=utimer_1mhz[15:0];  //h80002E
            if (cpu_addr[6:1]==6'b011000 && cpu_rd) memio_out <= utbuf_1mhz;  //h800030
            if (cpu_addr[6:1]==6'b011001 && cpu_rd) memio_out <= utimer_1khz[31:16]; utbuf_1khz<=utimer_1khz[15:0];  //h800032
            if (cpu_addr[6:1]==6'b011010 && cpu_rd) memio_out <= utbuf_1khz;  //h800034
            //------------- digital audio -----------------------------
            if (cpu_addr[6:1]==6'b011011 && cpu_rd) memio_out <= {3'd0,da_address}; //h800036
            //------------- keyboard ----------------------------- h800040-h80005f
            if (cpu_addr[6:5]==2'b10 && cpu_rd && !cpu_ds[1]) memio_out <= kbd_matrix[{cpu_addr[4:1], 1'b0}];
            if (cpu_addr[6:5]==2'b10 && cpu_rd && !cpu_ds[0]) memio_out <= kbd_matrix[{cpu_addr[4:1], 1'b1}];
            //------------- joystick -----------------------------
            if (cpu_addr[6:1]==6'b110000 && cpu_rd && !cpu_ds[1]) memio_out <= js0; //h800060
            if (cpu_addr[6:1]==6'b110000 && cpu_rd && !cpu_ds[0]) memio_out <= js1; //h800061
        end else begin
		    //------------- P8 Audio ----------------------------- h800100-h8001FF
		    if (cpu_rd) memio_out <= p8audio_dout;
        end
	end
end

always @(negedge memio_go) // write memory mapped ports
begin
	if (memio_rd) begin
        if (cpu_addr[8] == 1'b0) begin
            // ------------  ql-sd io -------------------------------------------------
            if (cpu_addr[6:1]==6'b000010 && cpu_wr ) qlsd_din <= cpu_dout[7:0];    //h800004
            if (cpu_addr[6:1]==6'b000000 && cpu_wr ) ql_sd_w <= cpu_dout[0];       //h800000
            if (cpu_addr[6:1]==6'b000001 && cpu_wr ) qlsd_div <= cpu_dout[7:0];    //h800002
            if (cpu_addr[6:1]==6'b000101 && cpu_wr ) begin ql_sd_cs0_n_o <= cpu_dout[0]; ql_sd_cs1_n_o <= cpu_dout[1]; end //h80000a
            //------------- post code -------------------------------------------------------
            if (cpu_addr[6:1]==6'b000110 && cpu_wr && !cpu_ds[1] ) post_code <= cpu_dout[5:0]; //h80000C
            // ------------ video ----------------------------------------------------
            if (cpu_addr[6:1]==6'b000111 && cpu_wr && !cpu_ds[1]) vfrontreq <= cpu_dout[0]; //h80000E
            // ------------ parameters -------------------------------------------------------
            if (cpu_addr[6:1]==6'b001001 && cpu_wr && !cpu_ds[0]) params[7:0] <= cpu_dout[7:0]; //h800013  bit0=key_ms
            if (cpu_addr[6:1]==6'b001001 && cpu_wr && !cpu_ds[1]) params[15:8] <= cpu_dout[15:8]; //h800012
            //-------------- RTC -------------------------------------------------------
            if (cpu_addr[6:1]==6'b010000 && cpu_wr ) i2c_dout <= cpu_dout[7:0]; //h800021
            if (cpu_addr[6:1]==6'b010001 && cpu_wr ) begin i2c_rw <= cpu_dout[1];  i2c_ena <= cpu_dout[0]; end //h800023
            //-------------- UART ------------------------------------------------------
            if (cpu_addr[6:1]==6'b010010 && cpu_wr && !cpu_ds[1]) begin esp_r <= cpu_dout[9]; esp_w <= cpu_dout[8]; end //h800024
            if (cpu_addr[6:1]==6'b010010 && cpu_wr && !cpu_ds[0]) begin esp_din <= cpu_dout[7:0]; end //h800025
            // ---------- esp baud rate divider  ------------------------------------------------------
            if (cpu_addr[6:1]==6'b010110 && cpu_wr ) begin esp_div <= cpu_dout[14:0]; end //h80002C   8388652
            // --------------- digital audio -----------------------------------------------------------
            if (cpu_addr[6:1]==6'b011011 && cpu_wr ) begin da_start <= cpu_dout[0]; da_mono<= cpu_dout[8]; end //h800036
            if (cpu_addr[6:1]==6'b011100 && cpu_wr ) begin da_period <= cpu_dout[11:0]; end //h800038
            //------------------ CPU ------------------------------
            if (cpu_addr[6:1]==6'b011111 && cpu_wr ) begin cpu_type <= cpu_dout[1:0]; end //h80003E 8388670-1
            //------------------ debug ------------------------------
            if (cpu_addr[6:1]==6'b110001 && cpu_wr) debug_reg[31:16] <= cpu_dout; //h800062
            if (cpu_addr[6:1]==6'b110010 && cpu_wr) debug_reg[15:0]  <= cpu_dout; //h800064
        end
	end
end

//------------- HDMI -------------------------------------


wire [9:0] ored,ogreen,oblue;
wire [3:0] tmds_out_p,tmds_out_n;
wire [15:0] pcm_audio_L,pcm_audio_R;

// Mix digital audio (da_playing) with P8 audio (p8audio_pcm_out)
// P8 audio is mono, send to both channels
assign pcm_audio_L = (da_playing ? (da_mono ? da_data : {da_data[7:0], 8'd0}) : 16'd0) + 
                     p8audio_pcm_out;
assign pcm_audio_R = (da_playing ? (da_mono ? da_data : {da_data[15:8], 8'd0}) : 16'd0) + 
                     p8audio_pcm_out;

hdmi_out_xilinx hdmiqout (
	.clock_pixel_i 	(clk65),
	.clock_tmds_i  	(clk1625),
	.clock_tmds_n_i (clk1625n),
	.red_i	(ored),
	.green_i	(ogreen),
	.blue_i	(oblue),
	.tmds_out_p (hdmi_p_o),
	.tmds_out_n (hdmi_n_o)
);

hdmi hdmi (
	.I_CLK_PIXEL (clk65),
	.I_R         	( video_r ),
	.I_G         	( video_g ),
	.I_B         	( video_b ),
	.I_BLANK			( iblank ),
	.I_HSYNC			( video_hs ),
	.I_VSYNC      	( video_vs ),
	.I_AUDIO_ENABLE ( 1'b1 ),
	.I_AUDIO_PCM_L   ( pcm_audio_L ),
	.I_AUDIO_PCM_R    ( pcm_audio_R ),
	.O_RED 	(ored),
	.O_GREEN (ogreen),
	.O_BLUE	(oblue)
	);


//-------------- tube -----------------

wire [7:0] tube_stdout;
wire [7:0] tube_stderr;
assign tube_stdout = (memio_go && cpu_enable && cpu_wr && {cpu_addr[23:1], 1'b0} == 24'hfffffe && !cpu_ds[1]) ? cpu_dout[15:8] : 8'dz;
assign tube_stderr = (memio_go && cpu_enable && cpu_wr && {cpu_addr[23:1], 1'b0} == 24'hfffffe && !cpu_ds[0]) ? cpu_dout[7:0] : 8'dz;

//--------------------------------------------------------
//-- Unused outputs
//--------------------------------------------------------

// -- Interal audio (speaker, not fitted)
assign audioint_o     = 1'bZ;

// K7
assign mic_port_o     = 1'b0;

//-- Spectrum Next Bus
assign bus_addr_o     = 16'bZ;
assign bus_busack_n_o = 1'bz;
assign bus_clk35_o    = 1'bz;
assign bus_data_io    = 8'bZ;
assign bus_halt_n_o   = 1'bz;
assign bus_iorq_n_o   = 1'bz;
assign bus_m1_n_o     = 1'bz;
assign bus_mreq_n_o   = 1'bz;
assign bus_rd_n_io     = 1'bz;
assign bus_rfsh_n_o   = 1'bz;
assign bus_rst_n_io   = 1'bz;
assign bus_wr_n_o     = 1'bz;
assign bus_int_n_io   = 1'bz;
//assign bus_romcs_i    = 1'bZ;
assign bus_y_o        = 1'bz;

//-- ESP 8266 module
assign esp_gpio0_io   = 1'bZ;
assign esp_gpio2_io   = 1'bZ;
assign esp_cts_n_o    = 1'b0;
//assign esp_tx_o       = 1'b1;

assign flash_hold_o   = 1'b1;
assign flash_wp_o     = 1'b1;
assign flash_cs_n_o   = 1'b1;
assign flash_sclk_o   = 1'b1;
assign flash_mosi_o   = 1'b1;

// PI GPIO
// bits [27:22] output POST code
genvar gpio_idx;
generate
    // Lower 22 bits are not used.
    for (gpio_idx = 0; gpio_idx < 22; gpio_idx = gpio_idx + 1) begin : gpio_input
        IOBUF gpio_buf (
            .IO(accel_io[gpio_idx]),
            .I(1'b0),
            .O(),
            .T(1'b1)           // Tristate enabled (high-Z)
        );
    end

    // Upper 6 bits are POST code
    for (gpio_idx = 22; gpio_idx < 28; gpio_idx = gpio_idx + 1) begin : gpio_output
        IOBUF gpio_buf (
            .IO(accel_io[gpio_idx]),
            .I(post_code[gpio_idx-22]),
            .O(),
            .T(1'b0)           // Tristate disabled (output enabled)
        );
    end
endgenerate

// Vacant pins
assign extras_o      = 1'bz;
assign extras_2_io      = 1'bz;
assign extras_3_io      = 1'bz;

assign adc_control_o = 1'bz;


endmodule


