//================================================================
// p8audio.sv
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
`timescale 1ns/1ps
`default_nettype wire

module p8audio (
    // Clock and reset
    input  wire        mclk,        // mclk: 33MHz system clock
    input  wire        clk_pcm,     // clk_pcm: 22.05kHz PCM sample clock
    input  wire        clk_pcm_8x,  // clk_pcm_8x: 176.4kHz (8× PCM sample clock for time-multiplexing)
    input  wire        resetn_sys,     // mclk: Active-low reset (synchronized to mclk)
    input  wire        resetn_pcm,     // clk_pcm: Active-low reset (synchronized to clk_pcm)
    input  wire        resetn_pcm_8x,  // clk_pcm_8x: Active-low reset (synchronized to clk_pcm_8x)

    // MMIO (16-bit data path, 7-bit address) - mclk domain
    input  wire [6:0]    address,   // mclk: Register address
    input  wire [15:0]   din,       // mclk: Write data
    output reg  [15:0]   dout,      // mclk: Read data
    input wire           nUDS,      // mclk: Upper data strobe (active low)
    input wire           nLDS,      // mclk: Lower data strobe (active low)
    input wire           write_en,  // mclk: Write enable
    input wire           read_en,   // mclk: Read enable

    // PCM mono out - clk_pcm domain
    output reg signed [7:0] pcm_out,   // clk_pcm: PCM audio output sample (mixed, zero when inactive)

    // Shared DMA master to Base RAM - mclk domain
    output wire [30:0]  dma_addr,    // mclk: DMA address (word address, 16-bit words)
    input  wire [15:0]  dma_rdata,   // mclk: DMA read data (16-bit bus)
    output wire         dma_req,     // mclk: DMA request
    input  wire         dma_ack      // mclk: DMA acknowledge
);

//==============================================================
// Constants
//==============================================================
localparam [15:0] VERSION            = 16'd1;
localparam integer NUM_VOICES        = 4;         // Fixed voices
localparam [5:0]  MAX_PATTERN_INDEX  = 6'd63;     // MUSIC pattern wrap
localparam [7:0]  NOTE_TICK_DIV      = 8'd183;    // global note tick divider (samples)

//==============================================================
// MMIO registers (mclk domain)
//==============================================================

// Version and control
localparam [7:0] ADDR_VERSION = 8'h00;
localparam [7:0] ADDR_CTRL = 8'h02;
reg [15:0] reg_version;                 // mclk: Version register (read-only)
reg [15:0] reg_ctrl;                    // mclk: Control register (bit0 = RUN)

// Configuration
localparam [7:0] ADDR_SFX_BASE_HI = 8'h04;
localparam [7:0] ADDR_SFX_BASE_LO = 8'h06;
localparam [7:0] ADDR_MUSIC_BASE_HI = 8'h08;
localparam [7:0] ADDR_MUSIC_BASE_LO = 8'h0A;
localparam [7:0] ADDR_HWFX40 = 8'h0D;
localparam [7:0] ADDR_HWFX41 = 8'h0F;
localparam [7:0] ADDR_HWFX42 = 8'h11;
localparam [7:0] ADDR_HWFX43 = 8'h13;
reg [31:0] reg_sfx_base;                // mclk: SFX data base address in RAM
reg [31:0] reg_music_base;              // mclk: Music data base address in RAM
reg [7:0] hwfx_5f40, hwfx_5f41, hwfx_5f42, hwfx_5f43;  // mclk: PICO-8 hardware FX state snapshot

// SFX API
localparam [7:0] ADDR_SFX_CMD = 8'h18;
localparam [7:0] ADDR_SFX_LEN = 8'h1A;
reg [15:0] reg_sfx_len;                 // mclk: SFX length override

// MUSIC API
localparam [7:0] ADDR_MUSIC_CMD = 8'h1C;
localparam [7:0] ADDR_MUSIC_FADE = 8'h1E;
reg [15:0] reg_music_fade;              // mclk: Music fade time (frames for crossfade)

// stat(46..49): sfx index per channel
localparam [7:0] ADDR_STAT46 = 8'h20;
localparam [7:0] ADDR_STAT47 = 8'h22;
localparam [7:0] ADDR_STAT48 = 8'h24;
localparam [7:0] ADDR_STAT49 = 8'h26;
// stat(50..53): note index per channel
localparam [7:0] ADDR_STAT50 = 8'h28;
localparam [7:0] ADDR_STAT51 = 8'h2A;
localparam [7:0] ADDR_STAT52 = 8'h2C;
localparam [7:0] ADDR_STAT53 = 8'h2E;
// stat(54..56): music pattern id / count / tick count
localparam [7:0] ADDR_STAT54 = 8'h30;
localparam [7:0] ADDR_STAT55 = 8'h32;
localparam [7:0] ADDR_STAT56 = 8'h34;
// stat(57): music playing flag
localparam [7:0] ADDR_STAT57 = 8'h36;

always @(posedge mclk) begin
    if (!resetn_sys) begin
        reg_ctrl        <= 0;
        reg_sfx_base    <= 0;
        reg_music_base  <= 0;
        reg_version     <= VERSION;
        reg_sfx_len     <= 0;
        reg_music_fade  <= 0;
        hwfx_5f40       <= 0;
        hwfx_5f41       <= 0;
        hwfx_5f42       <= 0;
        hwfx_5f43       <= 0;
    end else if (write_en) begin
        case (address)
            ADDR_CTRL[7:1]:          reg_ctrl                <= din;
            ADDR_SFX_BASE_HI[7:1]:   reg_sfx_base[31:16]     <= din;
            ADDR_SFX_BASE_LO[7:1]:   reg_sfx_base[15:0]      <= din;
            ADDR_MUSIC_BASE_HI[7:1]: reg_music_base[31:16]   <= din;
            ADDR_MUSIC_BASE_LO[7:1]: reg_music_base[15:0]    <= din;
            ADDR_SFX_LEN[7:1]:       reg_sfx_len             <= din;
            ADDR_MUSIC_FADE[7:1]:    reg_music_fade          <= din;
            ADDR_HWFX40[7:1]:        hwfx_5f40               <= din[7:0];
            ADDR_HWFX41[7:1]:        hwfx_5f41               <= din[7:0];
            ADDR_HWFX42[7:1]:        hwfx_5f42               <= din[7:0];
            ADDR_HWFX43[7:1]:        hwfx_5f43               <= din[7:0];
            default: begin
                // Ignore writes to undefined addresses
            end
        endcase
    end
end

//==============================================================
// DMA arbiter (core_mux + sequencer) - mclk domain
//==============================================================
wire [30:0] core_mux_dma_addr;           // mclk: DMA address from core_mux
wire        core_mux_dma_req;            // mclk: DMA request from core_mux
wire        core_mux_dma_ack;            // mclk: DMA acknowledge to core_mux

reg  [30:0] seq_dma_addr;               // mclk: DMA address from sequencer (word address)
reg  [31:0] seq_dma_addr_temp;          // mclk: Temporary for DMA address calculations
reg         seq_dma_req;                // mclk: DMA request from sequencer (pulse)
wire        seq_dma_ack;                // mclk: DMA acknowledge to sequencer

// DMA arbiter instance (2 managers: core_mux + sequencer)
// Priority: core_mux > Sequencer (lowest index = highest priority)
dma_arbiter #(
    .NUM_MANAGERS(2),
    .ADDR_WIDTH(31)
) u_dma_arbiter (
    .clk(mclk),
    .resetn(resetn_sys),
    // Concatenated addresses: {seq, core_mux}
    .mgr_dma_addr({seq_dma_addr, core_mux_dma_addr}),
    // Concatenated requests: {seq, core_mux}
    .mgr_dma_req({seq_dma_req, core_mux_dma_req}),
    // Concatenated acks: {seq, core_mux}
    .mgr_dma_ack({seq_dma_ack, core_mux_dma_ack}),
    .sub_dma_addr(dma_addr),
    .sub_dma_req(dma_req),
    .sub_dma_ack(dma_ack)
);


//==============================================================
// Voices - Clock Domain: mixed (see comments)
//==============================================================
wire signed [7:0]  voice_pcm [0:3];             // clk_pcm: S8F7 PCM output per voice (zero when inactive)
wire [3:0]         voice_busy_pcm;               // clk_pcm_8x: Voice active status
wire [3:0]         voice_done_pcm;               // clk_pcm_8x: Context done pulse
wire [3:0]         voice_looping_pcm;            // clk_pcm_8x: Context looping status
wire [5:0]         v_stat_sfx_index_pcm [0:3];   // clk_pcm_8x: Current SFX index
wire [5:0]         v_stat_note_index_pcm[0:3];   // clk_pcm_8x: Current note index

// CDC: Synchronize voice signals from clk_pcm to mclk domain
(* ASYNC_REG = "TRUE" *) reg [3:0] voice_busy_sys_d;                  // mclk: CDC stage 1
(* ASYNC_REG = "TRUE" *) reg [3:0] voice_busy_sys_q;                  // mclk: CDC stage 2 (stable)
wire [3:0] voice_busy = voice_busy_sys_q;    // mclk: Synchronized voice busy status

(* ASYNC_REG = "TRUE" *) reg [3:0] voice_done_sys_d;                  // mclk: CDC stage 1
(* ASYNC_REG = "TRUE" *) reg [3:0] voice_done_sys_q;                  // mclk: CDC stage 2 (stable)
wire [3:0] voice_done = voice_done_sys_q;    // mclk: Synchronized voice done pulses

(* ASYNC_REG = "TRUE" *) reg [3:0] voice_looping_sys_d;               // mclk: CDC stage 1
(* ASYNC_REG = "TRUE" *) reg [3:0] voice_looping_sys_q;               // mclk: CDC stage 2 (stable)

(* ASYNC_REG = "TRUE" *) reg [5:0] v_stat_sfx_index_sys_d [0:3];      // mclk: CDC stage 1
(* ASYNC_REG = "TRUE" *) reg [5:0] v_stat_sfx_index [0:3];            // mclk: CDC stage 2 (stable)

(* ASYNC_REG = "TRUE" *) reg [5:0] v_stat_note_index_sys_d [0:3];     // mclk: CDC stage 1
(* ASYNC_REG = "TRUE" *) reg [5:0] v_stat_note_index [0:3];           // mclk: CDC stage 2 (stable)

// Loop variable for CDC synchronizer
integer k;

always @(posedge mclk) begin
    if (!resetn_sys) begin
        voice_busy_sys_d <= 4'b0000;
        voice_busy_sys_q <= 4'b0000;
        voice_done_sys_d <= 4'b0000;
        voice_done_sys_q <= 4'b0000;
        voice_looping_sys_d <= 4'b0000;
        voice_looping_sys_q <= 4'b0000;
        for (k=0; k<NUM_VOICES; k=k+1) begin
            v_stat_sfx_index_sys_d[k] <= 6'd0;
            v_stat_sfx_index[k] <= 6'd0;
            v_stat_note_index_sys_d[k] <= 6'd0;
            v_stat_note_index[k] <= 6'd0;
        end
    end else begin
        voice_busy_sys_d <= voice_busy_pcm;
        voice_busy_sys_q <= voice_busy_sys_d;
        voice_done_sys_d <= voice_done_pcm;
        voice_done_sys_q <= voice_done_sys_d;
        voice_looping_sys_d <= voice_looping_pcm;
        voice_looping_sys_q <= voice_looping_sys_d;
        for (k=0; k<NUM_VOICES; k=k+1) begin
            v_stat_sfx_index_sys_d[k] <= v_stat_sfx_index_pcm[k];
            v_stat_sfx_index[k] <= v_stat_sfx_index_sys_d[k];
            v_stat_note_index_sys_d[k] <= v_stat_note_index_pcm[k];
            v_stat_note_index[k] <= v_stat_note_index_sys_d[k];
        end
    end
end

//==============================================================
// Voice control signals (mclk domain)
//==============================================================
reg  [3:0]  play_strobe_sys;      // mclk: One-cycle pulse to start SFX playback
reg  [5:0]  play_sfx_index [0:3]; // mclk: SFX index to play (0-63)
reg  [5:0]  play_sfx_off   [0:3]; // mclk: Starting note offset (0-31)
reg  [15:0] play_sfx_len   [0:3]; // mclk: Number of notes to play (0=full)
reg  [3:0]  force_stop_sys;       // mclk: One-cycle pulse to stop voice immediately
reg  [3:0]  force_release_sys;    // mclk: One-cycle pulse to release voice from looping

//==============================================================
// Time-multiplexed SFX core instance (mclk + clk_pcm_8x domains)
//==============================================================
p8sfx_core_mux core_mux_inst (
    .clk_sys             (mclk),
    .clk_pcm_8x          (clk_pcm_8x),
    .resetn_sys          (resetn_sys),
    .resetn_pcm_8x       (resetn_pcm_8x),
    .run                 (reg_ctrl[0]),
    .base_addr           (reg_sfx_base),
    .sfx_index_in        (play_sfx_index),
    .sfx_offset          (play_sfx_off),
    .sfx_length          (play_sfx_len),
    .play_strobe         (play_strobe_sys),
    .force_stop          (force_stop_sys),
    .force_release       (force_release_sys),
    .voice_busy          (voice_busy_pcm),
    .sfx_done            (voice_done_pcm),
    .looping             (voice_looping_pcm),
    // DMA client
    .dma_addr            (core_mux_dma_addr),
    .dma_req             (core_mux_dma_req),
    .dma_rdata           (dma_rdata),
    .dma_ack             (core_mux_dma_ack),
    // PCM
    .pcm_out             (voice_pcm),
    // stat
    .stat_sfx_index      (v_stat_sfx_index_pcm),
    .stat_note_index     (v_stat_note_index_pcm),
    // hwfx
    .hwfx_5f40           (hwfx_5f40),
    .hwfx_5f41           (hwfx_5f41),
    .hwfx_5f42           (hwfx_5f42),
    .hwfx_5f43           (hwfx_5f43)
);

//==============================================================
// Note tick generation and music fade (clk_pcm domain)
//==============================================================
reg note_tick_toggle_pcm;         // clk_pcm: Toggle on each note tick for CDC
reg music_stop_toggle_pcm;        // clk_pcm: Toggle when fade-out completes (stop request)
reg [7:0] note_tick_counter;      // clk_pcm: Counter for note tick timing (0-182)

reg [15:0] music_fade_ctr_in;   // mclk: Fade-in frame counter
reg [15:0] music_fade_ctr_out;  // mclk: Fade-out frame counter
reg [15:0] music_fade_len;      // mclk: Music fade length (snapshot of reg_music_fade)

wire music_fade_in  = (music_fade_ctr_in  != 16'd0);
wire music_fade_out = (music_fade_ctr_out != 16'd0);

// CDC: Synchronize music fade parameters from mclk to clk_pcm domain
reg [15:0] music_fade_ctr_in_pcm;     // clk_pcm: Fade-in counter (managed in clk_pcm)
reg [15:0] music_fade_ctr_out_pcm;    // clk_pcm: Fade-out counter (managed in clk_pcm)
(* ASYNC_REG = "TRUE" *) reg [15:0] music_fade_len_pcm_d;      // clk_pcm: CDC stage 1
(* ASYNC_REG = "TRUE" *) reg [15:0] music_fade_len_pcm;        // clk_pcm: CDC stage 2 (stable)

// Synchronize fade counter initialization from mclk
(* ASYNC_REG = "TRUE" *) reg [15:0] music_fade_ctr_in_init_d;  // clk_pcm: CDC stage 1 for initialization
(* ASYNC_REG = "TRUE" *) reg [15:0] music_fade_ctr_in_init;    // clk_pcm: CDC stage 2 for initialization
(* ASYNC_REG = "TRUE" *) reg [15:0] music_fade_ctr_out_init_d; // clk_pcm: CDC stage 1 for initialization
(* ASYNC_REG = "TRUE" *) reg [15:0] music_fade_ctr_out_init;   // clk_pcm: CDC stage 2 for initialization
reg [15:0] music_fade_ctr_in_init_prev;   // clk_pcm: Previous value for edge detection
reg [15:0] music_fade_ctr_out_init_prev;  // clk_pcm: Previous value for edge detection

always @(posedge clk_pcm) begin
    if (!resetn_pcm) begin
        music_fade_ctr_in_pcm    <= 16'd0;
        music_fade_ctr_out_pcm   <= 16'd0;
        music_fade_len_pcm_d     <= 16'd0;
        music_fade_len_pcm       <= 16'd0;
        music_fade_ctr_in_init_d <= 16'd0;
        music_fade_ctr_in_init   <= 16'd0;
        music_fade_ctr_out_init_d <= 16'd0;
        music_fade_ctr_out_init  <= 16'd0;
        music_fade_ctr_in_init_prev <= 16'd0;
        music_fade_ctr_out_init_prev <= 16'd0;
        note_tick_toggle_pcm <= 1'b0;
        music_stop_toggle_pcm <= 1'b0;
        note_tick_counter <= 8'd0;
    end else begin
        // Synchronize fade parameters from mclk
        music_fade_ctr_in_init_d  <= music_fade_ctr_in;
        music_fade_ctr_in_init    <= music_fade_ctr_in_init_d;
        music_fade_ctr_out_init_d <= music_fade_ctr_out;
        music_fade_ctr_out_init   <= music_fade_ctr_out_init_d;
        music_fade_len_pcm_d      <= music_fade_len;
        music_fade_len_pcm        <= music_fade_len_pcm_d;

        // Load new fade values when source changes (edge detection)
        if (music_fade_ctr_in_init != music_fade_ctr_in_init_prev && music_fade_ctr_in_init != 16'd0) begin
            music_fade_ctr_in_pcm <= music_fade_ctr_in_init;
        end else if (music_fade_ctr_in_pcm != 16'd0) begin
            music_fade_ctr_in_pcm <= music_fade_ctr_in_pcm - 16'd1;
        end
        if (music_fade_ctr_out_init != music_fade_ctr_out_init_prev && music_fade_ctr_out_init != 16'd0) begin
            music_fade_ctr_out_pcm <= music_fade_ctr_out_init;
        end else if (music_fade_ctr_out_pcm != 16'd0) begin
            music_fade_ctr_out_pcm <= music_fade_ctr_out_pcm - 16'd1;
            // When fade-out reaches zero, stop music playback
            if (music_fade_ctr_out_pcm == 16'd1) begin
                // Stop music playback
                music_stop_toggle_pcm <= ~music_stop_toggle_pcm;
            end
        end
        music_fade_ctr_in_init_prev <= music_fade_ctr_in_init;
        music_fade_ctr_out_init_prev <= music_fade_ctr_out_init;

        // Note tick generation
        if (note_tick_counter >= 8'd182) begin  // NOTE_TICK_DIV - 1 = 183 - 1 = 182
            note_tick_counter <= 8'd0;
            note_tick_toggle_pcm <= ~note_tick_toggle_pcm;
        end else begin
            note_tick_counter <= note_tick_counter + 1;
        end
    end
end

wire music_fade_in_pcm  = (music_fade_ctr_in_pcm  != 16'd0);
wire music_fade_out_pcm = (music_fade_ctr_out_pcm != 16'd0);

//==============================================================
// Mono mixer (clk_pcm domain)
//==============================================================
// Mix all 4 voices with saturation
// Note: Voices output zero when inactive, so we can unconditionally add them

// Mixer: S10F7 register for summing 4 S8F7 voices (range: -512 to +508)
reg signed [9:0] sum;       // clk_pcm: S10F7 mixer sum (10 bits for arithmetic headroom)
reg signed [31:0] num;      // clk_pcm: Signed numerator for fade calculation
reg signed [31:0] numo;     // clk_pcm: Signed numerator for fade-out calculation
reg signed [31:0] denom;    // clk_pcm: Signed denominator for fade calculation

always @(posedge clk_pcm) begin
    if (!resetn_pcm || !reg_ctrl[0]) begin
        pcm_out<=0;
    end else begin
        // Mix 4 voices: S8F7 + S8F7 + S8F7 + S8F7 = S10F7
        sum = $signed({voice_pcm[0][7], voice_pcm[0][7], voice_pcm[0]})
            + $signed({voice_pcm[1][7], voice_pcm[1][7], voice_pcm[1]})
            + $signed({voice_pcm[2][7], voice_pcm[2][7], voice_pcm[2]})
            + $signed({voice_pcm[3][7], voice_pcm[3][7], voice_pcm[3]});

        // Apply fade effects
        denom = $signed({{16{1'b0}}, music_fade_len_pcm == 16'd0 ? 16'd1 : music_fade_len_pcm});
        if (music_fade_in_pcm) begin
            // Fade in: multiply by (len - ctr) / len
            num = $signed(denom - music_fade_ctr_in_pcm);
            sum = ($signed({{22{sum[9]}}, sum}) * num) / denom;
        end
        if (music_fade_out_pcm) begin
            // Fade out: multiply by ctr / len
            numo = $signed({{16{1'b0}}, music_fade_ctr_out_pcm});
            sum = ($signed({{22{sum[9]}}, sum}) * numo) / denom;
        end


        // Saturation to S8F7 output (range: -128 to +127)
        if (sum > 10'sd127) sum = 10'sd127;
        if (sum < -10'sd128) sum = -10'sd128;
        pcm_out <= sum[7:0];
    end
end

//==============================================================
// MUSIC Sequencer + stat counters (mclk domain)
//==============================================================
// Music sequencer state machine (mclk domain)
localparam [2:0] MUSIC_IDLE     = 3'd0;
localparam [2:0] MUSIC_LOADING  = 3'd1;
localparam [2:0] MUSIC_LOADED   = 3'd2;
localparam [2:0] MUSIC_PLAYING  = 3'd3;
localparam [2:0] MUSIC_ADVANCE  = 3'd4;
localparam [2:0] MUSIC_STOPPING = 3'd5;

reg [5:0] cur_frame;                      // mclk: Current music pattern frame index
reg [2:0] music_state;                    // mclk: Music sequencer state
reg [7:0] frame_bytes [0:3];              // mclk: Current frame data (4 bytes)
reg [1:0] fb_idx;                         // mclk: Frame byte fetch index

reg [5:0] loop_start, loop_end;           // mclk: Loop start/end frame indices
reg       loop_start_seen, loop_end_seen; // mclk: Track if loop markers encountered
reg       stop_on_loop;                   // mclk: Stop flag
reg [3:0] music_mask;                     // mclk: SFX auto-assign avoidance mask (1=prefer last for auto-assign)
wire      loop_def = loop_start_seen && loop_end_seen; // mclk: Loop active when both markers seen

reg [3:0] seq_played_mask;                // mclk: Channels triggered by current pattern

reg [15:0] stat_music_pattern;            // mclk: Current pattern index (stat 54)
reg [15:0] stat_music_pattern_count;      // mclk: Pattern loop count (stat 55)
reg [15:0] stat_music_tick_count;         // mclk: Note tick count (stat 56)
wire       stat_music_playing = (music_state != MUSIC_IDLE);

// CDC: note_tick toggle synchronizer from clk_pcm to mclk
(* ASYNC_REG = "TRUE" *) reg note_tick_toggle_sys_d;               // mclk: CDC stage 1
(* ASYNC_REG = "TRUE" *) reg note_tick_toggle_sys_q;               // mclk: CDC stage 2

// CDC: music stop request from clk_pcm to mclk
(* ASYNC_REG = "TRUE" *) reg music_stop_toggle_sys_d;              // mclk: CDC stage 1
(* ASYNC_REG = "TRUE" *) reg music_stop_toggle_sys_q;              // mclk: CDC stage 2
reg music_stop_toggle_sys_prev;                                    // mclk: Edge detect
wire music_stop_pulse = (music_stop_toggle_sys_q != music_stop_toggle_sys_prev);

// CDC: Reserved for future use
(* ASYNC_REG = "TRUE" *) reg frame_toggle_sys_d;                   // mclk: CDC stage 1 (unused)
(* ASYNC_REG = "TRUE" *) reg frame_toggle_sys_q;                   // mclk: CDC stage 2 (unused)

//==============================================================
// SFX API queueing (mclk domain)
//==============================================================
// Queue for pending SFX requests per voice
reg         q_valid [0:3];  // mclk: Queue entry valid
reg [5:0]   q_index [0:3];  // mclk: Queued SFX index
reg [5:0]   q_off   [0:3];  // mclk: Queued note offset
reg [15:0]  q_len   [0:3];  // mclk: Queued note length

reg [1:0] find_idle_next;   // mclk: Round-robin start index for auto-assign

// Round-robin auto-channel selection task.
// Searches all 4 channels starting from find_idle_next (wrapping), using
// 4-level priority: P1=idle+unmasked, P2=unmasked+music, P3=idle, P4=fallback.
task automatic find_idle;
    output reg [1:0] result;
    reg       found;
    reg [1:0] ci;
    integer   fi;
    begin
        found  = 1'b0;
        result = find_idle_next;  // P4 fallback
        // Priority 1: idle and not music-masked
        for (fi=0; fi<NUM_VOICES; fi=fi+1) begin
            ci = find_idle_next + fi[1:0];
            if (!found && !voice_busy[ci] && !music_mask[ci]) begin
                result = ci; found = 1'b1;
            end
        end
        // Priority 2: not music-masked and currently playing music (preemptable)
        if (!found) for (fi=0; fi<NUM_VOICES; fi=fi+1) begin
            ci = find_idle_next + fi[1:0];
            if (!found && !music_mask[ci] && seq_played_mask[ci]) begin
                result = ci; found = 1'b1;
            end
        end
        // Priority 3: idle (music-masked channel with no music)
        if (!found) for (fi=0; fi<NUM_VOICES; fi=fi+1) begin
            ci = find_idle_next + fi[1:0];
            if (!found && !voice_busy[ci]) begin
                result = ci; found = 1'b1;
            end
        end
        // Priority 4: fallback = find_idle_next (result already set)
        find_idle_next = result + 2'd1;
    end
endtask

// SFX queueing variables
integer l;
integer m;
reg [2:0]  ch_f;
reg [5:0]  idx_f;
reg [5:0]  off_f;
reg [1:0]  chx;

// Music command variables
reg [5:0] pat;
reg [3:0] msk;
reg start;
reg stop;
reg [5:0] next_frame;

// Sequencer variables
integer ch;
reg [1:0] leftmost_nonloop;

//==============================================================
// SFX queueing + MUSIC sequencer + Note tick counter (mclk domain)
//==============================================================
always @(posedge mclk) begin
    if (!resetn_sys) begin
        // SFX queueing resets
        find_idle_next <= 2'd0;
        for (l=0;l<NUM_VOICES;l=l+1) begin
            q_valid[l]<=0; q_index[l]<=0; q_off[l]<=0; q_len[l]<=0;
            play_strobe_sys[l]<=0; play_sfx_index[l]<=0; play_sfx_off[l]<=0; play_sfx_len[l]<=0;
            force_stop_sys[l]<=0;
            force_release_sys[l]<=0;
        end
        // MUSIC command handler resets
        music_state<=MUSIC_IDLE; music_mask<=4'b0000; cur_frame<=0;
        music_fade_ctr_in<=0; music_fade_ctr_out<=0; music_fade_len<=0;
        // Sequencer resets
        seq_dma_req<=0; fb_idx<=0;
        frame_toggle_sys_d <= 1'b0; frame_toggle_sys_q <= 1'b0;
        seq_played_mask <= 4'b0000;
        loop_start_seen<=0; loop_end_seen<=0; loop_start<=0; loop_end<=0; stop_on_loop<=0;
        stat_music_pattern<=0; stat_music_pattern_count<=0;
        // Note tick counter resets
        note_tick_toggle_sys_d <= 1'b0;
        note_tick_toggle_sys_q <= 1'b0;
        // Music stop request resets
        music_stop_toggle_sys_d <= 1'b0;
        music_stop_toggle_sys_q <= 1'b0;
        music_stop_toggle_sys_prev <= 1'b0;
        stat_music_tick_count <= 0;
        // Initialize frame_bytes to disabled channels (bit 6 set)
        frame_bytes[0] <= 8'h41; frame_bytes[1] <= 8'h42;
        frame_bytes[2] <= 8'h43; frame_bytes[3] <= 8'h44;
    end else begin
        play_strobe_sys <= 4'd0;
        force_stop_sys <= 4'b0000; force_release_sys <= 4'b0000;
        seq_dma_req<=0;

        // SFX command handler
        if (write_en && address==ADDR_SFX_CMD[7:1]) begin
            if (din[15]) begin
                ch_f = din[14:12];
                idx_f = din[5:0];
                off_f = din[11:6];

                if (idx_f==6'h3f) begin  // N=-1: Stop command (all ones in 6 bits)
                    if (ch_f==3'b111 || ch_f[2]) begin  // All channels if ch < 0
                        for (m=0; m<NUM_VOICES; m=m+1) begin
                            force_stop_sys[m] <= 1'b1;
                            q_valid[m] <= 1'b0;
                            seq_played_mask[m] <= 1'b0;
                        end
                    end else begin  // Specific channel
                        chx = ch_f[1:0];
                        force_stop_sys[chx] <= 1'b1;
                        q_valid[chx] <= 1'b0;
                        seq_played_mask[chx] <= 1'b0;
                    end
                end else if (idx_f==6'h3e) begin  // N=-2: Release from looping
                    if (ch_f==3'b111 || ch_f[2]) begin  // All channels if ch < 0
                        for (m=0; m<NUM_VOICES; m=m+1) begin
                            if (voice_busy[m]) begin
                                force_release_sys[m] <= 1'b1;
                            end
                        end
                    end else begin  // Specific channel
                        chx = ch_f[1:0];
                        if (voice_busy[chx]) begin
                            force_release_sys[chx] <= 1'b1;
                        end
                    end
                end else if (ch_f==3'b111) begin  // CHANNEL=-1: Auto-select idle channel
                    find_idle(chx);

                    if (!voice_busy[chx]) begin
                        // Idle channel found: start immediately
                        play_sfx_index[chx] <= idx_f;
                        play_sfx_off[chx]   <= off_f;
                        play_sfx_len[chx]   <= reg_sfx_len;
                        play_strobe_sys[chx] <= 1'b1;
                    end else begin
                        // Channel busy (music or user SFX): preempt via force-stop + queue
                        seq_played_mask[chx] <= 1'b0;
                        force_stop_sys[chx]  <= 1'b1;
                        q_index[chx] <= idx_f;
                        q_off[chx]   <= off_f;
                        q_len[chx]   <= reg_sfx_len;
                        q_valid[chx] <= 1'b1;
                    end
                end else if (ch_f==3'b110) begin  // CHANNEL=-2: Stop SFX on all channels playing it
                    for (m=0; m<NUM_VOICES; m=m+1) begin
                        if (voice_busy[m] && v_stat_sfx_index[m]==idx_f) begin
                            force_stop_sys[m] <= 1'b1;
                            q_valid[m] <= 1'b0;
                        end
                    end
                end else begin
                    chx = ch_f[1:0];
                    seq_played_mask[chx] <= 1'b0;
                    if (!voice_busy[chx]) begin
                        // Channel idle: start immediately
                        play_sfx_index[chx] <= idx_f;
                        play_sfx_off[chx]   <= off_f;
                        play_sfx_len[chx]   <= reg_sfx_len;
                        play_strobe_sys[chx] <= 1'b1;
                    end else begin
                        // Channel busy: force-stop current SFX and queue the new one
                        force_stop_sys[chx] <= 1'b1;
                        q_index[chx] <= idx_f;
                        q_off[chx]   <= off_f;
                        q_len[chx]   <= reg_sfx_len;
                        q_valid[chx] <= 1'b1;
                    end
                end
            end
        end

        // SFX queue processing - fire queued SFX once voice becomes idle
        for (l=0;l<NUM_VOICES;l=l+1) begin
            if (q_valid[l] && (voice_done[l] || !voice_busy[l])) begin
                play_sfx_index[l] <= q_index[l];
                play_sfx_off[l]   <= q_off[l];
                play_sfx_len[l]   <= q_len[l];
                play_strobe_sys[l] <= 1'b1;
                q_valid[l] <= 1'b0;
            end
        end

        // MUSIC command handler
        if (write_en && address==ADDR_MUSIC_CMD[7:1]) begin
            // PICO-8 API: music(n, fade_len, channel_mask)
            // n = -1 (0x3f in 6-bit) stops music
            // n = 0..63 starts music from pattern n
            pat = din[12:7];
            msk = din[6:3];
            if (pat == 6'h3f) begin
                // Stop music (pattern = -1)
                if (music_state != MUSIC_IDLE) begin
                    if (reg_music_fade == 16'd0) begin
                        // Immediate stop if fade length is zero
                        music_state<=MUSIC_STOPPING;
                    end else begin
                        // Start fade-out process
                        music_fade_ctr_in <= 0;
                        music_fade_ctr_out <= reg_music_fade;
                        music_fade_len <= reg_music_fade;
                    end
                end
            end else begin
                // Start music from pattern n
                music_mask         <= msk;
                music_fade_len     <= reg_music_fade;
                music_fade_ctr_in  <= reg_music_fade;
                music_fade_ctr_out <= 0;
                music_state<=MUSIC_LOADING;
                cur_frame <= pat;
                loop_start_seen<=0; loop_end_seen<=0; stop_on_loop<=0;
                stat_music_pattern <= {10'd0, pat};
                // pat << 2 = pat * 4 bytes per frame, then divide by 2 for word address
                seq_dma_addr_temp = (reg_music_base + ({26'd0, pat} << 2)) >> 1;
                seq_dma_addr <= seq_dma_addr_temp[30:0];
                seq_dma_req  <= 1'b1;
                fb_idx <= 0;
                stat_music_pattern       <= {10'd0, pat};
                stat_music_pattern_count <= 0;
                stat_music_tick_count    <= 0;
            end
        end

        case (music_state)
            MUSIC_LOADING: begin
                // MUSIC sequencer DMA: Fetch 4 bytes per frame (2 DMA reads of 16 bits each)
                if (seq_dma_ack) begin
                    // Unpack 16-bit DMA read into two consecutive bytes
                    // Big-endian: bits[15:8] = first byte (lower address), bits[7:0] = second byte (higher address)
                    frame_bytes[fb_idx]     <= dma_rdata[15:8];  // first byte at even position
                    frame_bytes[fb_idx + 1] <= dma_rdata[7:0];   // second byte at odd position
                    seq_dma_addr <= seq_dma_addr + 1;  // increment by 1 word (2 bytes)
                    fb_idx <= fb_idx + 2'd2;
                    if (fb_idx < 2'd2) begin
                        // More data needed - pulse for next transfer
                        seq_dma_req <= 1'b1;
                    end else begin
                        music_state <= MUSIC_LOADED;
                    end
                end
            end
            MUSIC_LOADED: begin
                // DMA done - process frame data
                fb_idx <= 0;
                seq_played_mask <= 4'b0000;
                for (ch=0; ch<NUM_VOICES; ch=ch+1) begin
                    if (frame_bytes[ch][6]) begin
                        // Channel disabled in pattern (bit 6 set): no retrigger
                    end else begin
                        play_sfx_index[ch] <= frame_bytes[ch][5:0];
                        play_sfx_off[ch]   <= 6'd0;
                        play_sfx_len[ch]   <= 16'd0;   // full SFX
                        play_strobe_sys[ch] <= 1'b1;
                        seq_played_mask[ch] <= 1'b1;
                    end
                end
                if (frame_bytes[0][7]) begin loop_start<=cur_frame; loop_start_seen<=1'b1; end
                if (frame_bytes[1][7]) begin loop_end<=cur_frame;   loop_end_seen<=1'b1; end
                if (frame_bytes[3][7]) begin stop_on_loop<=1'b1; end
                music_state <= MUSIC_PLAYING;
            end
            MUSIC_PLAYING: begin
                // Dynamically find leftmost non-looping channel among triggered channels
                leftmost_nonloop = 2'd0;  // default
                if (seq_played_mask[0] && !voice_looping_sys_q[0]) begin
                    leftmost_nonloop = 2'd0;
                end else if (seq_played_mask[1] && !voice_looping_sys_q[1]) begin
                    leftmost_nonloop = 2'd1;
                end else if (seq_played_mask[2] && !voice_looping_sys_q[2]) begin
                    leftmost_nonloop = 2'd2;
                end else if (seq_played_mask[3] && !voice_looping_sys_q[3]) begin
                    leftmost_nonloop = 2'd3;
                end

                // Advance immediately if nothing triggered, otherwise wait for a non-looping voice to complete
                if (seq_played_mask == 4'b0000 || voice_done[leftmost_nonloop]) begin
                    music_state <= MUSIC_ADVANCE;
                end
            end
            MUSIC_ADVANCE: begin
                // MUSIC sequencer pattern advancement
                if (loop_def && cur_frame==loop_end && stop_on_loop) begin
                    music_state<=MUSIC_STOPPING;
                end else begin
                    if (loop_def && cur_frame==loop_end) begin
                        // loop back to stored loop_start
                        next_frame = loop_start;
                    end else begin
                        next_frame = (cur_frame==MAX_PATTERN_INDEX) ? 6'd0 : (cur_frame+1);
                    end
                    cur_frame <= next_frame;
                    stat_music_pattern <= {10'd0, next_frame};
                    stat_music_pattern_count <= stat_music_pattern_count + 1;
                    // reg_music_base is byte address, convert to word address
                    seq_dma_addr_temp = (reg_music_base + ({26'd0, next_frame} << 2)) >> 1;
                    seq_dma_addr <= seq_dma_addr_temp[30:0];
                    seq_dma_req  <= 1'b1;
                    fb_idx <= 0;
                    music_state <= MUSIC_LOADING;
                end
            end
            MUSIC_STOPPING: begin
                // force_stop all channels that music triggered this pattern
                for (ch=0; ch<NUM_VOICES; ch=ch+1) begin
                    if (seq_played_mask[ch]) begin
                        force_stop_sys[ch] <= 1'b1;
                    end
                end
                music_state <= MUSIC_IDLE;
            end
        endcase

        // Note tick counter - detect edge from clk_pcm domain
        note_tick_toggle_sys_d <= note_tick_toggle_pcm;
        note_tick_toggle_sys_q <= note_tick_toggle_sys_d;
        if (note_tick_toggle_sys_q != note_tick_toggle_sys_d) begin
            stat_music_tick_count <= stat_music_tick_count + 1;
        end

        // Music stop request - detect edge from clk_pcm domain
        music_stop_toggle_sys_d <= music_stop_toggle_pcm;
        music_stop_toggle_sys_q <= music_stop_toggle_sys_d;
        if (music_stop_pulse && music_state != MUSIC_IDLE) begin
            music_state <= MUSIC_STOPPING;
        end
        music_stop_toggle_sys_prev <= music_stop_toggle_sys_q;
    end
end

//==============================================================
// MMIO readout for stat() equivalents (mclk domain)
//==============================================================
always @(*) begin                       // mclk: Combinational read mux
    case (address)
        ADDR_VERSION[7:1]: dout = reg_version;
        // stat(46..49): sfx index per channel; FFFF if idle
        ADDR_STAT46[7:1]: dout = voice_busy[0] ? {10'd0, v_stat_sfx_index[0]} : 16'hFFFF;
        ADDR_STAT47[7:1]: dout = voice_busy[1] ? {10'd0, v_stat_sfx_index[1]} : 16'hFFFF;
        ADDR_STAT48[7:1]: dout = voice_busy[2] ? {10'd0, v_stat_sfx_index[2]} : 16'hFFFF;
        ADDR_STAT49[7:1]: dout = voice_busy[3] ? {10'd0, v_stat_sfx_index[3]} : 16'hFFFF;
        // stat(50..53): note index per channel; FFFF if idle
        ADDR_STAT50[7:1]: dout = voice_busy[0] ? {10'd0, v_stat_note_index[0]} : 16'hFFFF;
        ADDR_STAT51[7:1]: dout = voice_busy[1] ? {10'd0, v_stat_note_index[1]} : 16'hFFFF;
        ADDR_STAT52[7:1]: dout = voice_busy[2] ? {10'd0, v_stat_note_index[2]} : 16'hFFFF;
        ADDR_STAT53[7:1]: dout = voice_busy[3] ? {10'd0, v_stat_note_index[3]} : 16'hFFFF;
        // stat(54..56): music pattern id / count / tick count
        ADDR_STAT54[7:1]: dout = stat_music_pattern;
        ADDR_STAT55[7:1]: dout = stat_music_pattern_count;
        ADDR_STAT56[7:1]: dout = stat_music_tick_count;
        ADDR_STAT57[7:1]: dout = {15'd0, stat_music_playing};
        default: dout = 16'h0000;
    endcase
end

endmodule
