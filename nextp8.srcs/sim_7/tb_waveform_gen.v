//================================================================
// tb_waveform_gen.v
//
// Test bench for p8sfx_core_mux.waveform_gen task
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

module tb_waveform_gen;

    //====================
    // Test state
    //====================
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // Per-combination statistics: [instrument][buzz][noiz]
    // instrument: 0-7, buzz: 0-1, noiz: 0-1
    integer combo_pass [0:7][0:1][0:1];
    integer combo_fail [0:7][0:1][0:1];
    integer i, b, n;

    //====================
    // DUT signals - minimal set needed to call waveform_gen
    //====================
    // The DUT is p8sfx_core_mux, but we're only testing the waveform_gen task
    // We need to instantiate the module to access its task

    reg clk_sys = 1'b0;
    reg clk_pcm_8x = 1'b0;
    reg resetn = 1'b0;

    // Generate clocks (not critical for this test, but needed for module)
    always #15 clk_sys = ~clk_sys;         // 33 MHz
    always #2.835 clk_pcm_8x = ~clk_pcm_8x; // ~176.4 MHz

    // Minimal DUT instantiation (we only need the waveform_gen task)
    // Most ports can be tied off since we're not running the full module
    wire [7:0] pcm_out_0, pcm_out_1, pcm_out_2, pcm_out_3;
    wire [3:0] voice_busy;
    wire [3:0] sfx_done_w;
    wire [3:0] looping;
    wire dma_req;
    wire [30:0] dma_addr;

    // Array inputs - tie off to zeros
    wire [5:0] sfx_index_in_0 = 6'd0;
    wire [5:0] sfx_index_in_1 = 6'd0;
    wire [5:0] sfx_index_in_2 = 6'd0;
    wire [5:0] sfx_index_in_3 = 6'd0;

    wire [5:0] sfx_offset_0 = 6'd0;
    wire [5:0] sfx_offset_1 = 6'd0;
    wire [5:0] sfx_offset_2 = 6'd0;
    wire [5:0] sfx_offset_3 = 6'd0;

    wire [5:0] sfx_length_0 = 6'd0;
    wire [5:0] sfx_length_1 = 6'd0;
    wire [5:0] sfx_length_2 = 6'd0;
    wire [5:0] sfx_length_3 = 6'd0;

    wire [5:0] stat_sfx_index_0, stat_sfx_index_1, stat_sfx_index_2, stat_sfx_index_3;
    wire [5:0] stat_note_index_0, stat_note_index_1, stat_note_index_2, stat_note_index_3;

    p8sfx_core_mux dut (
        .clk_sys(clk_sys),
        .clk_pcm_8x(clk_pcm_8x),
        .resetn(resetn),
        .run(1'b1),
        .base_addr(32'h0),
        .sfx_index_in('{sfx_index_in_0, sfx_index_in_1, sfx_index_in_2, sfx_index_in_3}),
        .sfx_offset('{sfx_offset_0, sfx_offset_1, sfx_offset_2, sfx_offset_3}),
        .sfx_length('{sfx_length_0, sfx_length_1, sfx_length_2, sfx_length_3}),
        .play_strobe(4'd0),
        .force_stop(4'd0),
        .force_release(4'd0),
        .voice_busy(voice_busy),
        .sfx_done(sfx_done_w),
        .looping(looping),
        .dma_addr(dma_addr),
        .dma_req(dma_req),
        .dma_rdata(16'd0),
        .dma_ack(1'b0),
        .pcm_out('{pcm_out_0, pcm_out_1, pcm_out_2, pcm_out_3}),
        .stat_sfx_index('{stat_sfx_index_0, stat_sfx_index_1, stat_sfx_index_2, stat_sfx_index_3}),
        .stat_note_index('{stat_note_index_0, stat_note_index_1, stat_note_index_2, stat_note_index_3}),
        .hwfx_5f40(8'd0),
        .hwfx_5f41(8'd0),
        .hwfx_5f42(8'd0),
        .hwfx_5f43(8'd0)
    );

    //====================
    // Test case task
    //====================
    // Inputs are in S32F23 format (signed 32-bit, 23 fractional bits)
    // phase needs conversion: S32F23 -> U18F18 (take bits [40:23])
    // brown_state needs conversion: S32F23 -> S8F7 (take bits [30:23])
    // expected_sample is in S32F23, needs conversion to S8F7 for comparison

    task test_case;
        input [2:0] instrument;      // Waveform type (0-7)
        input [5:0] pitch;           // Note pitch (0-63)
        input buzz;                  // Buzz filter flag
        input noiz;                  // Noiz filter flag
        input signed [31:0] phase;   // S32F23 phase input
        input signed [31:0] brown_state_in; // S32F23 brown noise state
        input signed [31:0] expected_sample; // S32F23 expected output

        reg signed [7:0] actual_sample;
        reg signed [7:0] expected_s8f7;
        reg [21:0] phase_u22f18;
        reg signed [7:0] brown_s8f7;
        integer error;

        begin
            test_count = test_count + 1;

            // Convert S32F23 phase to U22F18 (shift right by 5, take lower 22 bits)
            // Phase is unsigned in the range [0, 1), so we take absolute value
            phase_u22f18 = phase[26:5];  // Extract bits [26:5] = 22 bits as U22F18

            // Convert S32F23 brown_state to S8F7 (shift right by 16, take lower 8 bits)
            brown_s8f7 = brown_state_in >>> 16;  // Shift right by 16 to convert S32F23 to S8F7

            // Directly assign to internal signals using hierarchical names
            // Note: Can't use force on array elements, so use direct assignment
            // Using context 0 for testing

            // CRITICAL: Force ctx_idx to 0 so wire aliases point to _8x[0] registers
            force dut.ctx_idx = 3'd0;

            dut.phase_acc_8x[0] = phase_u22f18;
            dut.brown_state_8x[0] = brown_s8f7;
            dut.cur_wave_8x[0] = instrument;
            dut.cur_pitch_8x[0] = pitch;
            dut.note_idx_8x[0] = 6'd0;  // Note index for SAW waveform saw_offset calculation
            dut.filt_buzz_8x[0] = buzz;
            dut.filt_noiz_8x[0] = noiz;
            dut.filt_detune_8x[0] = 2'd0;
            dut.is_waveform_inst_8x[0] = 1'b0;
            dut.cur_custom_8x[0] = 1'b0;

            // Initialize LFSR for noise waveform
            if (dut.lfsr_8x[0] == 8'd0)
                dut.lfsr_8x[0] = 8'b10101010;  // Non-zero seed

            // Wait a delta cycle for signals to propagate
            #1;

            // Call the waveform_gen task
            dut.waveform_gen(phase_u22f18, actual_sample);

            // Release ctx_idx force
            release dut.ctx_idx;

            // Convert expected S32F23 to S8F7 for comparison (shift right by 16, take lower 8 bits)
            expected_s8f7 = expected_sample >>> 16;

            // Check result (allow ±1 LSB tolerance for rounding differences)
            error = $signed(actual_sample) - $signed(expected_s8f7);
            if (error < -1 || error > 1) begin
                $display("FAIL: Test %0d - instrument=%0d, pitch=%0d, buzz=%0b, noiz=%0b",
                         test_count, instrument, pitch, buzz, noiz);
                $display("      phase=0x%08x (U22F18=0x%06x), brown_state=0x%08x (S8F7=0x%02x)",
                         phase, phase_u22f18, brown_state_in, brown_s8f7);
                $display("      Expected: %d (0x%02x), Got: %d (0x%02x), Error: %0d",
                         $signed(expected_s8f7), expected_s8f7,
                         $signed(actual_sample), actual_sample, error);
                fail_count = fail_count + 1;
                combo_fail[instrument][buzz][noiz] = combo_fail[instrument][buzz][noiz] + 1;
            end else begin
                pass_count = pass_count + 1;
                $display("PASS: Test %0d - instrument=%0d, pitch=%0d, phase=0x%06x -> sample=%d",
                         test_count, instrument, pitch, phase_u22f18, $signed(actual_sample));
                combo_pass[instrument][buzz][noiz] = combo_pass[instrument][buzz][noiz] + 1;
            end
        end
    endtask

    //====================
    // Test stimulus
    //====================
    initial begin
        $display("=== Waveform Generation Test Bench ===");
        $display("Testing p8sfx_core_mux.waveform_gen task");
        $display("");

        // Initialize per-combination counters
        for (i = 0; i < 8; i = i + 1) begin
            for (b = 0; b < 2; b = b + 1) begin
                for (n = 0; n < 2; n = n + 1) begin
                    combo_pass[i][b][n] = 0;
                    combo_fail[i][b][n] = 0;
                end
            end
        end

        // Reset
        resetn = 1'b0;
        #100;
        resetn = 1'b1;
        #100;

        // Test cases: instrument, pitch, buzz, noiz, phase (S32F23), brown_state (S32F23), expected (S32F23)

        // instrument 0 buzz 0 phase 2.945312 => -0.390625
        test_case(0, 0, 0, 0, 24707072, 0, -3276800);
        // instrument 0 buzz 0 phase 1.828125 => -0.156250
        test_case(0, 0, 0, 0, 15335424, 0, -1310720);
        // instrument 0 buzz 0 phase 3.828125 => -0.156250
        test_case(0, 0, 0, 0, 32112640, 0, -1310720);
        // instrument 0 buzz 0 phase 1.117188 => -0.265625
        test_case(0, 0, 0, 0, 9371648, 0, -2228224);
        // instrument 0 buzz 0 phase 0.914062 => -0.328125
        test_case(0, 0, 0, 0, 7667712, 0, -2752512);
        // instrument 0 buzz 0 phase 3.382812 => 0.265625
        test_case(0, 0, 0, 0, 28377088, 0, 2228224);
        // instrument 0 buzz 0 phase 1.179688 => -0.140625
        test_case(0, 0, 0, 0, 9895936, 0, -1179648);
        // instrument 0 buzz 0 phase 2.175781 => -0.148438
        test_case(0, 0, 0, 0, 18251776, 0, -1245184);
        // instrument 0 buzz 0 phase 1.324219 => 0.148438
        test_case(0, 0, 0, 0, 11108352, 0, 1245184);
        // instrument 0 buzz 0 phase 1.468750 => 0.437500
        test_case(0, 0, 0, 0, 12320768, 0, 3670016);
        // instrument 0 buzz 0 phase 0.769531 => -0.039062
        test_case(0, 0, 0, 0, 6455296, 0, -327680);
        // instrument 0 buzz 0 phase 3.199219 => -0.101562
        test_case(0, 0, 0, 0, 26836992, 0, -851968);
        // instrument 0 buzz 0 phase 0.230469 => -0.039062
        test_case(0, 0, 0, 0, 1933312, 0, -327680);
        // instrument 0 buzz 0 phase 1.460938 => 0.421875
        test_case(0, 0, 0, 0, 12255232, 0, 3538944);
        // instrument 0 buzz 0 phase 1.386719 => 0.273438
        test_case(0, 0, 0, 0, 11632640, 0, 2293760);
        // instrument 0 buzz 0 phase 2.832031 => -0.164062
        test_case(0, 0, 0, 0, 23756800, 0, -1376256);
        // instrument 0 buzz 0 phase 3.046875 => -0.406250
        test_case(0, 0, 0, 0, 25559040, 0, -3407872);
        // instrument 0 buzz 0 phase 3.980469 => -0.460938
        test_case(0, 0, 0, 0, 33390592, 0, -3866624);
        // instrument 0 buzz 0 phase 1.574219 => 0.351562
        test_case(0, 0, 0, 0, 13205504, 0, 2949120);
        // instrument 0 buzz 0 phase 3.273438 => 0.046875
        test_case(0, 0, 0, 0, 27459584, 0, 393216);
        // instrument 0 buzz 0 phase 0.457031 => 0.414062
        test_case(0, 0, 0, 0, 3833856, 0, 3473408);
        // instrument 0 buzz 0 phase 2.894531 => -0.289062
        test_case(0, 0, 0, 0, 24281088, 0, -2424832);
        // instrument 0 buzz 0 phase 3.523438 => 0.453125
        test_case(0, 0, 0, 0, 29556736, 0, 3801088);
        // instrument 0 buzz 0 phase 3.710938 => 0.078125
        test_case(0, 0, 0, 0, 31129600, 0, 655360);
        // instrument 0 buzz 0 phase 1.660156 => 0.179688
        test_case(0, 0, 0, 0, 13926400, 0, 1507328);
        // instrument 0 buzz 0 phase 1.964844 => -0.429688
        test_case(0, 0, 0, 1, 16482304, 0, -3604480);
        // instrument 0 buzz 1 phase 2.757812 => 0.079799
        test_case(0, 0, 1, 0, 23134208, 0, 669403);
        // instrument 0 buzz 1 phase 0.242188 => -0.067522
        test_case(0, 0, 1, 0, 2031616, 0, -566418);
        // instrument 0 buzz 1 phase 2.257812 => -0.039621
        test_case(0, 0, 1, 0, 18939904, 0, -332361);
        // instrument 0 buzz 1 phase 1.609375 => 0.260045
        test_case(0, 0, 1, 0, 13500416, 0, 2181412);
        // instrument 0 buzz 1 phase 3.023438 => -0.458147
        test_case(0, 0, 1, 0, 25362432, 0, -3843218);
        // instrument 0 buzz 1 phase 3.968750 => -0.390625
        test_case(0, 0, 1, 0, 33292288, 0, -3276800);
        // instrument 0 buzz 1 phase 1.097656 => -0.325614
        test_case(0, 0, 1, 0, 9207808, 0, -2731447);
        // instrument 0 buzz 1 phase 0.941406 => -0.294922
        test_case(0, 0, 1, 0, 7897088, 0, -2473984);
        // instrument 0 buzz 1 phase 1.046875 => -0.416295
        test_case(0, 0, 1, 0, 8781824, 0, -3492132);
        // instrument 0 buzz 1 phase 1.160156 => -0.214007
        test_case(0, 0, 1, 0, 9732096, 0, -1795218);
        // instrument 0 buzz 1 phase 2.871094 => -0.057757
        test_case(0, 0, 1, 0, 24084480, 0, -484498);
        // instrument 0 buzz 1 phase 3.136719 => -0.255859
        test_case(0, 0, 1, 0, 26312704, 0, -2146304);
        // instrument 0 buzz 1 phase 1.121094 => -0.283761
        test_case(0, 0, 1, 0, 9404416, 0, -2380361);
        // instrument 0 buzz 1 phase 3.246094 => -0.060547
        test_case(0, 0, 1, 0, 27230208, 0, -507904);
        // instrument 0 buzz 1 phase 0.027344 => -0.451172
        test_case(0, 0, 1, 0, 229376, 0, -3784704);
        // instrument 0 buzz 1 phase 1.218750 => -0.109375
        test_case(0, 0, 1, 0, 10223616, 0, -917504);
        // instrument 0 buzz 1 phase 2.375000 => 0.169643
        test_case(0, 0, 1, 0, 19922944, 0, 1423067);
        // instrument 0 buzz 1 phase 1.769531 => 0.065569
        test_case(0, 0, 1, 0, 14843904, 0, 550034);
        // instrument 0 buzz 1 phase 3.148438 => -0.234933
        test_case(0, 0, 1, 0, 26411008, 0, -1970761);
        // instrument 0 buzz 1 phase 0.281250 => 0.002232
        test_case(0, 0, 1, 0, 2359296, 0, 18724);
        // instrument 0 buzz 1 phase 3.816406 => 0.008650
        test_case(0, 0, 1, 0, 32014336, 0, 72557);
        // instrument 0 buzz 1 phase 0.250000 => -0.053571
        test_case(0, 0, 1, 0, 2097152, 0, -449389);
        // instrument 0 buzz 1 phase 0.191406 => -0.158203
        test_case(0, 0, 1, 0, 1605632, 0, -1327104);
        // instrument 0 buzz 1 phase 3.585938 => 0.288504
        test_case(0, 0, 1, 0, 30081024, 0, 2420151);
        // instrument 0 buzz 1 phase 1.406250 => 0.225446
        test_case(0, 0, 1, 0, 11796480, 0, 1891181);
        // instrument 0 buzz 1 phase 2.738281 => 0.103516
        test_case(0, 0, 1, 1, 22970368, 0, 868352);
        // instrument 1 buzz 0 phase 0.792969 => 0.406250
        test_case(1, 0, 0, 0, 6651904, 0, 3407872);
        // instrument 1 buzz 0 phase 2.679688 => 0.276786
        test_case(1, 0, 0, 0, 22478848, 0, 2321847);
        // instrument 1 buzz 0 phase 0.714844 => 0.316964
        test_case(1, 0, 0, 0, 5996544, 0, 2658889);
        // instrument 1 buzz 0 phase 0.707031 => 0.308036
        test_case(1, 0, 0, 0, 5931008, 0, 2583991);
        // instrument 1 buzz 0 phase 3.132812 => -0.348214
        test_case(1, 0, 0, 0, 26279936, 0, -2921033);
        // instrument 1 buzz 0 phase 3.511719 => 0.084821
        test_case(1, 0, 0, 0, 29458432, 0, 711533);
        // instrument 1 buzz 0 phase 3.375000 => -0.071429
        test_case(1, 0, 0, 0, 28311552, 0, -599186);
        // instrument 1 buzz 0 phase 2.136719 => -0.343750
        test_case(1, 0, 0, 0, 17924096, 0, -2883584);
        // instrument 1 buzz 0 phase 0.660156 => 0.254464
        test_case(1, 0, 0, 0, 5537792, 0, 2134601);
        // instrument 1 buzz 0 phase 0.703125 => 0.303571
        test_case(1, 0, 0, 0, 5898240, 0, 2546541);
        // instrument 1 buzz 0 phase 2.660156 => 0.254464
        test_case(1, 0, 0, 0, 22315008, 0, 2134601);
        // instrument 1 buzz 0 phase 1.394531 => -0.049107
        test_case(1, 0, 0, 0, 11698176, 0, -411940);
        // instrument 1 buzz 0 phase 2.144531 => -0.334821
        test_case(1, 0, 0, 0, 17989632, 0, -2808685);
        // instrument 1 buzz 0 phase 0.082031 => -0.406250
        test_case(1, 0, 0, 0, 688128, 0, -3407872);
        // instrument 1 buzz 0 phase 1.718750 => 0.321429
        test_case(1, 0, 0, 0, 14417920, 0, 2696338);
        // instrument 1 buzz 0 phase 3.820312 => 0.437500
        test_case(1, 0, 0, 0, 32047104, 0, 3670016);
        // instrument 1 buzz 0 phase 0.683594 => 0.281250
        test_case(1, 0, 0, 0, 5734400, 0, 2359296);
        // instrument 1 buzz 0 phase 0.429688 => -0.008929
        test_case(1, 0, 0, 0, 3604480, 0, -74898);
        // instrument 1 buzz 0 phase 0.425781 => -0.013393
        test_case(1, 0, 0, 0, 3571712, 0, -112347);
        // instrument 1 buzz 0 phase 2.128906 => -0.352679
        test_case(1, 0, 0, 0, 17858560, 0, -2958482);
        // instrument 1 buzz 0 phase 3.046875 => -0.446429
        test_case(1, 0, 0, 0, 25559040, 0, -3744914);
        // instrument 1 buzz 0 phase 1.066406 => -0.424107
        test_case(1, 0, 0, 0, 8945664, 0, -3557668);
        // instrument 1 buzz 0 phase 2.933594 => 0.031250
        test_case(1, 0, 0, 0, 24608768, 0, 262144);
        // instrument 1 buzz 0 phase 0.953125 => -0.125000
        test_case(1, 0, 0, 0, 7995392, 0, -1048576);
        // instrument 1 buzz 0 phase 1.617188 => 0.205357
        test_case(1, 0, 0, 0, 13565952, 0, 1722660);
        // instrument 1 buzz 0 phase 0.078125 => -0.410714
        test_case(1, 0, 0, 1, 655360, 0, -3445321);
        // instrument 1 buzz 1 phase 2.597656 => 0.112981
        test_case(1, 0, 1, 0, 21790720, 0, 947751);
        // instrument 1 buzz 1 phase 3.121094 => -0.375801
        test_case(1, 0, 1, 0, 26181632, 0, -3152449);
        // instrument 1 buzz 1 phase 2.445312 => -0.043269
        test_case(1, 0, 1, 0, 20512768, 0, -362968);
        // instrument 1 buzz 1 phase 0.289062 => -0.203526
        test_case(1, 0, 1, 0, 2424832, 0, -1707297);
        // instrument 1 buzz 1 phase 2.019531 => -0.479968
        test_case(1, 0, 1, 0, 16941056, 0, -4026263);
        // instrument 1 buzz 1 phase 2.675781 => 0.193109
        test_case(1, 0, 1, 0, 22446080, 0, 1619915);
        // instrument 1 buzz 1 phase 2.621094 => 0.137019
        test_case(1, 0, 1, 0, 21987328, 0, 1149400);
        // instrument 1 buzz 1 phase 0.105469 => -0.391827
        test_case(1, 0, 1, 0, 884736, 0, -3286882);
        // instrument 1 buzz 1 phase 0.230469 => -0.263622
        test_case(1, 0, 1, 0, 1933312, 0, -2211420);
        // instrument 1 buzz 1 phase 2.601562 => 0.116987
        test_case(1, 0, 1, 0, 21823488, 0, 981359);
        // instrument 1 buzz 1 phase 3.875000 => 0.397436
        test_case(1, 0, 1, 0, 32505856, 0, 3333934);
        // instrument 1 buzz 1 phase 1.710938 => 0.229167
        test_case(1, 0, 1, 0, 14352384, 0, 1922389);
        // instrument 1 buzz 1 phase 2.863281 => 0.385417
        test_case(1, 0, 1, 0, 24018944, 0, 3233109);
        // instrument 1 buzz 1 phase 2.410156 => -0.079327
        test_case(1, 0, 1, 0, 20217856, 0, -665442);
        // instrument 1 buzz 1 phase 0.312500 => -0.179487
        test_case(1, 0, 1, 0, 2621440, 0, -1505647);
        // instrument 1 buzz 1 phase 0.761719 => 0.281250
        test_case(1, 0, 1, 0, 6389760, 0, 2359296);
        // instrument 1 buzz 1 phase 3.945312 => 0.469551
        test_case(1, 0, 1, 0, 33095680, 0, 3938881);
        // instrument 1 buzz 1 phase 3.652344 => 0.169070
        test_case(1, 0, 1, 0, 30638080, 0, 1418266);
        // instrument 1 buzz 1 phase 3.082031 => -0.415865
        test_case(1, 0, 1, 0, 25853952, 0, -3488531);
        // instrument 1 buzz 1 phase 2.550781 => 0.064904
        test_case(1, 0, 1, 0, 21397504, 0, 544453);
        // instrument 1 buzz 1 phase 0.058594 => -0.439904
        test_case(1, 0, 1, 0, 491520, 0, -3690181);
        // instrument 1 buzz 1 phase 3.796875 => 0.317308
        test_case(1, 0, 1, 0, 31850496, 0, 2661769);
        // instrument 1 buzz 1 phase 0.335938 => -0.155449
        test_case(1, 0, 1, 0, 2818048, 0, -1303998);
        // instrument 1 buzz 1 phase 1.714844 => 0.233173
        test_case(1, 0, 1, 0, 14385152, 0, 1955997);
        // instrument 1 buzz 1 phase 2.128906 => -0.367788
        test_case(1, 0, 1, 0, 17858560, 0, -3085233);
        // instrument 1 buzz 1 phase 3.839844 => 0.361378
        test_case(1, 0, 1, 1, 32210944, 0, 3031460);
        // instrument 2 buzz 0 phase 3.976562 => -0.015305
        test_case(2, 0, 0, 0, 33357824, 0, -128385);
        // instrument 2 buzz 0 phase 0.820312 => -0.117336
        test_case(2, 0, 0, 0, 6881280, 0, -984285);
        // instrument 2 buzz 0 phase 0.210938 => 0.137742
        test_case(2, 0, 0, 0, 1769472, 0, 1155465);
        // instrument 2 buzz 0 phase 3.324219 => 0.211715
        test_case(2, 0, 0, 0, 27885568, 0, 1775992);
        // instrument 2 buzz 0 phase 1.707031 => -0.191309
        test_case(2, 0, 0, 0, 14319616, 0, -1604812);
        // instrument 2 buzz 0 phase 3.421875 => 0.275484
        test_case(2, 0, 0, 0, 28704768, 0, 2310930);
        // instrument 2 buzz 0 phase 3.957031 => -0.028059
        test_case(2, 0, 0, 0, 33193984, 0, -235372);
        // instrument 2 buzz 0 phase 0.050781 => 0.033160
        test_case(2, 0, 0, 0, 425984, 0, 278167);
        // instrument 2 buzz 0 phase 3.015625 => 0.010203
        test_case(2, 0, 0, 0, 25296896, 0, 85590);
        // instrument 2 buzz 0 phase 0.136719 => 0.089277
        test_case(2, 0, 0, 0, 1146880, 0, 748912);
        // instrument 2 buzz 0 phase 3.828125 => -0.112234
        test_case(2, 0, 0, 0, 32112640, 0, -941490);
        // instrument 2 buzz 0 phase 1.746094 => -0.165801
        test_case(2, 0, 0, 0, 14647296, 0, -1390837);
        // instrument 2 buzz 0 phase 3.820312 => -0.117336
        test_case(2, 0, 0, 0, 32047104, 0, -984285);
        // instrument 2 buzz 0 phase 0.718750 => -0.183656
        test_case(2, 0, 0, 0, 6029312, 0, -1540620);
        // instrument 2 buzz 0 phase 3.761719 => -0.155598
        test_case(2, 0, 0, 0, 31555584, 0, -1305247);
        // instrument 2 buzz 0 phase 3.957031 => -0.028059
        test_case(2, 0, 0, 0, 33193984, 0, -235372);
        // instrument 2 buzz 0 phase 2.117188 => 0.076523
        test_case(2, 0, 0, 0, 17760256, 0, 641925);
        // instrument 2 buzz 0 phase 2.574219 => -0.278035
        test_case(2, 0, 0, 0, 21594112, 0, -2332328);
        // instrument 2 buzz 0 phase 0.003906 => 0.002551
        test_case(2, 0, 0, 0, 32768, 0, 21397);
        // instrument 2 buzz 0 phase 2.839844 => -0.104582
        test_case(2, 0, 0, 0, 23822336, 0, -877297);
        // instrument 2 buzz 0 phase 1.976562 => -0.015305
        test_case(2, 0, 0, 0, 16580608, 0, -128385);
        // instrument 2 buzz 0 phase 3.363281 => 0.237223
        test_case(2, 0, 0, 0, 28213248, 0, 1989967);
        // instrument 2 buzz 0 phase 1.339844 => 0.221918
        test_case(2, 0, 0, 0, 11239424, 0, 1861582);
        // instrument 2 buzz 0 phase 0.976562 => -0.015305
        test_case(2, 0, 0, 0, 8192000, 0, -128385);
        // instrument 2 buzz 0 phase 2.015625 => 0.010203
        test_case(2, 0, 0, 0, 16908288, 0, 85590);
        // instrument 2 buzz 0 phase 3.425781 => 0.278035
        test_case(2, 0, 0, 1, 28737536, 0, 2332328);
        // instrument 2 buzz 1 phase 1.042969 => -0.032216
        test_case(2, 0, 1, 0, 8749056, 0, -270250);
        // instrument 2 buzz 1 phase 2.000000 => 0.000000
        test_case(2, 0, 1, 0, 16777216, 0, 0);
        // instrument 2 buzz 1 phase 0.621094 => -0.260868
        test_case(2, 0, 1, 0, 5210112, 0, -2188322);
        // instrument 2 buzz 1 phase 2.808594 => -0.159245
        test_case(2, 0, 1, 0, 23560192, 0, -1335846);
        // instrument 2 buzz 1 phase 3.281250 => 0.096930
        test_case(2, 0, 1, 0, 27525120, 0, 813105);
        // instrument 2 buzz 1 phase 0.117188 => 0.063514
        test_case(2, 0, 1, 0, 983040, 0, 532797);
        // instrument 2 buzz 1 phase 3.535156 => -0.251941
        test_case(2, 0, 1, 0, 29655040, 0, -2113431);
        // instrument 2 buzz 1 phase 3.714844 => -0.154552
        test_case(2, 0, 1, 0, 31162368, 0, -1296474);
        // instrument 2 buzz 1 phase 0.593750 => -0.275688
        test_case(2, 0, 1, 0, 4980736, 0, -2312642);
        // instrument 2 buzz 1 phase 1.242188 => 0.075758
        test_case(2, 0, 1, 0, 10420224, 0, 635505);
        // instrument 2 buzz 1 phase 0.820312 => -0.152894
        test_case(2, 0, 1, 0, 6881280, 0, -1282566);
        // instrument 2 buzz 1 phase 0.507812 => -0.322266
        test_case(2, 0, 1, 0, 4259840, 0, -2703360);
        // instrument 2 buzz 1 phase 0.015625 => 0.008469
        test_case(2, 0, 1, 0, 131072, 0, 71039);
        // instrument 2 buzz 1 phase 2.511719 => -0.320149
        test_case(2, 0, 1, 0, 21069824, 0, -2685600);
        // instrument 2 buzz 1 phase 2.585938 => -0.279923
        test_case(2, 0, 1, 0, 21692416, 0, -2348162);
        // instrument 2 buzz 1 phase 3.867188 => -0.071983
        test_case(2, 0, 1, 0, 32440320, 0, -603837);
        // instrument 2 buzz 1 phase 3.097656 => -0.002576
        test_case(2, 0, 1, 0, 25985024, 0, -21611);
        // instrument 2 buzz 1 phase 0.488281 => 0.264644
        test_case(2, 0, 1, 0, 4096000, 0, 2219991);
        // instrument 2 buzz 1 phase 0.593750 => -0.275688
        test_case(2, 0, 1, 0, 4980736, 0, -2312642);
        // instrument 2 buzz 1 phase 0.101562 => 0.055046
        test_case(2, 0, 1, 0, 851968, 0, 461758);
        // instrument 2 buzz 1 phase 2.054688 => 0.029640
        test_case(2, 0, 1, 0, 17235968, 0, 248639);
        // instrument 2 buzz 1 phase 1.265625 => 0.088461
        test_case(2, 0, 1, 0, 10616832, 0, 742065);
        // instrument 2 buzz 1 phase 2.906250 => -0.106317
        test_case(2, 0, 1, 0, 24379392, 0, -891848);
        // instrument 2 buzz 1 phase 1.125000 => 0.012244
        test_case(2, 0, 1, 0, 9437184, 0, 102708);
        // instrument 2 buzz 1 phase 3.531250 => -0.254058
        test_case(2, 0, 1, 0, 29622272, 0, -2131191);
        // instrument 2 buzz 1 phase 2.058594 => 0.031757
        test_case(2, 0, 1, 1, 17268736, 0, 266398);
        // instrument 3 buzz 0 phase 2.968750 => -0.250000
        test_case(3, 0, 0, 0, 24903680, 0, -2097152);
        // instrument 3 buzz 0 phase 2.496094 => 0.250000
        test_case(3, 0, 0, 0, 20938752, 0, 2097152);
        // instrument 3 buzz 0 phase 0.042969 => 0.250000
        test_case(3, 0, 0, 0, 360448, 0, 2097152);
        // instrument 3 buzz 0 phase 1.019531 => 0.250000
        test_case(3, 0, 0, 0, 8552448, 0, 2097152);
        // instrument 3 buzz 0 phase 2.941406 => -0.250000
        test_case(3, 0, 0, 0, 24674304, 0, -2097152);
        // instrument 3 buzz 0 phase 2.242188 => 0.250000
        test_case(3, 0, 0, 0, 18808832, 0, 2097152);
        // instrument 3 buzz 0 phase 2.757812 => -0.250000
        test_case(3, 0, 0, 0, 23134208, 0, -2097152);
        // instrument 3 buzz 0 phase 1.753906 => -0.250000
        test_case(3, 0, 0, 0, 14712832, 0, -2097152);
        // instrument 3 buzz 0 phase 2.015625 => 0.250000
        test_case(3, 0, 0, 0, 16908288, 0, 2097152);
        // instrument 3 buzz 0 phase 3.214844 => 0.250000
        test_case(3, 0, 0, 0, 26968064, 0, 2097152);
        // instrument 3 buzz 0 phase 2.070312 => 0.250000
        test_case(3, 0, 0, 0, 17367040, 0, 2097152);
        // instrument 3 buzz 0 phase 1.660156 => -0.250000
        test_case(3, 0, 0, 0, 13926400, 0, -2097152);
        // instrument 3 buzz 0 phase 1.449219 => 0.250000
        test_case(3, 0, 0, 0, 12156928, 0, 2097152);
        // instrument 3 buzz 0 phase 0.468750 => 0.250000
        test_case(3, 0, 0, 0, 3932160, 0, 2097152);
        // instrument 3 buzz 0 phase 1.148438 => 0.250000
        test_case(3, 0, 0, 0, 9633792, 0, 2097152);
        // instrument 3 buzz 0 phase 1.316406 => 0.250000
        test_case(3, 0, 0, 0, 11042816, 0, 2097152);
        // instrument 3 buzz 0 phase 1.085938 => 0.250000
        test_case(3, 0, 0, 0, 9109504, 0, 2097152);
        // instrument 3 buzz 0 phase 3.105469 => 0.250000
        test_case(3, 0, 0, 0, 26050560, 0, 2097152);
        // instrument 3 buzz 0 phase 0.824219 => -0.250000
        test_case(3, 0, 0, 0, 6914048, 0, -2097152);
        // instrument 3 buzz 0 phase 3.746094 => -0.250000
        test_case(3, 0, 0, 0, 31424512, 0, -2097152);
        // instrument 3 buzz 0 phase 1.011719 => 0.250000
        test_case(3, 0, 0, 0, 8486912, 0, 2097152);
        // instrument 3 buzz 0 phase 1.800781 => -0.250000
        test_case(3, 0, 0, 0, 15106048, 0, -2097152);
        // instrument 3 buzz 0 phase 0.718750 => -0.250000
        test_case(3, 0, 0, 0, 6029312, 0, -2097152);
        // instrument 3 buzz 0 phase 3.113281 => 0.250000
        test_case(3, 0, 0, 0, 26116096, 0, 2097152);
        // instrument 3 buzz 0 phase 1.414062 => 0.250000
        test_case(3, 0, 0, 0, 11862016, 0, 2097152);
        // instrument 3 buzz 0 phase 2.800781 => -0.250000
        test_case(3, 0, 0, 1, 23494656, 0, -2097152);
        // instrument 3 buzz 1 phase 2.796875 => -0.250000
        test_case(3, 0, 1, 0, 23461888, 0, -2097152);
        // instrument 3 buzz 1 phase 0.457031 => -0.250000
        test_case(3, 0, 1, 0, 3833856, 0, -2097152);
        // instrument 3 buzz 1 phase 3.246094 => 0.250000
        test_case(3, 0, 1, 0, 27230208, 0, 2097152);
        // instrument 3 buzz 1 phase 1.226562 => 0.250000
        test_case(3, 0, 1, 0, 10289152, 0, 2097152);
        // instrument 3 buzz 1 phase 3.441406 => -0.250000
        test_case(3, 0, 1, 0, 28868608, 0, -2097152);
        // instrument 3 buzz 1 phase 0.515625 => -0.250000
        test_case(3, 0, 1, 0, 4325376, 0, -2097152);
        // instrument 3 buzz 1 phase 2.355469 => 0.250000
        test_case(3, 0, 1, 0, 19759104, 0, 2097152);
        // instrument 3 buzz 1 phase 1.656250 => -0.250000
        test_case(3, 0, 1, 0, 13893632, 0, -2097152);
        // instrument 3 buzz 1 phase 3.734375 => -0.250000
        test_case(3, 0, 1, 0, 31326208, 0, -2097152);
        // instrument 3 buzz 1 phase 2.945312 => -0.250000
        test_case(3, 0, 1, 0, 24707072, 0, -2097152);
        // instrument 3 buzz 1 phase 3.382812 => 0.250000
        test_case(3, 0, 1, 0, 28377088, 0, 2097152);
        // instrument 3 buzz 1 phase 0.523438 => -0.250000
        test_case(3, 0, 1, 0, 4390912, 0, -2097152);
        // instrument 3 buzz 1 phase 0.296875 => 0.250000
        test_case(3, 0, 1, 0, 2490368, 0, 2097152);
        // instrument 3 buzz 1 phase 2.824219 => -0.250000
        test_case(3, 0, 1, 0, 23691264, 0, -2097152);
        // instrument 3 buzz 1 phase 1.960938 => -0.250000
        test_case(3, 0, 1, 0, 16449536, 0, -2097152);
        // instrument 3 buzz 1 phase 1.187500 => 0.250000
        test_case(3, 0, 1, 0, 9961472, 0, 2097152);
        // instrument 3 buzz 1 phase 2.082031 => 0.250000
        test_case(3, 0, 1, 0, 17465344, 0, 2097152);
        // instrument 3 buzz 1 phase 1.007812 => 0.250000
        test_case(3, 0, 1, 0, 8454144, 0, 2097152);
        // instrument 3 buzz 1 phase 2.554688 => -0.250000
        test_case(3, 0, 1, 0, 21430272, 0, -2097152);
        // instrument 3 buzz 1 phase 1.714844 => -0.250000
        test_case(3, 0, 1, 0, 14385152, 0, -2097152);
        // instrument 3 buzz 1 phase 0.773438 => -0.250000
        test_case(3, 0, 1, 0, 6488064, 0, -2097152);
        // instrument 3 buzz 1 phase 2.531250 => -0.250000
        test_case(3, 0, 1, 0, 21233664, 0, -2097152);
        // instrument 3 buzz 1 phase 1.843750 => -0.250000
        test_case(3, 0, 1, 0, 15466496, 0, -2097152);
        // instrument 3 buzz 1 phase 2.308594 => 0.250000
        test_case(3, 0, 1, 0, 19365888, 0, 2097152);
        // instrument 3 buzz 1 phase 1.585938 => -0.250000
        test_case(3, 0, 1, 0, 13303808, 0, -2097152);
        // instrument 3 buzz 1 phase 2.332031 => 0.250000
        test_case(3, 0, 1, 1, 19562496, 0, 2097152);
        // instrument 4 buzz 0 phase 1.984375 => -0.250000
        test_case(4, 0, 0, 0, 16646144, 0, -2097152);
        // instrument 4 buzz 0 phase 1.074219 => 0.250000
        test_case(4, 0, 0, 0, 9011200, 0, 2097152);
        // instrument 4 buzz 0 phase 2.480469 => -0.250000
        test_case(4, 0, 0, 0, 20807680, 0, -2097152);
        // instrument 4 buzz 0 phase 0.000000 => 0.250000
        test_case(4, 0, 0, 0, 0, 0, 2097152);
        // instrument 4 buzz 0 phase 1.519531 => -0.250000
        test_case(4, 0, 0, 0, 12746752, 0, -2097152);
        // instrument 4 buzz 0 phase 1.199219 => 0.250000
        test_case(4, 0, 0, 0, 10059776, 0, 2097152);
        // instrument 4 buzz 0 phase 2.824219 => -0.250000
        test_case(4, 0, 0, 0, 23691264, 0, -2097152);
        // instrument 4 buzz 0 phase 0.921875 => -0.250000
        test_case(4, 0, 0, 0, 7733248, 0, -2097152);
        // instrument 4 buzz 0 phase 0.433594 => -0.250000
        test_case(4, 0, 0, 0, 3637248, 0, -2097152);
        // instrument 4 buzz 0 phase 3.382812 => -0.250000
        test_case(4, 0, 0, 0, 28377088, 0, -2097152);
        // instrument 4 buzz 0 phase 0.859375 => -0.250000
        test_case(4, 0, 0, 0, 7208960, 0, -2097152);
        // instrument 4 buzz 0 phase 0.328125 => -0.250000
        test_case(4, 0, 0, 0, 2752512, 0, -2097152);
        // instrument 4 buzz 0 phase 2.101562 => 0.250000
        test_case(4, 0, 0, 0, 17629184, 0, 2097152);
        // instrument 4 buzz 0 phase 0.289062 => 0.250000
        test_case(4, 0, 0, 0, 2424832, 0, 2097152);
        // instrument 4 buzz 0 phase 3.878906 => -0.250000
        test_case(4, 0, 0, 0, 32538624, 0, -2097152);
        // instrument 4 buzz 0 phase 0.652344 => -0.250000
        test_case(4, 0, 0, 0, 5472256, 0, -2097152);
        // instrument 4 buzz 0 phase 1.472656 => -0.250000
        test_case(4, 0, 0, 0, 12353536, 0, -2097152);
        // instrument 4 buzz 0 phase 0.156250 => 0.250000
        test_case(4, 0, 0, 0, 1310720, 0, 2097152);
        // instrument 4 buzz 0 phase 1.613281 => -0.250000
        test_case(4, 0, 0, 0, 13533184, 0, -2097152);
        // instrument 4 buzz 0 phase 0.390625 => -0.250000
        test_case(4, 0, 0, 0, 3276800, 0, -2097152);
        // instrument 4 buzz 0 phase 1.332031 => -0.250000
        test_case(4, 0, 0, 0, 11173888, 0, -2097152);
        // instrument 4 buzz 0 phase 2.730469 => -0.250000
        test_case(4, 0, 0, 0, 22904832, 0, -2097152);
        // instrument 4 buzz 0 phase 3.792969 => -0.250000
        test_case(4, 0, 0, 0, 31817728, 0, -2097152);
        // instrument 4 buzz 0 phase 1.542969 => -0.250000
        test_case(4, 0, 0, 0, 12943360, 0, -2097152);
        // instrument 4 buzz 0 phase 2.289062 => 0.250000
        test_case(4, 0, 0, 0, 19202048, 0, 2097152);
        // instrument 4 buzz 0 phase 1.425781 => -0.250000
        test_case(4, 0, 0, 1, 11960320, 0, -2097152);
        // instrument 4 buzz 1 phase 2.839844 => -0.250000
        test_case(4, 0, 1, 0, 23822336, 0, -2097152);
        // instrument 4 buzz 1 phase 1.851562 => -0.250000
        test_case(4, 0, 1, 0, 15532032, 0, -2097152);
        // instrument 4 buzz 1 phase 0.386719 => -0.250000
        test_case(4, 0, 1, 0, 3244032, 0, -2097152);
        // instrument 4 buzz 1 phase 0.625000 => -0.250000
        test_case(4, 0, 1, 0, 5242880, 0, -2097152);
        // instrument 4 buzz 1 phase 0.757812 => -0.250000
        test_case(4, 0, 1, 0, 6356992, 0, -2097152);
        // instrument 4 buzz 1 phase 2.128906 => 0.250000
        test_case(4, 0, 1, 0, 17858560, 0, 2097152);
        // instrument 4 buzz 1 phase 2.988281 => -0.250000
        test_case(4, 0, 1, 0, 25067520, 0, -2097152);
        // instrument 4 buzz 1 phase 2.183594 => 0.250000
        test_case(4, 0, 1, 0, 18317312, 0, 2097152);
        // instrument 4 buzz 1 phase 2.433594 => -0.250000
        test_case(4, 0, 1, 0, 20414464, 0, -2097152);
        // instrument 4 buzz 1 phase 3.734375 => -0.250000
        test_case(4, 0, 1, 0, 31326208, 0, -2097152);
        // instrument 4 buzz 1 phase 0.164062 => 0.250000
        test_case(4, 0, 1, 0, 1376256, 0, 2097152);
        // instrument 4 buzz 1 phase 3.921875 => -0.250000
        test_case(4, 0, 1, 0, 32899072, 0, -2097152);
        // instrument 4 buzz 1 phase 2.121094 => 0.250000
        test_case(4, 0, 1, 0, 17793024, 0, 2097152);
        // instrument 4 buzz 1 phase 0.175781 => 0.250000
        test_case(4, 0, 1, 0, 1474560, 0, 2097152);
        // instrument 4 buzz 1 phase 2.390625 => -0.250000
        test_case(4, 0, 1, 0, 20054016, 0, -2097152);
        // instrument 4 buzz 1 phase 3.546875 => -0.250000
        test_case(4, 0, 1, 0, 29753344, 0, -2097152);
        // instrument 4 buzz 1 phase 3.347656 => -0.250000
        test_case(4, 0, 1, 0, 28082176, 0, -2097152);
        // instrument 4 buzz 1 phase 2.167969 => 0.250000
        test_case(4, 0, 1, 0, 18186240, 0, 2097152);
        // instrument 4 buzz 1 phase 3.539062 => -0.250000
        test_case(4, 0, 1, 0, 29687808, 0, -2097152);
        // instrument 4 buzz 1 phase 0.000000 => 0.250000
        test_case(4, 0, 1, 0, 0, 0, 2097152);
        // instrument 4 buzz 1 phase 0.058594 => 0.250000
        test_case(4, 0, 1, 0, 491520, 0, 2097152);
        // instrument 4 buzz 1 phase 2.527344 => -0.250000
        test_case(4, 0, 1, 0, 21200896, 0, -2097152);
        // instrument 4 buzz 1 phase 0.417969 => -0.250000
        test_case(4, 0, 1, 0, 3506176, 0, -2097152);
        // instrument 4 buzz 1 phase 3.644531 => -0.250000
        test_case(4, 0, 1, 0, 30572544, 0, -2097152);
        // instrument 4 buzz 1 phase 3.285156 => -0.250000
        test_case(4, 0, 1, 0, 27557888, 0, -2097152);
        // instrument 4 buzz 1 phase 2.621094 => -0.250000
        test_case(4, 0, 1, 1, 21987328, 0, -2097152);
        // instrument 5 buzz 0 phase 1.851562 => -0.069444
        test_case(5, 0, 0, 0, 15532032, 0, -582542);
        // instrument 5 buzz 0 phase 3.394531 => -0.052083
        test_case(5, 0, 0, 0, 28475392, 0, -436906);
        // instrument 5 buzz 0 phase 0.015625 => -0.291667
        test_case(5, 0, 0, 0, 131072, 0, -2446677);
        // instrument 5 buzz 0 phase 0.375000 => 0.000000
        test_case(5, 0, 0, 0, 3145728, 0, 0);
        // instrument 5 buzz 0 phase 1.164062 => 0.104167
        test_case(5, 0, 0, 0, 9764864, 0, 873813);
        // instrument 5 buzz 0 phase 3.621094 => -0.118056
        test_case(5, 0, 0, 0, 30375936, 0, -990321);
        // instrument 5 buzz 0 phase 1.324219 => 0.135417
        test_case(5, 0, 0, 0, 11108352, 0, 1135957);
        // instrument 5 buzz 0 phase 0.242188 => 0.312500
        test_case(5, 0, 0, 0, 2031616, 0, 2621440);
        // instrument 5 buzz 0 phase 0.574219 => -0.201389
        test_case(5, 0, 0, 0, 4816896, 0, -1689372);
        // instrument 5 buzz 0 phase 1.167969 => 0.114583
        test_case(5, 0, 0, 0, 9797632, 0, 961194);
        // instrument 5 buzz 0 phase 2.359375 => 0.041667
        test_case(5, 0, 0, 0, 19791872, 0, 349525);
        // instrument 5 buzz 0 phase 3.664062 => -0.041667
        test_case(5, 0, 0, 0, 30736384, 0, -349525);
        // instrument 5 buzz 0 phase 0.410156 => -0.093750
        test_case(5, 0, 0, 0, 3440640, 0, -786432);
        // instrument 5 buzz 0 phase 1.625000 => -0.111111
        test_case(5, 0, 0, 0, 13631488, 0, -932067);
        // instrument 5 buzz 0 phase 2.695312 => 0.013889
        test_case(5, 0, 0, 0, 22609920, 0, 116508);
        // instrument 5 buzz 0 phase 3.125000 => 0.000000
        test_case(5, 0, 0, 0, 26214400, 0, 0);
        // instrument 5 buzz 0 phase 2.789062 => 0.041667
        test_case(5, 0, 0, 0, 23396352, 0, 349525);
        // instrument 5 buzz 0 phase 0.511719 => -0.312500
        test_case(5, 0, 0, 0, 4292608, 0, -2621440);
        // instrument 5 buzz 0 phase 2.082031 => -0.114583
        test_case(5, 0, 0, 0, 17465344, 0, -961194);
        // instrument 5 buzz 0 phase 1.195312 => 0.187500
        test_case(5, 0, 0, 0, 10027008, 0, 1572864);
        // instrument 5 buzz 0 phase 0.800781 => 0.020833
        test_case(5, 0, 0, 0, 6717440, 0, 174762);
        // instrument 5 buzz 0 phase 3.742188 => 0.097222
        test_case(5, 0, 0, 0, 31391744, 0, 815559);
        // instrument 5 buzz 0 phase 2.609375 => -0.138889
        test_case(5, 0, 0, 0, 21889024, 0, -1165084);
        // instrument 5 buzz 0 phase 2.988281 => -0.312500
        test_case(5, 0, 0, 0, 25067520, 0, -2621440);
        // instrument 5 buzz 0 phase 0.214844 => 0.239583
        test_case(5, 0, 0, 0, 1802240, 0, 2009770);
        // instrument 5 buzz 0 phase 3.796875 => 0.027778
        test_case(5, 0, 0, 1, 31850496, 0, 233016);
        // instrument 5 buzz 1 phase 3.851562 => -0.013889
        test_case(5, 0, 1, 0, 32309248, 0, -116508);
        // instrument 5 buzz 1 phase 1.343750 => -0.011111
        test_case(5, 0, 1, 0, 11272192, 0, -93206);
        // instrument 5 buzz 1 phase 2.781250 => 0.111111
        test_case(5, 0, 1, 0, 23330816, 0, 932067);
        // instrument 5 buzz 1 phase 3.945312 => -0.180556
        test_case(5, 0, 1, 0, 33095680, 0, -1514609);
        // instrument 5 buzz 1 phase 3.210938 => 0.047222
        test_case(5, 0, 1, 0, 26935296, 0, 396128);
        // instrument 5 buzz 1 phase 2.019531 => -0.173611
        test_case(5, 0, 1, 0, 16941056, 0, -1456355);
        // instrument 5 buzz 1 phase 1.593750 => -0.111111
        test_case(5, 0, 1, 0, 13369344, 0, -932067);
        // instrument 5 buzz 1 phase 0.796875 => 0.083333
        test_case(5, 0, 1, 0, 6684672, 0, 699050);
        // instrument 5 buzz 1 phase 3.398438 => -0.069444
        test_case(5, 0, 1, 0, 28508160, 0, -582542);
        // instrument 5 buzz 1 phase 2.914062 => -0.125000
        test_case(5, 0, 1, 0, 24444928, 0, -1048576);
        // instrument 5 buzz 1 phase 2.820312 => 0.041667
        test_case(5, 0, 1, 0, 23658496, 0, 349525);
        // instrument 5 buzz 1 phase 2.320312 => 0.013889
        test_case(5, 0, 1, 0, 19464192, 0, 116508);
        // instrument 5 buzz 1 phase 2.640625 => -0.027778
        test_case(5, 0, 1, 0, 22151168, 0, -233016);
        // instrument 5 buzz 1 phase 0.609375 => -0.083333
        test_case(5, 0, 1, 0, 5111808, 0, -699050);
        // instrument 5 buzz 1 phase 1.468750 => -0.144444
        test_case(5, 0, 1, 0, 12320768, 0, -1211687);
        // instrument 5 buzz 1 phase 1.421875 => -0.094444
        test_case(5, 0, 1, 0, 11927552, 0, -792257);
        // instrument 5 buzz 1 phase 3.875000 => -0.055556
        test_case(5, 0, 1, 0, 32505856, 0, -466033);
        // instrument 5 buzz 1 phase 1.574219 => -0.145833
        test_case(5, 0, 1, 0, 13205504, 0, -1223338);
        // instrument 5 buzz 1 phase 1.738281 => 0.145833
        test_case(5, 0, 1, 0, 14581760, 0, 1223338);
        // instrument 5 buzz 1 phase 0.128906 => -0.040278
        test_case(5, 0, 1, 0, 1081344, 0, -337874);
        // instrument 5 buzz 1 phase 0.585938 => -0.125000
        test_case(5, 0, 1, 0, 4915200, 0, -1048576);
        // instrument 5 buzz 1 phase 2.949219 => -0.187500
        test_case(5, 0, 1, 0, 24739840, 0, -1572864);
        // instrument 5 buzz 1 phase 0.664062 => 0.013889
        test_case(5, 0, 1, 0, 5570560, 0, 116508);
        // instrument 5 buzz 1 phase 1.847656 => -0.006944
        test_case(5, 0, 1, 0, 15499264, 0, -58254);
        // instrument 5 buzz 1 phase 1.738281 => 0.145833
        test_case(5, 0, 1, 0, 14581760, 0, 1223338);
        // instrument 5 buzz 1 phase 0.261719 => 0.076389
        test_case(5, 0, 1, 1, 2195456, 0, 640796);
        // instrument 6 cur_pitch 13 noiz 0 phase 3.410156 brown_state -0.492188 => -1.203311
        test_case(6, 13, 0, 0, 28606464, -4128768, -10094105);
        // instrument 6 cur_pitch 62 noiz 0 phase 2.046875 brown_state 0.046875 => 0.070330
        test_case(6, 62, 0, 0, 17170432, 393216, 589972);
        // instrument 6 cur_pitch 61 noiz 0 phase 0.898438 brown_state 0.148438 => 0.222881
        test_case(6, 61, 0, 0, 7536640, 1245184, 1869658);
        // instrument 6 cur_pitch 12 noiz 0 phase 2.324219 brown_state -0.062500 => -0.155187
        test_case(6, 12, 0, 0, 19496960, -524288, -1301803);
        // instrument 6 cur_pitch 27 noiz 0 phase 1.089844 brown_state 0.304688 => 0.606266
        test_case(6, 27, 0, 0, 9142272, 2555904, 5085727);
        // instrument 6 cur_pitch 2 noiz 0 phase 2.828125 brown_state 0.476562 => 1.385021
        test_case(6, 2, 0, 0, 23724032, 3997696, 11618398);
        // instrument 6 cur_pitch 45 noiz 0 phase 3.773438 brown_state 0.085938 => 0.139429
        test_case(6, 45, 0, 0, 31653888, 720896, 1169617);
        // instrument 6 cur_pitch 44 noiz 0 phase 2.718750 brown_state -0.230469 => -0.377147
        test_case(6, 44, 0, 0, 22806528, -1933312, -3163734);
        // instrument 6 cur_pitch 13 noiz 0 phase 2.460938 brown_state 0.246094 => 0.601656
        test_case(6, 13, 0, 0, 20643840, 2064384, 5047052);
        // instrument 6 cur_pitch 16 noiz 0 phase 0.199219 brown_state 0.156250 => 0.364820
        test_case(6, 16, 0, 0, 1671168, 1310720, 3060328);
        // instrument 6 cur_pitch 15 noiz 0 phase 0.746094 brown_state 0.250000 => 0.592687
        test_case(6, 15, 0, 0, 6258688, 2097152, 4971820);
        // instrument 6 cur_pitch 27 noiz 0 phase 2.722656 brown_state 0.226562 => 0.450813
        test_case(6, 27, 0, 0, 22839296, 1900544, 3781694);
        // instrument 6 cur_pitch 14 noiz 0 phase 1.308594 brown_state -0.164062 => -0.394965
        test_case(6, 14, 0, 0, 10977280, -1376256, -3313209);
        // instrument 6 cur_pitch 10 noiz 0 phase 0.296875 brown_state 0.105469 => 0.270169
        test_case(6, 10, 0, 0, 2490368, 884736, 2266341);
        // instrument 6 cur_pitch 17 noiz 0 phase 3.164062 brown_state -0.210938 => -0.485092
        test_case(6, 17, 0, 0, 26542080, -1769472, -4069250);
        // instrument 6 cur_pitch 13 noiz 0 phase 0.679688 brown_state 0.316406 => 0.773557
        test_case(6, 13, 0, 0, 5701632, 2654208, 6489067);
        // instrument 6 cur_pitch 63 noiz 0 phase 2.324219 brown_state 0.281250 => 0.421875
        test_case(6, 63, 0, 0, 19496960, 2359296, 3538944);
        // instrument 6 cur_pitch 21 noiz 0 phase 2.109375 brown_state -0.449219 => -0.973307
        test_case(6, 21, 0, 0, 17694720, -3768320, -8164693);
        // instrument 6 cur_pitch 22 noiz 0 phase 2.554688 brown_state 0.437500 => 0.934193
        test_case(6, 22, 0, 0, 21430272, 3670016, 7836580);
        // instrument 6 cur_pitch 22 noiz 0 phase 3.062500 brown_state 0.113281 => 0.241889
        test_case(6, 22, 0, 0, 25690112, 950272, 2029114);
        // instrument 6 cur_pitch 62 noiz 0 phase 3.828125 brown_state -0.429688 => -0.644694
        test_case(6, 62, 0, 0, 32112640, -3604480, -5408082);
        // instrument 6 cur_pitch 14 noiz 0 phase 3.183594 brown_state 0.253906 => 0.611256
        test_case(6, 14, 0, 0, 26705920, 2129920, 5127585);
        // instrument 6 cur_pitch 45 noiz 0 phase 2.437500 brown_state 0.468750 => 0.760523
        test_case(6, 45, 0, 0, 20447232, 3932160, 6379729);
        // instrument 6 cur_pitch 6 noiz 0 phase 3.046875 brown_state -0.429688 => -1.172141
        test_case(6, 6, 0, 0, 25559040, -3604480, -9832629);
        // instrument 6 cur_pitch 9 noiz 0 phase 2.339844 brown_state 0.250000 => 0.650510
        test_case(6, 9, 0, 0, 19628032, 2097152, 5456875);
        // instrument 6 cur_pitch 48 noiz 1 phase 1.882812 brown_state -0.289062 => 0.107385
        test_case(6, 48, 0, 1, 15794176, -2424832, 900806);
        // instrument 6 cur_pitch 12 noiz 1 phase 3.195312 brown_state 0.296875 => 0.287945
        test_case(6, 12, 0, 1, 26804224, 2490368, 2415455);
        // instrument 6 cur_pitch 26 noiz 1 phase 2.855469 brown_state -0.363281 => 0.211848
        test_case(6, 26, 0, 1, 23953408, -3047424, 1777106);
        // instrument 6 cur_pitch 27 noiz 1 phase 3.050781 brown_state 0.136719 => 0.027629
        test_case(6, 27, 0, 1, 25591808, 1146880, 231771);
        // instrument 6 cur_pitch 13 noiz 1 phase 1.625000 brown_state 0.058594 => -0.107438
        test_case(6, 13, 0, 1, 13631488, 491520, -901259);
        // instrument 6 cur_pitch 11 noiz 1 phase 3.328125 brown_state -0.480469 => -0.795180
        test_case(6, 11, 0, 1, 27918336, -4030464, -6670457);
        // instrument 6 cur_pitch 33 noiz 1 phase 3.562500 brown_state -0.476562 => 0.767322
        test_case(6, 33, 0, 1, 29884416, -3997696, 6436766);
        // instrument 6 cur_pitch 15 noiz 1 phase 0.382812 brown_state 0.125000 => 0.226888
        test_case(6, 15, 0, 1, 3211264, 1048576, 1903274);
        // instrument 6 cur_pitch 18 noiz 1 phase 2.679688 brown_state 0.472656 => -0.685924
        test_case(6, 18, 0, 1, 22478848, 3964928, -5753950);
        // instrument 6 cur_pitch 53 noiz 1 phase 0.781250 brown_state -0.488281 => 0.328508
        test_case(6, 53, 0, 1, 6553600, -4096000, 2755724);
        // instrument 6 cur_pitch 21 noiz 1 phase 3.761719 brown_state 0.039062 => -0.040334
        test_case(6, 21, 0, 1, 31555584, 327680, -338346);
        // instrument 6 cur_pitch 51 noiz 1 phase 2.460938 brown_state 0.046875 => 0.067171
        test_case(6, 51, 0, 1, 20643840, 393216, 563471);
        // instrument 6 cur_pitch 60 noiz 1 phase 0.636719 brown_state 0.117188 => -0.128006
        test_case(6, 60, 0, 1, 5341184, 983040, -1073789);
        // instrument 6 cur_pitch 30 noiz 1 phase 1.007812 brown_state 0.027344 => 0.000817
        test_case(6, 30, 0, 1, 8454144, 229376, 6851);
        // instrument 6 cur_pitch 37 noiz 1 phase 2.035156 brown_state -0.480469 => -0.059305
        test_case(6, 37, 0, 1, 17072128, -4030464, -497488);
        // instrument 6 cur_pitch 34 noiz 1 phase 3.906250 brown_state 0.253906 => -0.086543
        test_case(6, 34, 0, 1, 32768000, 2129920, -725971);
        // instrument 6 cur_pitch 36 noiz 1 phase 3.375000 brown_state -0.007812 => -0.010403
        test_case(6, 36, 0, 1, 28311552, -65536, -87269);
        // instrument 6 cur_pitch 8 noiz 1 phase 3.156250 brown_state -0.046875 => -0.038719
        test_case(6, 8, 0, 1, 26476544, -393216, -324800);
        // instrument 6 cur_pitch 26 noiz 1 phase 0.582031 brown_state -0.019531 => 0.032938
        test_case(6, 26, 0, 1, 4882432, -163840, 276301);
        // instrument 6 cur_pitch 38 noiz 1 phase 3.925781 brown_state -0.316406 => 0.081544
        test_case(6, 38, 0, 1, 32931840, -2654208, 684037);
        // instrument 6 cur_pitch 59 noiz 1 phase 0.367188 brown_state 0.343750 => 0.380189
        test_case(6, 59, 0, 1, 3080192, 2883584, 3189253);
        // instrument 6 cur_pitch 40 noiz 1 phase 2.585938 brown_state 0.289062 => -0.406928
        test_case(6, 40, 0, 1, 21692416, 2424832, -3413557);
        // instrument 6 cur_pitch 42 noiz 1 phase 0.898438 brown_state 0.300781 => -0.101827
        test_case(6, 42, 0, 1, 7536640, 2523136, -854186);
        // instrument 6 cur_pitch 24 noiz 1 phase 1.417969 brown_state 0.429688 => 0.745262
        test_case(6, 24, 0, 1, 11894784, 3604480, 6251711);
        // instrument 6 cur_pitch 7 noiz 1 phase 2.699219 brown_state -0.375000 => 0.605740
        test_case(6, 7, 0, 1, 22642688, -3145728, 5081315);
        // instrument 6 cur_pitch 14 noiz 0 phase 3.808594 brown_state 0.488281 => 1.175492
        test_case(6, 14, 1, 0, 31948800, 4096000, 9860741);
        // instrument 6 cur_pitch 43 noiz 0 phase 0.582031 brown_state -0.394531 => -0.651439
        test_case(6, 43, 1, 0, 4882432, -3309568, -5464665);
        // instrument 6 cur_pitch 44 noiz 0 phase 0.187500 brown_state -0.277344 => -0.453854
        test_case(6, 44, 1, 0, 1572864, -2326528, -3807205);
        // instrument 6 cur_pitch 0 noiz 0 phase 1.066406 brown_state -0.191406 => -0.574219
        test_case(6, 0, 1, 0, 8945664, -1605632, -4816896);
        // instrument 6 cur_pitch 43 noiz 0 phase 2.277344 brown_state -0.058594 => -0.096748
        test_case(6, 43, 1, 0, 19103744, -491520, -811583);
        // instrument 6 cur_pitch 56 noiz 0 phase 2.144531 brown_state 0.371094 => 0.563513
        test_case(6, 56, 1, 0, 17989632, 3112960, 4727087);
        // instrument 6 cur_pitch 22 noiz 0 phase 2.546875 brown_state 0.308594 => 0.658940
        test_case(6, 22, 1, 0, 21364736, 2588672, 5527587);
        // instrument 6 cur_pitch 17 noiz 0 phase 2.683594 brown_state -0.449219 => -1.033067
        test_case(6, 17, 1, 0, 22511616, -3768320, -8665996);
        // instrument 6 cur_pitch 4 noiz 0 phase 1.421875 brown_state 0.230469 => 0.648901
        test_case(6, 4, 1, 0, 11927552, 1933312, 5443376);
        // instrument 6 cur_pitch 10 noiz 0 phase 1.804688 brown_state -0.500000 => -1.280801
        test_case(6, 10, 1, 0, 15138816, -4194304, -10744139);
        // instrument 6 cur_pitch 49 noiz 0 phase 1.453125 brown_state -0.089844 => -0.141421
        test_case(6, 49, 1, 0, 12189696, -753664, -1186322);
        // instrument 6 cur_pitch 3 noiz 0 phase 3.703125 brown_state 0.480469 => 1.374402
        test_case(6, 3, 1, 0, 31064064, 4030464, 11529321);
        // instrument 6 cur_pitch 34 noiz 0 phase 0.117188 brown_state 0.246094 => 0.447359
        test_case(6, 34, 1, 0, 983040, 2064384, 3752716);
        // instrument 6 cur_pitch 29 noiz 0 phase 3.062500 brown_state -0.175781 => -0.340468
        test_case(6, 29, 1, 0, 25690112, -1474560, -2856054);
        // instrument 6 cur_pitch 7 noiz 0 phase 3.230469 brown_state -0.312500 => -0.839120
        test_case(6, 7, 1, 0, 27099136, -2621440, -7039052);
        // instrument 6 cur_pitch 21 noiz 0 phase 1.402344 brown_state -0.148438 => -0.321615
        test_case(6, 21, 1, 0, 11763712, -1245184, -2697898);
        // instrument 6 cur_pitch 28 noiz 0 phase 1.335938 brown_state 0.355469 => 0.697772
        test_case(6, 28, 1, 0, 11206656, 2981888, 5853336);
        // instrument 6 cur_pitch 15 noiz 0 phase 1.492188 brown_state -0.242188 => -0.574166
        test_case(6, 15, 1, 0, 12517376, -2031616, -4816450);
        // instrument 6 cur_pitch 43 noiz 0 phase 2.507812 brown_state -0.335938 => -0.554690
        test_case(6, 43, 1, 0, 21037056, -2818048, -4653081);
        // instrument 6 cur_pitch 13 noiz 0 phase 1.402344 brown_state -0.386719 => -0.945459
        test_case(6, 13, 1, 0, 11763712, -3244032, -7931082);
        // instrument 6 cur_pitch 26 noiz 0 phase 0.195312 brown_state -0.378906 => -0.764400
        test_case(6, 26, 1, 0, 1638400, -3178496, -6412250);
        // instrument 6 cur_pitch 53 noiz 0 phase 2.792969 brown_state -0.054688 => -0.084098
        test_case(6, 53, 1, 0, 23429120, -458752, -705465);
        // instrument 6 cur_pitch 2 noiz 0 phase 0.574219 brown_state 0.082031 => 0.238405
        test_case(6, 2, 1, 0, 4816896, 688128, 1999888);
        // instrument 6 cur_pitch 9 noiz 0 phase 0.691406 brown_state -0.015625 => -0.040657
        test_case(6, 9, 1, 0, 5799936, -131072, -341054);
        // instrument 6 cur_pitch 37 noiz 0 phase 3.726562 brown_state -0.359375 => -0.630876
        test_case(6, 37, 1, 0, 31260672, -3014656, -5292168);
        // instrument 6 cur_pitch 59 noiz 1 phase 1.621094 brown_state -0.273438 => 0.312075
        test_case(6, 59, 1, 1, 13598720, -2293760, 2617871);
        // instrument 6 cur_pitch 7 noiz 1 phase 2.722656 brown_state 0.093750 => -0.139635
        test_case(6, 7, 1, 1, 22839296, 786432, -1171342);
        // instrument 6 cur_pitch 49 noiz 1 phase 1.625000 brown_state 0.027344 => -0.032281
        test_case(6, 49, 1, 1, 13631488, 229376, -270791);
        // instrument 6 cur_pitch 35 noiz 1 phase 3.210938 brown_state 0.339844 => 0.257538
        test_case(6, 35, 1, 1, 26935296, 2850816, 2160384);
        // instrument 6 cur_pitch 54 noiz 1 phase 0.906250 brown_state 0.460938 => -0.132284
        test_case(6, 54, 1, 1, 7602176, 3866624, -1109681);
        // instrument 6 cur_pitch 49 noiz 1 phase 1.417969 brown_state 0.023438 => 0.030840
        test_case(6, 49, 1, 1, 11894784, 196608, 258702);
        // instrument 6 cur_pitch 33 noiz 1 phase 0.546875 brown_state -0.488281 => 0.814269
        test_case(6, 33, 1, 1, 4587520, -4096000, 6830585);
        // instrument 6 cur_pitch 49 noiz 1 phase 2.878906 brown_state 0.035156 => -0.013402
        test_case(6, 49, 1, 1, 24150016, 294912, -112426);
        // instrument 6 cur_pitch 15 noiz 1 phase 0.593750 brown_state -0.187500 => 0.361169
        test_case(6, 15, 1, 1, 4980736, -1572864, 3029702);
        // instrument 6 cur_pitch 57 noiz 1 phase 2.769531 brown_state 0.160156 => -0.111737
        test_case(6, 57, 1, 1, 23232512, 1343488, -937321);
        // instrument 6 cur_pitch 28 noiz 1 phase 3.671875 brown_state -0.476562 => 0.613905
        test_case(6, 28, 1, 1, 30801920, -3997696, 5149810);
        // instrument 6 cur_pitch 48 noiz 1 phase 1.441406 brown_state -0.230469 => -0.322492
        test_case(6, 48, 1, 1, 12091392, -1933312, -2705260);
        // instrument 6 cur_pitch 10 noiz 1 phase 2.625000 brown_state -0.285156 => 0.547843
        test_case(6, 10, 1, 1, 22020096, -2392064, 4595638);
        // instrument 6 cur_pitch 60 noiz 1 phase 1.914062 brown_state -0.089844 => 0.023215
        test_case(6, 60, 1, 1, 16056320, -753664, 194744);
        // instrument 6 cur_pitch 10 noiz 1 phase 0.718750 brown_state -0.414062 => 0.596623
        test_case(6, 10, 1, 1, 6029312, -3473408, 5004838);
        // instrument 6 cur_pitch 0 noiz 1 phase 0.843750 brown_state -0.250000 => 0.234375
        test_case(6, 0, 1, 1, 7077888, -2097152, 1966080);
        // instrument 6 cur_pitch 13 noiz 1 phase 3.746094 brown_state 0.308594 => -0.383123
        test_case(6, 13, 1, 1, 31424512, 2588672, -3213865);
        // instrument 6 cur_pitch 54 noiz 1 phase 1.125000 brown_state -0.242188 => -0.092674
        test_case(6, 54, 1, 1, 9437184, -2031616, -777404);
        // instrument 6 cur_pitch 27 noiz 1 phase 1.101562 brown_state -0.167969 => -0.067889
        test_case(6, 27, 1, 1, 9240576, -1409024, -569495);
        // instrument 6 cur_pitch 27 noiz 1 phase 2.742188 brown_state 0.359375 => -0.368715
        test_case(6, 27, 1, 1, 23003136, 3014656, -3093002);
        // instrument 6 cur_pitch 61 noiz 1 phase 1.281250 brown_state -0.460938 => -0.389308
        test_case(6, 61, 1, 1, 10747904, -3866624, -3265751);
        // instrument 6 cur_pitch 23 noiz 1 phase 2.109375 brown_state -0.289062 => -0.133084
        test_case(6, 23, 1, 1, 17694720, -2424832, -1116392);
        // instrument 6 cur_pitch 4 noiz 1 phase 2.558594 brown_state 0.242188 => -0.601986
        test_case(6, 4, 1, 1, 21463040, 2031616, -5049827);
        // instrument 6 cur_pitch 21 noiz 1 phase 0.140625 brown_state 0.390625 => 0.238037
        test_case(6, 21, 1, 1, 1179648, 3276800, 1996799);
        // instrument 6 cur_pitch 53 noiz 1 phase 1.339844 brown_state 0.320312 => 0.334797
        test_case(6, 53, 1, 1, 11239424, 2686976, 2808477);
        // instrument 7 buzz 0 phase 3.570312 => 0.381013
        test_case(7, 0, 0, 0, 29949952, 0, 3196170);
        // instrument 7 buzz 0 phase 3.160156 => -0.198840
        test_case(7, 0, 0, 0, 26509312, 0, -1667990);
        // instrument 7 buzz 0 phase 2.246094 => -0.021425
        test_case(7, 0, 0, 0, 18841600, 0, -179728);
        // instrument 7 buzz 0 phase 2.507812 => 0.479593
        test_case(7, 0, 0, 0, 21037056, 0, 4023116);
        // instrument 7 buzz 0 phase 0.164062 => -0.172869
        test_case(7, 0, 0, 0, 1376256, 0, -1450133);
        // instrument 7 buzz 0 phase 0.472656 => 0.442448
        test_case(7, 0, 0, 0, 3964928, 0, 3711522);
        // instrument 7 buzz 0 phase 3.945312 => -0.366714
        test_case(7, 0, 0, 0, 33095680, 0, -3076220);
        // instrument 7 buzz 0 phase 3.984375 => -0.444602
        test_case(7, 0, 0, 0, 33423360, 0, -3729594);
        // instrument 7 buzz 0 phase 0.492188 => 0.481392
        test_case(7, 0, 0, 0, 4128768, 0, 4038209);
        // instrument 7 buzz 0 phase 3.351562 => 0.182813
        test_case(7, 0, 0, 0, 28114944, 0, 1533542);
        // instrument 7 buzz 0 phase 3.351562 => 0.182813
        test_case(7, 0, 0, 0, 28114944, 0, 1533542);
        // instrument 7 buzz 0 phase 1.160156 => -0.186719
        test_case(7, 0, 0, 0, 9732096, 0, -1566310);
        // instrument 7 buzz 0 phase 3.089844 => -0.339039
        test_case(7, 0, 0, 0, 25919488, 0, -2844064);
        // instrument 7 buzz 0 phase 3.316406 => 0.112713
        test_case(7, 0, 0, 0, 27820032, 0, 945505);
        // instrument 7 buzz 0 phase 2.632812 => 0.250331
        test_case(7, 0, 0, 0, 22085632, 0, 2099932);
        // instrument 7 buzz 0 phase 1.289062 => 0.070312
        test_case(7, 0, 0, 0, 10813440, 0, 589824);
        // instrument 7 buzz 0 phase 3.468750 => 0.416477
        test_case(7, 0, 0, 0, 29097984, 0, 3493664);
        // instrument 7 buzz 0 phase 1.226562 => -0.054309
        test_case(7, 0, 0, 0, 10289152, 0, -455574);
        // instrument 7 buzz 0 phase 0.667969 => 0.168111
        test_case(7, 0, 0, 0, 5603328, 0, 1410215);
        // instrument 7 buzz 0 phase 1.082031 => -0.342495
        test_case(7, 0, 0, 0, 9076736, 0, -2873058);
        // instrument 7 buzz 0 phase 2.324219 => 0.134351
        test_case(7, 0, 0, 0, 19496960, 0, 1127020);
        // instrument 7 buzz 0 phase 1.511719 => 0.483026
        test_case(7, 0, 0, 0, 12681216, 0, 4051912);
        // instrument 7 buzz 0 phase 0.773438 => -0.042187
        test_case(7, 0, 0, 0, 6488064, 0, -353894);
        // instrument 7 buzz 0 phase 0.601562 => 0.300521
        test_case(7, 0, 0, 0, 5046272, 0, 2520951);
        // instrument 7 buzz 0 phase 0.441406 => 0.380137
        test_case(7, 0, 0, 0, 3702784, 0, 3188822);
        // instrument 7 buzz 0 phase 3.855469 => -0.187571
        test_case(7, 0, 0, 1, 32342016, 0, -1573460);
        // instrument 7 buzz 1 phase 1.683594 => 0.124787
        test_case(7, 0, 1, 0, 14123008, 0, 1046788);
        // instrument 7 buzz 1 phase 2.167969 => -0.185014
        test_case(7, 0, 1, 0, 18186240, 0, -1552012);
        // instrument 7 buzz 1 phase 2.312500 => 0.090151
        test_case(7, 0, 1, 0, 19398656, 0, 756245);
        // instrument 7 buzz 1 phase 3.406250 => 0.312689
        test_case(7, 0, 1, 0, 28573696, 0, 2623029);
        // instrument 7 buzz 1 phase 2.457031 => 0.420005
        test_case(7, 0, 1, 0, 20611072, 0, 3523254);
        // instrument 7 buzz 1 phase 3.132812 => -0.237737
        test_case(7, 0, 1, 0, 26279936, 0, -1994280);
        // instrument 7 buzz 1 phase 1.140625 => -0.215246
        test_case(7, 0, 1, 0, 9568256, 0, -1805616);
        // instrument 7 buzz 1 phase 3.644531 => 0.240838
        test_case(7, 0, 1, 0, 30572544, 0, 2020296);
        // instrument 7 buzz 1 phase 0.101562 => -0.276657
        test_case(7, 0, 1, 0, 851968, 0, -2320768);
        // instrument 7 buzz 1 phase 2.632812 => 0.265956
        test_case(7, 0, 1, 0, 22085632, 0, 2231004);
        // instrument 7 buzz 1 phase 2.277344 => -0.003385
        test_case(7, 0, 1, 0, 19103744, 0, -28398);
        // instrument 7 buzz 1 phase 0.691406 => 0.097940
        test_case(7, 0, 1, 0, 5799936, 0, 821583);
        // instrument 7 buzz 1 phase 1.636719 => 0.249503
        test_case(7, 0, 1, 0, 13729792, 0, 2092981);
        // instrument 7 buzz 1 phase 0.308594 => 0.091880
        test_case(7, 0, 1, 0, 2588672, 0, 770743);
        // instrument 7 buzz 1 phase 1.242188 => -0.080445
        test_case(7, 0, 1, 0, 10420224, 0, -674822);
        // instrument 7 buzz 1 phase 1.871094 => -0.212618
        test_case(7, 0, 1, 0, 15695872, 0, -1783572);
        // instrument 7 buzz 1 phase 1.179688 => -0.163400
        test_case(7, 0, 1, 0, 9895936, 0, -1370695);
        // instrument 7 buzz 1 phase 3.687500 => 0.126515
        test_case(7, 0, 1, 0, 30932992, 0, 1061286);
        // instrument 7 buzz 1 phase 1.527344 => 0.475402
        test_case(7, 0, 1, 0, 12812288, 0, 3987964);
        // instrument 7 buzz 1 phase 0.421875 => 0.362027
        test_case(7, 0, 1, 0, 3538944, 0, 3036898);
        // instrument 7 buzz 1 phase 3.792969 => -0.096804
        test_case(7, 0, 1, 0, 31817728, 0, -812050);
        // instrument 7 buzz 1 phase 1.917969 => -0.303480
        test_case(7, 0, 1, 0, 16089088, 0, -2545776);
        // instrument 7 buzz 1 phase 3.914062 => -0.283570
        test_case(7, 0, 1, 0, 32833536, 0, -2378758);
        // instrument 7 buzz 1 phase 2.742188 => -0.025047
        test_case(7, 0, 1, 0, 23003136, 0, -210112);
        // instrument 7 buzz 1 phase 2.285156 => 0.017401
        test_case(7, 0, 1, 0, 19169280, 0, 145966);
        // instrument 7 buzz 1 phase 2.433594 => 0.373272
        test_case(7, 0, 1, 1, 20414464, 0, 3131230);

        //====================
        // Summary
        //====================
        #1000;
        $display("");
        $display("=== Test Summary ===");
        $display("Total tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);

        // Per-combination breakdown
        $display("");
        $display("=== Per-Combination Results ===");
        $display("");
        $display("Instruments 0-5, 7 (use buzz, ignore noiz):");
        $display("Instrument | buzz | PASS | FAIL | Total");
        $display("-----------|------|------|------|------");
        for (i = 0; i < 8; i = i + 1) begin
            if (i != 6) begin  // Skip NOISE
                for (b = 0; b < 2; b = b + 1) begin
                    // Sum across both noiz values (irrelevant for these instruments)
                    $display("    %0d      |  %0d   | %4d | %4d | %4d",
                             i, b,
                             combo_pass[i][b][0] + combo_pass[i][b][1],
                             combo_fail[i][b][0] + combo_fail[i][b][1],
                             combo_pass[i][b][0] + combo_pass[i][b][1] + combo_fail[i][b][0] + combo_fail[i][b][1]);
                end
            end
        end
        $display("");
        $display("Instrument 6 (NOISE - uses noiz, ignores buzz):");
        $display("noiz | PASS | FAIL | Total");
        $display("-----|------|------|------");
        for (n = 0; n < 2; n = n + 1) begin
            // Sum across both buzz values (irrelevant for NOISE)
            $display(" %0d   | %4d | %4d | %4d",
                     n,
                     combo_pass[6][0][n] + combo_pass[6][1][n],
                     combo_fail[6][0][n] + combo_fail[6][1][n],
                     combo_pass[6][0][n] + combo_pass[6][1][n] + combo_fail[6][0][n] + combo_fail[6][1][n]);
        end

        if (fail_count == 0) begin
            $display("");
            $display("*** ALL TESTS PASSED ***");
            $finish(0);
        end else begin
            $display("");
            $display("*** SOME TESTS FAILED ***");
            $finish(1);
        end
    end

    // Timeout
    initial begin
        #100000;
        $display("ERROR: Simulation timeout");
        $finish(2);
    end

endmodule
