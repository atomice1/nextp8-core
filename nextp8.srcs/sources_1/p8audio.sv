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
    input  wire        clk_sys,     // clk_sys: 33MHz system clock
    input  wire        clk_pcm,     // clk_pcm: 22.05kHz PCM sample clock
    input  wire        clk_pcm_8x,  // clk_pcm_8x: 176.4kHz (8× PCM sample clock for time-multiplexing)
    input  wire        resetn,      // async: Active-low reset

    // MMIO (16-bit data path, 7-bit address) - clk_sys domain
    input  wire [6:0]    address,   // clk_sys: Register address
    input  wire [15:0]   din,       // clk_sys: Write data
    output reg  [15:0]   dout,      // clk_sys: Read data
    input wire           nUDS,      // clk_sys: Upper data strobe (active low)
    input wire           nLDS,      // clk_sys: Lower data strobe (active low)
    input wire           write_en,  // clk_sys: Write enable
    input wire           read_en,   // clk_sys: Read enable

    // PCM mono out - clk_pcm domain
    output reg signed [7:0] pcm_out,   // clk_pcm: PCM audio output sample (mixed, zero when inactive)

    // Shared DMA master to Base RAM - clk_sys domain
    output wire [30:0]  dma_addr,    // clk_sys: DMA address (word address, 16-bit words)
    input  wire [15:0]  dma_rdata,   // clk_sys: DMA read data (16-bit bus)
    output wire         dma_req,     // clk_sys: DMA request
    input  wire         dma_ack      // clk_sys: DMA acknowledge
);

//==============================================================
// Constants
//==============================================================
localparam [15:0] VERSION            = 16'd1;
localparam integer NUM_VOICES        = 4;         // Fixed voices
localparam [5:0]  MAX_PATTERN_INDEX  = 6'd63;     // MUSIC pattern wrap
localparam [15:0] DEFAULT_NOTE_ATK   = 16'd16;    // samples
localparam [15:0] DEFAULT_NOTE_REL   = 16'd16;    // samples
localparam [15:0] DEFAULT_MUS_FADE   = 16'd16;    // frames
localparam [15:0] DEFAULT_MUSIC_RATE = 16'd16;    // frames / sec
localparam [7:0]  NOTE_TICK_DIV      = 8'd183;    // global note tick divider (samples)

//==============================================================
// MMIO registers (clk_sys domain)
//==============================================================

// Version and control
localparam [6:0] ADDR_VERSION       = 7'h00;
localparam [6:0] ADDR_CTRL          = 7'h01;
reg [15:0] reg_version;                 // clk_sys: Version register (read-only)
reg [15:0] reg_ctrl;                    // clk_sys: Control register (bit0 = RUN)

// Configuration
localparam [6:0] ADDR_SFX_BASE_HI   = 7'h02;
localparam [6:0] ADDR_SFX_BASE_LO   = 7'h03;
localparam [6:0] ADDR_MUSIC_BASE_HI = 7'h04;
localparam [6:0] ADDR_MUSIC_BASE_LO = 7'h05;
localparam [6:0] ADDR_HWFX_5F40     = 7'h06;
localparam [6:0] ADDR_HWFX_5F42     = 7'h07;
reg [31:0] reg_sfx_base;                // clk_sys: SFX data base address in RAM
reg [31:0] reg_music_base;              // clk_sys: Music data base address in RAM
reg [7:0] hwfx_5f40, hwfx_5f41, hwfx_5f42, hwfx_5f43;  // clk_sys: PICO-8 hardware FX state snapshot

// SFX API
localparam [6:0] ADDR_SFX_CMD       = 7'h0A;
localparam [6:0] ADDR_SFX_LEN       = 7'h0B;
reg [15:0] reg_sfx_cmd;                 // clk_sys: SFX command register
reg [15:0] reg_sfx_len;                 // clk_sys: SFX length override

// MUSIC API
localparam [6:0] ADDR_MUSIC_CMD     = 7'h0C;
localparam [6:0] ADDR_MUSIC_FADE    = 7'h0D;
reg [15:0] reg_music_cmd;               // clk_sys: Music command register
reg [15:0] reg_music_fade;              // clk_sys: Music fade time (frames for crossfade)

// stat(46..49): sfx index per channel
localparam [6:0] ADDR_STAT46        = 7'h0E;
localparam [6:0] ADDR_STAT47        = 7'h0F;
localparam [6:0] ADDR_STAT48        = 7'h10;
localparam [6:0] ADDR_STAT49        = 7'h11;
// stat(50..53): note index per channel
localparam [6:0] ADDR_STAT50        = 7'h12;
localparam [6:0] ADDR_STAT51        = 7'h13;
localparam [6:0] ADDR_STAT52        = 7'h14;
localparam [6:0] ADDR_STAT53        = 7'h15;
// stat(54..56): music pattern id / count / tick count
localparam [6:0] ADDR_STAT54        = 7'h16;
localparam [6:0] ADDR_STAT55        = 7'h17;
localparam [6:0] ADDR_STAT56        = 7'h18;

always @(posedge clk_sys) begin
    if (!resetn) begin
        reg_ctrl        <= 0;
        reg_sfx_base    <= 0;
        reg_music_base  <= 0;
        reg_version     <= VERSION;
        reg_sfx_cmd     <= 0;
        reg_sfx_len     <= 0;
        reg_music_cmd   <= 0;
        reg_music_fade  <= DEFAULT_MUS_FADE;
        hwfx_5f40       <= 0;
        hwfx_5f41       <= 0;
        hwfx_5f42       <= 0;
        hwfx_5f43       <= 0;
    end else if (write_en) begin
        case (address)
            ADDR_CTRL:          reg_ctrl                <= din;
            ADDR_SFX_BASE_HI:   reg_sfx_base[31:16]     <= din;
            ADDR_SFX_BASE_LO:   reg_sfx_base[15:0]      <= din;
            ADDR_MUSIC_BASE_HI: reg_music_base[31:16]   <= din;
            ADDR_MUSIC_BASE_LO: reg_music_base[15:0]    <= din;
            ADDR_SFX_CMD:       reg_sfx_cmd             <= din;
            ADDR_SFX_LEN:       reg_sfx_len             <= din;
            ADDR_MUSIC_CMD:     reg_music_cmd           <= din;
            ADDR_MUSIC_FADE:    reg_music_fade          <= din;
            ADDR_HWFX_5F40: begin
                if (!nUDS) hwfx_5f40 <= din[15:8];
                if (!nLDS) hwfx_5f41 <= din[7:0];
            end
            ADDR_HWFX_5F42: begin
                if (!nUDS) hwfx_5f42 <= din[15:8];
                if (!nLDS) hwfx_5f43 <= din[7:0];
            end
            default: begin
                // Ignore writes to undefined addresses
            end
        endcase
    end
end

//==============================================================
// DMA arbiter (core_mux + sequencer) - clk_sys domain
//==============================================================
wire [30:0] core_mux_dma_addr;           // clk_sys: DMA address from core_mux
wire        core_mux_dma_req;            // clk_sys: DMA request from core_mux
wire        core_mux_dma_ack;            // clk_sys: DMA acknowledge to core_mux

reg  [30:0] seq_dma_addr;               // clk_sys: DMA address from sequencer (word address)
reg  [31:0] seq_dma_addr_temp;          // clk_sys: Temporary for DMA address calculations
reg         seq_dma_req;                // clk_sys: DMA request from sequencer (pulse)
wire        seq_dma_ack;                // clk_sys: DMA acknowledge to sequencer

// DMA arbiter instance (2 managers: core_mux + sequencer)
// Priority: core_mux > Sequencer (lowest index = highest priority)
dma_arbiter #(
    .NUM_MANAGERS(2),
    .ADDR_WIDTH(31)
) u_dma_arbiter (
    .clk(clk_sys),
    .resetn(resetn),
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
wire signed [7:0] voice_pcm [0:3];          // clk_pcm: S8F7 PCM output per voice (zero when inactive)
wire [3:0]         voice_busy_pcm;          // clk_pcm_8x: Voice active status
wire [3:0]         voice_done_pcm;          // clk_pcm_8x: Context done pulse
wire [3:0]         voice_looping_pcm;       // clk_pcm_8x: Context looping status
wire [5:0]         v_stat_sfx_index_pcm [0:3];   // clk_pcm_8x: Current SFX index
wire [5:0]         v_stat_note_index_pcm[0:3];   // clk_pcm_8x: Current note index

// CDC: Synchronize voice signals from clk_pcm to clk_sys domain
reg [3:0] voice_busy_sys_d;                  // clk_sys: CDC stage 1
reg [3:0] voice_busy_sys_q;                  // clk_sys: CDC stage 2 (stable)
wire [3:0] voice_busy = voice_busy_sys_q;    // clk_sys: Synchronized voice busy status

reg [3:0] voice_done_sys_d;                  // clk_sys: CDC stage 1
reg [3:0] voice_done_sys_q;                  // clk_sys: CDC stage 2 (stable)
wire [3:0] voice_done = voice_done_sys_q;    // clk_sys: Synchronized voice done pulses

reg [3:0] voice_looping_sys_d;               // clk_sys: CDC stage 1
reg [3:0] voice_looping_sys_q;               // clk_sys: CDC stage 2 (stable)

reg [5:0] v_stat_sfx_index_sys_d [0:3];      // clk_sys: CDC stage 1
reg [5:0] v_stat_sfx_index [0:3];            // clk_sys: CDC stage 2 (stable)

reg [5:0] v_stat_note_index_sys_d [0:3];     // clk_sys: CDC stage 1
reg [5:0] v_stat_note_index [0:3];           // clk_sys: CDC stage 2 (stable)

// Loop variable for CDC synchronizer
integer k;

always @(posedge clk_sys) begin
    if (!resetn) begin
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
// Voice control signals (clk_sys domain)
//==============================================================
reg  [3:0]  play_strobe_sys;      // clk_sys: One-cycle pulse to start SFX playback
reg  [3:0]  sfx_strobe_mask;      // clk_sys: Tracks which strobes were set by SFX commands
reg  [5:0]  play_sfx_index [0:3]; // clk_sys: SFX index to play (0-63)
reg  [5:0]  play_sfx_off   [0:3]; // clk_sys: Starting note offset (0-31)
reg  [5:0]  play_sfx_len   [0:3]; // clk_sys: Number of notes to play (0=full)
reg  [3:0]  force_stop_sys;       // clk_sys: One-cycle pulse to stop voice immediately
reg  [3:0]  force_release_sys;    // clk_sys: One-cycle pulse to release voice from looping

//==============================================================
// Time-multiplexed SFX core instance (clk_sys + clk_pcm_8x domains)
//==============================================================
p8sfx_core_mux core_mux_inst (
    .clk_sys             (clk_sys),
    .clk_pcm_8x          (clk_pcm_8x),
    .resetn              (resetn),
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
reg [7:0] note_tick_counter;      // clk_pcm: Counter for note tick timing (0-182)

reg [15:0] music_fade_ctr_in;   // clk_sys: Fade-in frame counter
reg [15:0] music_fade_ctr_out;  // clk_sys: Fade-out frame counter
reg [15:0] music_fade_len;      // clk_sys: Music fade length (snapshot of reg_music_fade)

wire music_fade_in  = (music_fade_ctr_in  != 16'd0);
wire music_fade_out = (music_fade_ctr_out != 16'd0);

// CDC: Synchronize music fade parameters from clk_sys to clk_pcm domain
reg [15:0] music_fade_ctr_in_pcm;     // clk_pcm: Fade-in counter (managed in clk_pcm)
reg [15:0] music_fade_ctr_out_pcm;    // clk_pcm: Fade-out counter (managed in clk_pcm)
reg [15:0] music_fade_len_pcm_d;      // clk_pcm: CDC stage 1
reg [15:0] music_fade_len_pcm;        // clk_pcm: CDC stage 2 (stable)

// Synchronize fade counter initialization from clk_sys
reg [15:0] music_fade_ctr_in_init_d;  // clk_pcm: CDC stage 1 for initialization
reg [15:0] music_fade_ctr_in_init;    // clk_pcm: CDC stage 2 for initialization
reg [15:0] music_fade_ctr_out_init_d; // clk_pcm: CDC stage 1 for initialization
reg [15:0] music_fade_ctr_out_init;   // clk_pcm: CDC stage 2 for initialization

always @(posedge clk_pcm) begin
    if (!resetn) begin
        music_fade_ctr_in_pcm    <= 16'd0;
        music_fade_ctr_out_pcm   <= 16'd0;
        music_fade_len_pcm_d     <= 16'd0;
        music_fade_len_pcm       <= 16'd0;
        music_fade_ctr_in_init_d <= 16'd0;
        music_fade_ctr_in_init   <= 16'd0;
        music_fade_ctr_out_init_d <= 16'd0;
        music_fade_ctr_out_init  <= 16'd0;
        note_tick_toggle_pcm <= 1'b0;
        note_tick_counter <= 8'd0;
    end else begin
        // Synchronize fade parameters from clk_sys
        music_fade_ctr_in_init_d  <= music_fade_ctr_in;
        music_fade_ctr_in_init    <= music_fade_ctr_in_init_d;
        music_fade_ctr_out_init_d <= music_fade_ctr_out;
        music_fade_ctr_out_init   <= music_fade_ctr_out_init_d;
        music_fade_len_pcm_d      <= music_fade_len;
        music_fade_len_pcm        <= music_fade_len_pcm_d;

        // Load new fade values when they change (edge detection)
        if (music_fade_ctr_in_init != music_fade_ctr_in_pcm && music_fade_ctr_in_init != 16'd0) begin
            music_fade_ctr_in_pcm <= music_fade_ctr_in_init;
        end
        if (music_fade_ctr_out_init != music_fade_ctr_out_pcm && music_fade_ctr_out_init != 16'd0) begin
            music_fade_ctr_out_pcm <= music_fade_ctr_out_init;
        end

        // Note tick generation
        if (note_tick_counter >= 8'd182) begin  // NOTE_TICK_DIV - 1 = 183 - 1 = 182
            note_tick_counter <= 8'd0;
            note_tick_toggle_pcm <= ~note_tick_toggle_pcm;

            // Decrement fade counters on note tick (in clk_pcm domain)
            if (music_fade_ctr_in_pcm != 16'd0) begin
                music_fade_ctr_in_pcm <= music_fade_ctr_in_pcm - 16'd1;
            end
            if (music_fade_ctr_out_pcm != 16'd0) begin
                music_fade_ctr_out_pcm <= music_fade_ctr_out_pcm - 16'd1;
            end
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
    if (!resetn || !reg_ctrl[0]) begin
        pcm_out<=0;
    end else begin
        // Mix 4 voices: S8F7 + S8F7 + S8F7 + S8F7 = S10F7
        sum = $signed({voice_pcm[0][7], voice_pcm[0][7], voice_pcm[0]})
            + $signed({voice_pcm[1][7], voice_pcm[1][7], voice_pcm[1]})
            + $signed({voice_pcm[2][7], voice_pcm[2][7], voice_pcm[2]})
            + $signed({voice_pcm[3][7], voice_pcm[3][7], voice_pcm[3]});

        // Apply fade effects
        denom = $signed({{16{1'b0}}, music_fade_len_pcm == 16'd0 ? 32'd1 : music_fade_len_pcm});
        if (music_fade_in_pcm) begin
            // Fade in: multiply by (len - ctr) / len
            num = $signed(denom - music_fade_ctr_in_pcm);
            sum = (sum * num) / denom;
        end
        if (music_fade_out_pcm) begin
            // Fade out: multiply by ctr / len
            numo = $signed({{16{1'b0}}, music_fade_ctr_out_pcm});
            sum = (sum * numo) / denom;
        end

        // Saturation to S8F7 output (range: -128 to +127)
        if (sum > 18'sd127) sum = 18'sd127;
        if (sum < -18'sd128) sum = -18'sd128;
        pcm_out <= sum[7:0];
    end
end

//==============================================================
// MUSIC Sequencer + stat counters (clk_sys domain)
//==============================================================
reg [5:0] cur_frame;                      // clk_sys: Current music pattern frame index
reg       music_active;                   // clk_sys: Music sequencer active flag
reg [7:0] frame_bytes [0:3];              // clk_sys: Current frame data (4 bytes)
reg [1:0] fb_idx;                         // clk_sys: Frame byte fetch index

reg [5:0] loop_start, loop_end;           // clk_sys: Loop start/end frame indices
reg       loop_def, stop_on_loop;         // clk_sys: Loop flags
reg [3:0] music_mask;                     // clk_sys: Channel enable mask for music

reg [3:0] seq_played_mask;                // clk_sys: Channels triggered by current pattern
reg       seq_waiting;                    // clk_sys: Wait for voice_done before advancing

reg [15:0] stat_music_pattern;            // clk_sys: Current pattern index (stat 54)
reg [15:0] stat_music_pattern_count;      // clk_sys: Pattern loop count (stat 55)
reg [15:0] stat_music_tick_count;         // clk_sys: Note tick count (stat 56)

// CDC: note_tick toggle synchronizer from clk_pcm to clk_sys
reg note_tick_toggle_sys_d;               // clk_sys: CDC stage 1
reg note_tick_toggle_sys_q;               // clk_sys: CDC stage 2

// CDC: Reserved for future use
reg frame_toggle_sys_d;                   // clk_sys: CDC stage 1 (unused)
reg frame_toggle_sys_q;                   // clk_sys: CDC stage 2 (unused)

//==============================================================
// SFX API queueing (clk_sys domain)
//==============================================================
// Queue for pending SFX requests per voice
reg        q_valid [0:3];  // clk_sys: Queue entry valid
reg [5:0]  q_index [0:3];  // clk_sys: Queued SFX index
reg [5:0]  q_off   [0:3];  // clk_sys: Queued note offset
reg [5:0]  q_len   [0:3];  // clk_sys: Queued note length

function [1:0] find_idle;
    input dummy;  // Dummy input required by Verilog
    begin
        if (!voice_busy[0]) find_idle=2'd0;
        else if (!voice_busy[1]) find_idle=2'd1;
        else if (!voice_busy[2]) find_idle=2'd2;
        else if (!voice_busy[3]) find_idle=2'd3;
        else find_idle=2'd0;
    end
endfunction

// SFX queueing variables
integer l;
integer m;
reg [2:0] ch_f;
reg [5:0] idx_f;
reg [5:0] off_f;
reg [5:0] len_f;
reg [1:0] chx;

// Music command variables
reg [5:0] pat;
reg [3:0] msk;
reg start;
reg stop;

// Sequencer variables
integer ch;
reg [1:0] leftmost_nonloop;

//==============================================================
// SFX queueing + MUSIC sequencer + Note tick counter (clk_sys domain)
//==============================================================
always @(posedge clk_sys) begin
    if (!resetn) begin
        // SFX queueing resets
        for (l=0;l<NUM_VOICES;l=l+1) begin
            q_valid[l]<=0; q_index[l]<=0; q_off[l]<=0; q_len[l]<=0;
            play_strobe_sys[l]<=0; play_sfx_index[l]<=0; play_sfx_off[l]<=0; play_sfx_len[l]<=0;
            force_stop_sys[l]<=0;
            force_release_sys[l]<=0;
        end
        sfx_strobe_mask <= 4'b0000;
        // MUSIC command handler resets
        music_active<=0; music_mask<=4'b1111; cur_frame<=0;
        music_fade_ctr_in<=0; music_fade_ctr_out<=0; music_fade_len<=0;
        // Sequencer resets
        seq_dma_req<=0; fb_idx<=0;
        frame_toggle_sys_d <= 1'b0; frame_toggle_sys_q <= 1'b0;
        seq_played_mask <= 4'b0000; seq_waiting <= 1'b0;
        loop_def<=0; loop_start<=0; loop_end<=0; stop_on_loop<=0;
        stat_music_pattern<=0; stat_music_pattern_count<=0;
        // Note tick counter resets
        note_tick_toggle_sys_d <= 1'b0;
        note_tick_toggle_sys_q <= 1'b0;
        stat_music_tick_count <= 0;
        // Initialize frame_bytes to disabled channels (bit 6 set)
        frame_bytes[0] <= 8'h41; frame_bytes[1] <= 8'h42;
        frame_bytes[2] <= 8'h43; frame_bytes[3] <= 8'h44;
    end else begin
        // Clear SFX-triggered strobes from previous cycle
        if (sfx_strobe_mask != 4'b0000) begin
            for (l=0; l<NUM_VOICES; l=l+1) begin
                if (sfx_strobe_mask[l]) play_strobe_sys[l] <= 1'b0;
            end
            sfx_strobe_mask <= 4'b0000;
        end

        force_stop_sys <= 4'b0000; force_release_sys <= 4'b0000;

        // SFX command handler
        if (write_en && address==ADDR_SFX_CMD) begin
            if (din[15]) begin
                ch_f = din[14:12];
                idx_f = din[5:0];
                off_f = din[11:6];
                len_f = reg_sfx_len[5:0];

                if (idx_f==6'h3f) begin  // N=-1: Stop command (all ones in 6 bits)
                    if (ch_f==3'b111 || ch_f[2]) begin  // All channels if ch < 0
                        for (m=0; m<NUM_VOICES; m=m+1) begin
                            force_stop_sys[m] <= 1'b1;
                            q_valid[m] <= 1'b0;
                        end
                    end else begin  // Specific channel
                        chx = ch_f[1:0];
                        force_stop_sys[chx] <= 1'b1;
                        q_valid[chx] <= 1'b0;
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
                    chx = find_idle(1'b0);
                    if (!voice_busy[chx]) begin
                        play_sfx_index[chx] <= idx_f;
                        play_sfx_off[chx]   <= off_f;
                        play_sfx_len[chx]   <= len_f;
                        play_strobe_sys[chx] <= 1'b1;
                        sfx_strobe_mask[chx] <= 1'b1;
                    end else begin
                        q_index[chx] <= idx_f;
                        q_off[chx]   <= off_f;
                        q_len[chx]   <= len_f;
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
                    if (!voice_busy[chx]) begin
                        play_sfx_index[chx] <= idx_f;
                        play_sfx_off[chx]   <= off_f;
                        play_sfx_len[chx]   <= len_f;
                        play_strobe_sys[chx] <= 1'b1;
                        sfx_strobe_mask[chx] <= 1'b1;
                    end else begin
                        q_index[chx] <= idx_f;
                        q_off[chx]   <= off_f;
                        q_len[chx]   <= len_f;
                        q_valid[chx] <= 1'b1;
                    end
                end
            end
        end

        // SFX queue processing - trigger queued SFX when voices become available
        for (l=0;l<NUM_VOICES;l=l+1) begin
            if (q_valid[l] && (voice_done[l] || !voice_busy[l])) begin
                play_sfx_index[l] <= q_index[l];
                play_sfx_off[l]   <= q_off[l];
                play_sfx_len[l]   <= q_len[l];
                play_strobe_sys[l] <= 1'b1;
                sfx_strobe_mask[l] <= 1'b1;
                q_valid[l] <= 1'b0;
            end
        end

        // MUSIC command handler
        if (write_en && address==ADDR_MUSIC_CMD) begin
            pat = din[12:7];
            msk = din[6:3];
            start = din[13];
            stop  = din[14];
            if (stop) begin
                music_active<=0; seq_dma_req<=0;
                music_fade_ctr_in <= 0;
                music_fade_ctr_out <= reg_music_fade;
                music_fade_len <= reg_music_fade;
            end
            if (start) begin
                music_mask <= (msk==4'b0000) ? 4'b1111 : msk;
                music_fade_len     <= reg_music_fade;
                music_fade_ctr_in  <= reg_music_fade;
                music_fade_ctr_out <= 0;
                music_active<=1;
                cur_frame <= pat;
                loop_def<=0; stop_on_loop<=0;
                // reg_music_base is byte address, convert to word address
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

        // Clear music-triggered play strobes
        if (seq_played_mask != 4'b0000) begin
            for (ch=0; ch<NUM_VOICES; ch=ch+1) begin
                if (seq_played_mask[ch]) play_strobe_sys[ch] <= 1'b0;
            end
        end

        // MUSIC sequencer DMA: Fetch 4 bytes per frame (2 DMA reads of 16 bits each)
        if (seq_dma_ack) begin
            // Unpack 16-bit DMA read into two consecutive bytes
            // Big-endian: bits[15:8] = first byte (lower address), bits[7:0] = second byte (higher address)
            frame_bytes[fb_idx]     <= dma_rdata[15:8];  // first byte at even position
            frame_bytes[fb_idx + 1] <= dma_rdata[7:0];   // second byte at odd position
            fb_idx <= fb_idx + 2;
            seq_dma_addr <= seq_dma_addr + 1;  // increment by 1 word (2 bytes)
            if (fb_idx >= 2'd2) begin
                // Done - clear request
                seq_dma_req <= 1'b0;
                fb_idx <= 0;
                seq_played_mask <= 4'b0000;
                for (ch=0; ch<NUM_VOICES; ch=ch+1) begin
                    if (music_mask[ch]) begin
                        if (frame_bytes[ch][6]) begin
                            // CONTINUE: no retrigger
                        end else begin
                            play_sfx_index[ch] <= frame_bytes[ch][5:0];
                            play_sfx_off[ch]   <= 6'd0;
                            play_sfx_len[ch]   <= 6'd0;   // full SFX
                            play_strobe_sys[ch]    <= 1'b1;
                            seq_played_mask[ch] <= 1'b1;
                        end
                    end
                end
                if (frame_bytes[0][7]) begin loop_start<=cur_frame; loop_def<=1'b1; end
                if (frame_bytes[1][7]) begin loop_end<=cur_frame;   loop_def<=1'b1; end
                if (frame_bytes[3][7]) begin stop_on_loop<=1'b1; end
                // if any channels were triggered, wait for a voice_done before advancing
                seq_waiting <= |seq_played_mask;
            end else begin
                // More data needed - pulse for next transfer
                seq_dma_req <= 1'b1;
            end
        end else if (seq_dma_req) begin
            // Clear pulse after one cycle
            seq_dma_req <= 1'b0;
        end

        // MUSIC sequencer pattern advancement
        if (music_active) begin
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

            // advance only if not waiting or if leftmost non-looping channel reports done
            if ((!seq_waiting || (seq_waiting && voice_done[leftmost_nonloop])) && !seq_dma_req) begin
                if (loop_def && cur_frame==loop_end) begin
                    if (stop_on_loop) begin
                        music_active<=1'b0;
                    end else begin
                        // loop back to stored loop_start
                        cur_frame<=loop_start;
                        stat_music_pattern_count <= stat_music_pattern_count + 1;
                    end
                end else begin
                    cur_frame <= (cur_frame==MAX_PATTERN_INDEX) ? 6'd0 : (cur_frame+1);
                    stat_music_pattern_count <= stat_music_pattern_count + 1;
                end
                stat_music_pattern <= {10'd0, cur_frame};
                // reg_music_base is byte address, convert to word address
                seq_dma_addr_temp = (reg_music_base + ({26'd0, cur_frame} << 2)) >> 1;
                seq_dma_addr <= seq_dma_addr_temp[30:0];
                seq_dma_req  <= 1'b1;
                fb_idx <= 0;
                // clear waiting flag for next frame
                seq_waiting <= 1'b0;
            end
        end

        // Note tick counter - detect edge from clk_pcm domain
        note_tick_toggle_sys_d <= note_tick_toggle_pcm;
        note_tick_toggle_sys_q <= note_tick_toggle_sys_d;
        if (note_tick_toggle_sys_q != note_tick_toggle_sys_d) begin
            stat_music_tick_count <= stat_music_tick_count + 1;
        end
    end
end

//==============================================================
// MMIO readout for stat() equivalents (clk_sys domain)
//==============================================================
always @(*) begin                       // clk_sys: Combinational read mux
    case(address)
        ADDR_VERSION: dout = reg_version;
        // stat(46..49): sfx index per channel; FFFF if idle
        ADDR_STAT46: dout = voice_busy[0] ? {10'd0, v_stat_sfx_index[0]} : 16'hFFFF;
        ADDR_STAT47: dout = voice_busy[1] ? {10'd0, v_stat_sfx_index[1]} : 16'hFFFF;
        ADDR_STAT48: dout = voice_busy[2] ? {10'd0, v_stat_sfx_index[2]} : 16'hFFFF;
        ADDR_STAT49: dout = voice_busy[3] ? {10'd0, v_stat_sfx_index[3]} : 16'hFFFF;
        // stat(50..53): note index per channel; FFFF if idle
        ADDR_STAT50: dout = voice_busy[0] ? {10'd0, v_stat_note_index[0]} : 16'hFFFF;
        ADDR_STAT51: dout = voice_busy[1] ? {10'd0, v_stat_note_index[1]} : 16'hFFFF;
        ADDR_STAT52: dout = voice_busy[2] ? {10'd0, v_stat_note_index[2]} : 16'hFFFF;
        ADDR_STAT53: dout = voice_busy[3] ? {10'd0, v_stat_note_index[3]} : 16'hFFFF;
        // stat(54..56): music pattern id / count / tick count
        ADDR_STAT54: dout = stat_music_pattern;
        ADDR_STAT55: dout = stat_music_pattern_count;
        ADDR_STAT56: dout = stat_music_tick_count;
        default: dout = 16'h0000;
    endcase
end

endmodule
