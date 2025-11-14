//================================================================
// tb_p8audio_sfx.v
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

module tb_p8audio_sfx;
    //====================
    // Clocks & Reset
    //====================
    reg clk_sys = 1'b0;     // 33 MHz system clock
    reg clk_pcm = 1'b0;     // ~22.05 kHz PCM sample clock
    reg clk_pcm_8x = 1'b0;  // 8× PCM sample clock for time-multiplexing
    reg resetn  = 1'b0;

    // 33MHz: 30ns period
    always #15 clk_sys = ~clk_sys;
    // 22.05kHz: ~45.351us period
    //localparam integer PCM_HALF_NS = 1000000000/22050/2; // 22.675us ~ 44.101kHz
    // Note: the test bench runs the PCM clock at 1000x to reduce simulation time.
    localparam integer PCM_HALF_NS = 1000000/22050/2; // 22.675ns ~ 44.101MHz
    always #(PCM_HALF_NS) clk_pcm = ~clk_pcm;
    // 8× PCM rate: ~352.8MHz, period ~2.835ns
    always #(PCM_HALF_NS/8) clk_pcm_8x = ~clk_pcm_8x;

    //====================
    // MMIO signals
    //====================
    reg  [6:0]  address;
    reg  [15:0] din;
    wire [15:0] dout;
    reg         nUDS, nLDS;
    reg         write_en, read_en;

    // MMIO register addresses (mirror of p8audio.sv)
    localparam [6:0] ADDR_CTRL        = 7'h01;
    localparam [6:0] ADDR_SFX_BASE_HI = 7'h02;
    localparam [6:0] ADDR_SFX_BASE_LO = 7'h03;
    localparam [6:0] ADDR_NOTE_ATK    = 7'h08;
    localparam [6:0] ADDR_NOTE_REL    = 7'h09;
    localparam [6:0] ADDR_SFX_CMD     = 7'h0A;
    localparam [6:0] ADDR_SFX_LEN     = 7'h0B;

    //====================
    // PCM output
    //====================
    wire signed [7:0] pcm_out;

    //====================
    // DMA interface
    //====================
    wire [30:0] dma_addr; // word address
    reg  [15:0] dma_rdata;
    wire        dma_req;
    reg         dma_ack;

    //====================
    // DUT: p8audio
    //====================
    p8audio dut (
        .clk_sys(clk_sys), .clk_pcm(clk_pcm), .clk_pcm_8x(clk_pcm_8x), .resetn(resetn),
        .address(address), .din(din), .dout(dout), .nUDS(nUDS), .nLDS(nLDS), .write_en(write_en), .read_en(read_en),
        .pcm_out(pcm_out),
        .dma_addr(dma_addr), .dma_rdata(dma_rdata), .dma_req(dma_req), .dma_ack(dma_ack)
    );

    //====================
    // Fake Base RAM (bytes)
    //====================
    // Allocate 64KB for convenience
    reg [7:0] base_mem [0:65535];

    // Provide 16-bit big-endian data on DMA reads from byte-addressed memory.
    // Combinatorial data output, registered ack
    wire [15:0] byte_addr = dma_addr[15:0] * 2;

    // Combinatorial read - data available immediately
    always @* begin
        dma_rdata = { base_mem[byte_addr], base_mem[byte_addr+16'd1] };
    end

    // Registered ack
    always @(posedge clk_sys or negedge resetn) begin
        if (!resetn) begin
            dma_ack   <= 1'b0;
        end else begin
            if (dma_req && !dma_ack) begin
                dma_ack   <= 1'b1;
                $display("TB DMA: word_addr=0x%08h, byte_addr=0x%04h, mem[%04h]=0x%02h, mem[%04h]=0x%02h, rdata=0x%04h",
                         dma_addr, byte_addr, byte_addr, base_mem[byte_addr], byte_addr+16'd1, base_mem[byte_addr+16'd1],
                         {base_mem[byte_addr], base_mem[byte_addr+16'd1]});
            end else begin
                dma_ack <= 1'b0;
            end
        end
    end

    //====================
    // Helpers: MMIO write/read
    //====================
    task mmio_write(input [6:0] a, input [15:0] d);
    begin
        @(posedge clk_sys); address<=a; din<=d; write_en<=1'b1; read_en<=1'b0; nUDS<=1'b0; nLDS<=1'b0;
        @(posedge clk_sys); write_en<=1'b0; nUDS<=1'b1; nLDS<=1'b1;
    end endtask

    task mmio_read(input [6:0] a, output [15:0] d);
    begin
        @(posedge clk_sys); address<=a; write_en<=1'b0; read_en<=1'b1; nUDS<=1'b0; nLDS<=1'b0;
        @(posedge clk_sys); d = dout; read_en<=1'b0; nUDS<=1'b1; nLDS<=1'b1;
    end endtask

    //====================
    // SFX Base and loader for PICO-8 .p8 __sfx__ block
    //====================
    localparam integer SFX_BYTES = 68;
    localparam [15:0]  SFX_BASE  = 16'h3200; // byte address

    // Helpers for hex parsing
    function integer hex_nibble;
        input [7:0] ch;
        begin
            if (ch >= "0" && ch <= "9") hex_nibble = ch - "0";
            else if (ch >= "a" && ch <= "f") hex_nibble = 10 + (ch - "a");
            else if (ch >= "A" && ch <= "F") hex_nibble = 10 + (ch - "A");
            else hex_nibble = -1;
        end
    endfunction

    function is_space;
        input [7:0] ch;
        begin
            is_space = ((ch == " " || ch == "\t" || ch == "\r" || ch == "\n") ? 1'b1 : 1'b0);
        end
    endfunction

    // Load __sfx__ section from a .p8 text file into base_mem
    // Converts from on-disk format (84 bytes) to in-memory format (68 bytes)
    task load_p8_sfx(input [1023:0] filename);
        integer fd, ch;
        reg in_sfx;
        integer sfx_idx;
        reg [7:0] linebuf [0:511];
        integer lb_len;
        integer i, j, s, e;
        integer nybble_idx, val;
        integer base, mem_base;
        reg [7:0] disk_bytes [0:83];  // On-disk format: 84 bytes
        reg [3:0] nybbles [0:167];    // 168 nybbles from disk
        integer nybble_cnt;
    begin
        fd = $fopen(filename, "r");
        if (fd == 0) begin
            $display("ERROR: could not open %0s", filename);
            $finish;
        end else begin
            in_sfx = 0; sfx_idx = 0; lb_len = 0;
            // clear SFX region
            for (i=0;i<64*SFX_BYTES;i=i+1) base_mem[{16'd0, SFX_BASE} + i] = 8'h00;
            while ((ch = $fgetc(fd)) != -1) begin
                if (ch == "\n") begin
                    // process the line in linebuf[0..lb_len-1]
                    // trim
                    s = 0; e = lb_len;
                    while (s < e && is_space(linebuf[s])) s = s + 1;
                    while (e > s && is_space(linebuf[e-1])) e = e - 1;
                    if (e > s) begin
                        // detect section markers
                        if (!in_sfx) begin
                            if ((e - s) >= 7 &&
                                linebuf[s+0] == "_" && linebuf[s+1] == "_" && linebuf[s+2] == "s" &&
                                linebuf[s+3] == "f" && linebuf[s+4] == "x" && linebuf[s+5] == "_" && linebuf[s+6] == "_") begin
                                in_sfx = 1;
                            end
                        end else begin
                            // if next section starts, stop
                            if ((e - s) >= 2 && linebuf[s] == "_" && linebuf[s+1] == "_") begin
                                in_sfx = 0;
                            end else if (sfx_idx < 64) begin
                                // Parse 168 hex nybbles from disk (84 bytes MSB-first)
                                nybble_cnt = 0;
                                for (i = s; i < e && nybble_cnt < 168; i = i + 1) begin
                                    val = hex_nibble(linebuf[i]);
                                    if (val >= 0) begin
                                        nybbles[nybble_cnt] = val[3:0];
                                        nybble_cnt = nybble_cnt + 1;
                                    end
                                end

                                if (nybble_cnt >= 168) begin
                                    // Convert to in-memory format
                                    mem_base = {16'd0, SFX_BASE} + sfx_idx*SFX_BYTES;

                                    // Bytes 0-3 on disk (8 nybbles) -> bytes 64-67 in memory
                                    base_mem[mem_base + 64] = {nybbles[0], nybbles[1]};  // editor mode/filters
                                    base_mem[mem_base + 65] = {nybbles[2], nybbles[3]};  // speed
                                    base_mem[mem_base + 66] = {nybbles[4], nybbles[5]};  // loop start
                                    base_mem[mem_base + 67] = {nybbles[6], nybbles[7]};  // loop end

                                    // Bytes 4-83 on disk (160 nybbles) -> 32 notes (64 bytes) in memory
                                    // Disk: 5 nybbles/note (pitch[2], wave, vol, effect)
                                    // Memory: 16-bit little-endian (custom, effect[3], vol[3], wave[3], pitch[6])
                                    for (i = 0; i < 32; i = i + 1) begin
                                        integer byte_offset;
                                        integer note_pitch, note_waveform, note_volume, note_effect;
                                        integer note_word;

                                        // Each note is 5 nybbles, starting at byte 4
                                        byte_offset = 8 + i * 5;  // nybble offset: 8 (header) + i * 5

                                        // Decode note
                                        note_pitch = {nybbles[byte_offset + 0], nybbles[byte_offset + 1]};
                                        note_waveform = nybbles[byte_offset + 2];
                                        note_volume = nybbles[byte_offset + 3];
                                        note_effect = nybbles[byte_offset + 4];

                                        // Encode note to in-memory format (16-bit little-endian)
                                        note_word = ((note_waveform > 7 ? 1 : 0) << 15) |
                                                    (note_effect << 12) |
                                                    (note_volume << 9) |
                                                    ((note_waveform > 7 ? note_waveform - 8 : note_waveform) << 6) |
                                                    note_pitch;

                                        // Write to memory (little-endian: low byte first)
                                        base_mem[mem_base + (i*2) + 0] = note_word[7:0];
                                        base_mem[mem_base + (i*2) + 1] = note_word[15:8];
                                    end
                                end

                                // advance to next SFX slot
                                sfx_idx = sfx_idx + 1;
                            end
                        end
                    end
                    // reset buffer for next line
                    lb_len = 0;
                end else begin
                    if (lb_len < 512) begin
                        linebuf[lb_len] = ch[7:0];
                        lb_len = lb_len + 1;
                    end
                end
            end
            $fclose(fd);

            $display("Loaded %0d SFX slots from %0s", sfx_idx, filename);
        end
    end endtask

    // Dump SFX memory contents in hex format
    task dump_sfx_memory();
        integer addr, i;
        reg [7:0] bytes [0:67];
    begin
        $display("=== SFX Memory Dump ===");
        // Dump 64 SFX slots * 68 bytes = 4352 bytes (0x3200 to 0x42FF)
        for (addr = {16'd0, SFX_BASE}; addr < {16'd0, SFX_BASE} + 64*SFX_BYTES; addr = addr + 68) begin
            // Read 68 bytes from base_mem
            for (i = 0; i < 68; i = i + 1) begin
                bytes[i] = base_mem[addr + i];
            end
            // Print in format: <4 hex addr> <2 hex>*68
            $display("%04x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x",
                     addr[15:0],
                     bytes[ 0], bytes[ 1], bytes[ 2], bytes[ 3], bytes[ 4], bytes[ 5], bytes[ 6], bytes[ 7],
                     bytes[ 8], bytes[ 9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
                     bytes[16], bytes[17], bytes[18], bytes[19], bytes[20], bytes[21], bytes[22], bytes[23],
                     bytes[24], bytes[25], bytes[26], bytes[27], bytes[28], bytes[29], bytes[30], bytes[31],
                     bytes[32], bytes[33], bytes[34], bytes[35], bytes[36], bytes[37], bytes[38], bytes[39],
                     bytes[40], bytes[41], bytes[42], bytes[43], bytes[44], bytes[45], bytes[46], bytes[47],
                     bytes[48], bytes[49], bytes[50], bytes[51], bytes[52], bytes[53], bytes[54], bytes[55],
                     bytes[56], bytes[57], bytes[58], bytes[59], bytes[60], bytes[61], bytes[62], bytes[63],
                     bytes[64], bytes[65], bytes[66], bytes[67]);
        end
        $display("=== End SFX Memory Dump ===");
    end endtask

    //====================
    // WAV writer (mono, 16-bit, SR=22050)
    //====================
    localparam integer WAV_SR = 22050;
    task wav_write_header(input integer f, input integer n_samples);
        integer bytes, br;
    begin
        bytes = n_samples * 2; // 16-bit mono
        br = WAV_SR * 2;       // bytes/sec
        // RIFF header
        $fwrite(f, "RIFF");
        $fwrite(f, "%c%c%c%c", (bytes+36)&255, ((bytes+36)>>8)&255, ((bytes+36)>>16)&255, ((bytes+36)>>24)&255);
        $fwrite(f, "WAVEfmt ");
        $fwrite(f, "%c%c%c%c", 16,0,0,0); // PCM chunk size
        $fwrite(f, "%c%c", 1,0);          // PCM format
        $fwrite(f, "%c%c", 1,0);          // channels=1
        $fwrite(f, "%c%c%c%c", WAV_SR&255,(WAV_SR>>8)&255,(WAV_SR>>16)&255,(WAV_SR>>24)&255);
        $fwrite(f, "%c%c%c%c", br&255,(br>>8)&255,(br>>16)&255,(br>>24)&255);
        $fwrite(f, "%c%c", 2,0);          // block align
        $fwrite(f, "%c%c", 16,0);         // bits per sample
        $fwrite(f, "data");
        $fwrite(f, "%c%c%c%c", bytes&255,(bytes>>8)&255,(bytes>>16)&255,(bytes>>24)&255);
    end endtask

    //====================
    // Test sequence
    //====================
    integer sfx_idx;
    integer wav;
    integer n_samples;
    integer count;
    reg [1023:0] p8_path;
    localparam integer SAMPLES_PER_TICK = 183;
    localparam integer NOTES_PER_SFX = 32;

    initial begin : init_and_run
        integer i;
        integer plusarg_found;
        // Init signals
        address=0; din=0; write_en=0; read_en=0; nUDS=1'b1; nLDS=1'b1; dma_ack=0; dma_rdata=0;
        for (i=0;i<65536;i=i+1) base_mem[i]=8'h00;

        // Select PICO-8 cart path via +CART=... or default to tb_p8audio_sfx.p8
        p8_path = "tb_p8audio_sfx.p8";
        plusarg_found = $value$plusargs("CART=%s", p8_path);
        $display("Using P8 cart: %0s", p8_path);
        // Load SFX from PICO-8 cart file
        load_p8_sfx(p8_path);

        // Dump SFX memory contents
        dump_sfx_memory();

        // Verify memory contents at key locations
        $display("Memory check: base_mem[0x3240]=0x%02h, base_mem[0x3241]=0x%02h",
                 base_mem[16'h3240], base_mem[16'h3241]);

        // Release reset
        #200; resetn=1'b1;
        // Configure SFX base @0x3200 and RUN=1
        mmio_write(ADDR_SFX_BASE_HI, 16'h0000);   // SFX_BASE_HI
        mmio_write(ADDR_SFX_BASE_LO, SFX_BASE);   // SFX_BASE_LO
        mmio_write(ADDR_CTRL,        16'h0001);   // CTRL.RUN=1
        // Default attack/release
        mmio_write(ADDR_NOTE_ATK,    16'd20);
        mmio_write(ADDR_NOTE_REL,    16'd20);

        // Sweep SFX 8..21, capture duration derived from SFX speed (byte 65)

        for (sfx_idx=8; sfx_idx<=21; sfx_idx=sfx_idx+1) begin
            integer speed, ticks, quot, rem;
            // speed byte is at offset 65 within each 68-byte SFX slot
            speed = {24'd0, base_mem[{16'd0, SFX_BASE} + sfx_idx*SFX_BYTES + 65]};
            ticks = NOTES_PER_SFX * speed;
            n_samples = ticks * SAMPLES_PER_TICK;

            $display("Load SFX %d...", sfx_idx);

            // Write length override = 0 (full SFX)
            mmio_write(ADDR_SFX_LEN, 16'd0);
            // Trigger on channel 0: SFX_CMD bit15=1, ch=0, off=0, idx=sfx_idx
            mmio_write(ADDR_SFX_CMD, {1'b1, 3'b000, 6'd0, sfx_idx[5:0]});

            // Wait for the SFX to load and  warm up
            count = 0;
            while (count < 200 && dut.core_mux_inst.pcm_state[1] != dut.core_mux_inst.PCM_PLAYING) begin
                @(posedge clk_pcm);
                count = count + 1;
            end
            assert(count != 200) else $error("SFX %d failed to load.", sfx_idx);
            $display("SFX %d loaded and playing.", sfx_idx);

            // Open WAV file tb_p8audio_sfx_out_XX.wav
            // iverilog supports $sformatf for filename formatting
            $display("Start recording...");
            wav = $fopen($sformatf("tb_p8audio_sfx_out_%0d.wav", sfx_idx), "wb");
            wav_write_header(wav, n_samples);

            count=0;
            // Capture at the PCM clock
            while (count < n_samples) begin
                // Write little-endian PCM samples as bytes
                $fwrite(wav, "%c%c", 8'd0, pcm_out[7:0]);
                @(posedge clk_pcm);
                count = count + 1;
            end
            $fclose(wav);
            $display("Wrote tb_p8audio_sfx_out_%0d.wav (speed=%d, ticks=%d, %d samples)", sfx_idx, speed, ticks, n_samples);

            // Force stop channel 0 before playing the next SFX
            // SFX_CMD format: [15]=1 (cmd), [14:12]=channel, [11:6]=offset, [5:0]=index
            // index=6'h3f encodes STOP (N=-1)
            mmio_write(ADDR_SFX_CMD, {1'b1, 3'b000, 6'd0, 6'h3f});

            // Let it settle a couple of PCM cycles before next SFX
            repeat (10) @(posedge clk_pcm);
        end

        $display("All SFX WAVs written.");
        $finish;
    end

endmodule
