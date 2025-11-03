//==============================================================
// p8sfx_core.v
// SFX/waveform generator
// Clock domains: clk_sys (DMA/loading), clk_pcm (playback/DSP)
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

module p8sfx_core (
    // Clocks & Reset
    input         clk_sys,                    // System clock for DMA and control
    input         clk_pcm,                    // Audio sample clock for playback
    input         resetn,                     // Active-low async reset
    
    // Control (clk_sys domain)
    input         run,                        // clk_sys: Global run enable
    input  [31:0] base_addr,                  // clk_sys: SFX base address (e.g., 0x3200)
    input  [1:0]  channel_id,                 // clk_sys: Channel ID 0-3 (for hwfx bit decode)
    
    // Trigger inputs (clk_sys domain)
    input  [5:0]  sfx_index_in,               // clk_sys: SFX slot to play (0-63)
    input  [5:0]  sfx_offset,                 // clk_sys: Starting note offset (0-31)
    input  [5:0]  sfx_length,                 // clk_sys: Number of notes to play (0=until end/loop)
    input         play_strobe,                // clk_sys: 1-cycle pulse to load & start playback
    input         force_stop,                 // clk_sys: 1-cycle pulse to hard stop (for sfx(-1,ch))
    input         force_release,              // clk_sys: 1-cycle pulse to release from looping (for sfx(-2,ch))
    
    // Timing (clk_pcm domain)
    input         note_tick,                  // clk_pcm: External note tick pulse
    input         note_tick_pre,              // clk_pcm: External note tick pre-pulse
    
    // Envelope controls (clk_sys domain)
    input  [15:0] note_attack_samps,          // clk_sys: Per-note attack ramp in samples
    input  [15:0] note_release_samps,         // clk_sys: Per-note release ramp in samples
    
    // Status outputs (clk_pcm domain)
    output wire   voice_busy,                 // clk_pcm: High while playing
    output reg    sfx_done,                   // clk_pcm: 1-cycle pulse when SFX completes
    
    // DMA client (clk_sys domain)
    output reg [30:0] dma_addr,               // clk_sys: DMA address (word address, 16-bit words)
    output reg        dma_req,                // clk_sys: DMA request
    input      [15:0] dma_rdata,              // clk_sys: DMA read data (16-bit bus)
    input             dma_ack,                // clk_sys: DMA acknowledge
    
    // PCM output (clk_pcm domain)
    output reg  signed [15:0] pcm_out,        // clk_pcm: Mono PCM output sample (zero when inactive)
    
    // Status exports (clk_pcm domain)
    output [5:0] stat_sfx_index,              // clk_pcm: Current SFX index (or 0x3F if idle)
    output [5:0] stat_note_index,             // clk_pcm: Current note index (or 0x3F if idle)
    
    // Hardware FX bytes (clk_sys domain inputs, CDC'd internally)
    input [7:0] hwfx_5f40, hwfx_5f41, hwfx_5f42, hwfx_5f43,
    // Looping status (clk_pcm domain)
    output        looping,                   // clk_pcm: High while this channel is in loop mode and active

    // Custom instrument integration
    // MAIN -> CUSTOM control (clk_sys domain)
    output [5:0]  custom_sfx_index_out,       // clk_sys: SFX index 0..7 to play as custom instrument
    output        custom_play_strobe,         // clk_sys: Pulse to start custom SFX
    output        custom_force_stop,          // clk_sys: Pulse to stop/release custom SFX
    // CUSTOM -> MAIN PCM coupling (clk_pcm domain)
    input  signed [15:0] custom_pcm_in,       // clk_pcm: PCM from custom instance (zero when inactive)
    // Phase multiplier coupling (clk_pcm domain)
    input  [31:0] phase_multiplier_in,        // clk_pcm: Phase multiplier from MAIN (for CUSTOM)
    output [31:0] phase_multiplier_out        // clk_pcm: Phase multiplier to CUSTOM (from MAIN)
);

//==============================================================
// Constants
//==============================================================
localparam integer PCM_SAMPLE_RATE   = 22050;        // default rate
// Size localparams to match common signal widths to avoid width-expansion warnings
localparam        [7:0] SFX_BYTES      = 8'd68;       // bytes per SFX (used with 8-bit dma_cnt)
localparam        [5:0] NOTE_MAX_INDEX = 6'd31;       // last note index (used with 6-bit note_idx)
localparam        [7:0] NOTE_TICK_DIV  = 8'd183;      // global note tick divider (samples)

localparam [9:0] REVERB_TAPS_SHORT  = 10'd366;   // ~16.3ms @ 22.05KHz
localparam [9:0] REVERB_TAPS_LONG   = 10'd732;   // ~32.5ms @ 22.05KHz
localparam integer DAMP_FREQ_LOW     = 2400;     // Hz
localparam integer DAMP_FREQ_HIGH    = 1000;     // Hz
localparam integer DAMP_FREQ_STRONG  = 700;      // Hz
localparam integer TWO_PI_X1000      = 6283;     // ≈2π×1000

// Custom instrument pitch reference
localparam [6:0] PITCH_REF_C2        = 7'd24;    // C2 note index for pitch reference

// Header byte indices in SFX
localparam [6:0] HEADER_IDX_FILTERS  = 7'd64;
localparam [6:0] HEADER_IDX_SPEED    = 7'd65;
localparam [6:0] HEADER_IDX_LOOPST   = 7'd66;
localparam [6:0] HEADER_IDX_LOOPEN   = 7'd67;

//==============================================================
// Memories (clk_sys domain for writes, clk_pcm for reads)
//==============================================================
(* ram_style="distributed" *)
reg [7:0] sfx_mem [0:SFX_BYTES-1];  // clk_sys(W)/clk_pcm(R): SFX data (68 bytes)

(* ram_style="block" *) reg signed [15:0] reverb_2 [0:(REVERB_TAPS_SHORT-1)];  // clk_pcm: Reverb delay line (short)
(* ram_style="block" *) reg signed [15:0] reverb_4 [0:(REVERB_TAPS_LONG-1)];  // clk_pcm: Reverb delay line (long)

//==============================================================
// Playback State Variables
//==============================================================
// SFX header data (clk_sys domain - loaded, clk_pcm domain - read via CDC)
reg [7:0] speed_byte;            // clk_sys(W)/clk_pcm(R): Note speed divisor
reg       bass_flag;             // clk_sys(W)/clk_pcm(R): Half-speed bass mode
reg       is_waveform_inst;      // clk_sys(W)/clk_pcm(R): Is this a waveform instrument?

reg [5:0] start_idx;             // clk_sys: Starting note index (set on play_strobe)
reg [5:0] loop_start_sys;        // clk_sys: Loop start from loaded SFX data
reg [5:0] loop_end_sys;          // clk_sys: Loop end from loaded SFX data

reg [5:0] start_idx_pcm;         // clk_pcm: CDC'd copy of start_idx
reg [5:0] sfx_length_pcm;        // clk_pcm: CDC'd copy of sfx_length input
reg [5:0] loop_start, loop_end;  // clk_pcm: Loop bounds (modifiable on force_release)
reg [5:0] loop_start_cdc, loop_end_cdc;  // clk_pcm: CDC synchronized values from sys domain
reg loading_pcm;                 // clk_pcm: Loading state CDC stages

// Playback control (clk_pcm domain)
reg       sfx_loaded;            // clk_pcm: True when SFX data is loaded and ready
reg [5:0] note_idx;              // clk_pcm: Current note index (0-31)
reg [7:0] note_tick_acc;         // clk_pcm: Note tick accumulator

// SFX filter settings (clk_sys(W)/clk_pcm(R))
reg       filt_noiz;             // clk_sys(W)/clk_pcm(R): Noise filter enable
reg       filt_buzz;             // clk_sys(W)/clk_pcm(R): Buzz filter enable
reg [1:0] filt_detune;           // clk_sys(W)/clk_pcm(R): Detune amount (0-2)
reg [1:0] filt_reverb;           // clk_sys(W)/clk_pcm(R): Reverb amount (0-2)
reg [1:0] filt_dampen;           // clk_sys(W)/clk_pcm(R): Dampen amount (0-2)

reg [7:0] hwfx_5f40_pcm;         // clk_pcm: HWFX 0x5F40
reg [7:0] hwfx_5f41_pcm;         // clk_pcm: HWFX 0x5F41
reg [7:0] hwfx_5f42_pcm;         // clk_pcm: HWFX 0x5F42
reg [7:0] hwfx_5f43_pcm;         // clk_pcm: HWFX 0x5F43

assign stat_sfx_index = sfx_loaded ? sfx_index_in : 6'h3F;
assign stat_note_index = sfx_loaded ? note_idx : 6'h3F;
assign voice_busy = loading_pcm || sfx_loaded;  // Voice is busy while loading or playing
// Looping indicator: true when voice is active, loaded, sfx_length==0 (full SFX mode),
// AND has valid loop points: (loop_start != loop_end) AND NOT (loop_start != 0 && loop_end == 0)
// Special case: loop_start != 0 && loop_end == 0 means "play up to loop_start then stop" (one-shot)
assign looping = (sfx_loaded && voice_busy && (sfx_length_pcm == 6'd0) && 
                  (loop_start != loop_end) && !((loop_start != 6'd0) && (loop_end == 6'd0)));

//==============================================================
// SFX LOADING (clk_sys domain)
// Loads SFX data from memory via DMA
//==============================================================

// Loader FSM state and loading status (must be declared before use in CDC blocks)
// Enum values for load state
localparam L_IDLE = 3'd0;
localparam L_SFX  = 3'd1;
localparam L_SCAN = 3'd2;

reg [2:0] lstate;                // clk_sys: Loader FSM state
wire       loading_sys;          // clk_sys: High when loading in progress
assign loading_sys = (lstate != L_IDLE);

// Signal that triggers toggle (must be declared before use)
reg        sfx_load_done_sys;       // clk_sys: Pulse when loading completes

//==============================================================
// DMA Loader FSM (clk_sys domain)
//==============================================================
// Helper: map filter byte into 2-bit fields, avoiding width-trunc warnings
function [1:0] f_div3(input [7:0] x, input [7:0] div);
    reg [7:0] q8;
    begin
        // Compute q = (x/div)%3 in 8-bit space to match operands, then map to 2 bits
        q8 = (x / div) % 8'd3;
        case (q8)
            8'd0: f_div3 = 2'd0;
            8'd1: f_div3 = 2'd1;
            default: f_div3 = 2'd2;
        endcase
    end
endfunction

reg [7:0]    dma_cnt;            // clk_sys: DMA byte counter

always @(posedge clk_sys or negedge resetn) begin
    if (!resetn) begin
        lstate <= L_IDLE; dma_req<=0; dma_addr<=0; dma_cnt<=0;
        sfx_load_done_sys<=0;
        start_idx<=0;
        filt_noiz<=0; filt_buzz<=0; filt_detune<=0; filt_reverb<=0; filt_dampen<=0;
    end else begin
        sfx_load_done_sys <= 1'b0;
        if (force_stop) begin
            lstate <= L_IDLE;
        end
        case (lstate)
            L_IDLE: begin
                if (play_strobe) begin
                    // clamp start index to valid 0..31 range
                    start_idx  <= (sfx_offset > 6'd31) ? 6'd31 : sfx_offset;
                    dma_cnt  <= 0;
                    // base_addr is byte address, convert to word address (divide by 2)
                    // sfx_index_in * SFX_BYTES gives byte offset, also divide by 2
                    dma_addr <= (base_addr + sfx_index_in * SFX_BYTES) >> 1;
                    $display("DMA[%0d] time=%0t request: addr=0x%08h (byte 0x%08h)", 
                                0, $time, (base_addr + sfx_index_in * SFX_BYTES) >> 1, {(base_addr + sfx_index_in * SFX_BYTES) >> 1, 1'b0});
                    dma_req  <= 1'b1;
                    lstate   <= L_SFX;
                end else begin
                    dma_req <= 1'b0;
                end
            end
            L_SFX: begin
                // DMA handshake: pulse req for each transfer
                // Pulse dma_req for one cycle, wait for ack, then pulse again
                if (dma_ack) begin
                    // DMA acknowledge received - capture data
                    // 16-bit DMA read: unpack into two consecutive bytes
                    // dma_cnt tracks byte position (0..67), but DMA reads 16 bits at a time
                    // dma_addr is a word address (each word = 2 bytes)
                    // Big-endian: bits[15:8] = first byte (lower address), bits[7:0] = second byte (higher address)
                    sfx_mem[dma_cnt[6:0]]     <= dma_rdata[15:8];  // first byte at even address
                    sfx_mem[dma_cnt[6:0] + 1] <= dma_rdata[7:0];   // second byte at odd address
                    $display("  DMA[%0d] time=%0t response: addr=0x%08h (byte 0x%08h), data=0x%04h -> sfx_mem[%0d]=0x%02h, sfx_mem[%0d]=0x%02h", 
                                dma_cnt, $time, dma_addr, {dma_addr, 1'b0}, dma_rdata, 
                                dma_cnt[6:0], dma_rdata[15:8], dma_cnt[6:0]+1, dma_rdata[7:0]);
                    dma_cnt <= dma_cnt + 2;
                    dma_addr <= dma_addr + 1;  // increment by 1 word (2 bytes)
                    
                    if (dma_cnt + 2 >= SFX_BYTES) begin
                        // Done loading SFX - clear request and move to next state
                        dma_req <= 1'b0;
                        lstate  <= L_SCAN;
                    end else begin
                        // More data to fetch - pulse request for next transfer
                        dma_req <= 1'b1;
                        $display("DMA[%0d] time=%0t request: addr=0x%08h (byte 0x%08h)", 
                                    (dma_cnt + 2), $time, (dma_addr + 1), {(dma_addr + 1), 1'b0});
                    end
                end else begin
                    // No ack - clear pulse (single cycle only)
                    dma_req <= 1'b0;
                end
            end
            L_SCAN: begin
                speed_byte  <= (sfx_mem[HEADER_IDX_SPEED]==8'd0)?8'd1:sfx_mem[HEADER_IDX_SPEED];
                bass_flag   <= sfx_mem[HEADER_IDX_SPEED][0];
                loop_start_sys  <= sfx_mem[HEADER_IDX_LOOPST][5:0];
                loop_end_sys    <= sfx_mem[HEADER_IDX_LOOPEN][5:0];
                filt_noiz   <= (sfx_mem[HEADER_IDX_FILTERS] & 8'h02) != 8'h00;
                filt_buzz   <= (sfx_mem[HEADER_IDX_FILTERS] & 8'h04) != 8'h00;
                filt_detune <= f_div3(sfx_mem[HEADER_IDX_FILTERS], 8'd8);
                filt_reverb <= f_div3(sfx_mem[HEADER_IDX_FILTERS], 8'd24);
                filt_dampen <= f_div3(sfx_mem[HEADER_IDX_FILTERS], 8'd72);
                // Check if this is a waveform instrument (bit 7 of loop_start byte, only valid for SFX 0..7)
                is_waveform_inst = (sfx_index_in <= 6'd7) && sfx_mem[HEADER_IDX_LOOPST][7];
                // done scanning; signal load complete
                sfx_load_done_sys <= 1'b1;
                lstate   <= L_IDLE;
                $display("SFX %0d loaded: speed=%0d (raw=0x%02h), bass=%0d, loop=%0d-%0d", 
                         sfx_index_in, 
                         (sfx_mem[HEADER_IDX_SPEED]==8'd0)?8'd1:sfx_mem[HEADER_IDX_SPEED],
                         sfx_mem[HEADER_IDX_SPEED], 
                         sfx_mem[HEADER_IDX_SPEED][0],
                         sfx_mem[HEADER_IDX_LOOPST][5:0], 
                         sfx_mem[HEADER_IDX_LOOPEN][5:0]);
            end
            default: begin
                // Handle undefined states gracefully
                lstate <= L_IDLE;
            end
        endcase
    end
end

//==============================================================
// CDC: clk_sys -> clk_pcm toggle-based pulse signals
//==============================================================
// Toggle registers in clk_sys domain
reg play_toggle_sys;                // clk_sys: Toggle on play_strobe
reg sfx_load_done_toggle_sys;       // clk_sys: Toggle on load completion
reg force_stop_toggle_sys;          // clk_sys: Toggle on force_stop
reg force_release_toggle_sys;       // clk_sys: Toggle on force_release

// CDC stages in clk_pcm domain
reg play_toggle_pcm_d,          play_toggle_pcm_q;          // clk_pcm: play_strobe CDC stages
reg sfx_load_done_toggle_pcm_d, sfx_load_done_toggle_pcm_q; // clk_pcm: sfx_load_done CDC stages
reg force_stop_toggle_pcm_d,    force_stop_toggle_pcm_q;    // clk_pcm: force_stop CDC stages
reg force_release_toggle_pcm_d, force_release_toggle_pcm_q; // clk_pcm: force_release CDC stages

// Output pulses in clk_pcm domain
wire play_strobe_pcm    = (play_toggle_pcm_d ^ play_toggle_pcm_q);          // clk_pcm: play_strobe pulse
wire sfx_load_done_pcm  = (sfx_load_done_toggle_pcm_d ^ sfx_load_done_toggle_pcm_q); // clk_pcm: load done pulse
wire force_stop_pcm     = (force_stop_toggle_pcm_d ^ force_stop_toggle_pcm_q);       // clk_pcm: force_stop pulse
wire force_release_pcm  = (force_release_toggle_pcm_d ^ force_release_toggle_pcm_q); // clk_pcm: force_release pulse
reg        play_req_toggle_pcm;       // clk_pcm: Toggle for custom instrument play request
reg        stop_req_toggle_pcm;       // clk_pcm: Toggle for custom instrument stop request

// CDC data registers
reg loading_pcm_d;              // clk_pcm: Loading state CDC stages

// clk_sys: Generate toggle signals
always @(posedge clk_sys or negedge resetn) begin
    if (!resetn) begin
        play_toggle_sys <= 1'b0;
        sfx_load_done_toggle_sys <= 1'b0;
        force_stop_toggle_sys <= 1'b0;
        force_release_toggle_sys <= 1'b0;
    end else begin
        if (play_strobe)      play_toggle_sys <= ~play_toggle_sys;
        if (sfx_load_done_sys) sfx_load_done_toggle_sys <= ~sfx_load_done_toggle_sys;
        if (force_stop)       force_stop_toggle_sys <= ~force_stop_toggle_sys;
        if (force_release)    force_release_toggle_sys <= ~force_release_toggle_sys;
    end
end

// clk_pcm: Synchronize toggles and generate pulses
always @(posedge clk_pcm or negedge resetn) begin
    if (!resetn) begin
        play_toggle_pcm_d <= 1'b0;          play_toggle_pcm_q <= 1'b0;
        sfx_load_done_toggle_pcm_d <= 1'b0; sfx_load_done_toggle_pcm_q <= 1'b0;
        force_stop_toggle_pcm_d <= 1'b0;    force_stop_toggle_pcm_q <= 1'b0;
        force_release_toggle_pcm_d <= 1'b0; force_release_toggle_pcm_q <= 1'b0;
        start_idx_pcm <= 6'd0;
        sfx_length_pcm <= 6'd0;
        loop_start_cdc <= 6'd0;
        loop_end_cdc <= 6'd0;
        loading_pcm_d<=1'b0; loading_pcm<=1'b0;
    end else begin
        // Stage 1: Synchronize toggles from clk_sys
        play_toggle_pcm_d <= play_toggle_sys;
        sfx_load_done_toggle_pcm_d <= sfx_load_done_toggle_sys;
        force_stop_toggle_pcm_d <= force_stop_toggle_sys;
        force_release_toggle_pcm_d <= force_release_toggle_sys;
        
        // Stage 2: Delay for edge detection
        play_toggle_pcm_q <= play_toggle_pcm_d;
        sfx_load_done_toggle_pcm_q <= sfx_load_done_toggle_pcm_d;
        force_stop_toggle_pcm_q <= force_stop_toggle_pcm_d;
        force_release_toggle_pcm_q <= force_release_toggle_pcm_d;
        
        // Capture start_idx and sfx_length when load completes
        if (sfx_load_done_pcm) begin
            start_idx_pcm <= start_idx;
            sfx_length_pcm <= sfx_length;
            loop_start_cdc <= loop_start_sys;
            loop_end_cdc <= loop_end_sys;
        end

        loading_pcm_d<=loading_sys; loading_pcm<=loading_pcm_d;
    end
end

//==============================================================
// Current Note Parameters (must be declared before tasks that use them)
//==============================================================
reg [5:0] cur_pitch;   // clk_pcm: Current note pitch (0-63)
reg [2:0] cur_wave;    // clk_pcm: Current waveform (0-7)
reg [2:0] cur_vol;     // clk_pcm: Current volume (0-7)
reg [2:0] cur_eff;     // clk_pcm: Current effect (0-7)
reg       cur_custom;  // clk_pcm: Custom waveform flag

// Previous note parameters (for slide effect)
reg [5:0] prev_pitch;  // clk_pcm: Previous note pitch
reg [2:0] prev_vol;    // clk_pcm: Previous volume
reg [2:0] prev_wave;   // clk_pcm: Previous waveform

// Next note parameters (for release)
reg [5:0] next_pitch;   // clk_pcm: Next note pitch (0-63)
reg [2:0] next_wave;    // clk_pcm: Next waveform (0-7)
reg [2:0] next_vol;     // clk_pcm: Next volume (0-7)
reg [2:0] next_eff;     // clk_pcm: Next effect (0-7)
reg       next_custom;  // clk_pcm: Next custom waveform flag

// Note offset accumulator (fractional progress through current note)
// offset ranges from 0.0 to 1.0 over the duration of a note
reg [31:0] note_offset;  // clk_pcm: 32-bit U32F32 offset (0 = start, 2^32 = end)

// Envelope and effect state (used by tasks, must be declared before tasks)
reg [15:0] attack_ctr;      // clk_pcm: Attack/crossfade sample counter
reg [15:0] release_ctr;     // clk_pcm: Release sample counter
reg        releasing;       // clk_pcm: Release mode active flag
reg        arp_active;      // clk_pcm: Arpeggio active flag
reg [7:0] arp_accum;             // clk_pcm: Arpeggio tick accumulator
wire [7:0] arp_speed;            // clk_pcm: Arpeggio speed (computed combinationally)
reg [1:0]  next_group_pos;  // clk_pcm: Next arpeggio group position
reg signed [15:0] eff_vib_depth;  // clk_pcm: Vibrato depth

reg        inst_active_pcm;           // clk_pcm: Custom instrument currently active
reg  [2:0] inst_idx_pcm;              // clk_pcm: Custom instrument SFX index (0..7)

//==============================================================
// PITCH TABLE
//==============================================================
// Pitch table (32-bit fixed-point phase increments for PICO-8 pitches 0..95)
// PICO-8 pitch 0 = C0 = piano C2
// phase_inc = (2^32 * freq) / 22050; freq = 440*2^((note-33)/12)
// Note 33 = A2 = Piano A4 = 440 Hz (the reference)
reg [31:0] pitch_phase_inc [0:95];
initial begin
    pitch_phase_inc[ 0] = 32'h00c265db; pitch_phase_inc[ 1] = 32'h00cdf516;
    pitch_phase_inc[ 2] = 32'h00da3449; pitch_phase_inc[ 3] = 32'h00e72de9;
    pitch_phase_inc[ 4] = 32'h00f4ed0d; pitch_phase_inc[ 5] = 32'h01037d73;
    pitch_phase_inc[ 6] = 32'h0112eb8c; pitch_phase_inc[ 7] = 32'h01234489;
    pitch_phase_inc[ 8] = 32'h0134965f; pitch_phase_inc[ 9] = 32'h0146efdc;
    pitch_phase_inc[10] = 32'h015a60ad; pitch_phase_inc[11] = 32'h016ef96d;
    pitch_phase_inc[12] = 32'h0184cbb6; pitch_phase_inc[13] = 32'h019bea2d;
    pitch_phase_inc[14] = 32'h01b46892; pitch_phase_inc[15] = 32'h01ce5bd2;
    pitch_phase_inc[16] = 32'h01e9da1a; pitch_phase_inc[17] = 32'h0206fae6;
    pitch_phase_inc[18] = 32'h0225d719; pitch_phase_inc[19] = 32'h02468912;
    pitch_phase_inc[20] = 32'h02692cbf; pitch_phase_inc[21] = 32'h028ddfb9;
    pitch_phase_inc[22] = 32'h02b4c15a; pitch_phase_inc[23] = 32'h02ddf2db;
    pitch_phase_inc[24] = 32'h0309976d; pitch_phase_inc[25] = 32'h0337d45b;
    pitch_phase_inc[26] = 32'h0368d125; pitch_phase_inc[27] = 32'h039cb7a5;
    pitch_phase_inc[28] = 32'h03d3b434; pitch_phase_inc[29] = 32'h040df5cc;
    pitch_phase_inc[30] = 32'h044bae33; pitch_phase_inc[31] = 32'h048d1225;
    pitch_phase_inc[32] = 32'h04d2597f; pitch_phase_inc[33] = 32'h051bbf72;
    pitch_phase_inc[34] = 32'h056982b5; pitch_phase_inc[35] = 32'h05bbe5b7;
    pitch_phase_inc[36] = 32'h06132edb; pitch_phase_inc[37] = 32'h066fa8b6;
    pitch_phase_inc[38] = 32'h06d1a24a; pitch_phase_inc[39] = 32'h07396f4b;
    pitch_phase_inc[40] = 32'h07a76868; pitch_phase_inc[41] = 32'h081beb99;
    pitch_phase_inc[42] = 32'h08975c67; pitch_phase_inc[43] = 32'h091a244a;
    pitch_phase_inc[44] = 32'h09a4b2fe; pitch_phase_inc[45] = 32'h0a377ee5;
    pitch_phase_inc[46] = 32'h0ad3056a; pitch_phase_inc[47] = 32'h0b77cb6e;
    pitch_phase_inc[48] = 32'h0c265db7; pitch_phase_inc[49] = 32'h0cdf516d;
    pitch_phase_inc[50] = 32'h0da34494; pitch_phase_inc[51] = 32'h0e72de96;
    pitch_phase_inc[52] = 32'h0f4ed0d1; pitch_phase_inc[53] = 32'h1037d732;
    pitch_phase_inc[54] = 32'h112eb8ce; pitch_phase_inc[55] = 32'h12344894;
    pitch_phase_inc[56] = 32'h134965fd; pitch_phase_inc[57] = 32'h146efdcb;
    pitch_phase_inc[58] = 32'h15a60ad5; pitch_phase_inc[59] = 32'h16ef96dc;
    pitch_phase_inc[60] = 32'h184cbb6f; pitch_phase_inc[61] = 32'h19bea2db;
    pitch_phase_inc[62] = 32'h1b468928; pitch_phase_inc[63] = 32'h1ce5bd2c;
    pitch_phase_inc[64] = 32'h1e9da1a3; pitch_phase_inc[65] = 32'h206fae64;
    pitch_phase_inc[66] = 32'h225d719d; pitch_phase_inc[67] = 32'h24689129;
    pitch_phase_inc[68] = 32'h2692cbfa; pitch_phase_inc[69] = 32'h28ddfb96;
    pitch_phase_inc[70] = 32'h2b4c15aa; pitch_phase_inc[71] = 32'h2ddf2db9;
    pitch_phase_inc[72] = 32'h309976df; pitch_phase_inc[73] = 32'h337d45b6;
    pitch_phase_inc[74] = 32'h368d1251; pitch_phase_inc[75] = 32'h39cb7a58;
    pitch_phase_inc[76] = 32'h3d3b4347; pitch_phase_inc[77] = 32'h40df5cc9;
    pitch_phase_inc[78] = 32'h44bae33a; pitch_phase_inc[79] = 32'h48d12252;
    pitch_phase_inc[80] = 32'h4d2597f5; pitch_phase_inc[81] = 32'h51bbf72d;
    pitch_phase_inc[82] = 32'h56982b55; pitch_phase_inc[83] = 32'h5bbe5b72;
    pitch_phase_inc[84] = 32'h6132edbe; pitch_phase_inc[85] = 32'h66fa8b6c;
    pitch_phase_inc[86] = 32'h6d1a24a2; pitch_phase_inc[87] = 32'h7396f4b1;
    pitch_phase_inc[88] = 32'h7a76868f; pitch_phase_inc[89] = 32'h81beb992;
    pitch_phase_inc[90] = 32'h8975c674; pitch_phase_inc[91] = 32'h91a244a5;
    pitch_phase_inc[92] = 32'h9a4b2fea; pitch_phase_inc[93] = 32'ha377ee5a;
    pitch_phase_inc[94] = 32'had3056aa; pitch_phase_inc[95] = 32'hb77cb6e4;
end

//==============================================================
// NOTE DECODING
//==============================================================
// Decode note from SFX memory (2 bytes per note)
// PICO-8 note format (16 bits): {custom, eff[2:0], vol[2:0], wave[2:0], pitch[5:0]}
task decode_note(input [5:0] idx);
    begin
        cur_custom = sfx_mem[2*idx+1][7];
        cur_eff    = sfx_mem[2*idx+1][6:4];
        cur_vol    = sfx_mem[2*idx+1][3:1];
        cur_wave   = {sfx_mem[2*idx+1][0], sfx_mem[2*idx][7:6]};
        cur_pitch  = sfx_mem[2*idx][5:0];
        if (cur_eff != 3'd1 /* not a slide */ &&
            (cur_custom != 1'b1 || ((cur_wave != prev_wave || cur_pitch != prev_pitch || prev_vol == 3'd0) ^ (cur_eff == 3'd3)))) begin
            attack_ctr <= note_attack_samps;
            //$display("attack_ctr=", note_attack_samps);
        end
        releasing <= 0;
    end
endtask

task decode_next_note(input [5:0] idx);
    begin
        next_custom = sfx_mem[2*idx+1][7];
        next_eff    = sfx_mem[2*idx+1][6:4];
        next_vol    = sfx_mem[2*idx+1][3:1];
        next_wave   = {sfx_mem[2*idx+1][0], sfx_mem[2*idx][7:6]};
        next_pitch  = sfx_mem[2*idx][5:0];
        if (next_eff != 3'd1 /* not a slide */ &&
            (next_custom != 1'b1 || ((next_wave != cur_wave || next_pitch != cur_pitch || cur_vol == 3'd0) ^ (next_eff == 3'd3)))) begin
            //$display("release_ctr=", note_release_samps);
            release_ctr <= note_release_samps; releasing <= 1;
        end
    end
endtask

// Shared note trigger logic: set ramps/effects and advance note pointer
task next_note();
    reg [2:0] eff;
    begin
        // Save previous note for slide effect
        prev_pitch = cur_pitch;
        prev_vol   = cur_vol;
        prev_wave  = cur_wave;
        eff        = sfx_mem[2*note_idx+1][6:4];
        // TODO: There is a click at the start of a new note inside an arpeggio group
        if (eff==3'd6 || eff==3'd7) begin
            // Only decode a new note at the start of an arpeggio group
            if (!arp_active || note_idx[1:0] == 2'b00) begin
                arp_accum <= 8'd0;
                next_group_pos <= 2'd1;
                decode_note({note_idx[5:2],2'b00});
            end
            arp_active <= 1'b1;
        end else begin
            decode_note(note_idx);
            arp_active <= 1'b0;
        end
        if (cur_eff==3'd2) eff_vib_depth<=16'sd16; else eff_vib_depth<=16'sd0;

        if (sfx_length == 6'b111111) begin
            // Continuous loop mode: always wrap at NOTE_MAX_INDEX
            if (note_idx == NOTE_MAX_INDEX) begin
                note_idx <= 0;
            end else begin
                note_idx <= note_idx + 1;
            end
        end else if (sfx_length!=0) begin
            // Limited-length mode: play specified number of notes
            if (note_idx == NOTE_MAX_INDEX || note_idx  >= sfx_offset + sfx_length) begin
                sfx_done<=1'b1; sfx_loaded<=1'b0;
            end else begin
                note_idx<=note_idx+1;
            end
        end else begin
            // Full SFX mode (sfx_length==0): check loop points
            if ((loop_start != 6'd0) && (loop_end == 6'd0)) begin
                // Special case: play from 0 up to (but not including) loop_start, then stop
                if (note_idx + 1 >= loop_start) begin
                    sfx_done<=1'b1; sfx_loaded<=1'b0;
                end else begin
                    note_idx <= note_idx + 1;
                end
            end else if (loop_start == loop_end) begin
                // No loop: play through once to NOTE_MAX_INDEX then stop
                if (note_idx==NOTE_MAX_INDEX) begin
                    sfx_done<=1'b1; sfx_loaded<=1'b0;
                end else begin
                    note_idx <= note_idx + 1;
                end
            end else begin
                // Normal loop: loop between loop_start and loop_end
                if (note_idx==loop_end) note_idx<=loop_start;
                else note_idx<= (note_idx==NOTE_MAX_INDEX)?loop_start:(note_idx+1);
            end
        end
    end
endtask

//==============================================================
// PITCH/VOLUME/EFFECT CALCULATIONS
// Combinational logic for note effects and pitch modulation
//==============================================================
// Phase accumulator and effects (clk_pcm domain)
reg signed [15:0] eff_vib_phase;  // clk_pcm: Vibrato phase accumulator
reg [31:0]        phase_acc;      // clk_pcm: U32F15 phase accumulator (32768 = 1.0, bits [14:0] = fractional phase)
reg [31:0]        detune_acc;      // clk_pcm: U32F15 phase accumulator (32768 = 1.0, bits [14:0] = fractional phase)
reg [31:0]        eff_inc;        // clk_pcm: Effective phase increment (with modulation)
reg [7:0]         eff_vol;        // clk_pcm: Effective volume after fade effects (0-7, 8-bit for precision)

// Hardware FX clock modulation bits (clk_pcm domain, from hwfx_reg[0])
// hw_low_clk is handled in p8audio.v by halving clk_pcm
wire hw_high_clk = hwfx_5f40_pcm[{1'b1,channel_id}];   // clk_pcm: Octave-down bit

// Phase multiplier calculation and application (clk_pcm domain)
reg [31:0] phase_mult;  // clk_pcm: U32F15 Current phase multiplier (for MAIN->CUSTOM)
reg [31:0] detune_inc;  // clk_pcm: Detune phase increment

// Temporary variables for phase calculation (combinational logic)
integer p;
integer p_prev;
reg [31:0] base_inc;
reg [31:0] base_inc_prev;
reg [63:0] mult_result;
reg signed [31:0] freq_mod;
integer v_prev;
reg signed [15:0] vib_t;

always @(*) begin
    p = {26'd0, cur_pitch};
    p_prev = {26'd0, prev_pitch};
    
    mult_result = 64'd0;  // Initialize to avoid latch
    freq_mod = 32'sd0;
    
    if (p<0) p=0; if (p>95) p=95;
    if (p_prev<0) p_prev=0; if (p_prev>95) p_prev=95;
    if (hw_high_clk) p = (p>=12) ? (p-12) : 0;
    
    // Apply note effects to pitch before computing phase increment
    case (cur_eff)
        3'd1: begin  // Slide from prev_pitch to cur_pitch
            // Linear interpolation: pitch = prev + (cur - prev) * note_offset
            if (p_prev != p) begin
                base_inc_prev = pitch_phase_inc[p_prev] >> (bass_flag?1:0);
                base_inc = pitch_phase_inc[p] >> (bass_flag?1:0);
                // Interpolate: base_inc = prev + (cur - prev) * note_offset / 65536
                base_inc = base_inc_prev + (({32'd0, (base_inc - base_inc_prev)} * {32'd0, note_offset}) / (64'd1 << 32));
            end else begin
                base_inc = pitch_phase_inc[p] >> (bass_flag?1:0);
            end
        end
        3'd2: begin  // Vibrato: 7.5 Hz, +/-0.5 semitone
            vib_t = eff_vib_phase;
            freq_mod = ({{16{vib_t[15]}}, vib_t} * 3) / 100;
            base_inc = (pitch_phase_inc[p] >> (bass_flag?1:0)) + freq_mod;
        end
        3'd3: begin  // Drop: freq *= (1.0 - note_offset)
            base_inc = pitch_phase_inc[p] >> (bass_flag?1:0);
            base_inc = (({32'd0, base_inc} * ((64'd1 << 32) - {32'd0, note_offset})) / (64'd1 << 32));
        end
        default: begin  // No pitch effect (fade in/out handled by volume)
            base_inc = (pitch_phase_inc[p] >> (bass_flag?1:0)) + {{15{eff_vib_depth[15]}}, eff_vib_depth, 1'b0};
        end
    endcase
    
    // CUSTOM core: apply phase multiplier from parent
    if (phase_multiplier_in != 32'd0) begin
        eff_inc = ({32'd0, base_inc} * {32'd0, phase_multiplier_in}) >> 15;
    end else begin
        eff_inc = base_inc;
    end
    
    // Calculate detune phase increment
    case (cur_wave)
        3'd0: begin // TRIANGLE
            if (filt_detune == 2'd1)
                detune_inc = eff_inc - (eff_inc >> 2);
            else if (filt_detune == 2'd2)
                detune_inc = eff_inc + (eff_inc >> 1);
            else
                detune_inc = eff_inc;
        end

        3'd5: begin // ORGAN
            if (filt_detune == 2'd1)
                detune_inc = eff_inc + (eff_inc / 199);
            else if (filt_detune == 2'd2)
                detune_inc = (eff_inc + (eff_inc / 199)) << 2;
            else
                detune_inc = eff_inc;
        end

        3'd7: begin // PHASER
            if (filt_detune == 2'd1)
                detune_inc = eff_inc - (eff_inc / 50);
            else if (filt_detune == 2'd2)
                detune_inc = (eff_inc + (eff_inc / 199)) << 1;
            else
                detune_inc = eff_inc;
        end

        default: begin
            if (filt_detune == 2'd1)
                detune_inc = eff_inc + (eff_inc / 199); 
            else if (filt_detune == 2'd2)
                detune_inc = (eff_inc + (eff_inc / 199)) << 1;
            else
                detune_inc = eff_inc;
        end
    endcase

    // Volume effects
    case (cur_eff)
        3'd1: begin  // Slide: interpolate volume
            if (prev_vol > 3'd0) begin
                v_prev = {29'd0, prev_vol};
                eff_vol = (v_prev << 5) + ((({29'd0, cur_vol} - v_prev) * {32'd0, note_offset}) >> 27);
            end else begin
                eff_vol = cur_vol << 5;
            end
        end
        3'd4: eff_vol = ({56'd0, cur_vol} * {32'd0, note_offset}) >> 27;  // Fade in
        3'd5: eff_vol = (({56'd0, cur_vol} * ((64'd1 << 32) - {32'd0, note_offset})) >> 27);  // Fade out
        default: eff_vol = cur_vol << 5;
    endcase
    
    // Phase multiplier for custom instruments: pitch ratio relative to C2
    if (cur_custom && pitch_phase_inc[PITCH_REF_C2] != 32'd0) begin
        phase_mult = ({32'd0, eff_inc} << 15) / pitch_phase_inc[PITCH_REF_C2];
    end else begin
        phase_mult = 32'd0;
    end
end

assign phase_multiplier_out = phase_mult;

// Arpeggio rate
assign arp_speed = (cur_eff==3'd6) ? ((speed_byte <= 8) ? 8'd2 : 8'd4) :
                   (cur_eff==3'd7) ? ((speed_byte <= 8) ? 8'd4 : 8'd8) : 8'd0;


//==============================================================
// PHASE ACCUMULATORS & TIMING (clk_pcm domain)
// Phase accumulator updates and note timing
//==============================================================
always @(posedge clk_pcm or negedge resetn) begin
    if (!resetn) begin
        note_idx<=0; eff_vib_phase<=0; eff_vib_depth<=0;
        phase_acc<=0; detune_acc<=0; cur_pitch<=0; cur_wave<=0; cur_vol<=0; cur_eff<=0; cur_custom<=0;
        prev_pitch<=0; prev_vol<=0; note_offset<=0;
        arp_accum<=0; arp_active<=0; next_group_pos<=0;
        attack_ctr<=0; release_ctr<=0; releasing<=0;
        sfx_loaded<=0; sfx_done<=0;
        note_tick_acc<=0;
        loop_start<=6'd0; loop_end<=6'd0;
        inst_active_pcm<=1'b0; inst_idx_pcm<=3'd0; play_req_toggle_pcm<=1'b0; stop_req_toggle_pcm<=1'b0;
    end else begin
        sfx_done <= 1'b0;
        
        // Handle loading completion - start playback immediately
        if (sfx_load_done_pcm) begin
            sfx_loaded <= 1'b1;
            note_idx = start_idx_pcm;
            note_tick_acc <= 8'd0;
            loop_start <= loop_start_cdc;
            loop_end <= loop_end_cdc;
            // Trigger the first note immediately since play command has already passed
            // This sets up all the note parameters (pitch, volume, waveform, etc.)
            if (is_waveform_inst) begin
                cur_custom = 1'd0;
                cur_eff    = 3'd0;
                cur_vol    = 3'd5;
                cur_wave   = 3'd0;
                cur_pitch  = 6'd24;
                attack_ctr <= 1'd0;
                releasing <= 1'd0;
            end else begin
                next_note();
                update_custom_instrument();
            end
            $display("  SFX loaded and started: note_idx=%0d", start_idx_pcm);
        end
        
        // Handle force stop
        if (force_stop_pcm) begin
            sfx_loaded <= 1'b0;
            arp_active <= 1'b0;
            // stop any active instrument immediately
            inst_request_stop();
        end
        
        // Handle force release (break loop by setting loop_start = loop_end)
        if (force_release_pcm && sfx_loaded) begin
            loop_start <= loop_end;
        end

        // Handle note progression during playback
        if (sfx_loaded) begin
            if (!is_waveform_inst) begin
                if (note_tick) begin
                    // accumulate note_tick pulses; only trigger a new note when counter reaches speed_byte - 1
                    // (because we start counting from 0, so speed_byte ticks = 0..speed_byte-1)
                    if (note_tick_acc >= speed_byte - 1) begin
                        note_tick_acc <= 8'd0;
                        next_note();
                        update_custom_instrument();
                    end else if (arp_active && (arp_speed!=0) && arp_accum + 1 >= arp_speed) begin
                        // TODO: arpeggios have a slight click -- may need release / attack ramps between arpeggio notes
                        arp_accum <= 8'd0;
                        next_group_pos <= (next_group_pos==2'd3)?2'd0:(next_group_pos + 2'd1);
                        decode_note({note_idx[5:2], next_group_pos});
                        update_custom_instrument();
                    end else if (run) begin
                        note_tick_acc <= note_tick_acc + 1;
                        if (arp_active && (arp_speed!=0)) begin
                            arp_accum <= arp_accum + 1;
                        end
                    end
                end else if (note_tick_pre && note_release_samps!=0) begin
                    if (note_tick_acc >= speed_byte - 1) begin
                        decode_next_note(note_idx);
                    end else if (arp_active && (arp_speed!=0) && arp_accum + 1 >= arp_speed) begin
                        decode_next_note({note_idx[5:2], next_group_pos});
                    end
                end else begin
                    // Envelope counter decrements every clk_pcm cycle
                    if (attack_ctr!=0)  attack_ctr  <= attack_ctr  - 1;
                    if (release_ctr!=0) release_ctr <= release_ctr - 1;
                end

                eff_vib_phase <= eff_vib_phase + 16'sd200;
                if (cur_eff!=3'd2) eff_vib_depth <= 16'sd0;
            end

            // TODO: rationalize use of run
            if (run) begin
                phase_acc  <= phase_acc  + (eff_inc >> 17);
                detune_acc  <= detune_acc  + (detune_inc >> 17);
                // note_offset ramps 0->2^32 over (speed_byte * NOTE_TICK_DIV) samples for effect interpolation
                if (sfx_load_done_pcm) begin
                    note_offset <= 32'd0;
                end else if (note_tick && (note_tick_acc >= speed_byte - 1)) begin
                    // A note advance occurred this sample -> keep offset at 0
                    note_offset <= 32'd0;
                end else begin
                    if (speed_byte != 0) begin
                        // U32F32 increment: 2^32 / (speed_byte * NOTE_TICK_DIV)
                        note_offset <= note_offset + ((64'd1 << 32) / (speed_byte * NOTE_TICK_DIV));
                    end
                end
            end
        end
    end
end

//==============================================================
// NOISE GENERATION (clk_pcm domain)
// White noise (LFSR) and brown noise (IIR filter)
//==============================================================
reg [15:0] lfsr;        // clk_pcm: Linear feedback shift register for white noise
reg signed [31:0] brown_state;  // clk_pcm: Brown noise IIR filter state (S32F15 format, ±32768 = ±1.0)

// Brown noise filter computation temporaries
reg signed [31:0] lfsr_signed;       // S32F15: sign-extended LFSR value (fractional ±1.0)
reg signed [31:0] brown_err;         // S32F15: error term for IIR filter
reg [31:0] pitch_ratio;              // U32F27: 8.6 * eff_inc (unsigned, max ~16)
reg [31:0] brown_alpha;              // U32F32: alpha coefficient for brown noise IIR filter

always @(posedge clk_pcm or negedge resetn) begin
    if (!resetn) begin
        lfsr <= 16'hACE1;
        brown_state <= 32'sd0;
    end else if (run && sfx_loaded) begin
        // Update LFSR for white noise (always running when sfx is loaded)
        lfsr <= {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[1]^lfsr[0]};  // LFSR taps
        
        // Brown noise IIR: brown_state += alpha * (lfsr - brown_state)
        // alpha = pitch_ratio / (1 + pitch_ratio), pitch_ratio = 8.86 * eff_inc
        lfsr_signed = {{16{lfsr[15]}}, lfsr};

        // pitch_ratio = 8.86 * eff_inc (U32F27): 8.86 ≈ 567/64
        pitch_ratio = ({32'd0, eff_inc} * 64'd567) >> 11;

        // brown_alpha = pitch_ratio / (1 + pitch_ratio) (U32F32)
        brown_alpha = ({32'd0, pitch_ratio} << 32) / ((32'd1 << 27) + pitch_ratio);
        if (brown_alpha < 4096) brown_alpha = 4096;   // clamp for stability

        brown_err = lfsr_signed - brown_state;
        brown_state <= brown_state + (($signed({{32{brown_err[31]}}, brown_err}) * $signed({32'd0, brown_alpha})) >>> 32);
    end
end


//==============================================================
// WAVEFORM GENERATION
// Helper functions and waveform synthesis task
//==============================================================
// Absolute value function for 32-bit signed values
function signed [31:0] abs32(input signed [31:0] x);
    abs32 = x[31] ? -x : x;
endfunction

// S32F15 fixed-point multiplication: (a * b) / 32768
function signed [31:0] fp_mul(input signed [31:0] a, input signed [31:0] b);
    fp_mul = ($signed({{32{a[31]}}, a}) * $signed(b)) >>> 15;
endfunction

// S32F15 fixed-point division: (a / b) * 32768
function signed [31:0] fp_div(input signed [31:0] a, input signed [31:0] b);
    fp_div = ($signed({{32{a[31]}}, a}) <<< 15) / $signed(b);
endfunction

// Waveform generator: produces 16-bit PCM samples for PICO-8 waveforms 0-7
task waveform_gen(
    output signed [15:0] out,
    input [2:0] wave,
    input [31:0] phase_in,
    input [5:0] note_idx_in,
    input filt_buzz_local,
    input filt_noiz_local
);
    // 17/15 fixed-point constants: ±32768 = ±1.0
    localparam signed [31:0] FP_ONE      = 32'sd32768;   // 1.0
    localparam signed [31:0] FP_TWO      = 32'sd65536;   // 2.0
    localparam signed [31:0] FP_THREE    = 32'sd98304;   // 3.0
    localparam signed [31:0] FP_FOUR     = 32'sd131072;  // 4.0
    localparam signed [31:0] FP_HALF     = 32'sd16384;   // 0.5
    localparam signed [31:0] FP_QUARTER  = 32'sd8192;    // 0.25
    localparam signed [31:0] FP_EIGHTH   = 32'sd4096;    // 0.125

    // Tilted saw breakpoints
    localparam signed [31:0] FP_0_875    = 32'sd28672;   // 0.875
    localparam signed [31:0] FP_0_975    = 32'sd31949;   // 0.975

    // Saw waveform constants
    localparam signed [31:0] FP_0_326    = 32'sd10682;   // 0.326
    localparam signed [31:0] FP_0_653    = 32'sd21845;   // 0.653 (2 * 0.326)
    localparam signed [31:0] FP_0_085    = 32'sd1393;    // 0.085 (buzz offset)
    localparam signed [31:0] FP_0_83     = 32'sd27197;   // 0.83 (buzz multiply)

    // Organ waveform constants  
    localparam signed [31:0] FP_SIX      = 32'sd196608;  // 6.0
    localparam signed [31:0] FP_TWELVE   = 32'sd393216;  // 12.0
    localparam signed [31:0] FP_NEG_1_875= -32'sd61440;  // -1.875
    localparam signed [31:0] FP_0_2      = 32'sd6554;    // 0.2

    // Noise waveform constants
    localparam signed [31:0] FP_1_5      = 32'sd49152;   // 1.5

    // Phase components
    reg signed [31:0] t_local;

    // Triangle waveform variables
    reg signed [31:0] tri_x;
    reg signed [31:0] tri_temp;

    // Tilted saw variables (used by TRIANGLE buzz and TILTED SAW)
    reg signed [31:0] tsaw_breakpoint;
    reg signed [31:0] tsaw_out;
    reg signed [31:0] tsaw_temp;

    // Linear saw variables (used by SAW and NOISE)
    reg signed [31:0] saw_base;
    reg signed [31:0] saw_offset;
    reg signed [31:0] saw_temp;

    // Square/Pulse variables
    reg sq_threshold;
    reg [4:0] pulse_duty;

    // Organ waveform variables
    reg signed [31:0] organ_val;

    // Noise waveform variables
    reg signed[31:0] noise_factor1;
    reg signed[31:0] noise_factor2;

    // Phaser variables
    reg signed [31:0] phaser_x;
    reg signed [31:0] phaser_109x110;
    reg signed [31:0] phaser_t109x110;
    reg signed [31:0] phaser_abs;
    reg signed [31:0] phaser_temp;
    reg signed [31:0] phaser_2x;
    reg signed [31:0] phaser_t2x;
    reg signed [31:0] phaser_4x;
    reg signed [31:0] phaser_t4x;

    begin
        t_local = $signed({17'd0, phase_in[14:0]});  // Extract fractional phase [0,1)
        out = 16'sd0;
        case (wave)
            3'd0: begin // TRIANGLE: 1 - abs(4*t - 2)
                tri_x = (t_local <<< 2) - FP_TWO;
                tri_temp = FP_ONE - abs32(tri_x);

                if (filt_buzz_local) begin  // Mix with tilted saw (75/25)
                    tsaw_breakpoint = FP_0_875;
                    if (t_local < tsaw_breakpoint) begin
                        tsaw_out = fp_div(t_local, tsaw_breakpoint) - FP_ONE;
                    end else begin
                        tsaw_out = fp_div(FP_ONE - t_local, FP_ONE - tsaw_breakpoint) - FP_ONE;
                    end
                    tri_temp = (tri_temp * 32'sd3 + tsaw_out * 32'sd4) / 32'sd4;
                end
                
                out = tri_temp >>> 1;
            end

            3'd1: begin // TILTED SAW: asymmetric breakpoint at 0.875 (0.975 with buzz)
                tsaw_breakpoint = filt_buzz_local ? FP_0_975 : FP_0_875;
                if (t_local < tsaw_breakpoint) begin
                    out = fp_div(t_local, tsaw_breakpoint) - FP_HALF;
                end else begin
                    out = fp_div(FP_ONE - t_local, FP_ONE - tsaw_breakpoint) - FP_HALF;
                end
            end

            3'd2: begin // SAW: (t < 0.5 ? t : t-1) * 0.653, buzz adds harmonic
                if (t_local < FP_HALF)
                    saw_base = t_local;
                else
                    saw_base = t_local - FP_ONE;
                
                if (filt_buzz_local) begin
                    saw_offset = note_idx_in[0] ? 32'sd0 : FP_0_085;
                    saw_base = fp_mul(saw_base, FP_0_83) - saw_offset;
                end
                
                out = fp_mul(saw_base, FP_0_653);
            end

            3'd3: begin // SQUARE: 50% duty (40% with buzz)
                if (filt_buzz_local)
                    sq_threshold = (phase_in[14:10] < 5'd13);
                else
                    sq_threshold = phase_in[14];
                out = sq_threshold ? FP_QUARTER : -FP_QUARTER;
            end

            3'd4: begin // PULSE: 31.6% duty (25.5% with buzz)
                pulse_duty = filt_buzz_local ? 5'd8 : 5'd10;
                out = (phase_in[14:10] < pulse_duty) ? FP_QUARTER : -FP_QUARTER;
            end

            3'd5: begin // ORGAN: piecewise triangle
                if (t_local < FP_HALF) begin
                    organ_val = abs32((t_local * 32'sd24) - FP_SIX);
                    organ_val = FP_THREE - organ_val;
                end else begin
                    organ_val = abs32((t_local * 32'sd16) - FP_TWELVE);
                    organ_val = FP_ONE - organ_val;
                end

                if (filt_buzz_local) begin
                    if (t_local < FP_HALF) begin
                        organ_val = (organ_val <<< 1) + FP_THREE;
                        if (organ_val > FP_NEG_1_875)
                            organ_val = fp_mul(organ_val, FP_0_2) - FP_ONE;
                        else
                            organ_val = organ_val + FP_HALF;
                    end else begin
                        organ_val = organ_val + FP_HALF;
                    end
                end

                organ_val = organ_val / 32'sd9;
                out = organ_val;
            end

            3'd6: begin // NOISE
                if (filt_noiz_local) begin
                    // TODO: this should be brown noise
                    out = lfsr;
                end else begin
                    noise_factor1 = FP_ONE - $signed({11'd0, cur_pitch, 15'd0}) / 32'sd63;
                    noise_factor2 = fp_mul(FP_1_5, FP_ONE + fp_mul(noise_factor1, noise_factor1));
                    out = fp_mul(brown_state, noise_factor2);
                end
            end

            3'd7: begin // PHASER: sum of triangle waves at 1.0x and ~0.99x freq
                phaser_abs = abs32((t_local <<< 3) - FP_FOUR);
                phaser_temp = FP_TWO - phaser_abs;

                // Secondary at 109/110 freq (~0.991)
                phaser_109x110 = phase_in - phase_in / 32'sd110;
                phaser_t109x110 = $signed({17'd0, phaser_109x110[14:0]});
                phaser_abs = abs32((phaser_t109x110 <<< 2) - FP_TWO);
                phaser_temp = phaser_temp + FP_ONE - phaser_abs;

                // Buzz adds harmonics at 2x and 4x
                if (filt_buzz_local) begin
                    phaser_2x = FP_HALF + (phase_in <<< 1);
                    phaser_t2x = $signed({17'd0, phaser_2x[14:0]});
                    phaser_abs = abs32(phaser_t2x - FP_HALF);
                    phaser_temp = phaser_temp + FP_QUARTER - phaser_abs;

                    phaser_4x = $signed(phase_in) <<< 2;
                    phaser_t4x = $signed({17'd0, phaser_4x[14:0]});
                    phaser_abs = abs32((phaser_t4x >>> 1) - FP_QUARTER);
                    phaser_temp = phaser_temp + FP_EIGHTH - phaser_abs;
                end

                phaser_temp = phaser_temp / 32'sd6;
                out = phaser_temp;
            end
        endcase
    end
endtask

// Base waveform: use custom instrument PCM or internal waveform generator
reg signed [15:0] base_sample;
always @(*) begin
    if (cur_custom) begin
        base_sample = custom_pcm_in;
    end else begin
        waveform_gen(base_sample, cur_wave, phase_acc, note_idx, filt_buzz, filt_noiz);
    end
end

// Custom waveform: 64-byte waveform table indexed by phase[14:9]
reg signed [15:0] custom_wav_sample;
reg [6:0] wav_idx;
reg signed [7:0] s8;

always @(*) begin
    wav_idx = {1'b0, phase_acc[14:9]};
    s8 = $signed(sfx_mem[wav_idx]);
    custom_wav_sample = {{8{s8[7]}}, s8} <<< 8;  // TODO: Pico-8 performs linear interpolation
end

// Detune/chorus: second waveform at slightly different freq
reg signed [15:0] detune_sample;
always @(*) begin
    detune_sample = 16'sd0;
    if (filt_detune!=2'd0 && cur_wave!=3'd6) begin
        waveform_gen(detune_sample, cur_wave, detune_acc, note_idx, filt_buzz, filt_noiz);
        detune_sample = detune_sample >>> 1;
    end
end


//==============================================================
// HARDWARE FX OVERRIDES
//==============================================================
// Reverb control (hwfx_5f41_pcm)
wire hw_low_rev  = hwfx_5f41_pcm[{1'b0,channel_id}];   // clk_pcm: Low reverb bit
wire hw_high_rev = hwfx_5f41_pcm[{1'b1,channel_id}];   // clk_pcm: High reverb bit
reg  [1:0] eff_reverb;                                 // clk_pcm: Effective reverb amount
always @(*) begin
    eff_reverb = filt_reverb;
    if (hw_low_rev) eff_reverb = 2'd2;
    else if (hw_high_rev && (eff_reverb < 2'd2)) eff_reverb = 2'd1;
end

// Bitcrush/distort control (hwfx_5f42_pcm)
wire hw_low_bcr  = hwfx_5f42_pcm[{1'b0,channel_id}];   // clk_pcm: Low bitcrush bit
wire hw_high_bcr = hwfx_5f42_pcm[{1'b1,channel_id}];   // clk_pcm: High bitcrush bit

// Dampen/lowpass filter control (hwfx_5f43_pcm)
wire hw_low_dmp  = hwfx_5f43_pcm[{1'b0,channel_id}];   // clk_pcm: Low dampen bit
wire hw_high_dmp = hwfx_5f43_pcm[{1'b1,channel_id}];   // clk_pcm: High dampen bit
reg  [1:0] eff_dampen;                                 // clk_pcm: Effective dampen amount
reg  [15:0] damp_alpha;                                // clk_pcm: Dampen filter coefficient
reg signed [31:0] damp_state;                          // clk_pcm: Dampen filter state
reg  [1:0] base;
integer a;

always @(*) begin
    base = filt_dampen;
    if (hw_low_dmp && hw_high_dmp) base = 2'd3;
    else if (hw_low_dmp) base = 2'd2;
    else if (hw_high_dmp && base < 2'd2) base = 2'd1;
    eff_dampen = base;
    a = 0;
    damp_alpha = 16'd0;
    if (eff_dampen==2'd0) begin
        damp_alpha = 16'd0;
    end else if (eff_dampen==2'd1) begin
        a = (TWO_PI_X1000 * DAMP_FREQ_LOW) / PCM_SAMPLE_RATE;
        if (a>32767) a=32767;
        damp_alpha = a[15:0];
    end else if (eff_dampen==2'd2) begin
        a = (TWO_PI_X1000 * DAMP_FREQ_HIGH) / PCM_SAMPLE_RATE;
        if (a>32767) a=32767;
        damp_alpha = a[15:0];
    end else begin
        a = (TWO_PI_X1000 * DAMP_FREQ_STRONG) / PCM_SAMPLE_RATE;
        if (a>32767) a=32767;
        damp_alpha = a[15:0];
    end
end

//==============================================================
// Reverb Delay Lines (clk_pcm domain)
//==============================================================
reg [8:0] rev_idx2;       // clk_pcm: Short reverb delay line write index
reg [9:0] rev_idx4;       // clk_pcm: Long reverb delay line write index
reg [8:0] rev_idx2_valid; // clk_pcm: Number of valid samples in short reverb delay line
reg [9:0] rev_idx4_valid; // clk_pcm: Number of valid samples in long reverb delay line

//==============================================================
// HARDWARE FX CDC (clk_sys -> clk_pcm)
// Synchronizes hardware effect bytes across clock domains
//==============================================================
reg [7:0] hwfx_5f40_pcm_d;  // clk_pcm: HWFX 0x5F40 CDC stages
reg [7:0] hwfx_5f41_pcm_d;  // clk_pcm: HWFX 0x5F41 CDC stages
reg [7:0] hwfx_5f42_pcm_d;  // clk_pcm: HWFX 0x5F42 CDC stages
reg [7:0] hwfx_5f43_pcm_d;  // clk_pcm: HWFX 0x5F43 CDC stages

always @(posedge clk_pcm or negedge resetn) begin
    if (!resetn) begin
        hwfx_5f40_pcm_d<=8'd0; hwfx_5f40_pcm<=8'd0;
        hwfx_5f41_pcm_d<=8'd0; hwfx_5f41_pcm<=8'd0;
        hwfx_5f42_pcm_d<=8'd0; hwfx_5f42_pcm<=8'd0;
        hwfx_5f43_pcm_d<=8'd0; hwfx_5f43_pcm<=8'd0;
    end else begin
        hwfx_5f40_pcm_d<=hwfx_5f40; hwfx_5f40_pcm<=hwfx_5f40_pcm_d;
        hwfx_5f41_pcm_d<=hwfx_5f41; hwfx_5f41_pcm<=hwfx_5f41_pcm_d;
        hwfx_5f42_pcm_d<=hwfx_5f42; hwfx_5f42_pcm<=hwfx_5f42_pcm_d;
        hwfx_5f43_pcm_d<=hwfx_5f43; hwfx_5f43_pcm<=hwfx_5f43_pcm_d;
    end
end

//==============================================================
// PCM OUTPUT CHAIN (clk_pcm domain)
// Volume scaling, filter application, and final output
//==============================================================

// Temporary variables for PCM output chain
integer s;
integer x;
integer err;
integer rel_gain;
// Attack/release temporaries (zero-extended unsigned math)
integer atk_den;
integer atk_num;
integer rel_den;
integer rel_num;

always @(posedge clk_pcm or negedge resetn) begin
    if (!resetn) begin
        pcm_out<=0; damp_state<=0; rev_idx2<=0; rev_idx4<=0; rev_idx2_valid<=0; rev_idx4_valid<=0;
    end else begin
        if (run && sfx_loaded) begin
            if (is_waveform_inst) begin
                // Use custom waveform sample directly (no standard waveform generation or detune)
                s = {{16{custom_wav_sample[15]}}, custom_wav_sample};
            end else begin
                // Use standard base + detune samples
                s = {{16{base_sample[15]}}, base_sample} + {{16{detune_sample[15]}}, detune_sample};
            end

            // volume (use eff_vol which includes fade and slide effects)
            s = (s * $signed({24'd0, eff_vol})) / 32'sd224;
            if (s>32767) s=32767; if (s<-32768) s=-32768;

            // attack/release ramps
            if (attack_ctr != 0) begin
                // zero-extend to 32-bit unsigned for safe arithmetic
                atk_den = (note_attack_samps == 16'd0) ? 32'd1 : {16'd0, note_attack_samps};
                atk_num = atk_den - {16'd0, attack_ctr};
                //s$display("atk_den=%d atk_num=%d attack_ctr=%d", atk_den, atk_num, attack_ctr);
                s = (s * atk_num) / atk_den;
            end

            if (releasing && note_release_samps != 0) begin
                rel_den = {16'd0, note_release_samps};
                rel_num = {16'd0, release_ctr};
                //$display("rel_den=%d rel_num=%d release_ctr=%d", rel_den, rel_num, release_ctr);
                s = (s * rel_num) / rel_den;
            end

            // reverb
            if (eff_reverb==2'd1) begin
                if (rev_idx2 < rev_idx2_valid)
                    s = s + (reverb_2[rev_idx2] >>> 1);
            end else if (eff_reverb==2'd2) begin
                if (rev_idx4 < rev_idx4_valid)
                    s = s + (reverb_4[rev_idx4] >>> 1);
            end
            reverb_2[rev_idx2] <= s[15:0];
            if (rev_idx2 + 1 > rev_idx2_valid)
                rev_idx2_valid <= rev_idx2 + 1;
            if (rev_idx2 + 1 == REVERB_TAPS_SHORT)
                rev_idx2 <= 0;
            else
                rev_idx2 <= rev_idx2 + 1;
            reverb_4[rev_idx4] <= s[15:0];
            if (rev_idx4 + 1 > rev_idx4_valid)
                rev_idx4_valid <= rev_idx4 + 1;
            if (rev_idx4 + 1 == REVERB_TAPS_LONG)
                rev_idx4 <= 0;
            else
                rev_idx4 <= rev_idx4 + 1;

            // dampen
            if (damp_alpha!=0) begin
                err = s - damp_state;
                damp_state <= damp_state + ((err * $signed(damp_alpha)) / 1000);
                s = damp_state;
            end

            // bitcrush/distort
            if (hw_low_bcr) begin
                s = {{16{s[15]}}, s[15:10], 10'd0};
            end else if (hw_high_bcr) begin
                x = s;
                if (x > 8191) x = 8191;
                else if (x < -8191) x = -8191;
                s = {{16{x[15]}}, x[15:10], 10'd0};
            end

            pcm_out <= s[15:0];
        end else begin
            // No output when not running or not loaded
            pcm_out <= 16'sd0;
        end
    end
end

//==============================================================
// CUSTOM INSTRUMENT INTERFACE
//==============================================================
// Drive custom instrument requests when advancing to a new note
// Note: next_note() is called from clk_pcm always block; modify regs there
// Helpers to request play/stop from within next_note()
task inst_request_play(input [2:0] idx);
    begin
        inst_idx_pcm <= idx;
        inst_active_pcm <= 1'b1;
        play_req_toggle_pcm <= ~play_req_toggle_pcm;
    end
endtask
task inst_request_stop();
    begin
        if (inst_active_pcm) begin
            inst_active_pcm <= 1'b0;
            stop_req_toggle_pcm <= ~stop_req_toggle_pcm;
        end
    end
endtask
// Update custom instrument state after note advance
// Call this after next_note() or decode_note() to sync instrument with current note
task update_custom_instrument();
    begin
        if (sfx_done) begin
            // Voice just stopped
            if (inst_active_pcm) inst_request_stop();
        end else if (cur_custom) begin
            // Effect 3 retrigger inversion: don't retrigger instrument if parent has effect 3
            if (!inst_active_pcm || ((inst_idx_pcm != cur_wave || cur_pitch != prev_pitch || prev_vol == 3'd0) ^ (cur_eff == 3'd3))) inst_request_play(cur_wave);
        end else begin
            if (inst_active_pcm) inst_request_stop();
        end
    end
endtask

//==============================================================
// CDC: Instrument play/stop toggles from clk_pcm -> clk_sys
//==============================================================
reg play_req_toggle_sys_d, play_req_toggle_sys_q;
reg stop_req_toggle_sys_d, stop_req_toggle_sys_q;
wire play_req_pulse_sys = play_req_toggle_sys_d ^ play_req_toggle_sys_q;
wire stop_req_pulse_sys = stop_req_toggle_sys_d ^ stop_req_toggle_sys_q;

// Synchronize index from clk_pcm to clk_sys using a simple handshake-less shadow
// Since index is stable around the toggle, capture on play edge in clk_sys.
reg [2:0] inst_idx_sys_shadow;

always @(posedge clk_sys or negedge resetn) begin
    if (!resetn) begin
        play_req_toggle_sys_d <= 1'b0; play_req_toggle_sys_q <= 1'b0;
        stop_req_toggle_sys_d <= 1'b0; stop_req_toggle_sys_q <= 1'b0;
        inst_idx_sys_shadow <= 3'd0;
    end else begin
        play_req_toggle_sys_d <= play_req_toggle_pcm;
        play_req_toggle_sys_q <= play_req_toggle_sys_d;
        stop_req_toggle_sys_d <= stop_req_toggle_pcm;
        stop_req_toggle_sys_q <= stop_req_toggle_sys_d;
        // Latch inst_idx_pcm immediately when the CDC edge is detected
        if (play_req_toggle_pcm ^ play_req_toggle_sys_d)
            inst_idx_sys_shadow <= inst_idx_pcm;
    end
end

assign custom_sfx_index_out = {3'd0, inst_idx_sys_shadow};
assign custom_play_strobe   = play_req_pulse_sys;
assign custom_force_stop    = stop_req_pulse_sys;

endmodule
