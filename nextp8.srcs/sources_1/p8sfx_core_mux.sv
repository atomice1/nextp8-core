//==============================================================
// p8sfx_core_mux.sv
// Time-multiplexed SFX/waveform generator core
// 8x context switching: 4 voices x 2 instruments (MAIN + CUSTOM)
//
// Clock: clk_pcm_8x (176.4 kHz) for 8-way time division multiplexing
//        clk_sys (nominally 33 MHz) for DMA and control
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

module p8sfx_core_mux (
    // Clocks & Reset
    input         clk_sys,                    // System clock for DMA (33 MHz)
    input         clk_pcm_8x,                 // 8x PCM sample clock (176.4 kHz)
    input         resetn,                     // Active-low async reset

    // Control (clk_sys domain)
    input         run,                        // clk_sys: Global run enable
    input  [31:0] base_addr,                  // clk_sys: SFX base address (e.g., 0x3200)

    // Per-context trigger inputs (clk_sys domain) - 4 MAIN contexts (contexts 1,3,5,7)
    input  [5:0]  sfx_index_in [0:3],         // clk_sys: SFX slot to play (0-63) for each MAIN context
    input  [5:0]  sfx_offset [0:3],           // clk_sys: Starting note offset (0-31)
    input  [5:0]  sfx_length [0:3],           // clk_sys: Number of notes to play (0=until end/loop)
    input  [3:0]  play_strobe,                // clk_sys: 1-cycle pulse per MAIN context to load & start
    input  [3:0]  force_stop,                 // clk_sys: 1-cycle pulse to hard stop
    input  [3:0]  force_release,              // clk_sys: 1-cycle pulse to release from looping

    // Status outputs per MAIN context (clk_pcm_8x domain)
    output wire [3:0] voice_busy,             // clk_pcm_8x: High while each MAIN context is playing
    output reg [3:0] sfx_done,                // clk_pcm_8x: 1-cycle pulse when SFX completes
    output reg [3:0] looping,                 // clk_pcm_8x: Loop status per MAIN context

    // DMA client (clk_sys domain) - shared across all contexts
    output reg [30:0] dma_addr,               // clk_sys: DMA address (word address)
    output reg        dma_req,                // clk_sys: DMA request
    input      [15:0] dma_rdata,              // clk_sys: DMA read data
    input             dma_ack,                // clk_sys: DMA acknowledge

    // PCM output (clk_pcm_8x domain) - 4 MAIN contexts (contexts 1,3,5,7)
    output reg signed [7:0] pcm_out [0:3],    // clk_pcm_8x: S8F7 PCM output per MAIN context

    // Status exports per MAIN context (clk_pcm_8x domain)
    output reg [5:0] stat_sfx_index [0:3],    // clk_pcm_8x: Current SFX index per MAIN context
    output reg [5:0] stat_note_index [0:3],   // clk_pcm_8x: Current note index per MAIN context

    // Hardware FX bytes (clk_sys domain inputs, CDC'd internally)
    input [7:0] hwfx_5f40, hwfx_5f41, hwfx_5f42, hwfx_5f43
);

//==============================================================
// Constants
//==============================================================
localparam integer PCM_SAMPLE_RATE     = 22050;      // Base rate (x8 = 176400 Hz)
localparam        [7:0] SFX_BYTES      = 8'd68;      // bytes per SFX
localparam        [5:0] NOTE_MAX_INDEX = 6'd31;      // last note index
localparam        [7:0] NOTE_TICK_DIV  = 8'd183;     // sample divider for note timing

localparam [9:0] REVERB_TAPS_SHORT  = 10'd366;   // ~16.6ms @ 22.05KHz
localparam [9:0] REVERB_TAPS_LONG   = 10'd732;   // ~33.2ms @ 22.05KHz

// For reference - the alpha values are precalculated below
// localparam integer DAMP_FREQ_LOW     = 2400;
// localparam integer DAMP_FREQ_HIGH    = 1000;
// localparam integer DAMP_FREQ_STRONG  = 700;

// Pre-calculated dampen filter alpha constants (U8F8 format)
// alpha = (2*pi*freq) / sample_rate, scaled to U8F8
localparam [7:0] DAMP_ALPHA_LOW    = 8'd175;  // U8F8: 0.684
localparam [7:0] DAMP_ALPHA_HIGH   = 8'd73;   // U8F8: 0.285
localparam [7:0] DAMP_ALPHA_STRONG = 8'd51;   // U8F8: 0.199

// Custom instrument pitch reference
localparam [6:0] PITCH_REF_C2        = 7'd24;

// Header byte indices in SFX
localparam [6:0] HEADER_IDX_FILTERS  = 7'd64;
localparam [6:0] HEADER_IDX_SPEED    = 7'd65;
localparam [6:0] HEADER_IDX_LOOPST   = 7'd66;
localparam [6:0] HEADER_IDX_LOOPEN   = 7'd67;

// DMA loader states
localparam L_IDLE = 3'd0;
localparam L_START_LOAD = 3'd1;
localparam L_LOAD = 3'd2;
localparam L_SCAN = 3'd3;

//==============================================================
// Context Rotation
//==============================================================
reg [2:0] ctx_idx;  // clk_pcm_8x: Current context being processed (0-7)

// Context mapping functions
function [1:0] voice_from_ctx;
    input [2:0] ctx;
    begin
        voice_from_ctx = ctx >> 1;
    end
endfunction

function [2:0] ctx_from_voice;
    input [1:0] voice;
    input       is_main;
    begin
        ctx_from_voice = {voice, is_main};
    end
endfunction

function is_main_context;
    input [2:0] ctx;
    begin
        is_main_context = ctx[0];
    end
endfunction

function [2:0] custom_from_main;
    input [2:0] main_ctx;
    begin
        custom_from_main = {main_ctx[2:1], 1'b0};  // Clear LSB: 1→0, 3→2, 5→4, 7→6
    end
endfunction

reg clock_toggle; // Clock toggle for HWFX half-clock-rate

always @(posedge clk_pcm_8x) begin
    if (!resetn) begin
        ctx_idx <= 3'd0;
        // Reset clock cycle toggle for HWFX processing
        clock_toggle <= 1'b0;
    end else begin
        ctx_idx <= (ctx_idx == 3'd7) ? 3'd0 : ctx_idx + 1;
    end
    // Toggle clock cycle for HWFX processing
    if (ctx_idx == 3'd7) begin
        clock_toggle <= ~clock_toggle;
    end
end

// Context mapping helpers
wire [1:0] voice_idx = ctx_idx[2:1];  // Voice number (0-3) derived from context

//==============================================================
// Memories
//==============================================================
// Per-context SFX note cache (32 notes × 16-bit per context)
// Merged into single distributed RAM: 256 entries (8 contexts × 32 notes) = 4096 bits
// Address format: {ctx_idx[2:0], note_addr[4:0]} = 8 bits total
(* ram_style = "distributed" *) reg [15:0] sfx_notes [0:255];  // clk_sys(W)/clk_pcm_8x(R)
// Each entry contains 2 bytes: [15:8] = note_byte1, [7:0] = note_byte0

// Per-context reverb delay lines
(* ram_style = "block" *) reg signed [7:0] reverb_2_8x_0 [0:REVERB_TAPS_SHORT-1];
(* ram_style = "block" *) reg signed [7:0] reverb_2_8x_1 [0:REVERB_TAPS_SHORT-1];
(* ram_style = "block" *) reg signed [7:0] reverb_2_8x_2 [0:REVERB_TAPS_SHORT-1];
(* ram_style = "block" *) reg signed [7:0] reverb_2_8x_3 [0:REVERB_TAPS_SHORT-1];
(* ram_style = "block" *) reg signed [7:0] reverb_2_8x_4 [0:REVERB_TAPS_SHORT-1];
(* ram_style = "block" *) reg signed [7:0] reverb_2_8x_5 [0:REVERB_TAPS_SHORT-1];
(* ram_style = "block" *) reg signed [7:0] reverb_2_8x_6 [0:REVERB_TAPS_SHORT-1];
(* ram_style = "block" *) reg signed [7:0] reverb_2_8x_7 [0:REVERB_TAPS_SHORT-1];

(* ram_style = "block" *) reg signed [7:0] reverb_4_8x_0 [0:REVERB_TAPS_LONG-1];
(* ram_style = "block" *) reg signed [7:0] reverb_4_8x_1 [0:REVERB_TAPS_LONG-1];
(* ram_style = "block" *) reg signed [7:0] reverb_4_8x_2 [0:REVERB_TAPS_LONG-1];
(* ram_style = "block" *) reg signed [7:0] reverb_4_8x_3 [0:REVERB_TAPS_LONG-1];
(* ram_style = "block" *) reg signed [7:0] reverb_4_8x_4 [0:REVERB_TAPS_LONG-1];
(* ram_style = "block" *) reg signed [7:0] reverb_4_8x_5 [0:REVERB_TAPS_LONG-1];
(* ram_style = "block" *) reg signed [7:0] reverb_4_8x_6 [0:REVERB_TAPS_LONG-1];
(* ram_style = "block" *) reg signed [7:0] reverb_4_8x_7 [0:REVERB_TAPS_LONG-1];

//==============================================================
// Per-Context State Storage (8x replicated arrays)
//==============================================================

// SFX header data (loaded from DMA)
reg [7:0] header_filters_sys_8x [0:7];
reg [7:0] header_speed_sys_8x [0:7];
reg [7:0] header_loopst_sys_8x [0:7];
reg [7:0] header_loopen_sys_8x [0:7];
reg [7:0] speed_byte_8x [0:7]; // 0-255
reg       bass_flag_8x [0:7];
reg       is_waveform_inst_8x [0:7];
reg [5:0] loop_start_8x [0:7]; // 0-32
reg [5:0] loop_end_8x [0:7];   // 0-32

// Filter settings
reg       filt_noiz_8x [0:7];
reg       filt_buzz_8x [0:7];
reg [1:0] filt_detune_8x [0:7]; // 0-2
reg [1:0] filt_reverb_8x [0:7]; // 0-2
reg [1:0] filt_dampen_8x [0:7]; // 0-2

// Internal PCM output storage for CUSTOM contexts
reg signed [7:0] custom_pcm_out [0:3];  // S8F7 PCM output per CUSTOM context (contexts 0,2,4,6)

//==============================================================
// Explicit State Machine Registers
//==============================================================
// clk_pcm_8x domain states
localparam [1:0] PCM_IDLE     = 2'd0;  // Inactive, no SFX loaded
localparam [1:0] PCM_WARM_UP  = 2'd1;  // Warming up - decode first note
localparam [1:0] PCM_PLAYING  = 2'd2;  // Active playback
localparam [1:0] PCM_STOPPING = 2'd3;  // Stopping

reg [1:0] pcm_state [0:7];  // Per-context state in clk_pcm_8x domain

reg [5:0] start_idx_8x [0:7];   // 0-32
reg [5:0] sfx_length_val_8x [0:7]; // 0-32
reg [5:0] note_idx_8x [0:7];    // 0-32
reg [7:0] sample_ctr_8x [0:7];  // Sample counter for note timing (0-182)
reg [7:0] note_ctr_8x [0:7];    // Note counter (0-speed-1)

// Current note parameters
reg [5:0] cur_pitch_8x [0:7];   // 0-63
reg [2:0] cur_wave_8x [0:7];    // 0-7
reg [2:0] cur_vol_8x [0:7];     // 0-7
reg [2:0] cur_eff_8x [0:7];     // 0-7
reg       cur_custom_8x [0:7];

// Previous note (for slide)
reg [5:0] prev_pitch_8x [0:7];  // 0-63
reg [2:0] prev_vol_8x [0:7];    // 0-7

// Note envelope
reg [23:0] note_offset_8x [0:7];  // U24F24
reg [4:0] attack_ctr_8x [0:7];    // 0-16
reg [4:0] release_ctr_8x [0:7];   // 0-16
reg       releasing_8x [0:7];

// Arpeggio
reg        arp_active_8x [0:7];
reg [2:0]  arp_accum_8x [0:7];    // 0-7
reg [1:0]  next_group_pos_8x [0:7];
reg [7:0]  arp_speed_8x [0:7];    // Arpeggio speed 0,2,4,8

// SFX data from RAM
// Used for both note data and waveform dat
reg [15:0] sfx_data_8x [0:7];        // 16-bit word read from RAM
reg [4:0]  sfx_read_addr_8x [0:7];   // Read address (0-31 for 32 16-bit words)
reg        sfx_byte_sel_8x [0:7];    // Byte select bit for waveform mode

// DSP state
reg [10:0] eff_vib_phase_8x [0:10];  // U11F11
reg [21:0] phase_acc_8x [0:7];       // U22F18
reg [21:0] detune_acc_8x [0:7];      // U22F18
reg [17:0] eff_inc_8x [0:7];         // U18F18
reg [7:0]  eff_vol_8x [0:7];         // U8F8
reg [17:0] phase_mult_8x [0:7];      // U18F12 0.25-60.40795601
reg [17:0] detune_inc_8x [0:7];      // U18F18

// Noise generators
reg [7:0]         lfsr_8x [0:7];         // U8F8
reg signed [7:0]  brown_state_8x [0:7];  // S8F7

// Filter state
reg signed [7:0] damp_state_8x [0:7];  // S8F7
reg [7:0]        damp_alpha_8x [0:7];  // U8F8
reg [1:0]        eff_reverb_8x [0:7];  // 0-2

// Reverb indices (per-context)
reg [8:0] rev_idx2_8x [0:7];        // 0-(REVERB_TAPS_SHORT-1) - current write position
reg [9:0] rev_idx4_8x [0:7];        // 0-(REVERB_TAPS_LONG-1) - current write position
reg [8:0] rev_idx2_valid_8x [0:7];  // 0-(REVERB_TAPS_SHORT-1) - number of valid delay line samples
reg [9:0] rev_idx4_valid_8x [0:7];  // 0-(REVERB_TAPS_LONG-1) - number of valid delay line samples

// Reverb read data registers
reg signed [7:0] reverb_2_rdata_8x [0:7];  // Read data from reverb_2
reg signed [7:0] reverb_4_rdata_8x [0:7];  // Read data from reverb_4

// Pre-reverb sample (saved before reverb is mixed, for writing to delay line)
reg [7:0] pre_reverb_sample_8x [0:7];  // S8F7 sample before reverb mixing

// HWFX bytes (CDC'd from clk_sys)
reg [7:0] hwfx_5f40_sys;
reg [7:0] hwfx_5f41_sys;
reg [7:0] hwfx_5f42_sys;
reg [7:0] hwfx_5f43_sys;
reg [7:0] hwfx_5f40_pcm, hwfx_5f40_pcm_q;
reg [7:0] hwfx_5f41_pcm, hwfx_5f41_pcm_q;
reg [7:0] hwfx_5f42_pcm, hwfx_5f42_pcm_q;
reg [7:0] hwfx_5f43_pcm, hwfx_5f43_pcm_q;

// Custom instrument load request CDC (clk_pcm_8x -> clk_sys)
// Use per-voice toggles to handle multiple simultaneous requests
// Only MAIN contexts (1,3,5,7) can request, loading into CUSTOM contexts (0,2,4,6)
reg [3:0] custom_load_toggle_pcm;         // One bit per voice (0-3)
reg [2:0] custom_load_wave_pcm [0:3];     // Wave ID per voice
reg [3:0] custom_load_toggle_sys, custom_load_toggle_sys_q;

//==============================================================
// Current Context Wires (mux into current context)
//==============================================================

// SFX header data
wire [7:0] speed_byte = speed_byte_8x[ctx_idx];
wire       bass_flag = bass_flag_8x[ctx_idx];
wire       is_waveform_inst = is_waveform_inst_8x[ctx_idx];
wire [5:0] loop_start = loop_start_8x[ctx_idx];
wire [5:0] loop_end = loop_end_8x[ctx_idx];

// Filter settings
wire       filt_noiz = filt_noiz_8x[ctx_idx];
wire       filt_buzz = filt_buzz_8x[ctx_idx];
wire [1:0] filt_detune = filt_detune_8x[ctx_idx];
wire [1:0] filt_reverb = filt_reverb_8x[ctx_idx];
wire [1:0] filt_dampen = filt_dampen_8x[ctx_idx];

// Playback state
wire [5:0] start_idx = start_idx_8x[ctx_idx];

// Combinatorial status outputs (derived from FSM state)
assign voice_busy[0] = (pcm_state[1] != PCM_IDLE);
assign voice_busy[1] = (pcm_state[3] != PCM_IDLE);
assign voice_busy[2] = (pcm_state[5] != PCM_IDLE);
assign voice_busy[3] = (pcm_state[7] != PCM_IDLE);

// Aliases for current playback state
wire [5:0] sfx_length_val = sfx_length_val_8x[ctx_idx];
wire [5:0] note_idx = note_idx_8x[ctx_idx];
wire [7:0] sample_ctr = sample_ctr_8x[ctx_idx];
wire [7:0] note_ctr = note_ctr_8x[ctx_idx];

// Current note parameters
wire [5:0] cur_pitch = cur_pitch_8x[ctx_idx];
wire [2:0] cur_wave = cur_wave_8x[ctx_idx];
wire [2:0] cur_vol = cur_vol_8x[ctx_idx];
wire [2:0] cur_eff = cur_eff_8x[ctx_idx];
wire       cur_custom = cur_custom_8x[ctx_idx];

// Previous note (for slide)
wire [5:0] prev_pitch = prev_pitch_8x[ctx_idx];
wire [2:0] prev_vol = prev_vol_8x[ctx_idx];

// Note envelope
wire [23:0] note_offset = note_offset_8x[ctx_idx];
wire [4:0] attack_ctr = attack_ctr_8x[ctx_idx];
wire [4:0] release_ctr = release_ctr_8x[ctx_idx];
wire       releasing = releasing_8x[ctx_idx];

// Arpeggio
wire        arp_active = arp_active_8x[ctx_idx];
wire [2:0]  arp_accum = arp_accum_8x[ctx_idx];
wire [1:0]  next_group_pos = next_group_pos_8x[ctx_idx];
wire [7:0]  arp_speed = arp_speed_8x[ctx_idx];

// SFX data from RAM
wire [15:0] sfx_data = sfx_data_8x[ctx_idx];
wire        sfx_byte_sel = sfx_byte_sel_8x[ctx_idx];

// DSP state
wire [11:0]  eff_vib_phase = eff_vib_phase_8x[ctx_idx];
wire [21:0] phase_acc = phase_acc_8x[ctx_idx];
wire [21:0] detune_acc = detune_acc_8x[ctx_idx];
wire [17:0] eff_inc = eff_inc_8x[ctx_idx];
wire [7:0]  eff_vol = eff_vol_8x[ctx_idx];
wire [15:0] phase_mult = phase_mult_8x[ctx_idx];
wire [17:0] detune_inc = detune_inc_8x[ctx_idx];

// Noise generators
wire [7:0]         lfsr = lfsr_8x[ctx_idx];
wire signed [7:0]  brown_state = brown_state_8x[ctx_idx];

// Filter state
wire signed [7:0] damp_state = damp_state_8x[ctx_idx];
wire [7:0]        damp_alpha = damp_alpha_8x[ctx_idx];
wire [1:0]        eff_reverb = eff_reverb_8x[ctx_idx];

// Reverb indices
wire [8:0] rev_idx2 = rev_idx2_8x[ctx_idx];
wire [9:0] rev_idx4 = rev_idx4_8x[ctx_idx];
wire [8:0] rev_idx2_valid = rev_idx2_valid_8x[ctx_idx];
wire [9:0] rev_idx4_valid = rev_idx4_valid_8x[ctx_idx];

// Reverb read data
wire signed [7:0] reverb_2_rdata = reverb_2_rdata_8x[ctx_idx];
wire signed [7:0] reverb_4_rdata = reverb_4_rdata_8x[ctx_idx];

// Hardware FX (CDC'd from clk_sys)
wire [7:0] hwfx_5f40_val = hwfx_5f40_pcm_q;
wire [7:0] hwfx_5f41_val = hwfx_5f41_pcm_q;
wire [7:0] hwfx_5f42_val = hwfx_5f42_pcm_q;
wire [7:0] hwfx_5f43_val = hwfx_5f43_pcm_q;

//==============================================================
// Shared Lookup Tables (ROM, not replicated)
//==============================================================
// 18-bits gives max frequency error of 0.10%. A 0.3%-0.5% error
// is the typical threshold for sounding out of tune.
reg [17:0] pitch_phase_inc [0:95]; // U18F18
initial begin
    pitch_phase_inc[ 0] = 18'h0309; pitch_phase_inc[ 1] = 18'h0337;
    pitch_phase_inc[ 2] = 18'h0368; pitch_phase_inc[ 3] = 18'h039c;
    pitch_phase_inc[ 4] = 18'h03d3; pitch_phase_inc[ 5] = 18'h040d;
    pitch_phase_inc[ 6] = 18'h044b; pitch_phase_inc[ 7] = 18'h048d;
    pitch_phase_inc[ 8] = 18'h04d2; pitch_phase_inc[ 9] = 18'h051b;
    pitch_phase_inc[10] = 18'h0569; pitch_phase_inc[11] = 18'h05bb;
    pitch_phase_inc[12] = 18'h0613; pitch_phase_inc[13] = 18'h066f;
    pitch_phase_inc[14] = 18'h06d1; pitch_phase_inc[15] = 18'h0739;
    pitch_phase_inc[16] = 18'h07a7; pitch_phase_inc[17] = 18'h081b;
    pitch_phase_inc[18] = 18'h0897; pitch_phase_inc[19] = 18'h091a;
    pitch_phase_inc[20] = 18'h09a4; pitch_phase_inc[21] = 18'h0a37;
    pitch_phase_inc[22] = 18'h0ad3; pitch_phase_inc[23] = 18'h0b77;
    pitch_phase_inc[24] = 18'h0c26; pitch_phase_inc[25] = 18'h0cdf;
    pitch_phase_inc[26] = 18'h0da3; pitch_phase_inc[27] = 18'h0e72;
    pitch_phase_inc[28] = 18'h0f4e; pitch_phase_inc[29] = 18'h1037;
    pitch_phase_inc[30] = 18'h112e; pitch_phase_inc[31] = 18'h1234;
    pitch_phase_inc[32] = 18'h1349; pitch_phase_inc[33] = 18'h146e;
    pitch_phase_inc[34] = 18'h15a6; pitch_phase_inc[35] = 18'h16ef;
    pitch_phase_inc[36] = 18'h184c; pitch_phase_inc[37] = 18'h19be;
    pitch_phase_inc[38] = 18'h1b46; pitch_phase_inc[39] = 18'h1ce5;
    pitch_phase_inc[40] = 18'h1e9d; pitch_phase_inc[41] = 18'h206f;
    pitch_phase_inc[42] = 18'h225d; pitch_phase_inc[43] = 18'h2468;
    pitch_phase_inc[44] = 18'h2692; pitch_phase_inc[45] = 18'h28dd;
    pitch_phase_inc[46] = 18'h2b4c; pitch_phase_inc[47] = 18'h2ddf;
    pitch_phase_inc[48] = 18'h3099; pitch_phase_inc[49] = 18'h337d;
    pitch_phase_inc[50] = 18'h368d; pitch_phase_inc[51] = 18'h39cb;
    pitch_phase_inc[52] = 18'h3d3b; pitch_phase_inc[53] = 18'h40df;
    pitch_phase_inc[54] = 18'h44ba; pitch_phase_inc[55] = 18'h48d1;
    pitch_phase_inc[56] = 18'h4d25; pitch_phase_inc[57] = 18'h51bb;
    pitch_phase_inc[58] = 18'h5698; pitch_phase_inc[59] = 18'h5bbe;
    pitch_phase_inc[60] = 18'h6132; pitch_phase_inc[61] = 18'h66fa;
    pitch_phase_inc[62] = 18'h6d1a; pitch_phase_inc[63] = 18'h7396;
    pitch_phase_inc[64] = 18'h7a76; pitch_phase_inc[65] = 18'h81be;
    pitch_phase_inc[66] = 18'h8975; pitch_phase_inc[67] = 18'h91a2;
    pitch_phase_inc[68] = 18'h9a4b; pitch_phase_inc[69] = 18'ha377;
    pitch_phase_inc[70] = 18'had30; pitch_phase_inc[71] = 18'hb77c;
    pitch_phase_inc[72] = 18'hc265; pitch_phase_inc[73] = 18'hcdf5;
    pitch_phase_inc[74] = 18'hda34; pitch_phase_inc[75] = 18'he72d;
    pitch_phase_inc[76] = 18'hf4ed; pitch_phase_inc[77] = 18'h1037d;
    pitch_phase_inc[78] = 18'h112eb; pitch_phase_inc[79] = 18'h12344;
    pitch_phase_inc[80] = 18'h13496; pitch_phase_inc[81] = 18'h146ef;
    pitch_phase_inc[82] = 18'h15a60; pitch_phase_inc[83] = 18'h16ef9;
    pitch_phase_inc[84] = 18'h184cb; pitch_phase_inc[85] = 18'h19bea;
    pitch_phase_inc[86] = 18'h1b468; pitch_phase_inc[87] = 18'h1ce5b;
    pitch_phase_inc[88] = 18'h1e9da; pitch_phase_inc[89] = 18'h206fa;
    pitch_phase_inc[90] = 18'h225d7; pitch_phase_inc[91] = 18'h24689;
    pitch_phase_inc[92] = 18'h2692c; pitch_phase_inc[93] = 18'h28ddf;
    pitch_phase_inc[94] = 18'h2b4c1; pitch_phase_inc[95] = 18'h2ddf2;
end

reg [16:0] note_offset_lut [0:255];  // U17F24
// 17-bits gives max frequency error of 0.26%
initial begin
    note_offset_lut[  0] = 17'h1ffff;
    note_offset_lut[  1] = 17'h1661e;   note_offset_lut[  2] = 17'h0b30f;   note_offset_lut[  3] = 17'h0775f;   note_offset_lut[  4] = 17'h05987;
    note_offset_lut[  5] = 17'h0479f;   note_offset_lut[  6] = 17'h03baf;   note_offset_lut[  7] = 17'h03328;   note_offset_lut[  8] = 17'h02cc3;
    note_offset_lut[  9] = 17'h027ca;   note_offset_lut[ 10] = 17'h023cf;   note_offset_lut[ 11] = 17'h0208e;   note_offset_lut[ 12] = 17'h01dd7;
    note_offset_lut[ 13] = 17'h01b8c;   note_offset_lut[ 14] = 17'h01994;   note_offset_lut[ 15] = 17'h017df;   note_offset_lut[ 16] = 17'h01661;
    note_offset_lut[ 17] = 17'h01510;   note_offset_lut[ 18] = 17'h013e5;   note_offset_lut[ 19] = 17'h012d9;   note_offset_lut[ 20] = 17'h011e7;
    note_offset_lut[ 21] = 17'h0110d;   note_offset_lut[ 22] = 17'h01047;   note_offset_lut[ 23] = 17'h00f92;   note_offset_lut[ 24] = 17'h00eeb;
    note_offset_lut[ 25] = 17'h00e53;   note_offset_lut[ 26] = 17'h00dc6;   note_offset_lut[ 27] = 17'h00d43;   note_offset_lut[ 28] = 17'h00cca;
    note_offset_lut[ 29] = 17'h00c59;   note_offset_lut[ 30] = 17'h00bef;   note_offset_lut[ 31] = 17'h00b8d;   note_offset_lut[ 32] = 17'h00b30;
    note_offset_lut[ 33] = 17'h00ada;   note_offset_lut[ 34] = 17'h00a88;   note_offset_lut[ 35] = 17'h00a3b;   note_offset_lut[ 36] = 17'h009f2;
    note_offset_lut[ 37] = 17'h009ad;   note_offset_lut[ 38] = 17'h0096c;   note_offset_lut[ 39] = 17'h0092e;   note_offset_lut[ 40] = 17'h008f3;
    note_offset_lut[ 41] = 17'h008bc;   note_offset_lut[ 42] = 17'h00886;   note_offset_lut[ 43] = 17'h00854;   note_offset_lut[ 44] = 17'h00823;
    note_offset_lut[ 45] = 17'h007f5;   note_offset_lut[ 46] = 17'h007c9;   note_offset_lut[ 47] = 17'h0079e;   note_offset_lut[ 48] = 17'h00775;
    note_offset_lut[ 49] = 17'h0074e;   note_offset_lut[ 50] = 17'h00729;   note_offset_lut[ 51] = 17'h00705;   note_offset_lut[ 52] = 17'h006e3;
    note_offset_lut[ 53] = 17'h006c1;   note_offset_lut[ 54] = 17'h006a1;   note_offset_lut[ 55] = 17'h00682;   note_offset_lut[ 56] = 17'h00665;
    note_offset_lut[ 57] = 17'h00648;   note_offset_lut[ 58] = 17'h0062c;   note_offset_lut[ 59] = 17'h00611;   note_offset_lut[ 60] = 17'h005f7;
    note_offset_lut[ 61] = 17'h005de;   note_offset_lut[ 62] = 17'h005c6;   note_offset_lut[ 63] = 17'h005af;   note_offset_lut[ 64] = 17'h00598;
    note_offset_lut[ 65] = 17'h00582;   note_offset_lut[ 66] = 17'h0056d;   note_offset_lut[ 67] = 17'h00558;   note_offset_lut[ 68] = 17'h00544;
    note_offset_lut[ 69] = 17'h00530;   note_offset_lut[ 70] = 17'h0051d;   note_offset_lut[ 71] = 17'h0050b;   note_offset_lut[ 72] = 17'h004f9;
    note_offset_lut[ 73] = 17'h004e7;   note_offset_lut[ 74] = 17'h004d6;   note_offset_lut[ 75] = 17'h004c6;   note_offset_lut[ 76] = 17'h004b6;
    note_offset_lut[ 77] = 17'h004a6;   note_offset_lut[ 78] = 17'h00497;   note_offset_lut[ 79] = 17'h00488;   note_offset_lut[ 80] = 17'h00479;
    note_offset_lut[ 81] = 17'h0046b;   note_offset_lut[ 82] = 17'h0045e;   note_offset_lut[ 83] = 17'h00450;   note_offset_lut[ 84] = 17'h00443;
    note_offset_lut[ 85] = 17'h00436;   note_offset_lut[ 86] = 17'h0042a;   note_offset_lut[ 87] = 17'h0041d;   note_offset_lut[ 88] = 17'h00411;
    note_offset_lut[ 89] = 17'h00406;   note_offset_lut[ 90] = 17'h003fa;   note_offset_lut[ 91] = 17'h003ef;   note_offset_lut[ 92] = 17'h003e4;
    note_offset_lut[ 93] = 17'h003d9;   note_offset_lut[ 94] = 17'h003cf;   note_offset_lut[ 95] = 17'h003c5;   note_offset_lut[ 96] = 17'h003ba;
    note_offset_lut[ 97] = 17'h003b1;   note_offset_lut[ 98] = 17'h003a7;   note_offset_lut[ 99] = 17'h0039e;   note_offset_lut[100] = 17'h00394;
    note_offset_lut[101] = 17'h0038b;   note_offset_lut[102] = 17'h00382;   note_offset_lut[103] = 17'h0037a;   note_offset_lut[104] = 17'h00371;
    note_offset_lut[105] = 17'h00369;   note_offset_lut[106] = 17'h00360;   note_offset_lut[107] = 17'h00358;   note_offset_lut[108] = 17'h00350;
    note_offset_lut[109] = 17'h00349;   note_offset_lut[110] = 17'h00341;   note_offset_lut[111] = 17'h00339;   note_offset_lut[112] = 17'h00332;
    note_offset_lut[113] = 17'h0032b;   note_offset_lut[114] = 17'h00324;   note_offset_lut[115] = 17'h0031d;   note_offset_lut[116] = 17'h00316;
    note_offset_lut[117] = 17'h0030f;   note_offset_lut[118] = 17'h00308;   note_offset_lut[119] = 17'h00302;   note_offset_lut[120] = 17'h002fb;
    note_offset_lut[121] = 17'h002f5;   note_offset_lut[122] = 17'h002ef;   note_offset_lut[123] = 17'h002e9;   note_offset_lut[124] = 17'h002e3;
    note_offset_lut[125] = 17'h002dd;   note_offset_lut[126] = 17'h002d7;   note_offset_lut[127] = 17'h002d1;   note_offset_lut[128] = 17'h002cc;
    note_offset_lut[129] = 17'h002c6;   note_offset_lut[130] = 17'h002c1;   note_offset_lut[131] = 17'h002bb;   note_offset_lut[132] = 17'h002b6;
    note_offset_lut[133] = 17'h002b1;   note_offset_lut[134] = 17'h002ac;   note_offset_lut[135] = 17'h002a7;   note_offset_lut[136] = 17'h002a2;
    note_offset_lut[137] = 17'h0029d;   note_offset_lut[138] = 17'h00298;   note_offset_lut[139] = 17'h00293;   note_offset_lut[140] = 17'h0028e;
    note_offset_lut[141] = 17'h0028a;   note_offset_lut[142] = 17'h00285;   note_offset_lut[143] = 17'h00281;   note_offset_lut[144] = 17'h0027c;
    note_offset_lut[145] = 17'h00278;   note_offset_lut[146] = 17'h00273;   note_offset_lut[147] = 17'h0026f;   note_offset_lut[148] = 17'h0026b;
    note_offset_lut[149] = 17'h00267;   note_offset_lut[150] = 17'h00263;   note_offset_lut[151] = 17'h0025f;   note_offset_lut[152] = 17'h0025b;
    note_offset_lut[153] = 17'h00257;   note_offset_lut[154] = 17'h00253;   note_offset_lut[155] = 17'h0024f;   note_offset_lut[156] = 17'h0024b;
    note_offset_lut[157] = 17'h00247;   note_offset_lut[158] = 17'h00244;   note_offset_lut[159] = 17'h00240;   note_offset_lut[160] = 17'h0023c;
    note_offset_lut[161] = 17'h00239;   note_offset_lut[162] = 17'h00235;   note_offset_lut[163] = 17'h00232;   note_offset_lut[164] = 17'h0022f;
    note_offset_lut[165] = 17'h0022b;   note_offset_lut[166] = 17'h00228;   note_offset_lut[167] = 17'h00224;   note_offset_lut[168] = 17'h00221;
    note_offset_lut[169] = 17'h0021e;   note_offset_lut[170] = 17'h0021b;   note_offset_lut[171] = 17'h00218;   note_offset_lut[172] = 17'h00215;
    note_offset_lut[173] = 17'h00211;   note_offset_lut[174] = 17'h0020e;   note_offset_lut[175] = 17'h0020b;   note_offset_lut[176] = 17'h00208;
    note_offset_lut[177] = 17'h00205;   note_offset_lut[178] = 17'h00203;   note_offset_lut[179] = 17'h00200;   note_offset_lut[180] = 17'h001fd;
    note_offset_lut[181] = 17'h001fa;   note_offset_lut[182] = 17'h001f7;   note_offset_lut[183] = 17'h001f4;   note_offset_lut[184] = 17'h001f2;
    note_offset_lut[185] = 17'h001ef;   note_offset_lut[186] = 17'h001ec;   note_offset_lut[187] = 17'h001ea;   note_offset_lut[188] = 17'h001e7;
    note_offset_lut[189] = 17'h001e5;   note_offset_lut[190] = 17'h001e2;   note_offset_lut[191] = 17'h001df;   note_offset_lut[192] = 17'h001dd;
    note_offset_lut[193] = 17'h001db;   note_offset_lut[194] = 17'h001d8;   note_offset_lut[195] = 17'h001d6;   note_offset_lut[196] = 17'h001d3;
    note_offset_lut[197] = 17'h001d1;   note_offset_lut[198] = 17'h001cf;   note_offset_lut[199] = 17'h001cc;   note_offset_lut[200] = 17'h001ca;
    note_offset_lut[201] = 17'h001c8;   note_offset_lut[202] = 17'h001c5;   note_offset_lut[203] = 17'h001c3;   note_offset_lut[204] = 17'h001c1;
    note_offset_lut[205] = 17'h001bf;   note_offset_lut[206] = 17'h001bd;   note_offset_lut[207] = 17'h001ba;   note_offset_lut[208] = 17'h001b8;
    note_offset_lut[209] = 17'h001b6;   note_offset_lut[210] = 17'h001b4;   note_offset_lut[211] = 17'h001b2;   note_offset_lut[212] = 17'h001b0;
    note_offset_lut[213] = 17'h001ae;   note_offset_lut[214] = 17'h001ac;   note_offset_lut[215] = 17'h001aa;   note_offset_lut[216] = 17'h001a8;
    note_offset_lut[217] = 17'h001a6;   note_offset_lut[218] = 17'h001a4;   note_offset_lut[219] = 17'h001a2;   note_offset_lut[220] = 17'h001a0;
    note_offset_lut[221] = 17'h0019e;   note_offset_lut[222] = 17'h0019c;   note_offset_lut[223] = 17'h0019b;   note_offset_lut[224] = 17'h00199;
    note_offset_lut[225] = 17'h00197;   note_offset_lut[226] = 17'h00195;   note_offset_lut[227] = 17'h00193;   note_offset_lut[228] = 17'h00192;
    note_offset_lut[229] = 17'h00190;   note_offset_lut[230] = 17'h0018e;   note_offset_lut[231] = 17'h0018c;   note_offset_lut[232] = 17'h0018b;
    note_offset_lut[233] = 17'h00189;   note_offset_lut[234] = 17'h00187;   note_offset_lut[235] = 17'h00186;   note_offset_lut[236] = 17'h00184;
    note_offset_lut[237] = 17'h00182;   note_offset_lut[238] = 17'h00181;   note_offset_lut[239] = 17'h0017f;   note_offset_lut[240] = 17'h0017d;
    note_offset_lut[241] = 17'h0017c;   note_offset_lut[242] = 17'h0017a;   note_offset_lut[243] = 17'h00179;   note_offset_lut[244] = 17'h00177;
    note_offset_lut[245] = 17'h00176;   note_offset_lut[246] = 17'h00174;   note_offset_lut[247] = 17'h00173;   note_offset_lut[248] = 17'h00171;
    note_offset_lut[249] = 17'h00170;   note_offset_lut[250] = 17'h0016e;   note_offset_lut[251] = 17'h0016d;   note_offset_lut[252] = 17'h0016b;
    note_offset_lut[253] = 17'h0016a;   note_offset_lut[254] = 17'h00168;   note_offset_lut[255] = 17'h00167;
end

//==============================================================
// DMA Loader (clk_sys domain) - Shared arbiter for 8 contexts
//==============================================================

// Loop variable for register initialization
integer i;

// DMA request queue (one bit per context)
reg [7:0] pending_load_sys;      // clk_sys: Bit[i] = context i has pending load request

// Per-context load request parameters (captured on play_strobe)
reg [5:0] sfx_index_req_8x [0:7];   // clk_sys: Requested SFX index per context
reg [5:0] sfx_offset_req_8x [0:7];  // clk_sys: Requested note offset per context
reg [5:0] sfx_length_req_8x [0:7];  // clk_sys[W], clk_pcm_8x[R]: Requested note length per context

// DMA arbiter state
reg [2:0] dma_state;             // clk_sys: L_IDLE, L_START_LOAD, L_LOAD, L_SCAN
reg [2:0] ctx_to_load;           // clk_sys: Context being loaded (0-7)
reg [2:0] last_served;           // clk_sys: Last context served (for round-robin)
reg [7:0] dma_cnt;               // clk_sys: Byte counter within current SFX (0-67)

// Per-context header data storage (clk_sys domain, written during L_SCAN)
reg [7:0] speed_byte_sys_8x [0:7];
reg       bass_flag_sys_8x [0:7];
reg       is_waveform_inst_sys_8x [0:7];
reg [5:0] loop_start_sys_8x [0:7];
reg [5:0] loop_end_sys_8x [0:7];
reg       filt_noiz_sys_8x [0:7];
reg       filt_buzz_sys_8x [0:7];
reg [1:0] filt_detune_sys_8x [0:7];
reg [1:0] filt_reverb_sys_8x [0:7];
reg [1:0] filt_dampen_sys_8x [0:7];

// Completion signaling (toggle-based CDC)
reg [7:0] load_done_toggle_sys;  // clk_sys: Toggle when context load completes

//==============================================================
// DMA Request Capture (clk_sys domain)
//==============================================================
always @(posedge clk_sys) begin
    if (!resetn) begin
        pending_load_sys <= 8'd0;
        for (i=0; i<8; i=i+1) begin
            sfx_index_req_8x[i] <= 6'd0;
            sfx_offset_req_8x[i] <= 6'd0;
            sfx_length_req_8x[i] <= 6'd0;
        end
    end else begin
        // Capture play_strobe pulses and store request parameters
        // Map 4 voice inputs to MAIN contexts (1,3,5,7)
        for (i=0; i<4; i=i+1) begin
            if (play_strobe[i]) begin
                pending_load_sys[ctx_from_voice(i, 1'b1)] <= 1'b1;
                sfx_index_req_8x[ctx_from_voice(i, 1'b1)] <= sfx_index_in[i];
                sfx_offset_req_8x[ctx_from_voice(i, 1'b1)] <= sfx_offset[i];
                sfx_length_req_8x[ctx_from_voice(i, 1'b1)] <= sfx_length[i];
            end else if (dma_state == L_SCAN && ctx_to_load == ctx_from_voice(i, 1'b1)) begin
                // Clear pending flag when load completes
                pending_load_sys[ctx_from_voice(i, 1'b1)] <= 1'b0;
            end
        end

        // Handle custom instrument load requests from clk_pcm_8x
        // Check the 4 voices, loading into their paired CUSTOM contexts (0,2,4,6)
        for (i=0; i<4; i=i+1) begin
            if (custom_load_toggle_sys[i] != custom_load_toggle_sys_q[i]) begin
                pending_load_sys[ctx_from_voice(i, 1'b0)] <= 1'b1;
                sfx_index_req_8x[ctx_from_voice(i, 1'b0)] <= {3'b0, custom_load_wave_pcm[i]};
                sfx_offset_req_8x[ctx_from_voice(i, 1'b0)] <= 6'd0;
                // Custom instruments should loop continuously (6'b111111 = continuous loop mode)
                sfx_length_req_8x[ctx_from_voice(i, 1'b0)] <= 6'b111111;
            end else if (dma_state == L_SCAN && ctx_to_load == ctx_from_voice(i, 1'b0)) begin
                // Clear pending flag when load completes for CUSTOM contexts
                pending_load_sys[ctx_from_voice(i, 1'b0)] <= 1'b0;
            end
        end
    end
end

//==============================================================
// DMA Arbiter FSM (clk_sys domain)
//==============================================================
always @(posedge clk_sys) begin
    if (!resetn) begin
        dma_state <= L_IDLE;
        dma_req <= 1'b0;
        dma_addr <= 31'd0;
        dma_cnt <= 8'd0;
        ctx_to_load <= 3'd0;
        last_served <= 3'd7;  // Start from 7 so first search starts at 0
        load_done_toggle_sys <= 8'd0;
        for (i=0; i<8; i=i+1) begin
            speed_byte_sys_8x[i] <= 8'd1;
            bass_flag_sys_8x[i] <= 1'b0;
            is_waveform_inst_sys_8x[i] <= 1'b0;
            loop_start_sys_8x[i] <= 6'd0;
            loop_end_sys_8x[i] <= 6'd0;
            filt_noiz_sys_8x[i] <= 1'b0;
            filt_buzz_sys_8x[i] <= 1'b0;
            filt_detune_sys_8x[i] <= 2'd0;
            filt_reverb_sys_8x[i] <= 2'd0;
            filt_dampen_sys_8x[i] <= 2'd0;
        end
    end else begin
        case (dma_state)
            L_IDLE: begin
                dma_req <= 1'b0;

                // Round-robin arbiter: find next pending request
                // Search order: (last_served+1), (last_served+2), ..., wrapping around
                if (pending_load_sys != 8'd0) begin
                    // Priority encoder with round-robin starting point
                    if      (pending_load_sys[(last_served+1)&3'b111]) ctx_to_load <= (last_served+1)&3'b111;
                    else if (pending_load_sys[(last_served+2)&3'b111]) ctx_to_load <= (last_served+2)&3'b111;
                    else if (pending_load_sys[(last_served+3)&3'b111]) ctx_to_load <= (last_served+3)&3'b111;
                    else if (pending_load_sys[(last_served+4)&3'b111]) ctx_to_load <= (last_served+4)&3'b111;
                    else if (pending_load_sys[(last_served+5)&3'b111]) ctx_to_load <= (last_served+5)&3'b111;
                    else if (pending_load_sys[(last_served+6)&3'b111]) ctx_to_load <= (last_served+6)&3'b111;
                    else if (pending_load_sys[(last_served+7)&3'b111]) ctx_to_load <= (last_served+7)&3'b111;
                    else if (pending_load_sys[last_served])       ctx_to_load <= last_served;

                    dma_state <= L_START_LOAD;
                end
            end

            L_START_LOAD: begin
                // Calculate DMA address: base + (sfx_index * 68) >> 1 (word address)
                // Start DMA transfer for selected context
                dma_cnt <= 8'd0;
                dma_addr <= (base_addr >> 1) + sfx_index_req_8x[ctx_to_load] * (SFX_BYTES >> 1);
                dma_req <= 1'b1;
                dma_state <= L_LOAD;
            end

            L_LOAD: begin
                // DMA handshake: wait for ack, then pulse req for next transfer
                if (dma_ack) begin
                    // DMA acknowledge received - write data to context's SFX memory
                    // Big-endian: bits[15:8] = first byte, bits[7:0] = second byte

                    if (dma_cnt < 64) begin
                        // Bytes 0-63: Note data (32 notes × 2 bytes) - write to cache
                        sfx_notes[{ctx_to_load, dma_cnt[5:1]}] <= dma_rdata;
                    end else if (dma_cnt == 64) begin
                        // Bytes 64-65: FILTERS (byte 64) and SPEED (byte 65)
                        header_filters_sys_8x[ctx_to_load] <= dma_rdata[15:8];
                        header_speed_sys_8x[ctx_to_load] <= dma_rdata[7:0];
                    end else if (dma_cnt == 66) begin
                        // Bytes 66-67: LOOPST (byte 66) and LOOPEN (byte 67)
                        header_loopst_sys_8x[ctx_to_load] <= dma_rdata[15:8];
                        header_loopen_sys_8x[ctx_to_load] <= dma_rdata[7:0];
                    end

                    dma_cnt <= dma_cnt + 2;
                    dma_addr <= dma_addr + 1;  // Increment by 1 word (2 bytes)

                    if (dma_cnt + 2 >= SFX_BYTES) begin
                        // Done loading SFX - move to header scan
                        dma_req <= 1'b0;
                        dma_state <= L_SCAN;
                    end else begin
                        // More data to fetch - pulse request for next transfer
                        dma_req <= 1'b1;
                    end
                end else begin
                    // No ack - clear pulse (single cycle only)
                    dma_req <= 1'b0;
                end
            end

            L_SCAN: begin
                // Decode SFX header for current context
                speed_byte_sys_8x[ctx_to_load] <= (header_speed_sys_8x[ctx_to_load] == 8'd0) ?
                                                   8'd1 : header_speed_sys_8x[ctx_to_load];
                bass_flag_sys_8x[ctx_to_load] <= header_speed_sys_8x[ctx_to_load][0];
                loop_start_sys_8x[ctx_to_load] <= header_loopst_sys_8x[ctx_to_load][5:0];
                loop_end_sys_8x[ctx_to_load] <= header_loopen_sys_8x[ctx_to_load][5:0];
                filt_noiz_sys_8x[ctx_to_load] <= header_filters_sys_8x[ctx_to_load][1];
                filt_buzz_sys_8x[ctx_to_load] <= header_filters_sys_8x[ctx_to_load][2];

                // filt_detune: (x/8)%3 using bit shift and mod3 lookup
                case (header_filters_sys_8x[ctx_to_load][7:3])
                    5'd0, 5'd3, 5'd6, 5'd9, 5'd12, 5'd15, 5'd18, 5'd21, 5'd24, 5'd27, 5'd30:
                        filt_detune_sys_8x[ctx_to_load] <= 2'd0;
                    5'd1, 5'd4, 5'd7, 5'd10, 5'd13, 5'd16, 5'd19, 5'd22, 5'd25, 5'd28, 5'd31:
                        filt_detune_sys_8x[ctx_to_load] <= 2'd1;
                    default:
                        filt_detune_sys_8x[ctx_to_load] <= 2'd2;
                endcase

                // filt_reverb: (x/24)%3
                case (header_filters_sys_8x[ctx_to_load][7:3])
                    5'd0, 5'd1, 5'd2, 5'd9, 5'd10, 5'd11, 5'd18, 5'd19, 5'd20, 5'd27, 5'd28, 5'd29:
                        filt_reverb_sys_8x[ctx_to_load] <= 2'd0;
                    5'd3, 5'd4, 5'd5, 5'd12, 5'd13, 5'd14, 5'd21, 5'd22, 5'd23, 5'd30, 5'd31:
                        filt_reverb_sys_8x[ctx_to_load] <= 2'd1;
                    default:
                        filt_reverb_sys_8x[ctx_to_load] <= 2'd2;
                endcase

                // filt_dampen: (x/72)%3
                case (header_filters_sys_8x[ctx_to_load][7:3])
                    5'd0, 5'd1, 5'd2, 5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8:
                        filt_dampen_sys_8x[ctx_to_load] <= 2'd0;
                    5'd9, 5'd10, 5'd11, 5'd12, 5'd13, 5'd14, 5'd15, 5'd16, 5'd17:
                        filt_dampen_sys_8x[ctx_to_load] <= 2'd1;
                    default:
                        filt_dampen_sys_8x[ctx_to_load] <= 2'd2;
                endcase

                // Check if waveform instrument (bit 7 of loop_start, only for SFX 0-7)
                is_waveform_inst_sys_8x[ctx_to_load] <= (sfx_index_req_8x[ctx_to_load] <= 6'd7) &&
                                                         header_loopst_sys_8x[ctx_to_load][7];

                // Signal completion via toggle
                load_done_toggle_sys[ctx_to_load] <= ~load_done_toggle_sys[ctx_to_load];

                // Update round-robin pointer
                last_served <= ctx_to_load;

                // Return to idle to check for more requests
                dma_state <= L_IDLE;
            end

            default: begin
                dma_state <= L_IDLE;
            end
        endcase
    end
end

//==============================================================
// CDC: clk_sys -> clk_pcm_8x
//==============================================================

// Toggle synchronizers and sticky flags(clk_pcm_8x domain)
reg [7:0] load_done_toggle_pcm;
reg [7:0] load_done_toggle_pcm_q;
reg [7:0] load_done_pcm_sticky;  // Sticky flag for load completion (persist until cleared)

// Force stop/release synchronizers and sticky flags
reg [7:0] force_stop_toggle_sys;
reg [7:0] force_stop_toggle_pcm;
reg [7:0] force_stop_toggle_pcm_q;
reg [7:0] force_stop_pcm_sticky;  // Sticky flags for force_stop (persist until cleared)

reg [7:0] force_release_toggle_sys;
reg [7:0] force_release_toggle_pcm;
reg [7:0] force_release_toggle_pcm_q;
reg [7:0] force_release_pcm_sticky;  // Sticky flags for force_release (persist until cleared)

// Generate toggles on force_stop/force_release inputs (clk_sys domain)
always @(posedge clk_sys) begin
    if (!resetn) begin
        force_stop_toggle_sys <= 8'd0;
        force_release_toggle_sys <= 8'd0;
    end else begin
        for (i=0; i<4; i=i+1) begin
            if (force_stop[i]) begin
                force_stop_toggle_sys[ctx_from_voice(i, 1'b1)] <= ~force_stop_toggle_sys[ctx_from_voice(i, 1'b1)];  // Contexts 1,3,5,7
            end
            if (force_release[i]) begin
                force_release_toggle_sys[ctx_from_voice(i, 1'b1)] <= ~force_release_toggle_sys[ctx_from_voice(i, 1'b1)];  // Contexts 1,3,5,7
            end
        end
    end
end

// HWFX synchronizers (clk_sys -> clk_pcm_8x)
always @(posedge clk_sys) begin
    if (!resetn) begin
        hwfx_5f40_sys <= 8'd0;
        hwfx_5f41_sys <= 8'd0;
        hwfx_5f42_sys <= 8'd0;
        hwfx_5f43_sys <= 8'd0;
    end else begin
        hwfx_5f40_sys <= hwfx_5f40;
        hwfx_5f41_sys <= hwfx_5f41;
        hwfx_5f42_sys <= hwfx_5f42;
        hwfx_5f43_sys <= hwfx_5f43;
    end
end

// Synchronize custom load request to clk_sys
always @(posedge clk_sys) begin
    if (!resetn) begin
        custom_load_toggle_sys <= 4'd0;
        custom_load_toggle_sys_q <= 4'd0;
    end else begin
        custom_load_toggle_sys <= custom_load_toggle_pcm;
        custom_load_toggle_sys_q <= custom_load_toggle_sys;
    end
end

// Synchronize to clk_pcm_8x and detect edges
always @(posedge clk_pcm_8x) begin
    if (!resetn) begin
        load_done_toggle_pcm <= 8'd0;
        load_done_toggle_pcm_q <= 8'd0;
        force_stop_toggle_pcm <= 8'd0;
        force_stop_toggle_pcm_q <= 8'd0;
        force_release_toggle_pcm <= 8'd0;
        force_release_toggle_pcm_q <= 8'd0;
    end else begin
        // Two-stage synchronizers
        load_done_toggle_pcm <= load_done_toggle_sys;
        load_done_toggle_pcm_q <= load_done_toggle_pcm;

        force_stop_toggle_pcm <= force_stop_toggle_sys;
        force_stop_toggle_pcm_q <= force_stop_toggle_pcm;

        force_release_toggle_pcm <= force_release_toggle_sys;
        force_release_toggle_pcm_q <= force_release_toggle_pcm;
    end
end

always @(posedge clk_pcm_8x) begin
    if (!resetn) begin
        hwfx_5f40_pcm <= 8'd0;
        hwfx_5f40_pcm_q <= 8'd0;
        hwfx_5f41_pcm <= 8'd0;
        hwfx_5f41_pcm_q <= 8'd0;
        hwfx_5f42_pcm <= 8'd0;
        hwfx_5f42_pcm_q <= 8'd0;
        hwfx_5f43_pcm <= 8'd0;
        hwfx_5f43_pcm_q <= 8'd0;
    end else begin
        hwfx_5f40_pcm <= hwfx_5f40_sys;
        hwfx_5f40_pcm_q <= hwfx_5f40_pcm;
        hwfx_5f41_pcm <= hwfx_5f41_sys;
        hwfx_5f41_pcm_q <= hwfx_5f41_pcm;
        hwfx_5f42_pcm <= hwfx_5f42_sys;
        hwfx_5f42_pcm_q <= hwfx_5f42_pcm;
        hwfx_5f43_pcm <= hwfx_5f43_sys;
        hwfx_5f43_pcm_q <= hwfx_5f43_pcm;
    end
end

// Edge detection strobes (transient, single-cycle pulses)
wire [7:0] force_stop_strobe = force_stop_toggle_pcm ^ force_stop_toggle_pcm_q;
wire [7:0] force_release_strobe = force_release_toggle_pcm ^ force_release_toggle_pcm_q;
wire [7:0] load_done_strobe = load_done_toggle_pcm ^ load_done_toggle_pcm_q;

//==============================================================
// Load Done Handler Task (clk_pcm_8x domain)
//==============================================================
// Handle DMA load completion in IDLE state
task load_done;
    begin
        // Copy header data from clk_sys domain (CDC crossing - safe because sys domain is idle)
        speed_byte_8x[ctx_idx] <= speed_byte_sys_8x[ctx_idx];
        bass_flag_8x[ctx_idx] <= bass_flag_sys_8x[ctx_idx];
        is_waveform_inst_8x[ctx_idx] <= is_waveform_inst_sys_8x[ctx_idx];
        loop_start_8x[ctx_idx] <= loop_start_sys_8x[ctx_idx];
        loop_end_8x[ctx_idx] <= loop_end_sys_8x[ctx_idx];
        filt_noiz_8x[ctx_idx] <= filt_noiz_sys_8x[ctx_idx];
        filt_buzz_8x[ctx_idx] <= filt_buzz_sys_8x[ctx_idx];
        filt_detune_8x[ctx_idx] <= filt_detune_sys_8x[ctx_idx];
        filt_reverb_8x[ctx_idx] <= filt_reverb_sys_8x[ctx_idx];
        filt_dampen_8x[ctx_idx] <= filt_dampen_sys_8x[ctx_idx];
        start_idx_8x[ctx_idx] <= (sfx_offset_req_8x[ctx_to_load] > 6'd31) ?
                                        6'd31 : sfx_offset_req_8x[ctx_to_load];
        sfx_length_val_8x[ctx_idx] <= sfx_length_req_8x[ctx_idx];

        // Initialize playback state for this context
        note_idx_8x[ctx_idx] <= start_idx;
        phase_acc_8x[ctx_idx] <= 22'd0;
        detune_acc_8x[ctx_idx] <= 22'd0;
        releasing_8x[ctx_idx] <= 1'b0;
        note_offset_8x[ctx_idx] <= 24'd0;
        attack_ctr_8x[ctx_idx] <= 5'd16;
        release_ctr_8x[ctx_idx] <= 5'd0;
        arp_active_8x[ctx_idx] <= 1'b0;
        arp_accum_8x[ctx_idx] <= 3'd0;
        next_group_pos_8x[ctx_idx] <= 2'd0;

        // Waveform instrument gets special initialization
        // Use is_waveform_inst_sys_8x directly since is_waveform_inst_8x was just updated above
        if (is_waveform_inst_sys_8x[ctx_idx]) begin
            cur_custom_8x[ctx_idx] <= 1'd0;
            cur_eff_8x[ctx_idx] <= 3'd0;
            cur_vol_8x[ctx_idx] <= 3'd5;
            cur_wave_8x[ctx_idx] <= 3'd0;
            cur_pitch_8x[ctx_idx] <= 6'd24;
            attack_ctr_8x[ctx_idx] <= 5'd0;
            releasing_8x[ctx_idx] <= 1'b0;
            // Clear sfx_data to prevent playing from stale data
            sfx_data_8x[ctx_idx] <= 16'd0;
            // Waveform instruments start immediately in PLAYING
            pcm_state[ctx_idx] <= PCM_PLAYING;
        end else begin
            eff_inc_8x[ctx_idx] <= 18'd0;
            detune_inc_8x[ctx_idx] <= 18'd0;
            eff_vol_8x[ctx_idx] <= 8'd0;

            // Note instruments: Set counters to just before note tick so normal timing logic handles initial decode
            // Need to be 3 samples before tick to allow time for:
            // - Sample -3: Default RAM read of note_idx
            // - Sample -2: Check for arpeggio, read arpeggio note if needed
            // - Sample -1: decode_current_note(), advance_note()
            // - Sample 0: First note tick, transition from PCM_WARM_UP to PCM_PLAYING
            sample_ctr_8x[ctx_idx] <= NOTE_TICK_DIV - 8'd3;
            note_ctr_8x[ctx_idx] <= speed_byte - 8'd1;

            pcm_state[ctx_idx] <= PCM_WARM_UP;
        end
    end
endtask

//==============================================================
// DSP Effects & Pitch Calculation (clk_pcm_8x domain)
//==============================================================
task calculate_eff_inc;
    reg [17:0] base_inc;                // U18F18 base phase increment
    reg [17:0] base_inc_prev;           // U18F18 previous phase increment
    reg signed [11:0] vib_temp;         // U12F12
    reg signed [18:0] slide_diff;       // S19F18 slide difference
    reg signed [11:0] vibrato_alpha;    // S12F11 vibrato multiplier
    localparam S12F11_0_5 = 12'sd1024;  // S12F11 representation of 0.5
    localparam S12F11_0_25 = 12'sd512;  // S12F11 representation of 0.25
    begin
        // Apply note effects to compute base phase increment
        case (cur_eff)
            3'd1: begin  // Slide from prev_pitch to cur_pitch
                if (prev_pitch != cur_pitch) begin
                    base_inc_prev = pitch_phase_inc[prev_pitch] >> (bass_flag ? 1 : 0);
                    base_inc = pitch_phase_inc[cur_pitch] >> (bass_flag ? 1 : 0);
                    // Linear interpolation: U18F18 base_inc = U18F18 base_inc_prev + (((U18F18 base_inc - U18F18 base_inc_prev) * U24F24 note_offset) >>> 24)
                    slide_diff = $signed({1'b0, base_inc}) - $signed({1'b0, base_inc_prev});
                    base_inc = base_inc_prev + (($signed({{24{slide_diff[18]}}, slide_diff}) * {{19{1'b0}}, note_offset}) >>> 24);
                end else begin
                    base_inc = pitch_phase_inc[cur_pitch] >> (bass_flag ? 1 : 0);
                end
            end

            3'd2: begin  // Vibrato: ~7.5 Hz (10.77Hz), +/-~0.5 (0.53) semitone
                base_inc = (pitch_phase_inc[cur_pitch] >> (bass_flag ? 1 : 0));
                // S12F11 vibrato_alpha = abs(U11F11 eff_vib_phase - S12F11 0.5) - S12F11 0.25
                vib_temp = $signed({1'b0, eff_vib_phase}) - S12F11_0_5;
                vibrato_alpha = $signed((vib_temp < 0 ? -vib_temp : vib_temp) - S12F11_0_25);
                // U18F18 base_inc = U18F18 base_inc + ((U18F18 base_inc / S6F0 32) * S12F11 vibrato_alpha) >>> 11
                //                 = U18F18 base_inc + (U18F18 base_inc * S12F11 vibrato_alpha) >>> 16
                base_inc = base_inc + ($signed({{12'd0, base_inc}}) * $signed({{18{vibrato_alpha[11]}}, vibrato_alpha})) >> 16;
            end

            3'd3: begin  // Drop: freq *= (1.0 - note_offset)
                base_inc = pitch_phase_inc[cur_pitch] >> (bass_flag ? 1 : 0);
                // U18F18 base_inc = U18F18 base_inc * (U24F24 1 - U24F24 note_offset) >> 24
                base_inc = ({{24'd0, base_inc}} * {{18'd0, ~note_offset}}) >> 24;
            end

            default: begin  // No pitch effect (effects 0, 4, 5, 6, 7 affect volume only)
                base_inc = pitch_phase_inc[cur_pitch] >> (bass_flag ? 1 : 0);
            end
        endcase

        // Hardware FX: octave-down (bit 4-7 of hwfx_5f40 for channels 0-3)
        if (hwfx_5f40_val[{1'b1, voice_idx}]) begin
            base_inc = base_inc >> 1;
        end

        // Phase multiplier for custom instruments (CUSTOM->MAIN coupling)
        // MAIN contexts (ctx_idx[0]=1, odd) compute phase multiplier for output
        // CUSTOM contexts (ctx_idx[0]=0, even) will read from their paired MAIN (ctx_idx+1)
        if (is_main_context(ctx_idx) && cur_custom) begin
            // MAIN context (odd) with custom instrument: compute pitch ratio relative to C2
            // U18F12 phase_mult = (U18F18 base_inc << 12) / U18F18 pitch_phase_inc[PITCH_REF_C2]
            phase_mult_8x[ctx_idx] = ($signed({base_inc, {12{1'b0}}}) / $signed({1'b0, pitch_phase_inc[PITCH_REF_C2]}));
        end else begin
            phase_mult_8x[ctx_idx] = 18'd0;
        end

        // CUSTOM instrument: apply phase multiplier from paired MAIN context
        // CUSTOM contexts (ctx_idx[0]=0, even) read phase_mult from their MAIN partner (ctx_idx+1)
        // MAIN contexts (ctx_idx[0]=1, odd) use base_inc directly
        if (!is_main_context(ctx_idx) && phase_mult_8x[ctx_idx + 1] != 18'd0) begin
            // CUSTOM context (even): multiply base_inc by phase multiplier from MAIN
            // U18F18 eff_inc = U18F18 base_inc * U18F12 phase_mult >> 12
            eff_inc_8x[ctx_idx] = ({{18'd0, base_inc}} * phase_mult_8x[ctx_idx + 1]) >> 12;
        end else begin
            // MAIN context or CUSTOM without multiplier: use base_inc
            eff_inc_8x[ctx_idx] = base_inc;  // U18F18
        end
    end
endtask

task calculate_detune_inc;
    begin
        // Calculate detune phase increment based on waveform
        case (cur_wave)
            3'd0: begin  // TRIANGLE
                if (filt_detune == 2'd1)
                    detune_inc_8x[ctx_idx] = eff_inc - (eff_inc >> 2);
                else if (filt_detune == 2'd2)
                    detune_inc_8x[ctx_idx] = eff_inc + (eff_inc >> 1);
                else
                    detune_inc_8x[ctx_idx] = eff_inc;
            end

            3'd5: begin  // ORGAN
                if (filt_detune == 2'd1)
                    detune_inc_8x[ctx_idx] = eff_inc + (eff_inc >> 8);
                else if (filt_detune == 2'd2)
                    detune_inc_8x[ctx_idx] = (eff_inc + (eff_inc >> 8)) << 2;
                else
                    detune_inc_8x[ctx_idx] = eff_inc;
            end

            3'd7: begin  // PHASER
                if (filt_detune == 2'd1)
                    detune_inc_8x[ctx_idx] = eff_inc - (eff_inc >> 6);
                else if (filt_detune == 2'd2)
                    detune_inc_8x[ctx_idx] = (eff_inc + (eff_inc >> 8)) << 1;
                else
                    detune_inc_8x[ctx_idx] = eff_inc;
            end

            default: begin  // Other waveforms
                if (filt_detune == 2'd1)
                    detune_inc_8x[ctx_idx] = eff_inc + (eff_inc >> 8);
                else if (filt_detune == 2'd2)
                    detune_inc_8x[ctx_idx] = (eff_inc + (eff_inc >> 8)) << 1;
                else
                    detune_inc_8x[ctx_idx] = eff_inc;
            end
        endcase
    end
endtask

task calculate_eff_vol;
    reg signed [3:0] vol_diff;  // S4F0 volume difference
    begin
        // Volume effects
        case (cur_eff)
            3'd1: begin  // Slide: interpolate volume
                if (prev_vol > 3'd0) begin
                    // U8F0 eff_vol = (U3F0 prev_vol << 5) + ((U3F0 cur_vol - U3F0 prev_vol) * U24F24 note_offset) >> 19
                    vol_diff = $signed({1'b0, cur_vol}) - $signed({1'b0, prev_vol});
                    eff_vol_8x[ctx_idx] = (prev_vol << 5) + (({{24{vol_diff[3]}}, vol_diff} * $signed({{4'd0, note_offset}})) >> 19);
                end else begin
                    eff_vol_8x[ctx_idx] = cur_vol << 5;
                end
            end

            3'd4: begin  // Fade in: volume * note_offset
                // U8F0 eff_vol = U3F0 cur_vol * U24F24 note_offset >> 24
                eff_vol_8x[ctx_idx] = ({{24'd0, cur_vol}} * {{5'd0, note_offset}}) >> 24;
            end

            3'd5: begin  // Fade out: volume * (1.0 - note_offset)
                // U8F0 eff_vol = U3F0 cur_vol * (U24F24 1 - U24F24 note_offset) >> 24
                // ~note_offset = 1-note_offset.
                eff_vol_8x[ctx_idx] = ({{24'd0, cur_vol}} * {{5'd0, (~note_offset)}}) >>>24;
            end

            default: begin  // No volume effect
                eff_vol_8x[ctx_idx] = cur_vol << 5;
            end
        endcase
    end
endtask

//==============================================================
// Per-Context Note Timing & Processing (clk_pcm_8x domain)
//==============================================================
// Decode note task (sets current note parameters from RAM data)
task decode_current_note;
    reg [7:0] note_byte0;  // Low byte of current note
    reg [7:0] note_byte1;  // High byte of current note
    reg       custom;
    reg [2:0] eff;
    reg [3:0] vol;
    reg [2:0] wave;
    reg [5:0] pitch;
    reg       should_attack;
    begin
        // Save previous note for slide effect
        prev_pitch_8x[ctx_idx] <= cur_pitch;
        prev_vol_8x[ctx_idx] <= cur_vol;

        // Read note bytes from RAM (sfx_data was pre-fetched in main always block)
        // sfx_data[15:8] = byte0, sfx_data[7:0] = byte1
        note_byte0 = sfx_data[15:8];
        note_byte1 = sfx_data[7:0];

        // Decode note parameters
        custom = note_byte1[7];
        eff    = note_byte1[6:4];
        vol    = note_byte1[3:1];
        wave   = {note_byte1[0], note_byte0[7:6]};
        pitch  = note_byte0[5:0];

        // Store current note parameters
        cur_custom_8x[ctx_idx] <= custom;
        cur_eff_8x[ctx_idx] <= eff;
        cur_vol_8x[ctx_idx] <= vol;
        cur_wave_8x[ctx_idx] <= wave;
        cur_pitch_8x[ctx_idx] <= pitch;

        // Arpeggio speed calculation
        arp_speed_8x[ctx_idx] <= (eff == 3'd6) ? ((speed_byte <= 8) ? 8'd2 : 8'd4) :
                                 (eff == 3'd7) ? ((speed_byte <= 8) ? 8'd4 : 8'd8) :
                                 8'd0;

        // Check if attack is needed
        should_attack = (eff != 3'd1) &&
                        (custom != 1'b1 ||
                        ((wave != cur_wave ||
                            pitch != cur_pitch ||
                            cur_vol == 3'd0) ^ (vol == 3'd3)));
        if (should_attack) begin
            attack_ctr_8x[ctx_idx] <= 5'd16;
        end
        releasing_8x[ctx_idx] <= 1'b0;

        // Handle custom instruments: when cur_custom is set, trigger SFX loading on paired CUSTOM context
        if (custom && is_main_context(ctx_idx)) begin
            // MAIN context with custom instrument: request loading of SFX with ID = cur_wave on paired CUSTOM context
            if ((pcm_state[custom_from_main(ctx_idx)] == PCM_IDLE) || ((cur_wave != wave || pitch != cur_pitch || cur_vol == 3'd0) ^ (eff == 3'd3))) begin
                custom_load_toggle_pcm[voice_from_ctx(ctx_idx)] <= ~custom_load_toggle_pcm[voice_from_ctx(ctx_idx)];
                custom_load_wave_pcm[voice_from_ctx(ctx_idx)] <= wave;
                pcm_state[custom_from_main(ctx_idx)] <= PCM_IDLE;
            end
        end else if (!custom && is_main_context(ctx_idx) && cur_custom) begin
            // Switching away from custom instrument: stop the paired CUSTOM context's SFX
            pcm_state[custom_from_main(ctx_idx)] <= PCM_IDLE;
        end
    end
endtask

// Advance to next note task
task advance_note;
    output reg should_stop;
    output reg new_arpeggio_group;
    reg [5:0] new_note_idx;
    begin
        // Default: not stopping
        should_stop = 1'b0;

        // Compute new note_idx based on mode
        new_note_idx = note_idx; // default

        // Advance note index based on mode
        if (sfx_length_val == 6'b111111) begin
            // Continuous loop mode
            if (note_idx == NOTE_MAX_INDEX) begin
                new_note_idx = 6'd0;
            end else begin
                new_note_idx = note_idx + 1;
            end
        end else if (sfx_length_val != 6'd0) begin
            // Limited-length mode
            if (note_idx == NOTE_MAX_INDEX + 1 || note_idx >= start_idx + sfx_length_val) begin
                should_stop = 1'b1;
            end else begin
                new_note_idx = note_idx + 1;
            end
        end else begin
            // Full SFX mode: check loop points
            if ((loop_start != 6'd0) && (loop_end == 6'd0)) begin
                // Play from 0 up to (but not including) loop_start, then stop
                if (note_idx >= loop_start) begin
                    should_stop = 1'b1;
                end else begin
                    new_note_idx = note_idx + 1;
                end
            end else if (loop_start == loop_end) begin
                // No loop: play through once
                if (note_idx == NOTE_MAX_INDEX + 1) begin
                    should_stop = 1'b1;
                end else begin
                    new_note_idx = note_idx + 1;
                end
            end else begin
                // Normal loop
                if (note_idx == loop_end) begin
                    new_note_idx = loop_start;
                end else if (note_idx == NOTE_MAX_INDEX) begin
                    new_note_idx = loop_start;
                end else begin
                    new_note_idx = note_idx + 1;
                end
            end
        end

        // Apply the new note_idx
        note_idx_8x[ctx_idx] <= new_note_idx;

        // Reset arpeggio group position if we moved to a new group
        if (new_note_idx[5:2] != note_idx[5:2]) begin
            new_arpeggio_group <= 1'b1;
        end else begin
            new_arpeggio_group <= 1'b0;
        end
    end
endtask

// Advance sample and note timing
task advance_note_timing;
    reg should_stop;
    reg new_arpeggio_group;
    begin
        // Start releasing 16 samples before the next note or arpeggio advance
        // Check if we're close to advancing
        if (sample_ctr == NOTE_TICK_DIV - 16) begin
            if (note_ctr >= speed_byte - 1 ||
                (arp_active && (arp_accum + 1 >= arp_speed))) begin
                // About to advance to next note
                releasing_8x[ctx_idx] <= 1'b1;
                release_ctr_8x[ctx_idx] <= 5'd16;
            end
        end

        // Arpeggio accumulator: increment every sample when arpeggio is active
        if (arp_active && sample_ctr >= NOTE_TICK_DIV - 1) begin
            if (arp_accum >= arp_speed - 1) begin
                arp_accum_8x[ctx_idx] <= 3'd0;

                // Advance to next position in group
                next_group_pos_8x[ctx_idx] <= (next_group_pos == 2'd3) ? 2'd0 : (next_group_pos + 2'd1);
            end else begin
                arp_accum_8x[ctx_idx] <= arp_accum + 3'd1;
            end
        end

        // Sample counter: increment every cycle
        if (sample_ctr >= NOTE_TICK_DIV - 1) begin
            sample_ctr_8x[ctx_idx] <= 8'd0;

            // Note counter: check if note should advance
            if (note_ctr >= speed_byte - 1) begin
                note_ctr_8x[ctx_idx] <= 8'd0;

                // Advance to next note
                advance_note(should_stop, new_arpeggio_group);

                if (new_arpeggio_group) begin
                    next_group_pos_8x[ctx_idx] <= 2'd0;
                end

                // Handle state transitions after first note advance
                if (should_stop) begin
                    pcm_state[ctx_idx] <= PCM_STOPPING;
                end else begin
                    // Transition from warm-up to playing after first note decoded
                    pcm_state[ctx_idx] <= PCM_PLAYING;
                end
            end else begin
                note_ctr_8x[ctx_idx] <= note_ctr + 1;
            end
        end else begin
            sample_ctr_8x[ctx_idx] <= sample_ctr + 1;
        end
    end
endtask

// Noise state update task
task update_noise_state;
    reg signed [8:0]  brown_err;    // S9F8
    reg [7:0]         brown_alpha;  // U8F8
    begin
        // LFSR for noise
        lfsr_8x[ctx_idx] <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[1]^lfsr[0]};

        // Brown noise IIR
        brown_alpha = eff_inc[17:10];
        brown_err = $signed(lfsr) - brown_state;
        // S8F7 brown_state = S8F7 brown_state + ((S9F8 brown_err * U8F8 brown_alpha * 8) >>> 8)
        brown_state_8x[ctx_idx] <= brown_state + (($signed({{11{brown_err[8]}}, brown_err}) * $signed({{9{1'b0}}, {brown_alpha, {3{1'b0}}}})) >>> 8);
    end
endtask

// Tick one sample
task sample_tick;
    begin
        // Update sample and note timing
        if (!is_waveform_inst) begin
            advance_note_timing();
        end

        // Calculate effective phase increment
        calculate_eff_inc();

        // Calculate detune phase increment
        calculate_detune_inc();

        // Calculate effective volume
        calculate_eff_vol();

        // Phase accumulator updates
        phase_acc_8x[ctx_idx] <= phase_acc + eff_inc;
        detune_acc_8x[ctx_idx] <= detune_acc + detune_inc;
        // Vibrato phase accumulator (~7.5 Hz (10.77 Hz) modulation)
        eff_vib_phase_8x[ctx_idx] <= eff_vib_phase + 1;

        // Note offset ramp (for slide/drop effects)
        note_offset_8x[ctx_idx] <= note_offset + {7'b0, note_offset_lut[speed_byte]};

        // Attack/release counters
        if (attack_ctr != 5'd0) begin
            attack_ctr_8x[ctx_idx] <= attack_ctr - 1;
        end
        if (release_ctr != 5'd0) begin
            release_ctr_8x[ctx_idx] <= release_ctr - 1;
        end

        // Update noise state (LFSR and brown noise)
        update_noise_state();
    end
endtask

//==============================================================
// Waveform Generation Tasks
//==============================================================
// Hardware FX local wires (from hwfx CDC registers)
wire hw_low_rev = hwfx_5f41_val[{1'b0, voice_idx}];
wire hw_high_rev = hwfx_5f41_val[{1'b1, voice_idx}];
wire hw_low_bcr = hwfx_5f42_val[{1'b0, voice_idx}];
wire hw_high_bcr = hwfx_5f42_val[{1'b1, voice_idx}];
wire hw_low_dmp = hwfx_5f43_val[{1'b0, voice_idx}];
wire hw_high_dmp = hwfx_5f43_val[{1'b1, voice_idx}];

// Base waveform generation task
// Waveform generation task (takes phase accumulator as input)
task waveform_gen;
    input [21:0] phase_in;      // U22F18 phase input
    output [7:0] sample_out;    // S8F7 waveform sample output

    // S22F18 fixed-point constants for waveform generation
    localparam signed [21:0] S22F18_ONE      = 22'sd262144;   // 1.0
    localparam signed [21:0] S22F18_TWO      = 22'sd524288;   // 2.0
    localparam signed [21:0] S22F18_THREE    = 22'sd786432;   // 3.0
    localparam signed [21:0] S22F18_FOUR     = 22'sd1048576;  // 4.0
    localparam signed [21:0] S22F18_SIX      = 22'sd1572864;  // 6.0
    localparam signed [21:0] S22F18_TWELVE   = 22'sd3145728;  // 12.0
    localparam signed [21:0] S22F18_HALF     = 22'sd131072;   // 0.5
    localparam signed [21:0] S22F18_QUARTER  = 22'sd65536;    // 0.25
    localparam signed [21:0] S22F18_EIGHTH   = 22'sd32768;    // 0.125
    localparam signed [21:0] S22F18_0_875    = 22'sd229376;   // 0.875
    localparam signed [21:0] S22F18_0_975    = 22'sd255590;   // 0.975
    localparam signed [21:0] S22F18_0_653    = 22'sd171179;   // 0.653
    localparam signed [21:0] S22F18_0_83     = 22'sd217579;   // 0.83
    localparam signed [21:0] S22F18_0_085    = 22'sd22282;    // 0.085
    localparam signed [21:0] S22F18_NEG_1_875= -22'sd491520;  // -1.875
    localparam signed [21:0] S22F18_0_125    = 22'sd32768;    // 0.0125
    localparam signed [21:0] S22F18_0_2      = 22'sd52429;    // 0.2
    localparam signed [21:0] S22F18_1_5      = 22'sd393216;   // 1.5 (for NOISE scaling)
    localparam [21:0] U22F18_109_110         = 22'd259770;    // 109/110 ≈ 0.990909 (for PHASER)

    // S8F7 fixed-point constants for waveform output
    localparam signed [7:0] S8F7_QUARTER    = 8'sd32;       // 0.25 in S8F7 (for SQUARE/PULSE)

    reg signed [21:0] t;           // S22F18 phase fraction (used by all waveforms)
    // General-purpose temporaries - shared across mutually-exclusive waveforms
    reg signed [21:0] temp0;       // S22F18
    reg signed [21:0] temp1;       // S22F18
    reg signed [21:0] temp2;       // S22F18
    reg signed [21:0] temp3;       // S22F18
    reg signed [21:0] temp4;       // S22F18
    reg [21:0] temp5;              // U22F18
    // Specialized wide temporaries - different bit widths
    reg signed [38:0] div6_temp;     // Temporary for divide-by-6 (phaser_temp * 43691)
    reg signed [29:0] noise_mult1_temp;  // Temporary for brown_state * saw_base (8-bit × 22-bit)
    reg signed [43:0] noise_mult2_temp;  // Temporary for temp4 * temp0 (22-bit × 22-bit)
    reg signed [43:0] noise_scale_temp;  // Temporary for scale calculations in NOISE
    reg [43:0] phaser_mult_temp;   // U44F36 temporary for phaser multiplication
    reg signed [44:0] organ_temp;  // S45F36 temporary for organ calculations
    reg signed [26:0] organ_abs;   // S27F18 after shift, for abs operation
    begin
        // Standard waveform generation using full phase precision

        t = $signed({4'b0, phase_in[17:0]});

        case (cur_wave)
            3'd0: begin // TRIANGLE
                // S22F18 temp1 = (4 * S22F18 t) - S22F18 2.0
                temp1 = (t <<< 2) - S22F18_TWO;
                // S22F18 temp1 = abs(S22F18 temp1)
                temp1 = temp1[21] ? -temp1 : temp1;
                // S22F18 temp2 = S22F18 1.0 - S22F18 temp1
                temp2 = S22F18_ONE - temp1;
                if (filt_buzz) begin
                    // Tilted saw component for blending
                    // Uses same formula as TILTED_SAW with a=0.875
                    if (t < S22F18_0_875) begin
                        // Rising segment: 2 * t / 0.875 - 1.0
                        // S22F18 temp4 = S22F18 t * 2
                        temp4 = t <<< 1;
                        // S22F18 temp3 = (S22F18 temp4 / S22F18 0.875) - S22F18 1.0
                        temp3 = ($signed({temp4, 18'b0}) / $signed({{18{S22F18_0_875[21]}}, S22F18_0_875})) - S22F18_ONE;
                    end else begin
                        // Falling segment: 2 * ((1 - t) / (1 - 0.875)) - 1.0
                        // S22F18 temp4 = (S22F18 1.0 - S22F18 t) * 2
                        temp4 = (S22F18_ONE - t) <<< 1;
                        // S22F18 temp3 = (S22F18 temp4 / S22F18 0.125) - S22F18 1.0
                        temp3 = ($signed({temp4, 18'b0}) / $signed({{18{S22F18_0_125[21]}}, S22F18_0_125})) - S22F18_ONE;
                    end
                    // Blend: 75% triangle + 25% tilted_saw
                    // S22F18 temp0 = (S22F18 temp2 * 3 + S22F18 temp3) >>> 2
                    temp0 = (($signed({{22{temp2[21]}}, temp2}) * $signed(22'sd3)) +
                                     ($signed({{22{temp3[21]}}, temp3}))) >>> 2;
                end else begin
                    temp0 = temp2;
                end
                // Scale by 0.5
                // S22F18 temp0 = S22F18 temp0 >>> 1
                temp0 = temp0 >>> 1;
                // S8F7 sample_out = S22F18 temp0[18:11]
                sample_out = temp0[18:11];
            end

            3'd1: begin // TILTED SAW: asymmetric breakpoint
                // S22F18 temp1 = filt_buzz ? S22F18_0_975 : S22F18_0_875
                temp1 = filt_buzz ? S22F18_0_975 : S22F18_0_875;
                if (t < temp1) begin
                    // Rising segment: 2 * t / breakpoint - 1
                    // S22F18 temp2 = S22F18 t * 2 = S22F18 t << 1
                    temp2 = t <<< 1;
                    // S22F18 temp0 = (S22F18 temp2 / S22F18 temp1) - S22F18 1
                    // Division: extend temp2 by 18 bits, divide, result is S22F18
                    temp0 = ($signed({temp2, 18'b0}) / $signed({{18{temp1[21]}}, temp1})) - S22F18_ONE;
                end else begin
                    // Falling segment: 2 * ((1 - t) / (1 - breakpoint)) - 1
                    // S22F18 temp2 = S22F18 1 - S22F18 t
                    temp2 = S22F18_ONE - t;
                    // S22F18 temp2 = S22F18 temp2 * 2
                    temp2 = temp2 <<< 1;
                    // S22F18 temp3 = S22F18 1 - S22F18 temp1
                    temp3 = S22F18_ONE - temp1;
                    // S22F18 temp0 = (S22F18 temp2 / S22F18 temp3) - S22F18 1
                    temp0 = ($signed({temp2, 18'b0}) / $signed({{18{temp3[21]}}, temp3})) - S22F18_ONE;
                end
                // Scale by 0.5
                // S22F18 temp0 = S22F18 temp0 >>> 1
                temp0 = temp0 >>> 1;
                // S8F7 sample_out = S22F18 temp0[18:11]
                sample_out = temp0[18:11];
            end

            3'd2: begin // SAW: linear ramp with buzz harmonic
                if (t < S22F18_HALF) begin  // phase < 0.5
                    temp1 = t;
                end else begin
                    temp1 = t - S22F18_ONE;
                end
                if (filt_buzz) begin
                    // Buzz harmonic: ret * 0.83 - (condition ? 0.085 : 0)
                    // Condition: abs(phase_in mod 2 - 1) < 0.5
                    // phase_in mod 2 uses bits [19:0] of U22F18 phase_in
                    // S22F18 temp4 = S22F18(U20F18 phase_in[19:0]) - S22F18 1
                    temp4 = $signed({2'b0, phase_in[19:0]}) - S22F18_ONE;
                    // S22F18 temp4 = abs(S22F18 temp4)
                    temp4 = temp4[21] ? -temp4 : temp4;
                    // S22F18 temp2 = (temp4 < S22F18 0.5) ? S22F18 0.085 : 0
                    temp2 = (temp4 < S22F18_HALF) ? S22F18_0_085 : 22'sd0;
                    // S22F18 temp1 = (S22F18 temp1 * S22F18 0.83) >>> 18 - S22F18 temp2
                    temp1 = (($signed({{22{temp1[21]}}, temp1}) * $signed({{22{1'b0}}, S22F18_0_83})) >>> 18) - temp2;
                end
                // S22F18 temp0 = (S22F18 temp1 * S22F18 0.653) >>> 18
                temp0 = (($signed({{22{temp1[21]}}, temp1}) * $signed({{22{1'b0}}, S22F18_0_653})) >>> 18);
                // S8F7 sample_out = S22F18 temp0[18:11]
                sample_out = temp0[18:11];
            end

            3'd3: begin // SQUARE: 50% duty (40% with buzz), amplitude ±0.25
                if (filt_buzz) begin
                    sample_out = (phase_in[17:12] < 6'd26) ? S8F7_QUARTER : -S8F7_QUARTER;
                end else begin
                    sample_out = phase_in[17] ? -S8F7_QUARTER : S8F7_QUARTER;
                end
            end

            3'd4: begin // PULSE: 31.6% duty (25.5% with buzz), amplitude ±0.25
                if (filt_buzz) begin
                    sample_out = (phase_in[17:13] < 5'd8) ? S8F7_QUARTER : -S8F7_QUARTER;
                end else begin
                    sample_out = (phase_in[17:13] < 5'd10) ? S8F7_QUARTER : -S8F7_QUARTER;
                end
            end

            3'd5: begin // ORGAN: piecewise triangle
                if (t < S22F18_HALF) begin  // First half (t < 0.5)
                    // Calculate 24 * t (treating 24 as integer, result is S22F18)
                    // This doesn't overflow S22F18 since t < 0.5
                    temp1 = t * 24;
                    // Subtract 6.0 (S22F18)
                    temp1 = temp1 - S22F18_SIX;
                    // Take absolute value
                    temp1 = temp1[21] ? -temp1 : temp1;
                    // Subtract from 3.0
                    temp1 = S22F18_THREE - temp1;
                end else begin  // Second half (t >= 0.5)
                    // Calculate 16 * t (treating 16 as integer, result is S22F18)
                    temp1 = t * 16;
                    // Subtract 12.0 (S22F18)
                    temp1 = temp1 - S22F18_TWELVE;
                    // Take absolute value
                    temp1 = temp1[21] ? -temp1 : temp1;
                    // Subtract from 1.0
                    temp1 = S22F18_ONE - temp1;
                end

                // Buzz processing
                if (filt_buzz) begin
                    if (t < S22F18_HALF) begin
                        // S22F18 temp1 = (S22F18 temp1 * 2) + S22F18 3.0
                        temp1 = (temp1 <<< 1) + S22F18_THREE;
                    end
                    if (t < S22F18_HALF && temp1 > S22F18_NEG_1_875) begin
                        // S22F18 temp1 = (S22F18 temp1 * S22F18 0.2) >>> 18 - S22F18 1.0
                        temp1 = (($signed({{22{temp1[21]}}, temp1}) * $signed({{22{1'b0}}, S22F18_0_2})) >>> 18) - S22F18_ONE;
                    end else begin
                        // S22F18 temp1 = S22F18 temp1 + S22F18 0.5
                        temp1 = temp1 + S22F18_HALF;
                    end
                end

                // Divide by 9
                // S22F18 temp0 = (S22F18 temp1 * 29127) >>> 18  // 29127/262144 ≈ 1/9
                temp0 = (($signed({{22{temp1[21]}}, temp1}) * $signed(22'sd29127)) >>> 18);
                // S8F7 sample_out = S22F18 temp0[18:11]
                sample_out = temp0[18:11];
            end

            3'd6: begin // NOISE: white (LFSR) or brown (filtered)
                // Apply pitch-dependent scaling
                // Calculate factor = 1 - cur_pitch / 63
                // U22F18 pitch_scaled = (cur_pitch << 18) / 63
                // S22F18 factor = S22F18_ONE - pitch_scaled
                // Need 40-bit intermediate for (cur_pitch << 18) to avoid truncation
                temp2 = S22F18_ONE - ((40'd0 + cur_pitch) <<< 18) / 40'd63;

                // S22F18 factor_sq = (S22F18 factor * S22F18 factor) >>> 18
                // 22-bit × 22-bit = 44 bits, must use temp to avoid truncation
                noise_scale_temp = $signed({{22{temp2[21]}}, temp2}) * $signed({{22{temp2[21]}}, temp2});
                temp3 = $signed(noise_scale_temp[39:18]);

                // S22F18 scale = S22F18 1.0 + S22F18 factor_sq
                temp0 = S22F18_ONE + temp3;

                // S22F18 scale = S22F18 scale * S22F18 1.5
                // 22-bit × 22-bit = 44 bits, must use temp to avoid truncation
                noise_scale_temp = $signed({{22{temp0[21]}}, temp0}) * $signed({{22{1'b0}}, S22F18_1_5});
                temp0 = $signed(noise_scale_temp[39:18]);

                if (filt_noiz) begin
                    // Multiply brown_state by SAW waveform
                    // S22F18 saw_wave = t < 0.5 ? S22F18 t : S22F18 t - S22F18 1
                    temp1 = (t < S22F18_HALF) ? t : (t - S22F18_ONE);
                    // S22F18 saw_wave = S22F18 saw_wave * S22F18 2
                    temp1 = temp1 <<< 1;

                    // S22F18 noise_temp = (S8F7 brown_state * S22F18 saw_wave) >>> 7
                    // 8-bit × 22-bit = 30 bits, must use temp to avoid truncation
                    noise_mult1_temp = $signed({{15{brown_state[7]}}, brown_state}) * $signed({{22{temp1[21]}}, temp1});
                    temp4 = $signed(noise_mult1_temp[28:7]);

                    // S22F18 temp0 = (S22F18 noise_temp * S22F18 scale) >>> 18
                    // 22-bit × 22-bit = 44 bits, must use temp to avoid truncation
                    noise_mult2_temp = $signed({{22{temp4[21]}}, temp4}) * $signed({{22{temp0[21]}}, temp0});
                    temp0 = $signed(noise_mult2_temp[39:18]);

                    // S8F7 sample_out = S22F18 temp0[18:11]
                    sample_out = temp0[18:11];
                end else begin
                    // Brown noise: just brown_state scaled by pitch factor
                    // S22F18 noise_temp = S8F7 brown_state extended to S22F18
                    temp4 = $signed({{15{brown_state[7]}}, brown_state});
                    // S22F18 temp0 = (S22F18 noise_temp * S22F18 scale) >>> 7
                    // 22-bit × 22-bit = 44 bits, must use temp to avoid truncation
                    noise_mult2_temp = $signed({{22{temp4[21]}}, temp4}) * $signed({{22{temp0[21]}}, temp0});
                    temp0 = $signed(noise_mult2_temp[28:7]);
                    // S8F7 sample_out = S22F18 temp0[18:11]
                    sample_out = temp0[18:11];
                end
            end

            3'd7: begin // PHASER: sum of triangle waves at 1.0x and ~0.99x freq
                // Primary triangle: 2 - abs(8*t - 4)
                temp2 = t * 8;          // S22F18 = S22F18 * 8
                temp2 = temp2 - S22F18_FOUR;
                temp2 = temp2[21] ? -temp2 : temp2;  // abs
                temp2 = S22F18_TWO - temp2;

                // Secondary triangle at 109/110 frequency
                // Calculate phase * 109/110, take fractional part
                phaser_mult_temp = phase_in * U22F18_109_110;  // U44F36
                temp5 = phaser_mult_temp >>> 18;      // U22F18
                // Extract t_secondary (fractional part)
                temp4 = $signed({4'b0, temp5[17:0]});
                // Calculate: 1 - abs(4 * t_sec - 2)
                temp1 = temp4 * 4;
                temp1 = temp1 - S22F18_TWO;
                temp1 = temp1[21] ? -temp1 : temp1;  // abs
                temp2 = temp2 + S22F18_ONE - temp1;

                // Buzz harmonics
                if (filt_buzz) begin
                    // Harmonic at 2x: 0.25 - abs(1 * ((phase*2 + 0.5) mod 1) - 0.5)
                    // phase*2 + 0.5, take fractional part
                    temp3 = (phase_in <<< 1) + S22F18_HALF;
                    temp4 = $signed({4'b0, temp3[17:0]});  // fractional part
                    // Calculate: 0.25 - abs(t - 0.5)
                    temp1 = temp4 - S22F18_HALF;
                    temp1 = temp1[21] ? -temp1 : temp1;  // abs
                    temp2 = temp2 + S22F18_QUARTER - temp1;

                    // Harmonic at 4x: 0.125 - abs(0.5 * ((phase*4) mod 1) - 0.25)
                    // phase*4, take fractional part
                    temp4 = phase_in <<< 2;
                    temp4 = $signed({4'b0, temp4[17:0]});  // fractional part
                    // Calculate: 0.125 - abs(0.5*t - 0.25)
                    temp1 = (temp4 >>> 1) - S22F18_QUARTER;  // 0.5*t - 0.25
                    temp1 = temp1[21] ? -temp1 : temp1;  // abs
                    temp2 = temp2 + S22F18_EIGHTH - temp1;
                end

                // Divide by 6
                // 1/6 ≈ 43691/262144 in U18F18
                div6_temp = temp2 * 43691;
                temp0 = div6_temp >>> 18;
                sample_out = temp0[18:11];
            end
        endcase
    end
endtask

// Waveform sample generation task
task generate_waveform_sample;
    output [7:0] sample_out;        // S8F7 output sample

    reg signed [7:0] base_sample;   // S8F7 base waveform output
    reg signed [7:0] detune_sample; // S8F7 detune waveform output
    reg signed [8:0] s9_temp;       // S9F8 temporary for additions
    reg signed [8:0] s9_err;        // S9F8 dampen filter error
    reg signed [7:0] s8_sample;     // S8F7 processed sample for PCM chain
    begin
        // Generate base waveform sample (S8F7)
        if (is_waveform_inst) begin
            // Custom waveform: use pre-fetched 16-bit word from RAM, select byte
            // sfx_byte_sel: 0=high byte, 1=low byte
            sample_out = sfx_byte_sel ? $signed(sfx_data[7:0]) : $signed(sfx_data[15:8]);
        end else if (cur_custom && is_main_context(ctx_idx)) begin
            sample_out = custom_pcm_out[voice_idx];
        end else begin
            waveform_gen(phase_acc, base_sample);

            // Generate detune waveform sample (S8F7) if needed
            if (filt_detune != 2'd0 && cur_wave != 3'd6) begin
                waveform_gen(detune_acc, detune_sample);
                // Mix base + (detune>>1) with saturation
                s9_temp = $signed({base_sample[7], base_sample}) + ($signed({detune_sample[7], detune_sample}) >>> 1);
                if (s9_temp > 9'sd127) sample_out = 8'sd127;
                else if (s9_temp < -9'sd128) sample_out = -8'sd128;
                else sample_out = s9_temp[7:0];
            end else begin
                sample_out = base_sample;
            end
        end
    end
endtask

//==============================================================
// Waveform Post-Processing Tasks
//==============================================================
// Reverb sample mixing (uses pre-read reverb data)
// This task only does the arithmetic - RAM access happens in main always block
task apply_reverb_mix;
    inout [7:0] s8_sample;         // S8F7 input/output sample

    reg signed [8:0] s9_temp;      // S9F8 temporary for additions
    begin
        // Calculate effective reverb with HWFX overrides
        if (hw_low_rev) begin
            eff_reverb_8x[ctx_idx] = 2'd2;
        end else if (hw_high_rev && (filt_reverb < 2'd2)) begin
            eff_reverb_8x[ctx_idx] = 2'd1;
        end else begin
            eff_reverb_8x[ctx_idx] = filt_reverb;
        end

        // Mix reverb data (from previous cycle's read) with current sample
        if (eff_reverb == 2'd1) begin
            if (rev_idx2 < rev_idx2_valid) begin
                s9_temp = $signed({s8_sample[7], s8_sample}) + ($signed({reverb_2_rdata[7], reverb_2_rdata}) >>> 1);
                if (s9_temp > 9'sd127) s8_sample = 8'sd127;
                else if (s9_temp < -9'sd128) s8_sample = -8'sd128;
                else s8_sample = s9_temp[7:0];
            end
        end else if (eff_reverb == 2'd2) begin
            if (rev_idx4 < rev_idx4_valid) begin
                s9_temp = $signed({s8_sample[7], s8_sample}) + ($signed({reverb_4_rdata[7], reverb_4_rdata}) >>> 1);
                if (s9_temp > 9'sd127) s8_sample = 8'sd127;
                else if (s9_temp < -9'sd128) s8_sample = -8'sd128;
                else s8_sample = s9_temp[7:0];
            end
        end
    end
endtask

// Dampen filter application task
task apply_dampen;
    inout [7:0] s8_sample;         // S8F7 input/output sample

    reg signed [8:0] s9_err;       // S9F8 dampen filter error
    begin
        // Calculate dampen alpha with HWFX overrides
        if (hw_low_dmp && hw_high_dmp) begin
            damp_alpha_8x[ctx_idx] <= DAMP_ALPHA_STRONG;
        end else if (hw_low_dmp) begin
            damp_alpha_8x[ctx_idx] <= DAMP_ALPHA_HIGH;
        end else if (hw_high_dmp && filt_dampen < 2'd2) begin
            damp_alpha_8x[ctx_idx] <= DAMP_ALPHA_LOW;
        end else begin
            case (filt_dampen)
                2'd0:    damp_alpha_8x[ctx_idx] <= 8'd0;
                2'd1:    damp_alpha_8x[ctx_idx] <= DAMP_ALPHA_LOW;
                2'd2:    damp_alpha_8x[ctx_idx] <= DAMP_ALPHA_HIGH;
                default: damp_alpha_8x[ctx_idx] <= DAMP_ALPHA_STRONG;
            endcase
        end

        // Apply dampen filter (IIR lowpass)
        if (damp_alpha != 8'd0) begin
            s9_err = $signed({s8_sample[7], s8_sample}) - $signed({damp_state[7], damp_state});
            // S8F7 damp_state = S8F7 damp_state + S9F8 s9_err * U8F0 damp_alpha
            damp_state_8x[ctx_idx] <= damp_state + $signed({{8{s9_err[7]}}, s9_err[7:0]}) * $signed({{8{1'b0}}, damp_alpha});
            s8_sample = damp_state;
        end
    end
endtask

// Bitcrush/distort application task
task apply_bitcrush;
    inout [7:0] s8_sample;         // S8F7 input/output sample
    begin
        // Apply bitcrush/distort (HWFX 0x5F42)
        if (hw_low_bcr) begin
            s8_sample = {s8_sample[7:2], 2'd0};
        end else if (hw_high_bcr) begin
            if (s8_sample > 8'sd31) s8_sample = 8'sd31;
            else if (s8_sample < -8'sd31) s8_sample = -8'sd31;
            s8_sample = {s8_sample[7:2], 2'd0};
        end
    end
endtask

//==============================================================
// PCM processing chain
//==============================================================
task process_pcm_chain;
    reg [7:0] s8_sample;         // S8F7 sample
    begin
        // Generate waveform sample
        generate_waveform_sample(s8_sample);

        // Volume scaling
        // S8F7 s8_sample = S8F7 s8_sample * U8F0 eff_vol
        s8_sample = (($signed({{8{s8_sample[7]}}, s8_sample}) * $signed({{8{1'b0}}, eff_vol}))) >>> 8;

        // Attack ramp
        if (attack_ctr != 5'd0) begin
            // S8F7 s8_sample = S8F7 s8_sample * (U4F0 16 - U4F0 attack_ctr) / 16
            s8_sample = ($signed({{4{s8_sample[7]}}, s8_sample}) * $signed({{8{1'b0}}, 5'd16 - attack_ctr})) >>> 4;
        end

        // Release ramp
        if (releasing) begin
            // S8F7 s8_sample = S8F7 s8_sample * U4F0 release_ctr / 16
            s8_sample = ($signed({{4{s8_sample[7]}}, s8_sample}) * $signed({{8{1'b0}}, release_ctr})) >>> 4;
        end

        // Save pre-reverb sample (for delay line write in main always block)
        pre_reverb_sample_8x[ctx_idx] = s8_sample;

        // Apply reverb (add delayed sample with saturation)
        apply_reverb_mix(s8_sample);

        // Apply dampen filter
        apply_dampen(s8_sample);

        // Apply bitcrush/distort
        apply_bitcrush(s8_sample);

        // Final PCM output
        if (is_main_context(ctx_idx)) begin
            pcm_out[voice_idx] <= s8_sample;
        end else begin
            // CUSTOM contexts (0,2,4,6) - store for use by paired MAIN contexts
            custom_pcm_out[voice_idx] <= s8_sample;
        end
    end
endtask

//==============================================================
// Main processing loop
//==============================================================
task update_status_outputs;
    begin
        // Update status outputs for current context
        // Only output status for MAIN contexts (odd indices: 1,3,5,7)
        if (is_main_context(ctx_idx)) begin
            looping[voice_idx] <= (pcm_state[ctx_idx] == PCM_PLAYING) ? (loop_start != 6'd0) || (loop_end != 6'd31) : 1'b0;
            stat_sfx_index[voice_idx] <= (pcm_state[ctx_idx] == PCM_PLAYING) ? sfx_index_req_8x[ctx_idx] : 6'h3F;
            stat_note_index[voice_idx] <= (pcm_state[ctx_idx] == PCM_PLAYING) ? note_idx : 6'h3F;
        end
    end
endtask

reg [8:0] next_idx2;
reg [9:0] next_idx4;
reg ignore;
reg [4:0] sfx_read_addr;

// Combinatorial wires for timing conditions
wire is_two_samples_before_main_note_tick;
wire is_one_sample_before_main_note_tick;
wire is_one_sample_before_arp_note_tick;
wire should_check_arpeggio_effect;
wire should_decode_note;

assign is_two_samples_before_main_note_tick = (sample_ctr == NOTE_TICK_DIV - 2) && (note_ctr >= speed_byte - 1);
assign is_one_sample_before_main_note_tick = (sample_ctr == NOTE_TICK_DIV - 1) && (note_ctr >= speed_byte - 1);
assign is_one_sample_before_arp_note_tick = (sample_ctr == NOTE_TICK_DIV - 1) && arp_active && (arp_accum >= arp_speed - 1);
assign should_check_arpeggio_effect = !is_waveform_inst && is_two_samples_before_main_note_tick;
assign should_decode_note = !is_waveform_inst && (is_one_sample_before_main_note_tick || is_one_sample_before_arp_note_tick);

always @(posedge clk_pcm_8x) begin
    if (!resetn) begin
        // Reset control signals
        sfx_done <= 4'd0;
        force_stop_pcm_sticky <= 8'd0;
        force_release_pcm_sticky <= 8'd0;
        load_done_pcm_sticky <= 8'd0;

        // Reset all contexts
        for (i=0; i<8; i=i+1) begin
            pcm_state[i] <= PCM_IDLE;
            speed_byte_8x[i] <= 8'd0;
            bass_flag_8x[i] <= 1'b0;
            is_waveform_inst_8x[i] <= 1'b0;
            loop_start_8x[i] <= 6'd0;
            loop_end_8x[i] <= 6'd0;
            filt_noiz_8x[i] <= 1'b0;
            filt_buzz_8x[i] <= 1'b0;
            filt_detune_8x[i] <= 2'd0;
            filt_reverb_8x[i] <= 2'd0;
            filt_dampen_8x[i] <= 2'd0;
            start_idx_8x[i] <= 6'd0;
            sfx_length_val_8x[i] <= 6'd0;
            sample_ctr_8x[i] <= 8'd0;
            note_ctr_8x[i] <= 8'd0;
            note_idx_8x[i] <= 6'd0;
            phase_acc_8x[i] <= 22'd0;
            detune_acc_8x[i] <= 22'd0;
            // Initialize all other per-context registers
            cur_pitch_8x[i] <= 6'd0;
            cur_wave_8x[i] <= 3'd0;
            cur_vol_8x[i] <= 3'd0;
            cur_eff_8x[i] <= 3'd0;
            cur_custom_8x[i] <= 1'b0;
            prev_pitch_8x[i] <= 6'd0;
            prev_vol_8x[i] <= 3'd0;
            note_offset_8x[i] <= 24'd0;
            attack_ctr_8x[i] <= 5'd0;
            release_ctr_8x[i] <= 5'd0;
            releasing_8x[i] <= 1'b0;
            arp_active_8x[i] <= 1'b0;
            arp_accum_8x[i] <= 3'd0;
            next_group_pos_8x[i] <= 2'd0;
            arp_speed_8x[i] <= 8'd0;
            eff_vib_phase_8x[i] <= 11'd0;
            lfsr_8x[i] <= 8'hA5;  // Non-zero seed
            brown_state_8x[i] <= 8'sd0;
            damp_state_8x[i] <= 8'sd0;
            damp_alpha_8x[i] <= 8'd0;
            rev_idx2_8x[i] <= 9'd0;
            rev_idx4_8x[i] <= 10'd0;
            rev_idx2_valid_8x[i] <= 9'd0;
            rev_idx4_valid_8x[i] <= 10'd0;
        end
        // Reset main voice output arrays
        for (i=0; i<4; i=i+1) begin
            looping[i] <= 1'b0;
            pcm_out[i] <= 8'd0;
            custom_pcm_out[i] <= 8'sd0;
            custom_load_wave_pcm[i] <= 3'd0;
        end
        custom_load_toggle_pcm <= 4'd0;
    end else begin
        // Clear sfx_done pulses (will be set again if needed in FSM)
        sfx_done <= 4'd0;

        // Set sticky flags on edge detection for ALL contexts
        force_stop_pcm_sticky <= force_stop_pcm_sticky | force_stop_strobe;
        force_release_pcm_sticky <= force_release_pcm_sticky | force_release_strobe;
        load_done_pcm_sticky <= load_done_pcm_sticky | load_done_strobe;

        // Clear PCM outputs for current context
        if (is_main_context(ctx_idx)) begin
            pcm_out[voice_idx] <= 8'd0;
        end else begin
            custom_pcm_out[voice_idx] <= 8'sd0;
        end

        if (run) begin
            // State machine for current context
            case (pcm_state[ctx_idx])
                PCM_IDLE: begin
                    // Wait for load completion
                    if (load_done_pcm_sticky[ctx_idx]) begin
                        load_done();  // Handle load completion - transitions to PCM_WARM_UP or PCM_PLAYING
                        load_done_pcm_sticky[ctx_idx] <= 1'b0;
                    end

                    // Clear force_stop if it arrives while idle (no effect)
                    force_stop_pcm_sticky[ctx_idx] <= 1'b0;
                    if (is_main_context(ctx_idx)) begin
                        // When idle force the associated CUSTOM context to idle too.
                        pcm_state[custom_from_main(ctx_idx)] <= PCM_IDLE;
                    end
                end

                PCM_WARM_UP, PCM_PLAYING: begin
                    // Active synthesis - process audio and handle transitions

                    // Handle force_stop (stop immediately)
                    if (force_stop_pcm_sticky[ctx_idx]) begin
                        pcm_state[ctx_idx] <= PCM_STOPPING;
                        force_stop_pcm_sticky[ctx_idx] <= 1'b0;
                    end

                    // Handle force_release (disable looping, continue playing)
                    else if (force_release_pcm_sticky[ctx_idx]) begin
                        loop_end_8x[ctx_idx] <= loop_start[ctx_idx];
                        force_release_pcm_sticky[ctx_idx] <= 1'b0;
                        // State remains unchanged
                    end

                    // HWFX processing: if voice_idx bit set in hwfx_5f40_val then skip every other clock cycle, otherwise process every clock cycle
                    if (hwfx_5f40_val[{1'b1, voice_idx}] ? clock_toggle : 1'b1) begin
                        // Tick one sample - timing only during warm-up, full DSP during playing
                        if (pcm_state[ctx_idx] == PCM_WARM_UP) begin
                            // Warm-up: only advance timing, don't update phase/DSP state (note params not decoded yet)
                            if (!is_waveform_inst) begin
                                advance_note_timing();
                            end
                        end else begin
                            // Playing: full sample tick including phase accumulator and DSP updates
                            sample_tick();
                        end

                        // Process PCM output chain (only if playing, not during warm-up)
                        if (pcm_state[ctx_idx] == PCM_PLAYING) begin
                            process_pcm_chain();
                        end

                        // SFX RAM access logic
                        // Waveform instruments: always read from phase accumulator
                        // Note instruments:
                        //   - Default: read current note_idx
                        //   - 2 samples before main note tick: check for arpeggio effect, read arpeggio note if needed
                        if (is_waveform_inst) begin
                            // Waveform/PCM instrument: read from phase accumulator
                            sfx_read_addr = phase_acc[17:13];
                            sfx_byte_sel_8x[ctx_idx] <= phase_acc[12];
                        end else begin
                            // Note instrument: default read next note (note_idx)
                            sfx_read_addr = (note_idx <= NOTE_MAX_INDEX) ? note_idx[4:0] : 5'd0;
                            sfx_byte_sel_8x[ctx_idx] <= 1'b0;

                            // 2 samples before main note tick: check if next note has arpeggio effect
                            if (should_check_arpeggio_effect) begin
                                // sfx_data contains note_idx data from previous reads
                                // Check effect field: sfx_data[7:0] is byte1, bits [6:4] are effect
                                if ((sfx_data[6:4] == 3'd6 || sfx_data[6:4] == 3'd7) && note_idx <= NOTE_MAX_INDEX) begin
                                    // Arpeggio effect detected! Read arpeggio note instead.
                                    sfx_read_addr = ({note_idx[5:2], next_group_pos} <= NOTE_MAX_INDEX) ? {note_idx[5:2], next_group_pos} : 5'd0;
                                    arp_active_8x[ctx_idx] <= 1'b1;
                                    // Initialize arpeggio state
                                    if (!arp_active) begin
                                        arp_accum_8x[ctx_idx] <= 3'd0;
                                    end
                                end else begin
                                    // No arpeggio effect
                                    arp_active_8x[ctx_idx] <= 1'b0;
                                end
                            end
                            // 1 sample before note tick: decode the note
                            else if (should_decode_note) begin
                                decode_current_note();
                            end
                        end

                        // Reverb BRAM access (must be in main always block for proper inference)
                        // This happens every sample regardless of PREFETCH or PLAYING state
                        // Calculate next indices
                        next_idx2 = (rev_idx2 + 1 == REVERB_TAPS_SHORT) ? 9'd0 : rev_idx2 + 1;
                        next_idx4 = (rev_idx4 + 1 == REVERB_TAPS_LONG) ? 10'd0 : rev_idx4 + 1;

                        // Read from next position, write to current position
                        // Read SFX note data from merged array (block RAM)
                        sfx_data_8x[ctx_idx] <= sfx_notes[{ctx_idx, sfx_read_addr}];

                        // Use case statement for reverb array selection (context-specific arrays)
                        case (ctx_idx)
                            3'd0: begin
                                reverb_2_rdata_8x[0] <= reverb_2_8x_0[next_idx2];
                                reverb_4_rdata_8x[0] <= reverb_4_8x_0[next_idx4];
                                reverb_2_8x_0[rev_idx2] <= pre_reverb_sample_8x[0];
                                reverb_4_8x_0[rev_idx4] <= pre_reverb_sample_8x[0];
                            end
                            3'd1: begin
                                reverb_2_rdata_8x[1] <= reverb_2_8x_1[next_idx2];
                                reverb_4_rdata_8x[1] <= reverb_4_8x_1[next_idx4];
                                reverb_2_8x_1[rev_idx2] <= pre_reverb_sample_8x[1];
                                reverb_4_8x_1[rev_idx4] <= pre_reverb_sample_8x[1];
                            end
                            3'd2: begin
                                reverb_2_rdata_8x[2] <= reverb_2_8x_2[next_idx2];
                                reverb_4_rdata_8x[2] <= reverb_4_8x_2[next_idx4];
                                reverb_2_8x_2[rev_idx2] <= pre_reverb_sample_8x[2];
                                reverb_4_8x_2[rev_idx4] <= pre_reverb_sample_8x[2];
                            end
                            3'd3: begin
                                reverb_2_rdata_8x[3] <= reverb_2_8x_3[next_idx2];
                                reverb_4_rdata_8x[3] <= reverb_4_8x_3[next_idx4];
                                reverb_2_8x_3[rev_idx2] <= pre_reverb_sample_8x[3];
                                reverb_4_8x_3[rev_idx4] <= pre_reverb_sample_8x[3];
                            end
                            3'd4: begin
                                reverb_2_rdata_8x[4] <= reverb_2_8x_4[next_idx2];
                                reverb_4_rdata_8x[4] <= reverb_4_8x_4[next_idx4];
                                reverb_2_8x_4[rev_idx2] <= pre_reverb_sample_8x[4];
                                reverb_4_8x_4[rev_idx4] <= pre_reverb_sample_8x[4];
                            end
                            3'd5: begin
                                reverb_2_rdata_8x[5] <= reverb_2_8x_5[next_idx2];
                                reverb_4_rdata_8x[5] <= reverb_4_8x_5[next_idx4];
                                reverb_2_8x_5[rev_idx2] <= pre_reverb_sample_8x[5];
                                reverb_4_8x_5[rev_idx4] <= pre_reverb_sample_8x[5];
                            end
                            3'd6: begin
                                reverb_2_rdata_8x[6] <= reverb_2_8x_6[next_idx2];
                                reverb_4_rdata_8x[6] <= reverb_4_8x_6[next_idx4];
                                reverb_2_8x_6[rev_idx2] <= pre_reverb_sample_8x[6];
                                reverb_4_8x_6[rev_idx4] <= pre_reverb_sample_8x[6];
                            end
                            3'd7: begin
                                reverb_2_rdata_8x[7] <= reverb_2_8x_7[next_idx2];
                                reverb_4_rdata_8x[7] <= reverb_4_8x_7[next_idx4];
                                reverb_2_8x_7[rev_idx2] <= pre_reverb_sample_8x[7];
                                reverb_4_8x_7[rev_idx4] <= pre_reverb_sample_8x[7];
                            end
                        endcase

                        // Update reverb indices to next position
                        rev_idx2_8x[ctx_idx] <= next_idx2;
                        if (rev_idx2 > rev_idx2_valid)
                            rev_idx2_valid_8x[ctx_idx] <= rev_idx2 + 1;

                        rev_idx4_8x[ctx_idx] <= next_idx4;
                        if (rev_idx4 > rev_idx4_valid)
                            rev_idx4_valid_8x[ctx_idx] <= rev_idx4 + 1;
                    end // sample tick
                end

                PCM_STOPPING: begin
                    // Transition to idle (cleanup state before stopping)
                    pcm_state[ctx_idx] <= PCM_IDLE;
                    // Set sfx_done pulse for MAIN contexts
                    if (is_main_context(ctx_idx)) begin
                        sfx_done[voice_idx] <= 1'b1;
                    end
                end

                default: begin
                    pcm_state[ctx_idx] <= PCM_IDLE;
                end
            endcase
        end
    end

    // Update status outputs
    update_status_outputs();
end

endmodule
