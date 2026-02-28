`timescale 1ns/1ps

import tb_test_framework_pkg::*;

module tb_p8audio_api;
    //====================
    // Clocks & Reset
    //====================
    reg clk_sys = 1'b0;
    reg clk_pcm = 1'b0;
    reg clk_pcm_8x = 1'b0;
    reg resetn  = 1'b0;

    always #4 clk_sys = ~clk_sys;
    always #7 clk_pcm_8x = ~clk_pcm_8x;

    reg [1:0] pcm_div_counter = 2'd0;
    always @(posedge clk_pcm_8x or negedge resetn) begin
        if (!resetn) begin
            pcm_div_counter <= 2'd0;
            clk_pcm <= 1'b0;
        end else begin
            pcm_div_counter <= pcm_div_counter + 1;
            if (pcm_div_counter == 2'd3)
                clk_pcm <= ~clk_pcm;
        end
    end

    //====================
    // MMIO signals
    //====================
    reg  [6:0]  address;
    reg  [15:0] din;
    wire [15:0] dout;
    reg         nUDS, nLDS;
    reg         write_en, read_en;

    localparam [7:0] ADDR_VERSION       = 8'h00;
    localparam [7:0] ADDR_CTRL          = 8'h02;
    localparam [7:0] ADDR_SFX_BASE_HI   = 8'h04;
    localparam [7:0] ADDR_SFX_BASE_LO   = 8'h06;
    localparam [7:0] ADDR_MUSIC_BASE_HI = 8'h08;
    localparam [7:0] ADDR_MUSIC_BASE_LO = 8'h0A;
    localparam [7:0] ADDR_HWFX40        = 8'h0D;
    localparam [7:0] ADDR_HWFX41        = 8'h0F;
    localparam [7:0] ADDR_HWFX42        = 8'h11;
    localparam [7:0] ADDR_HWFX43        = 8'h13;
    localparam [7:0] ADDR_SFX_CMD       = 8'h18;
    localparam [7:0] ADDR_SFX_LEN       = 8'h1A;
    localparam [7:0] ADDR_MUSIC_CMD     = 8'h1C;
    localparam [7:0] ADDR_MUSIC_FADE    = 8'h1E;
    localparam [7:0] ADDR_STAT46        = 8'h20;
    localparam [7:0] ADDR_STAT47        = 8'h22;
    localparam [7:0] ADDR_STAT48        = 8'h24;
    localparam [7:0] ADDR_STAT49        = 8'h26;
    localparam [7:0] ADDR_STAT50        = 8'h28;
    localparam [7:0] ADDR_STAT51        = 8'h2A;
    localparam [7:0] ADDR_STAT52        = 8'h2C;
    localparam [7:0] ADDR_STAT53        = 8'h2E;
    localparam [7:0] ADDR_STAT54        = 8'h30;
    localparam [7:0] ADDR_STAT57        = 8'h36;

    //====================
    // PCM output
    //====================
    wire signed [7:0] pcm_out;

    //====================
    // DMA interface
    //====================
    wire [30:0] dma_addr;
    reg  [15:0] dma_rdata;
    wire        dma_req;
    reg         dma_ack;

    //====================
    // Reset synchronizers
    //====================
    reg resetn_sys_d = 0, resetn_sys_q = 0;
    reg resetn_pcm_d = 0, resetn_pcm_q = 0;
    reg resetn_pcm_8x_d = 0, resetn_pcm_8x_q = 0;

    always @(posedge clk_sys or negedge resetn) begin
        if (!resetn) begin
            resetn_sys_d <= 1'b0;
            resetn_sys_q <= 1'b0;
        end else begin
            resetn_sys_d <= 1'b1;
            resetn_sys_q <= resetn_sys_d;
        end
    end

    always @(posedge clk_pcm or negedge resetn) begin
        if (!resetn) begin
            resetn_pcm_d <= 1'b0;
            resetn_pcm_q <= 1'b0;
        end else begin
            resetn_pcm_d <= 1'b1;
            resetn_pcm_q <= resetn_pcm_d;
        end
    end

    always @(posedge clk_pcm_8x or negedge resetn) begin
        if (!resetn) begin
            resetn_pcm_8x_d <= 1'b0;
            resetn_pcm_8x_q <= 1'b0;
        end else begin
            resetn_pcm_8x_d <= 1'b1;
            resetn_pcm_8x_q <= resetn_pcm_8x_d;
        end
    end

    //====================
    // DUT: p8audio
    //====================
    p8audio dut (
        .mclk(clk_sys), .clk_pcm(clk_pcm), .clk_pcm_8x(clk_pcm_8x),
        .resetn_sys(resetn_sys_q), .resetn_pcm(resetn_pcm_q), .resetn_pcm_8x(resetn_pcm_8x_q),
        .address(address), .din(din), .dout(dout), .nUDS(nUDS), .nLDS(nLDS), .write_en(write_en), .read_en(read_en),
        .pcm_out(pcm_out),
        .dma_addr(dma_addr), .dma_rdata(dma_rdata), .dma_req(dma_req), .dma_ack(dma_ack)
    );

    //====================
    // Fake Base RAM (bytes)
    //====================
    reg [7:0] base_mem [0:65535];

    wire [15:0] byte_addr = dma_addr[15:0] * 2;

    always @* begin
        dma_rdata = { base_mem[byte_addr], base_mem[byte_addr+16'd1] };
    end

    always @(posedge clk_sys or negedge resetn) begin
        if (!resetn) begin
            dma_ack <= 1'b0;
        end else begin
            if (dma_req && !dma_ack) begin
                dma_ack <= 1'b1;
            end else begin
                dma_ack <= 1'b0;
            end
        end
    end

    //====================
    // Helpers: MMIO write/read
    //====================
    task mmio_write(input [7:0] cpu_addr, input [15:0] d);
    begin
        @(posedge clk_sys); address <= cpu_addr[7:1]; din <= d; write_en <= 1'b1; read_en <= 1'b0; nUDS <= 1'b0; nLDS <= 1'b0;
        @(posedge clk_sys); write_en <= 1'b0; nUDS <= 1'b1; nLDS <= 1'b1;
    end endtask

    task mmio_read(input [7:0] cpu_addr, output [15:0] d);
    begin
        @(posedge clk_sys); address <= cpu_addr[7:1]; write_en <= 1'b0; read_en <= 1'b1; nUDS <= 1'b0; nLDS <= 1'b0;
        @(posedge clk_sys); d = dout; read_en <= 1'b0; nUDS <= 1'b1; nLDS <= 1'b1;
    end endtask

    //====================
    // SFX/MUSIC memory layout
    //====================
    localparam integer SFX_BYTES = 68;
    localparam integer MUSIC_BYTES = 4;
    localparam [15:0]  SFX_BASE  = 16'h3200;
    localparam [15:0]  MUSIC_BASE = 16'h3100;

    localparam [5:0] SFX_IDX_STOP = 6'h3f;
    localparam [5:0] SFX_IDX_RELEASE = 6'h3e;
    localparam [2:0] CH_AUTO = 3'h7;
    localparam [2:0] CH_STOP_SFX_ANY = 3'h6;

    localparam int PCM_TIMEOUT_SHORT = 6000;
    localparam int PCM_TIMEOUT_MED = 20000;
    localparam int PCM_TIMEOUT_LONG = 40000;
    localparam int PCM_TIMEOUT_XLONG = 70000;

    bit p8audio_inited = 0;

    task write_note(input int sfx, input int note_idx, input [5:0] pitch,
                    input [2:0] wave, input [2:0] vol, input [2:0] effect);
        int base;
        reg [7:0] low;
        reg [7:0] high;
    begin
        // PICO-8 note format (little-endian):
        // low byte: pitch[5:0] + wave[1:0] in bits 7-6
        // high byte: wave[2] in bit 0 + vol[2:0] in bits 3-1 + effect[2:0] in bits 6-4
        low  = pitch[5:0] + {wave[1:0], 6'b0};
        high = {1'b0, effect[2:0], vol[2:0], wave[2]};
        base = SFX_BASE + (sfx * SFX_BYTES) + (note_idx * 2);
        base_mem[base + 0] = low;
        base_mem[base + 1] = high;
    end endtask

    task init_sfx_slot(input int sfx, input [5:0] pitch, input [2:0] wave,
                       input [2:0] vol, input [7:0] speed, input [5:0] loop_start,
                       input [5:0] loop_end);
        int i;
        int base;
    begin
        for (i = 0; i < 32; i = i + 1) begin
            write_note(sfx, i, pitch, wave, vol, 3'd0);
        end
        base = SFX_BASE + (sfx * SFX_BYTES);
        base_mem[base + 64] = 8'h01;
        base_mem[base + 65] = speed;
        base_mem[base + 66] = {2'b00, loop_start};
        base_mem[base + 67] = {2'b00, loop_end};
    end endtask

    task init_music_patterns();
        int base0;
        int base1;
        int base2;
    begin
        base0 = MUSIC_BASE + 0 * MUSIC_BYTES;
        base1 = MUSIC_BASE + 1 * MUSIC_BYTES;
        base2 = MUSIC_BASE + 2 * MUSIC_BYTES;

        base_mem[base0 + 0] = 8'h80 | 8'h00;
        base_mem[base0 + 1] = 8'h01;
        base_mem[base0 + 2] = 8'h02;
        base_mem[base0 + 3] = 8'h40;

        base_mem[base1 + 0] = 8'h00;
        base_mem[base1 + 1] = 8'h80 | 8'h01;
        base_mem[base1 + 2] = 8'h02;
        base_mem[base1 + 3] = 8'h40;

        base_mem[base2 + 0] = 8'd11;
        base_mem[base2 + 1] = 8'd12;
        base_mem[base2 + 2] = 8'd13;
        base_mem[base2 + 3] = 8'h40;
    end endtask

    task init_audio_memory();
        int i;
    begin
        for (i = 0; i < 65536; i = i + 1) begin
            base_mem[i] = 8'h00;
        end

        init_sfx_slot(0, 6'd24, 3'd3, 3'd7, 8'd2, 6'd0, 6'd0);
        init_sfx_slot(1, 6'd28, 3'd3, 3'd7, 8'd2, 6'd0, 6'd0);
        init_sfx_slot(2, 6'd31, 3'd3, 3'd7, 8'd2, 6'd0, 6'd0);
        init_sfx_slot(3, 6'd35, 3'd3, 3'd7, 8'd2, 6'd0, 6'd0);
        init_sfx_slot(4, 6'd36, 3'd2, 3'd7, 8'd1, 6'd0, 6'd0);
        init_sfx_slot(5, 6'd24, 3'd3, 3'd7, 8'd2, 6'd0, 6'd1);
        init_sfx_slot(6, 6'd24, 3'd3, 3'd2, 8'd2, 6'd0, 6'd0);
        init_sfx_slot(7, 6'd24, 3'd3, 3'd2, 8'd2, 6'd0, 6'd0);
        init_sfx_slot(8, 6'd24, 3'd3, 3'd2, 8'd2, 6'd0, 6'd0);
        init_sfx_slot(9, 6'd24, 3'd7, 3'd2, 8'd2, 6'd0, 6'd0);
        init_sfx_slot(11, 6'd24, 3'd3, 3'd7, 8'd2, 6'd0, 6'd31);
        init_sfx_slot(12, 6'd28, 3'd3, 3'd7, 8'd8, 6'd0, 6'd0);
        init_sfx_slot(13, 6'd31, 3'd3, 3'd7, 8'd4, 6'd0, 6'd0);

        init_music_patterns();
    end endtask

    task p8audio_init();
    begin
        if (p8audio_inited) begin
            return;
        end
        mmio_write(ADDR_SFX_BASE_HI, 16'h0000);
        mmio_write(ADDR_SFX_BASE_LO, SFX_BASE);
        mmio_write(ADDR_MUSIC_BASE_HI, 16'h0000);
        mmio_write(ADDR_MUSIC_BASE_LO, MUSIC_BASE);
        mmio_write(ADDR_MUSIC_FADE, 16'h0000);
        mmio_write(ADDR_HWFX40, 16'h0000);
        mmio_write(ADDR_HWFX41, 16'h0000);
        mmio_write(ADDR_HWFX42, 16'h0000);
        mmio_write(ADDR_HWFX43, 16'h0000);
        mmio_write(ADDR_SFX_LEN, 16'h0000);
        mmio_write(ADDR_CTRL, 16'h0001);
        p8audio_inited = 1'b1;
    end endtask

    task sfx_cmd(input int idx, input int ch, input int offset);
        int idx_f;
        int ch_f;
        reg [15:0] cmd;
    begin
        if (idx < 0) begin
            idx_f = (idx == -2) ? SFX_IDX_RELEASE : SFX_IDX_STOP;
        end else begin
            idx_f = idx & 6'h3f;
        end

        if (ch < 0) begin
            ch_f = (ch == -2) ? CH_STOP_SFX_ANY : CH_AUTO;
        end else begin
            ch_f = ch & 3'h7;
        end

        cmd = {1'b1, ch_f[2:0], offset[5:0], idx_f[5:0]};
        mmio_write(ADDR_SFX_CMD, cmd);
    end endtask

    task music_cmd(input int pat, input int fade_len, input int mask);
        int pat_f;
        int mask_f;
        reg [15:0] cmd;
    begin
        pat_f = (pat < 0) ? 6'h3f : (pat & 6'h3f);
        mask_f = mask & 4'hf;
        mmio_write(ADDR_MUSIC_FADE, fade_len[15:0]);
        cmd = (pat_f << 7) | (mask_f << 3);
        mmio_write(ADDR_MUSIC_CMD, cmd);
    end endtask

    task stop_all();
    begin
        sfx_cmd(-1, -1, 0);
        music_cmd(-1, 16'h0000, 0);
        repeat (10) @(posedge clk_pcm);
    end endtask

    function [7:0] stat_sfx_addr(input int ch);
        case (ch)
            0: stat_sfx_addr = ADDR_STAT46;
            1: stat_sfx_addr = ADDR_STAT47;
            2: stat_sfx_addr = ADDR_STAT48;
            default: stat_sfx_addr = ADDR_STAT49;
        endcase
    endfunction

    function [7:0] stat_note_addr(input int ch);
        case (ch)
            0: stat_note_addr = ADDR_STAT50;
            1: stat_note_addr = ADDR_STAT51;
            2: stat_note_addr = ADDR_STAT52;
            default: stat_note_addr = ADDR_STAT53;
        endcase
    endfunction

    task wait_for_sfx_on_channel(input int ch, input int sfx, input int timeout_pcm, output bit ok);
        int count;
        reg [15:0] val;
        reg [15:0] note_val;
    begin
        ok = 1'b0;
        for (count = 0; count < timeout_pcm; count = count + 1) begin
            mmio_read(stat_sfx_addr(ch), val);
            mmio_read(stat_note_addr(ch), note_val);
            if (val != 16'hffff && note_val != 16'hffff && (val[5:0] == sfx[5:0]) && (note_val[5:0] < 6'd32)) begin
                ok = 1'b1;
                disable wait_for_sfx_on_channel;
            end
            @(posedge clk_pcm);
        end
    end endtask

    task wait_for_sfx_any(input int sfx, input int timeout_pcm, output bit ok, output int ch_out);
        int count;
        int ch;
        reg [15:0] val;
        reg [15:0] note_val;
    begin
        ok = 1'b0;
        ch_out = -1;
        for (count = 0; count < timeout_pcm; count = count + 1) begin
            for (ch = 0; ch < 4; ch = ch + 1) begin
                mmio_read(stat_sfx_addr(ch), val);
                mmio_read(stat_note_addr(ch), note_val);
                if (val != 16'hffff && note_val != 16'hffff && (val[5:0] == sfx[5:0]) && (note_val[5:0] < 6'd32)) begin
                    ok = 1'b1;
                    ch_out = ch;
                    disable wait_for_sfx_any;
                end
            end
            @(posedge clk_pcm);
        end
    end endtask

    task wait_for_idle(input int ch, input int timeout_pcm, output bit ok);
        int count;
        reg [15:0] val;
    begin
        ok = 1'b0;
        for (count = 0; count < timeout_pcm; count = count + 1) begin
            mmio_read(stat_sfx_addr(ch), val);
            if (val == 16'hffff) begin
                ok = 1'b1;
                disable wait_for_idle;
            end
            @(posedge clk_pcm);
        end
    end endtask

    task wait_for_release(input int ch, input int timeout_pcm, output bit ok);
        int count;
        reg [15:0] sfx_val;
        reg [15:0] note_val;
    begin
        ok = 1'b0;
        for (count = 0; count < timeout_pcm; count = count + 1) begin
            mmio_read(stat_sfx_addr(ch), sfx_val);
            mmio_read(stat_note_addr(ch), note_val);
            if (sfx_val == 16'hffff || (note_val != 16'hffff && note_val[5:0] >= 6'd32)) begin
                ok = 1'b1;
                disable wait_for_release;
            end
            @(posedge clk_pcm);
        end
    end endtask

    task ensure_idle_for(input int ch, input int duration_pcm, output bit ok);
        int count;
        reg [15:0] val;
    begin
        ok = 1'b1;
        for (count = 0; count < duration_pcm; count = count + 1) begin
            mmio_read(stat_sfx_addr(ch), val);
            if (val != 16'hffff) begin
                ok = 1'b0;
                disable ensure_idle_for;
            end
            @(posedge clk_pcm);
        end
    end endtask

    task wait_for_music_pattern(input [5:0] pat, input int timeout_pcm, output bit ok);
        int count;
        reg [15:0] val;
    begin
        ok = 1'b0;
        for (count = 0; count < timeout_pcm; count = count + 1) begin
            mmio_read(ADDR_STAT54, val);
            if (val[5:0] == pat) begin
                ok = 1'b1;
                disable wait_for_music_pattern;
            end
            @(posedge clk_pcm);
        end
    end endtask

    task wait_for_music_playing(input int timeout_pcm, output bit ok);
        int count;
        reg [15:0] val;
    begin
        ok = 1'b0;
        for (count = 0; count < timeout_pcm; count = count + 1) begin
            mmio_read(ADDR_STAT57, val);
            if (val[0]) begin
                ok = 1'b1;
                disable wait_for_music_playing;
            end
            @(posedge clk_pcm);
        end
    end endtask

    task wait_for_note_at_least(input int ch, input [5:0] note, input int timeout_pcm, output bit ok);
        int count;
        reg [15:0] val;
    begin
        ok = 1'b0;
        for (count = 0; count < timeout_pcm; count = count + 1) begin
            mmio_read(stat_note_addr(ch), val);
            if (val != 16'hffff && (val[5:0] >= note)) begin
                ok = 1'b1;
                disable wait_for_note_at_least;
            end
            @(posedge clk_pcm);
        end
    end endtask

    task pcm_avg_rms(input int samples, output int avg);
        int i;
        int sum;
        int samp;
    begin
        sum = 0;
        for (i = 0; i < samples; i = i + 1) begin
            samp = $signed(pcm_out);
            sum = sum + samp * samp;
            @(posedge clk_pcm);
        end
        avg = $sqrt(sum / samples);
    end endtask

    task test_setup();
    begin
        p8audio_init();
        mmio_write(ADDR_SFX_LEN, 16'h0000);
        stop_all();
    end endtask

    task test_cleanup();
    begin
        stop_all();
        mmio_write(ADDR_SFX_LEN, 16'h0000);
    end endtask

    task automatic test_p8audio_version(output bit pass);
        reg [15:0] val;
    begin : test_p8audio_version
        pass = 1'b1;
        p8audio_init();
        mmio_read(ADDR_VERSION, val);
        $display("Version: 0x%04h", val);
    end endtask

    task automatic test_sfx_auto_channel(output bit pass);
        bit ok;
        int ch;
    begin : test_sfx_auto_channel
        pass = 1'b1;
        sfx_cmd(0, -1, 0);
        wait_for_sfx_any(0, PCM_TIMEOUT_SHORT, ok, ch);
        if (!ok) begin
            $display("FAIL: sfx auto channel not active");
            pass = 1'b0;
        end
    end endtask

    task automatic test_sfx_explicit_queue(output bit pass);
        bit ok;
    begin : test_sfx_explicit_queue
        pass = 1'b1;
        mmio_write(ADDR_SFX_LEN, 16'h0004);
        sfx_cmd(0, 0, 0);
        wait_for_sfx_on_channel(0, 0, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: sfx0 did not start on ch0");
            pass = 1'b0;
            disable test_sfx_explicit_queue;
        end
        sfx_cmd(1, 0, 0);
        wait_for_sfx_on_channel(0, 1, PCM_TIMEOUT_LONG, ok);
        if (!ok) begin
            $display("FAIL: queued sfx1 did not play on ch0");
            pass = 1'b0;
        end
        mmio_write(ADDR_SFX_LEN, 16'h0000);
    end endtask

    task automatic test_sfx_stop_channel(output bit pass);
        bit ok;
    begin : test_sfx_stop_channel
        pass = 1'b1;
        sfx_cmd(2, 1, 0);
        wait_for_sfx_on_channel(1, 2, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: sfx2 did not start on ch1");
            pass = 1'b0;
            disable test_sfx_stop_channel;
        end
        sfx_cmd(-1, 1, 0);
        wait_for_idle(1, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: sfx(-1,1) did not stop ch1");
            pass = 1'b0;
        end
    end endtask

    task automatic test_sfx_stop_by_index(output bit pass);
        bit ok0, ok1;
    begin : test_sfx_stop_by_index
        pass = 1'b1;
        sfx_cmd(3, 0, 0);
        sfx_cmd(3, 1, 0);
        wait_for_sfx_on_channel(0, 3, PCM_TIMEOUT_SHORT, ok0);
        wait_for_sfx_on_channel(1, 3, PCM_TIMEOUT_SHORT, ok1);
        if (!(ok0 && ok1)) begin
            $display("FAIL: sfx3 not active on ch0/ch1");
            pass = 1'b0;
            disable test_sfx_stop_by_index;
        end
        sfx_cmd(3, -2, 0);
        wait_for_idle(0, PCM_TIMEOUT_SHORT, ok0);
        wait_for_idle(1, PCM_TIMEOUT_SHORT, ok1);
        if (!(ok0 && ok1)) begin
            $display("FAIL: sfx(3,-2) did not stop both channels");
            pass = 1'b0;
        end
    end endtask

    task automatic test_sfx_release_loop(output bit pass);
        bit ok;
        reg [15:0] note_val;
        int last_note;
        int curr_note;
        bit looped;
    begin : test_sfx_release_loop
        pass = 1'b1;
        sfx_cmd(5, 2, 0);
        wait_for_sfx_on_channel(2, 5, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: sfx5 did not start on ch2");
            pass = 1'b0;
            disable test_sfx_release_loop;
        end
        mmio_read(stat_note_addr(2), note_val);
        last_note = note_val[5:0];
        looped = 1'b0;
        for (curr_note = 0; curr_note < 500; curr_note = curr_note + 1) begin
            @(posedge clk_pcm);
            mmio_read(stat_note_addr(2), note_val);
            if (note_val == 16'hffff) begin
                $display("FAIL: looping sfx5 stopped early");
                pass = 1'b0;
                disable test_sfx_release_loop;
            end
            if (note_val[5:0] <= last_note) begin
                looped = 1'b1;
                break;
            end
            last_note = note_val[5:0];
        end
        if (!looped) begin
            $display("FAIL: sfx5 did not loop within 500 pcm ticks");
            pass = 1'b0;
            disable test_sfx_release_loop;
        end
        sfx_cmd(-2, 2, 0);
        wait_for_release(2, PCM_TIMEOUT_MED, ok);
        if (!ok) begin
            $display("FAIL: sfx(-2,2) did not release loop");
            pass = 1'b0;
        end
    end endtask

    task automatic test_sfx_offset_length(output bit pass);
        bit ok;
        reg [15:0] note_val;
        int last_note;
        int count;
    begin : test_sfx_offset_length
        pass = 1'b1;
        mmio_write(ADDR_SFX_LEN, 16'h000A);
        sfx_cmd(4, 3, 16);
        wait_for_sfx_on_channel(3, 4, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: sfx4 did not start on ch3");
            pass = 1'b0;
            disable test_sfx_offset_length;
        end
        mmio_read(stat_note_addr(3), note_val);
        wait_for_note_at_least(3, 6'd16, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: offset not honored");
            pass = 1'b0;
            disable test_sfx_offset_length;
        end
        last_note = -1;
        for (count = 0; count < PCM_TIMEOUT_MED; count = count + 1) begin
            mmio_read(stat_note_addr(3), note_val);
            if (note_val == 16'hffff || note_val[5:0] >= 6'd32) begin
                break;
            end
            last_note = note_val[5:0];
            @(posedge clk_pcm);
        end
        if (last_note != 25) begin
            $display("FAIL: offset+length expected last note 25, got %0d", last_note);
            pass = 1'b0;
        end
        mmio_write(ADDR_SFX_LEN, 16'h0000);
    end endtask

    task automatic test_sfx_offset_length_edges(output bit pass);
        bit ok;
        reg [15:0] note_val;
        int last_note;
        int count;
    begin : test_sfx_offset_length_edges
        pass = 1'b1;
        mmio_write(ADDR_SFX_LEN, 16'h0002);
        sfx_cmd(4, 0, 30);
        wait_for_sfx_on_channel(0, 4, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: sfx4 did not start on ch0");
            pass = 1'b0;
            disable test_sfx_offset_length_edges;
        end
        wait_for_note_at_least(0, 6'd30, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: offset 30 not honored");
            pass = 1'b0;
            disable test_sfx_offset_length_edges;
        end
        last_note = -1;
        for (count = 0; count < PCM_TIMEOUT_MED; count = count + 1) begin
            mmio_read(stat_note_addr(0), note_val);
            if (note_val == 16'hffff || note_val[5:0] >= 6'd32) begin
                break;
            end
            last_note = note_val[5:0];
            @(posedge clk_pcm);
        end
        if (last_note != 31) begin
            $display("FAIL: offset+length expected last note 31, got %0d", last_note);
            pass = 1'b0;
        end
        mmio_write(ADDR_SFX_LEN, 16'h0000);
    end endtask

    task automatic test_sfx_stop_all(output bit pass);
        bit ok0, ok1, ok2;
    begin : test_sfx_stop_all
        pass = 1'b1;
        sfx_cmd(0, 0, 0);
        sfx_cmd(1, 1, 0);
        sfx_cmd(2, 2, 0);
        wait_for_sfx_on_channel(0, 0, PCM_TIMEOUT_SHORT, ok0);
        wait_for_sfx_on_channel(1, 1, PCM_TIMEOUT_SHORT, ok1);
        wait_for_sfx_on_channel(2, 2, PCM_TIMEOUT_SHORT, ok2);
        if (!(ok0 && ok1 && ok2)) begin
            $display("FAIL: setup for sfx(-1) did not start");
            pass = 1'b0;
            disable test_sfx_stop_all;
        end
        sfx_cmd(-1, -1, 0);
        wait_for_idle(0, PCM_TIMEOUT_SHORT, ok0);
        wait_for_idle(1, PCM_TIMEOUT_SHORT, ok1);
        wait_for_idle(2, PCM_TIMEOUT_SHORT, ok2);
        if (!(ok0 && ok1 && ok2)) begin
            $display("FAIL: sfx(-1) did not stop all channels");
            pass = 1'b0;
        end
    end endtask

    task automatic test_sfx_release_all(output bit pass);
        bit ok0, ok1;
    begin : test_sfx_release_all
        pass = 1'b1;
        sfx_cmd(5, 0, 0);
        sfx_cmd(5, 1, 0);
        wait_for_sfx_on_channel(0, 5, PCM_TIMEOUT_SHORT, ok0);
        wait_for_sfx_on_channel(1, 5, PCM_TIMEOUT_SHORT, ok1);
        if (!(ok0 && ok1)) begin
            $display("FAIL: setup for sfx(-2) did not start");
            pass = 1'b0;
            disable test_sfx_release_all;
        end
        sfx_cmd(-2, -1, 0);
        wait_for_release(0, PCM_TIMEOUT_MED, ok0);
        wait_for_release(1, PCM_TIMEOUT_MED, ok1);
        if (!(ok0 && ok1)) begin
            $display("FAIL: sfx(-2) did not release looping on all channels");
            pass = 1'b0;
        end
    end endtask

    task automatic test_sfx_loop_offset_wrap(output bit pass);
        bit ok;
        reg [15:0] note_val;
        int sfx_slot;
        int i;
        int base;
        bit wrapped;
    begin : test_sfx_loop_offset_wrap
        pass = 1'b1;
        sfx_slot = 10;
        base = SFX_BASE + (sfx_slot * SFX_BYTES);

        for (i = 0; i < 16; i = i + 1) begin
            write_note(sfx_slot, i, i * 2, 3'd0, 3'd7, 3'd0);
        end
        base_mem[base + 64] = 8'h01;
        base_mem[base + 65] = 8'd4;
        base_mem[base + 66] = 8'd0;
        base_mem[base + 67] = 8'd15;

        mmio_write(ADDR_SFX_LEN, 16'h0008);
        sfx_cmd(sfx_slot, 0, 12);
        wait_for_sfx_on_channel(0, sfx_slot, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: loop offset sfx did not start on ch0");
            pass = 1'b0;
            disable test_sfx_loop_offset_wrap;
        end

        wrapped = 1'b0;
        for (i = 0; i < PCM_TIMEOUT_LONG; i = i + 1) begin
            mmio_read(stat_note_addr(0), note_val);
            if (note_val == 16'hffff || note_val[5:0] >= 6'd32) begin
                break;
            end
            if (note_val[5:0] < 6'd10) begin
                wrapped = 1'b1;
                break;
            end
            @(posedge clk_pcm);
        end

        if (!wrapped) begin
            $display("FAIL: loop offset sfx did not wrap around");
            pass = 1'b0;
        end
        mmio_write(ADDR_SFX_LEN, 16'h0000);
    end endtask

    task automatic test_multi_channel_play(output bit pass);
        bit ok0, ok1, ok2, ok3;
    begin : test_multi_channel_play
        pass = 1'b1;
        sfx_cmd(6, 0, 0);
        sfx_cmd(7, 1, 0);
        sfx_cmd(8, 2, 0);
        sfx_cmd(9, 3, 0);
        wait_for_sfx_on_channel(0, 6, PCM_TIMEOUT_SHORT, ok0);
        wait_for_sfx_on_channel(1, 7, PCM_TIMEOUT_SHORT, ok1);
        wait_for_sfx_on_channel(2, 8, PCM_TIMEOUT_SHORT, ok2);
        wait_for_sfx_on_channel(3, 9, PCM_TIMEOUT_SHORT, ok3);
        if (!(ok0 && ok1 && ok2 && ok3)) begin
            $display("FAIL: not all channels active");
            pass = 1'b0;
        end
    end endtask

    task automatic test_all_channels_busy_auto_queue(output bit pass);
        bit ok0, ok1, ok2, ok3;
    begin : test_all_channels_busy_auto_queue
        pass = 1'b1;
        mmio_write(ADDR_SFX_LEN, 16'h0002);
        sfx_cmd(0, 0, 0);
        sfx_cmd(1, 1, 0);
        sfx_cmd(2, 2, 0);
        sfx_cmd(3, 3, 0);
        wait_for_sfx_on_channel(0, 0, PCM_TIMEOUT_SHORT, ok0);
        wait_for_sfx_on_channel(1, 1, PCM_TIMEOUT_SHORT, ok1);
        wait_for_sfx_on_channel(2, 2, PCM_TIMEOUT_SHORT, ok2);
        wait_for_sfx_on_channel(3, 3, PCM_TIMEOUT_SHORT, ok3);
        if (!(ok0 && ok1 && ok2 && ok3)) begin
            $display("FAIL: setup for all channels busy failed");
            pass = 1'b0;
            disable test_all_channels_busy_auto_queue;
        end
        sfx_cmd(4, -1, 0);
        // Auto-assign preempts the round-robin selected channel (PICO-8 behavior)
        begin
            int ch_got;
            wait_for_sfx_any(4, PCM_TIMEOUT_LONG, ok0, ch_got);
            if (!ok0) begin
                $display("FAIL: auto-assign did not preempt any channel for sfx4");
                pass = 1'b0;
            end
        end
        mmio_write(ADDR_SFX_LEN, 16'h0000);
    end endtask

    task automatic test_busy_channel_queue(output bit pass);
        bit ok;
    begin : test_busy_channel_queue
        pass = 1'b1;
        mmio_write(ADDR_SFX_LEN, 16'h0003);
        sfx_cmd(0, 1, 0);
        wait_for_sfx_on_channel(1, 0, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: sfx0 did not start on ch1");
            pass = 1'b0;
            disable test_busy_channel_queue;
        end
        sfx_cmd(1, 1, 0);
        wait_for_sfx_on_channel(1, 1, PCM_TIMEOUT_LONG, ok);
        if (!ok) begin
            $display("FAIL: queued sfx1 did not play on busy ch1");
            pass = 1'b0;
        end
        mmio_write(ADDR_SFX_LEN, 16'h0000);
    end endtask

    task automatic test_sfx_explicit_preempt(output bit pass);
        bit ok;
    begin : test_sfx_explicit_preempt
        pass = 1'b1;
        // Start a looping SFX on ch0 so it never finishes naturally
        sfx_cmd(5, 0, 0);
        wait_for_sfx_on_channel(0, 5, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: looping sfx5 did not start on ch0");
            pass = 1'b0;
            disable test_sfx_explicit_preempt;
        end
        // Preempt with sfx1 on the same channel - should start immediately
        sfx_cmd(1, 0, 0);
        wait_for_sfx_on_channel(0, 1, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: sfx1 did not preempt looping sfx5 on ch0 within short timeout");
            pass = 1'b0;
        end
        sfx_cmd(-1, 0, 0);
    end endtask

    task automatic test_pcm_mixing(output bit pass);
        bit ok0, ok1, ok2, ok3, ok4, ok5, ok6;
        int rms1, rms2, rms4;
    begin : test_pcm_mixing
        pass = 1'b1;
        sfx_cmd(9, 0, 0);
        wait_for_sfx_on_channel(0, 9, PCM_TIMEOUT_SHORT, ok0);
        if (!ok0) begin
            $display("FAIL: sfx9 did not start on ch0");
            pass = 1'b0;
            disable test_pcm_mixing;
        end
        pcm_avg_rms(5000, rms1);
        if (rms1 < 2) begin
            $display("FAIL: PCM is silent for single channel");
            pass = 1'b0;
            disable test_pcm_mixing;
        end

        sfx_cmd(-1, 0, 0);

        sfx_cmd(9, 0, 0);
        sfx_cmd(9, 1, 0);
        wait_for_sfx_on_channel(0, 9, PCM_TIMEOUT_SHORT, ok1);
        wait_for_sfx_on_channel(1, 9, PCM_TIMEOUT_SHORT, ok2);
        if ((!ok1) || (!ok2)) begin
            $display("FAIL: sfx9 did not start on ch0/ch1");
            pass = 1'b0;
            disable test_pcm_mixing;
        end
        pcm_avg_rms(5000, rms2);
        if (rms2 < (rms1 * 3) / 2) begin
            $display("FAIL: PCM mix not ~2x for two channels");
            pass = 1'b0;
            disable test_pcm_mixing;
        end

        sfx_cmd(-1, 0, 0);

        sfx_cmd(9, 0, 0);
        sfx_cmd(9, 1, 0);
        sfx_cmd(9, 2, 0);
        sfx_cmd(9, 3, 0);
        wait_for_sfx_on_channel(0, 9, PCM_TIMEOUT_SHORT, ok3);
        wait_for_sfx_on_channel(1, 9, PCM_TIMEOUT_SHORT, ok4);
        wait_for_sfx_on_channel(2, 9, PCM_TIMEOUT_SHORT, ok5);
        wait_for_sfx_on_channel(3, 9, PCM_TIMEOUT_SHORT, ok6);
        if ((!ok3) || (!ok4) || (!ok5) || (!ok6)) begin
            $display("FAIL: sfx9 did not start on ch0/ch1/ch2/ch3");
            pass = 1'b0;
            disable test_pcm_mixing;
        end
        pcm_avg_rms(5000, rms4);
        if (rms4 < rms2 + 2) begin
            $display("FAIL: PCM mix not higher for four channels");
            pass = 1'b0;
        end
    end endtask

    task automatic test_sfx_over_music(output bit pass);
        bit ok;
    begin : test_sfx_over_music
        pass = 1'b1;
        music_cmd(0, 16'h0000, 4'h7);
        wait_for_sfx_on_channel(0, 0, PCM_TIMEOUT_LONG, ok);
        if (!ok) begin
            $display("FAIL: music did not start on ch0");
            pass = 1'b0;
            disable test_sfx_over_music;
        end
        mmio_write(ADDR_SFX_LEN, 16'h0000);
        sfx_cmd(4, 0, 0);
        wait_for_sfx_on_channel(0, 4, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: sfx4 did not override music on ch0");
            pass = 1'b0;
            disable test_sfx_over_music;
        end
        mmio_write(ADDR_SFX_LEN, 16'h0000);
        music_cmd(-1, 16'h0000, 0);
    end endtask

    task automatic test_sfx_stop_release_while_music(output bit pass);
        bit ok;
    begin : test_sfx_stop_release_while_music
        pass = 1'b1;
        music_cmd(0, 16'h0000, 4'h7);
        wait_for_sfx_on_channel(1, 1, PCM_TIMEOUT_LONG, ok);
        if (!ok) begin
            $display("FAIL: music did not start on ch1");
            pass = 1'b0;
            disable test_sfx_stop_release_while_music;
        end
        sfx_cmd(5, 3, 0);
        wait_for_sfx_on_channel(3, 5, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: sfx5 did not start on ch3");
            pass = 1'b0;
            disable test_sfx_stop_release_while_music;
        end
        sfx_cmd(-1, 3, 0);
        wait_for_idle(3, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: sfx(-1,3) did not stop ch3");
            pass = 1'b0;
            disable test_sfx_stop_release_while_music;
        end
        sfx_cmd(5, 3, 0);
        wait_for_sfx_on_channel(3, 5, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: sfx5 did not restart on ch3");
            pass = 1'b0;
            disable test_sfx_stop_release_while_music;
        end
        sfx_cmd(-2, 3, 0);
        wait_for_release(3, PCM_TIMEOUT_MED, ok);
        if (!ok) begin
            $display("FAIL: sfx(-2,3) did not release loop");
            pass = 1'b0;
            disable test_sfx_stop_release_while_music;
        end
        wait_for_music_pattern(6'd1, PCM_TIMEOUT_XLONG, ok);
        if (!ok) begin
            $display("FAIL: music stopped advancing during sfx stop/release");
            pass = 1'b0;
        end
        music_cmd(-1, 16'h0000, 0);
    end endtask

    task automatic test_music_basic(output bit pass);
        bit ok;
        reg [15:0] stat_val;
        integer i;
    begin : test_music_basic
        pass = 1'b1;
        music_cmd(0, 16'h0000, 4'h7);
        wait_for_music_playing(PCM_TIMEOUT_LONG, ok);
        if (!ok) begin
            $display("FAIL: music did not start playing");
            pass = 1'b0;
            disable test_music_basic;
        end
        mmio_read(ADDR_STAT54, stat_val);
        if (stat_val[5:0] != 6'd0) begin
            $display("FAIL: music did not start at pattern 0");
            pass = 1'b0;
            disable test_music_basic;
        end
        wait_for_music_pattern(6'd1, PCM_TIMEOUT_XLONG, ok);
        if (!ok) begin
            $display("FAIL: music did not advance to pattern 1");
            pass = 1'b0;
            disable test_music_basic;
        end
        music_cmd(-1, 16'h0000, 0);
        repeat (200) @(posedge clk_pcm);
        mmio_read(ADDR_STAT57, stat_val);
        if (stat_val[0]) begin
            $display("FAIL: music still playing after stop command");
            pass = 1'b0;
        end
    end endtask

    task automatic test_music_mask(output bit pass);
        bit ok0, ok1, ok2, ok3;
    begin : test_music_mask
        pass = 1'b1;
        // channel 1 masked only
        music_cmd(0, 16'h0000, 4'h2);
        wait_for_sfx_on_channel(0, 0, PCM_TIMEOUT_LONG, ok0);
        wait_for_sfx_on_channel(1, 1, PCM_TIMEOUT_LONG, ok1);
        wait_for_sfx_on_channel(2, 2, PCM_TIMEOUT_LONG, ok2);
        if (!(ok0 && ok1 && ok2)) begin
            $display("FAIL: music did not start on ch0/ch1/ch2");
            pass = 1'b0;
            disable test_music_mask;
        end
        // ch3 is disabled in pattern 0 so should remain idle
        ensure_idle_for(3, 4000, ok3);
        if (!ok3) begin
            $display("FAIL: music started ch3 but pattern 0 has ch3 disabled");
            pass = 1'b0;
            disable test_music_mask;
        end
        sfx_cmd(7, -1, 0);
        wait_for_sfx_on_channel(3, 7, PCM_TIMEOUT_LONG, ok3);
        if (!ok3) begin
            $display("FAIL: auto sfx did not use ch3 when music playing on other channels");
            pass = 1'b0;
            disable test_music_mask;
        end
        sfx_cmd(8, -1, 0);
        wait_for_sfx_on_channel(0, 8, PCM_TIMEOUT_LONG, ok0);
        if (!ok0) begin
            $display("FAIL: auto sfx did not use ch0 when sfx playing on all channels and ch0 not masked");
            pass = 1'b0;
            disable test_music_mask;
        end
        sfx_cmd(9, -1, 0);
        wait_for_sfx_on_channel(2, 9, PCM_TIMEOUT_LONG, ok2);
        if (!ok2) begin
            $display("FAIL: auto sfx did not use ch2 when sfx playing on all channels and ch2 masked");
            pass = 1'b0;
            disable test_music_mask;
        end
        music_cmd(-1, 16'h0000, 0);
        sfx_cmd(-1, 0, 0);
        sfx_cmd(-1, 2, 0);
        sfx_cmd(-1, 3, 0);
        wait_for_idle(0, PCM_TIMEOUT_SHORT, ok0);
        wait_for_idle(1, PCM_TIMEOUT_SHORT, ok1);
        wait_for_idle(2, PCM_TIMEOUT_SHORT, ok2);
        wait_for_idle(3, PCM_TIMEOUT_SHORT, ok3);
    end endtask

    task automatic test_sfx_rapid_preempt(output bit pass);
        bit ok;
    begin : test_sfx_rapid_preempt
        pass = 1'b1;
        // Trigger sfx0 on ch0, then immediately sfx1 on ch0 (one mclk cycle between writes).
        // The DMA for sfx0 may not have started yet when sfx1 is triggered.
        // sfx1 must win and play on ch0.
        sfx_cmd(0, 0, 0);
        sfx_cmd(1, 0, 0);  // back-to-back: 1 mclk gap between write pulses
        wait_for_sfx_on_channel(0, 1, PCM_TIMEOUT_SHORT, ok);
        if (!ok) begin
            $display("FAIL: rapid-fire sfx1 did not preempt sfx0 on ch0");
            pass = 1'b0;
        end
        sfx_cmd(-1, 0, 0);
    end endtask

    task automatic test_music_loop_fade(output bit pass);
        bit ok0, ok1, ok2;
    begin : test_music_loop_fade
        pass = 1'b1;
        music_cmd(0, 16'h0000, 4'h7);
        wait_for_sfx_on_channel(0, 0, PCM_TIMEOUT_LONG, ok0);
        wait_for_sfx_on_channel(1, 1, PCM_TIMEOUT_LONG, ok1);
        wait_for_sfx_on_channel(2, 2, PCM_TIMEOUT_LONG, ok2);
        if (!(ok0 && ok1 && ok2)) begin
            $display("FAIL: music did not start on ch0-2");
            pass = 1'b0;
            disable test_music_loop_fade;
        end
        sfx_cmd(3, -1, 0);
        wait_for_sfx_on_channel(3, 3, PCM_TIMEOUT_LONG, ok0);
        if (!ok0) begin
            $display("FAIL: auto sfx did not use ch3 with music mask");
            pass = 1'b0;
            disable test_music_loop_fade;
        end
        sfx_cmd(2, 0, 0);
        wait_for_sfx_on_channel(0, 2, PCM_TIMEOUT_LONG, ok0);
        if (!ok0) begin
            $display("FAIL: explicit sfx did not override music mask on ch0");
            pass = 1'b0;
            disable test_music_loop_fade;
        end
        wait_for_music_pattern(6'd1, PCM_TIMEOUT_XLONG, ok0);
        if (!ok0) begin
            $display("FAIL: music loop did not advance as expected");
            pass = 1'b0;
            disable test_music_loop_fade;
        end
        wait_for_music_pattern(6'd0, PCM_TIMEOUT_XLONG, ok0);
        if (!ok0) begin
            $display("FAIL: music loop did not wrap to pattern 0");
            pass = 1'b0;
            disable test_music_loop_fade;
        end
        music_cmd(-1, 16'h0000, 0);
        repeat (2000) @(posedge clk_pcm);
        wait_for_idle(0, PCM_TIMEOUT_LONG, ok0);
        wait_for_idle(1, PCM_TIMEOUT_LONG, ok1);
        wait_for_idle(2, PCM_TIMEOUT_LONG, ok2);
        if (!(ok0 && ok1 && ok2)) begin
            $display("FAIL: music stop did not idle channels");
            pass = 1'b0;
        end
    end endtask

    task automatic test_music_fade_out_time(output bit pass);
        bit ok;
        reg [15:0] val;
        int count;
        int expected;
        int tolerance;
    begin : test_music_fade_out_time
        pass = 1'b1;
        expected = 6615;   // 300ms at 22.05kHz
        tolerance = 200;

        music_cmd(0, expected, 4'h7);
        wait_for_music_playing(PCM_TIMEOUT_LONG, ok);
        if (!ok) begin
            $display("FAIL: music did not start for fade timing test");
            pass = 1'b0;
            disable test_music_fade_out_time;
        end

        music_cmd(-1, expected, 0);
        for (count = 0; count < PCM_TIMEOUT_XLONG; count = count + 1) begin
            mmio_read(ADDR_STAT57, val);
            if (!val[0]) begin
                break;
            end
            @(posedge clk_pcm);
        end

        if (count < (expected - tolerance)) begin
            $display("FAIL: fade too fast: %0d samples (expected ~%0d)", count, expected);
            pass = 1'b0;
        end else if (count > (expected + tolerance)) begin
            $display("FAIL: fade too slow: %0d samples (expected ~%0d)", count, expected);
            pass = 1'b0;
        end

        mmio_write(ADDR_MUSIC_FADE, 16'h0000);
    end endtask

    task automatic test_music_advance_timing(output bit pass);
        bit ok0, ok1, ok2;
        reg [15:0] pat_val;
    begin : test_music_advance_timing
        pass = 1'b1;
        music_cmd(2, 16'h0000, 4'h7);
        wait_for_sfx_on_channel(0, 11, PCM_TIMEOUT_LONG, ok0);
        wait_for_sfx_on_channel(1, 12, PCM_TIMEOUT_LONG, ok1);
        wait_for_sfx_on_channel(2, 13, PCM_TIMEOUT_LONG, ok2);
        if (!(ok0 && ok1 && ok2)) begin
            $display("FAIL: music pattern 2 did not start on ch0-2");
            pass = 1'b0;
            disable test_music_advance_timing;
        end
        wait_for_idle(2, PCM_TIMEOUT_LONG, ok2);
        if (!ok2) begin
            $display("FAIL: channel 2 (faster) did not finish");
            pass = 1'b0;
            disable test_music_advance_timing;
        end
        repeat (500) @(posedge clk_pcm);
        mmio_read(ADDR_STAT54, pat_val);
        if (pat_val[5:0] != 6'd2) begin
            $display("FAIL: music advanced before leftmost non-looping channel finished");
            pass = 1'b0;
            disable test_music_advance_timing;
        end
        wait_for_idle(1, PCM_TIMEOUT_LONG, ok1);
        if (!ok1) begin
            $display("FAIL: channel 1 (leftmost non-looping) did not finish");
            pass = 1'b0;
            disable test_music_advance_timing;
        end
        repeat (500) @(posedge clk_pcm);
        mmio_read(ADDR_STAT54, pat_val);
        if (pat_val[5:0] == 6'd2) begin
            $display("FAIL: music did not advance after leftmost non-looping channel finished");
            pass = 1'b0;
        end
        music_cmd(-1, 16'h0000, 0);
    end endtask

    task automatic run_test(input string name, input int test_id, input bit use_setup);
        bit pass;
    begin
        tf_start_test(name);
        if (use_setup) begin
            test_setup();
        end
        case (test_id)
            0: test_p8audio_version(pass);
            1: test_sfx_auto_channel(pass);
            2: test_sfx_explicit_queue(pass);
            3: test_sfx_stop_channel(pass);
            4: test_sfx_stop_by_index(pass);
            5: test_sfx_release_loop(pass);
            6: test_sfx_offset_length(pass);
            7: test_sfx_offset_length_edges(pass);
            8: test_sfx_loop_offset_wrap(pass);
            9: test_sfx_stop_all(pass);
            10: test_sfx_release_all(pass);
            11: test_multi_channel_play(pass);
            12: test_all_channels_busy_auto_queue(pass);
            13: test_busy_channel_queue(pass);
            14: test_pcm_mixing(pass);
            15: test_sfx_over_music(pass);
            16: test_sfx_stop_release_while_music(pass);
            17: test_music_basic(pass);
            18: test_music_mask(pass);
            19: test_music_loop_fade(pass);
            20: test_music_fade_out_time(pass);
            21: test_music_advance_timing(pass);
            22: test_sfx_explicit_preempt(pass);
            23: test_sfx_rapid_preempt(pass);
            default: begin
                $display("Unknown test id: %0d", test_id);
                pass = 1'b0;
            end
        endcase
        if (use_setup) begin
            test_cleanup();
        end
        tf_end_test(name, pass);
    end endtask

    initial begin : init_and_run
        integer i;
        address = 0;
        din = 0;
        write_en = 0;
        read_en = 0;
        nUDS = 1'b1;
        nLDS = 1'b1;
        dma_ack = 0;
        dma_rdata = 0;

        for (i = 0; i < 65536; i = i + 1) begin
            base_mem[i] = 8'h00;
        end

        init_audio_memory();

        #200; resetn = 1'b1;

        tf_init();
        tf_start_suite("p8audio_api");

        run_test("p8audio_version", 0, 1'b0);
        run_test("sfx_auto_channel", 1, 1'b1);
        run_test("sfx_explicit_queue", 2, 1'b1);
        run_test("sfx_stop_channel", 3, 1'b1);
        run_test("sfx_stop_by_index", 4, 1'b1);
        run_test("sfx_release_loop", 5, 1'b1);
        run_test("sfx_offset_length", 6, 1'b1);
        run_test("sfx_offset_length_edges", 7, 1'b1);
        run_test("sfx_loop_offset_wrap", 8, 1'b1);
        run_test("sfx_stop_all", 9, 1'b1);
        run_test("sfx_release_all", 10, 1'b1);
        run_test("multi_channel_play", 11, 1'b1);
        run_test("all_channels_busy_auto_queue", 12, 1'b1);
        run_test("busy_channel_queue", 13, 1'b1);
        run_test("pcm_mixing", 14, 1'b1);
        run_test("sfx_over_music", 15, 1'b1);
        run_test("sfx_stop_release_while_music", 16, 1'b1);
        run_test("music_basic", 17, 1'b1);
        run_test("music_mask", 18, 1'b1);
        run_test("music_loop_fade", 19, 1'b1);
        run_test("music_fade_out_time", 20, 1'b1);
        run_test("music_advance_timing", 21, 1'b1);
        run_test("sfx_explicit_preempt", 22, 1'b1);
        run_test("sfx_rapid_preempt", 23, 1'b1);

        tf_summary();
        if (tf_fail != 0) begin
            $fatal(1, "Test failures");
        end
        $finish;
    end
endmodule
