//==============================================================
// p8sfx_voice.v
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

module p8sfx_voice (
    // Clocks & Reset
    input         clk_sys,
    input         clk_pcm,
    input         resetn,

    // Control (clk_sys)
    input         run,
    input  [31:0] base_addr,
    input  [1:0]  channel_id,

    // Triggers (clk_sys)
    input  [5:0]  sfx_index_in,
    input  [5:0]  sfx_offset,
    input  [5:0]  sfx_length,
    input         play_strobe,
    input         force_stop,
    input         force_release,

    // Timing (clk_pcm)
    input         note_tick,
    input         note_tick_pre,

    // Envelope (clk_sys)
    input  [15:0] note_attack_samps,
    input  [15:0] note_release_samps,

    // Status (clk_pcm)
    output        voice_busy,
    output        sfx_done,
    output        looping,

    // DMA client (clk_sys)
    output [30:0] dma_addr,
    output        dma_req,
    input  [15:0] dma_rdata,
    input         dma_ack,

    // PCM (clk_pcm)
    output signed [15:0] pcm_out,

    // stat (clk_pcm)
    output [5:0]         stat_sfx_index,
    output [5:0]         stat_note_index,

    // HWFX (clk_sys)
    input  [7:0] hwfx_5f40,
    input  [7:0] hwfx_5f41,
    input  [7:0] hwfx_5f42,
    input  [7:0] hwfx_5f43
);

    // Internal wiring MAIN <-> CUSTOM
    wire [5:0]  custom_sfx_index_out;
    wire        custom_play_strobe;
    wire        custom_force_stop;
    wire signed [15:0] custom_pcm_in;
    wire [31:0] phase_multiplier_main_to_custom;  // MAIN -> CUSTOM phase multiplier

    // DMA mux between cores
    wire [30:0] dma_addr_main, dma_addr_cust;
    wire        dma_req_main,  dma_req_cust;
    wire        dma_ack_main,  dma_ack_cust;

    // DMA arbiter instance (2 managers: MAIN=0, CUSTOM=1)
    dma_arbiter #(
        .NUM_MANAGERS(2),
        .ADDR_WIDTH(31)
    ) u_dma_arbiter (
        .clk(clk_sys),
        .resetn(resetn),
        .mgr_dma_addr({dma_addr_cust, dma_addr_main}),  // Concatenated: {mgr[1], mgr[0]}
        .mgr_dma_req({dma_req_cust, dma_req_main}),
        .mgr_dma_ack({dma_ack_cust, dma_ack_main}),
        .sub_dma_addr(dma_addr),
        .sub_dma_req(dma_req),
        .sub_dma_ack(dma_ack)
    );

    // MAIN core outputs forwarded out
    wire signed [15:0] pcm_out_main;
    wire        voice_busy_main;
    wire        sfx_done_main;
    wire [5:0]  stat_sfx_index_main;
    wire [5:0]  stat_note_index_main;
    wire        looping_main;

    // CUSTOM core local PCM and unused outputs captured to dummy wires for lint cleanliness
    wire signed [15:0] pcm_out_cust;
    wire        voice_busy_cust_dummy;
    wire        sfx_done_cust_dummy;
    wire [5:0]  stat_sfx_index_cust_dummy;
    wire [5:0]  stat_note_index_cust_dummy;
    wire        looping_cust_dummy;
    wire [5:0]  custom_sfx_index_out_dummy;
    wire        custom_play_strobe_dummy;
    wire        custom_force_stop_dummy;
    wire [31:0] phase_multiplier_out_dummy;

    // MAIN instance
    p8sfx_core u_main (
        .clk_sys(clk_sys), .clk_pcm(clk_pcm), .resetn(resetn),
        .run(run), .base_addr(base_addr), .channel_id(channel_id),
        .sfx_index_in(sfx_index_in), .sfx_offset(sfx_offset), .sfx_length(sfx_length),
        .play_strobe(play_strobe), .force_stop(force_stop), .force_release(force_release),
        .note_tick(note_tick), .note_tick_pre(note_tick_pre), .note_attack_samps(note_attack_samps), .note_release_samps(note_release_samps),
        .voice_busy(voice_busy_main), .sfx_done(sfx_done_main),
        .dma_addr(dma_addr_main), .dma_req(dma_req_main), .dma_rdata(dma_rdata), .dma_ack(dma_ack_main),
        .pcm_out(pcm_out_main),
        .stat_sfx_index(stat_sfx_index_main), .stat_note_index(stat_note_index_main), .looping(looping_main),
        .hwfx_5f40(hwfx_5f40), .hwfx_5f41(hwfx_5f41), .hwfx_5f42(hwfx_5f42), .hwfx_5f43(hwfx_5f43),
        .custom_sfx_index_out(custom_sfx_index_out),
        .custom_play_strobe(custom_play_strobe),
        .custom_force_stop(custom_force_stop),
        .custom_pcm_in(pcm_out_cust),
        .phase_multiplier_in(32'd0),
        .phase_multiplier_out(phase_multiplier_main_to_custom)
    );

    // CUSTOM instance
    p8sfx_core u_custom (
        .clk_sys(clk_sys), .clk_pcm(clk_pcm), .resetn(resetn),
        .run(run), .base_addr(base_addr), .channel_id(channel_id),
        .sfx_index_in(custom_sfx_index_out), .sfx_offset(6'd0), .sfx_length(6'b111111) /* continuous looping */,
        .play_strobe(custom_play_strobe), .force_stop(custom_force_stop), .force_release(1'b0),
        .note_tick(note_tick), .note_tick_pre(note_tick_pre), .note_attack_samps(note_attack_samps), .note_release_samps(note_release_samps),
        .voice_busy(voice_busy_cust_dummy), .sfx_done(sfx_done_cust_dummy),
        .dma_addr(dma_addr_cust), .dma_req(dma_req_cust), .dma_rdata(dma_rdata), .dma_ack(dma_ack_cust),
        .pcm_out(pcm_out_cust),
        .stat_sfx_index(stat_sfx_index_cust_dummy), .stat_note_index(stat_note_index_cust_dummy), .looping(looping_cust_dummy),
        .hwfx_5f40(hwfx_5f40), .hwfx_5f41(hwfx_5f41), .hwfx_5f42(hwfx_5f42), .hwfx_5f43(hwfx_5f43),
        .custom_sfx_index_out(custom_sfx_index_out_dummy),
        .custom_play_strobe(custom_play_strobe_dummy),
        .custom_force_stop(custom_force_stop_dummy),
        .custom_pcm_in(16'sd0),
        .phase_multiplier_in(phase_multiplier_main_to_custom),
        .phase_multiplier_out(phase_multiplier_out_dummy)
    );

    // Forward MAIN outputs
    assign pcm_out = pcm_out_main;
    assign voice_busy = voice_busy_main;
    assign sfx_done = sfx_done_main;
    assign stat_sfx_index = stat_sfx_index_main;
    assign stat_note_index = stat_note_index_main;
    assign looping = looping_main;

endmodule
