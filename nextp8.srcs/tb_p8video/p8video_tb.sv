`timescale 1ns/1ns

//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2025 Chris January
//////////////////////////////////////////////////////////////////////////////////

module p8video_tb #(
    parameter ENABLE_OVERLAY = 0,
    parameter SCREEN_TRANSFORM = 0,
    parameter HIGH_COLOR_MODE = 0
)();

//Clock
reg clk_video = 0;  // 10.78MHz video clock
reg mclk = 0;
always #93 clk_video = ~clk_video;  // 10.78MHz (period ~92.8ns)
always #33 mclk = ~mclk; // ~30MHz for CPU clock

// ---------------------------------------------------------------------------------
// -------------------------------------- video ------------------------------------
// ---------------------------------------------------------------------------------

reg  [12:0] vaddr1_main;
wire [12:0] vaddr2_main;
wire [15:0] vdout1_main;
wire [15:0] vdout2_main;
reg [15:0] vdin1_main=16'd0;
reg [1:0] vw1_main=2'b00;

reg  [12:0] vaddr1_overlay;
wire [12:0] vaddr2_overlay;
wire [15:0] vdout1_overlay;
wire [15:0] vdout2_overlay;
reg [15:0] vdin1_overlay=16'd0;
reg [1:0] vw1_overlay=2'b00;
reg vfrontreq=1'b0;

reg overlay_enable = 1'b0;
reg [3:0] overlay_key_colour = 4'd0;


vram_main vram_main (
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

vram_overlay vram_overlay (
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

reg reset = 0;

// Reset synchronizers
reg reset_mclk_d = 1, reset_mclk_q = 1;
reg reset_video_d = 1, reset_video_q = 1;

always @(posedge mclk or posedge reset) begin
    if (reset) begin
        reset_mclk_d <= 1'b1;
        reset_mclk_q <= 1'b1;
    end else begin
        reset_mclk_d <= 1'b0;
        reset_mclk_q <= reset_mclk_d;
    end
end

always @(posedge clk_video or posedge reset) begin
    if (reset) begin
        reset_video_d <= 1'b1;
        reset_video_q <= 1'b1;
    end else begin
        reset_video_d <= 1'b0;
        reset_video_q <= reset_video_d;
    end
end

reg [2:0] address = 0;
reg [15:0] din = 0;
wire [15:0] dout;
reg nUDS = 1, nLDS = 1;
reg write_en = 0, read_en = 0;
reg pal_sel = 0;
reg sec_pal_write_en = 0;
reg sec_pal_sel = 0;
reg hc_bf_write_en = 0;
reg hc_bf_sel = 0;

reg [4:0] screen_palette [0:15];
reg [4:0] sec_palette_data [0:15];
reg [7:0] hc_bitfield_data [0:15];

p8video #(.VRAM_PIPELINE_LATENCY_PIXELS(2)) p8video (
	.mclk(mclk),
	.clk_video(clk_video),
	.reset_sys(reset_mclk_q),
	.reset_video(reset_video_q),
	.address(address),
	.din(din),
	.dout(dout),
	.nUDS(nUDS),
	.nLDS(nLDS),
	.write_en(write_en),
	.read_en(read_en),
    .pal_sel(pal_sel),
	.vaddress_main(vaddr2_main),
	.vdin_main(vdout2_main),
	.vaddress_overlay(vaddr2_overlay),
	.vdin_overlay(vdout2_overlay),
    .vfronto(vfront),
    .vfrontreq(vfrontreq),
    .overlay_enable(overlay_enable),
    .overlay_key_colour(overlay_key_colour),
    .screen_transform(SCREEN_TRANSFORM[7:0]),
    .high_color_mode(HIGH_COLOR_MODE[7:0]),
    .sec_pal_write_en(sec_pal_write_en),
    .sec_pal_sel(sec_pal_sel),
    .hc_bf_write_en(hc_bf_write_en),
    .hc_bf_sel(hc_bf_sel),
	.VSB(video_vs),
	.HS(video_hs),
	.iblank (iblank),
	.VR(video_r),
	.VG(video_g),
	.VB(video_b)
	);

integer x, y, c;
reg init_done = 0;

initial begin
    $display("=== p8video_tb: ENABLE_OVERLAY=%0d, SCREEN_TRANSFORM=%0d, HIGH_COLOR_MODE=0x%02h ===",
             ENABLE_OVERLAY, SCREEN_TRANSFORM, HIGH_COLOR_MODE);

    // Initialize palette arrays based on mode
    if (HIGH_COLOR_MODE == 0) begin
        for (int i = 0; i < 16; i++) screen_palette[i] = i * 2;
    end else begin
        for (int i = 0; i < 16; i++) screen_palette[i] = i;  // identity
    end
    for (int i = 0; i < 16; i++) sec_palette_data[i] = i + 16;  // extended colors
    for (int i = 0; i < 16; i++) hc_bitfield_data[i] = 8'h00;
    if (HIGH_COLOR_MODE == 'h10)
        for (int i = 8; i < 16; i++) hc_bitfield_data[i] = 8'hFF;  // bottom half
    else if (HIGH_COLOR_MODE == 'h35)
        for (int i = 0; i < 16; i++) hc_bitfield_data[i] = 8'hAA;  // alternating

    // Reset
    reset = 1;
    repeat(10) begin
        @(posedge mclk);
        @(posedge clk_video);
    end
    reset = 0;
    repeat(10) begin
        @(posedge mclk);
        @(posedge clk_video);
    end

    // Initialize main palette 1 through MMIO
    pal_sel <= 1;
    for (int i = 0; i < 16; i = i + 2) begin
        address <= i[3:1];
        din <= {screen_palette[i][4], 3'b0, screen_palette[i][3:0], screen_palette[i+1][4], 3'b0, screen_palette[i+1][3:0]};
        nUDS <= 0;
        nLDS <= 0;
        write_en <= 1;
        @(posedge mclk);
        @(posedge clk_video);
        write_en <= 0;
        nUDS <= 1;
        nLDS <= 1;
        repeat(2) begin
            @(posedge mclk);
            @(posedge clk_video);
        end
    end
    pal_sel <= 0;

    // Initialize secondary palette 1 (for high-color modes)
    if (HIGH_COLOR_MODE != 0) begin
        sec_pal_sel <= 1;
        for (int i = 0; i < 16; i = i + 2) begin
            address <= i[3:1];
            din <= {sec_palette_data[i][4], 3'b0, sec_palette_data[i][3:0],
                    sec_palette_data[i+1][4], 3'b0, sec_palette_data[i+1][3:0]};
            nUDS <= 0;
            nLDS <= 0;
            sec_pal_write_en <= 1;
            @(posedge mclk);
            @(posedge clk_video);
            sec_pal_write_en <= 0;
            nUDS <= 1;
            nLDS <= 1;
            repeat(2) begin
                @(posedge mclk);
                @(posedge clk_video);
            end
        end
        sec_pal_sel <= 0;
    end

    // Initialize bitfield 1 (for modes that use it)
    if (HIGH_COLOR_MODE == 'h10 || (HIGH_COLOR_MODE & 8'hF0) == 'h30) begin
        hc_bf_sel <= 1;
        for (int i = 0; i < 16; i = i + 2) begin
            address <= i[3:1];
            din <= {hc_bitfield_data[i], hc_bitfield_data[i+1]};
            nUDS <= 0;
            nLDS <= 0;
            hc_bf_write_en <= 1;
            @(posedge mclk);
            @(posedge clk_video);
            hc_bf_write_en <= 0;
            nUDS <= 1;
            nLDS <= 1;
            repeat(2) begin
                @(posedge mclk);
                @(posedge clk_video);
            end
        end
        hc_bf_sel <= 0;
    end

    // Write test pattern to main VRAM buffer 1 (bit 12 selects buffer)
    for (y = 0; y < 128; y = y + 1) begin
        for (x = 0; x < 128; x = x + 4) begin
            vw1_main <= 2'b11;
            vaddr1_main <= (1 << 12) | (y * 32 + x / 4);
            if (HIGH_COLOR_MODE == 'h10) begin
                // Horizontal stripes: color = y/8
                c = (y / 8) & 15;
                vdin1_main <= c * 16'h1111;
            end else if (HIGH_COLOR_MODE == 'h20) begin
                if (x < 64) begin
                    // Left half: horizontal stripes
                    c = (y / 8) & 15;
                    vdin1_main <= c * 16'h1111;
                end else begin
                    // Right half: top half = color 1 (mask), bottom half = color 0
                    vdin1_main <= (y < 64) ? 16'h1111 : 16'h0000;
                end
            end else if (HIGH_COLOR_MODE == 'h30) begin
                vdin1_main <= 16'h0000;  // all color 0
            end else if (HIGH_COLOR_MODE == 'h35) begin
                vdin1_main <= 16'h5555;  // all color 5
            end else begin
                // Default diagonal pattern
                vdin1_main <= ((y + x) & 4'hf) << 8 | (((y + x + 1) & 4'hf) << 12) | ((y + x + 2) & 4'hf) | (((y + x + 3) & 4'hf) << 4);
            end
            @(posedge mclk);
        end
    end

    if (ENABLE_OVERLAY) begin
        overlay_enable <= 1'b1;
        overlay_key_colour <= 4'd0;

        for (y = 0; y < 128; y = y + 1) begin
            for (x = 0; x < 128; x = x + 4) begin
                vw1_overlay <= 2'b11;
                vaddr1_overlay <= (1 << 12) | (y * 32 + x / 4);

                if (((x / 8) + (y / 8)) & 1) begin
                    vdin1_overlay <= 16'hFFFF;
                end else begin
                    vdin1_overlay <= 16'h0000;
                end
                @(posedge mclk);
            end
        end
    end

    vw1_main <= 0;
    vw1_overlay <= 0;

    // Flip to buffer 1
    vfrontreq <= 1'b1;

    // Wait a bit before starting validation
    repeat(10) begin
        @(posedge mclk);
        @(posedge clk_video);
    end
    init_done <= 1;
end

vidout_check #(.ENABLE_OVERLAY(ENABLE_OVERLAY),
               .SCREEN_TRANSFORM(SCREEN_TRANSFORM),
               .HIGH_COLOR_MODE(HIGH_COLOR_MODE)) check(
                   .clk_video(clk_video),
                   .video_vs(video_vs),
                   .video_hs(video_hs),
                   .iblank(iblank),
                   .video_r(video_r),
                   .video_g(video_g),
                   .video_b(video_b),
                   .init_done(init_done));

endmodule

module vidout_check #(
    parameter ENABLE_OVERLAY = 0,
    parameter SCREEN_TRANSFORM = 0,
    parameter HIGH_COLOR_MODE = 0
)(
    input wire clk_video,
    input wire video_vs,
    input wire video_hs,
    input wire iblank,
    input wire [7:0] video_r,
    input wire [7:0] video_g,
    input wire [7:0] video_b,
    input wire init_done
);

localparam overlay_enable = ENABLE_OVERLAY;
localparam [3:0] overlay_key_colour = 4'd0;

localparam integer SCREEN_PALETTE [0:31] = {
    24'h000000, 24'h1D2B53, 24'h7E2553,
    24'h008751, 24'hAB5236, 24'h5F574F,
    24'hC2C3C7, 24'hFFF1E8, 24'hFF004D,
    24'hFFA300, 24'hFFEC27, 24'h00E436,
    24'h29ADFF, 24'h83769C, 24'hFF77A8,
    24'hFFCCAA, 24'h291814, 24'h111D35,
    24'h422136, 24'h125359, 24'h742F29,
    24'h49333B, 24'hA28879, 24'hF3EF7D,
    24'hBE1250, 24'hFF6C24, 24'hA8E72E,
    24'h00B54E, 24'h065AB5, 24'h754665,
    24'hFF6E59, 24'hFF9D81
};

integer x=0, y=0;
integer px, py;
integer expected_colour;
integer expected_system_index;
integer expected_screen_index;
integer expected_overlay_index;
integer is_overlay_transparent;
integer pixel_has_overlay;
integer src_x, src_y;
integer bf_byte, bf_bit_idx, section;
reg iblank_prev;
reg video_vs_prev;
integer frame_count = 0;

// Map screen color to main palette system index
function automatic integer main_pal(input integer idx);
    if (HIGH_COLOR_MODE == 0)
        return idx * 2;
    else
        return idx;  // identity
endfunction

// Map index to secondary palette system index
function automatic integer sec_pal(input integer idx);
    return idx + 16;
endfunction

// Get bitfield byte for a given source line
function automatic integer get_bf_byte(input integer line);
    integer byte_idx;
    byte_idx = line / 8;
    case (HIGH_COLOR_MODE)
        'h10: begin
            if (byte_idx >= 8) return 'hFF;
            else return 'h00;
        end
        'h35: return 'hAA;
        default: return 'h00;
    endcase
endfunction

// Screen transform: maps output (ox, oy) to source (sx, sy)
function automatic void screen_xform(input integer mode, input integer ox, input integer oy,
                                     output integer sx, output integer sy);
    case (mode)
        1:   begin sx = ox / 2; sy = oy; end
        2:   begin sx = ox; sy = oy / 2; end
        3:   begin sx = ox / 2; sy = oy / 2; end
        5:   begin sx = (ox < 64) ? ox : (127 - ox); sy = oy; end
        6:   begin sx = ox; sy = (oy < 64) ? oy : (127 - oy); end
        7:   begin sx = (ox < 64) ? ox : (127 - ox); sy = (oy < 64) ? oy : (127 - oy); end
        129: begin sx = 127 - ox; sy = oy; end
        130: begin sx = ox; sy = 127 - oy; end
        131: begin sx = 127 - ox; sy = 127 - oy; end
        133: begin sx = 127 - oy; sy = ox; end
        134: begin sx = 127 - ox; sy = 127 - oy; end
        135: begin sx = oy; sy = 127 - ox; end
        default: begin sx = ox; sy = oy; end
    endcase
endfunction

always @(posedge clk_video) begin
    // Detect vsync falling edge (end of frame)
    if (video_vs_prev && !video_vs) begin
        frame_count <= frame_count + 1;
        $display("Frame %0d complete at time %t", frame_count, $time);
        if (frame_count >= 4) begin
            $display("SUCCESS: Two validated frames completed successfully");
            $finish;
        end
    end
    video_vs_prev <= video_vs;

    if (!video_vs)
         y <= 0;
    else begin
        if (iblank && !iblank_prev)
             y <= y + 1;
        if (!video_hs)
             x <= 0;
        else if (!iblank)
             x <= x + 2;
    end

    if (!iblank && init_done && frame_count >= 2) begin
         px = x / 6;
         py = y / 6;

         screen_xform(SCREEN_TRANSFORM, px, py, src_x, src_y);

         // Compute expected screen_index based on VRAM pattern
         case (HIGH_COLOR_MODE)
             'h10: expected_screen_index = (src_y / 8) & 4'hf;      // stripes
             'h20: expected_screen_index = (src_y / 8) & 4'hf;      // stripes (left half)
             'h30: expected_screen_index = 0;                        // all color 0
             'h35: expected_screen_index = 5;                        // all color 5
             default: expected_screen_index = (src_y + src_x) & 4'hf; // diagonal
         endcase

         if (ENABLE_OVERLAY && overlay_enable) begin
             pixel_has_overlay = ((px / 8) + (py / 8)) & 1;

             if (pixel_has_overlay) begin
                 expected_overlay_index = 15;
             end else begin
                 expected_overlay_index = 0;
             end

             is_overlay_transparent = (expected_overlay_index == overlay_key_colour);
             if (!is_overlay_transparent) begin
                 expected_system_index = expected_overlay_index;
             end else begin
                 expected_system_index = main_pal(expected_screen_index);
             end
         end else begin
             // High-color mode expected value computation
             case (HIGH_COLOR_MODE)
                 'h10: begin
                     // Per-line palette swap
                     bf_byte = get_bf_byte(src_y);
                     bf_bit_idx = src_y & 7;
                     if (bf_byte[bf_bit_idx])
                         expected_system_index = sec_pal(expected_screen_index);
                     else
                         expected_system_index = main_pal(expected_screen_index);
                 end
                 'h20: begin
                     // 5-bitplane: hidden pixel non-zero for top half (src_y < 64)
                     if (src_y < 64)
                         expected_system_index = sec_pal(expected_screen_index);
                     else
                         expected_system_index = main_pal(expected_screen_index);
                 end
                 'h30: begin
                     // Gradient fill replacing color 0
                     // system_index_primary = main_pal(0) = 0, (0 & 0xF) == 0 → gradient
                     section = src_y / 8;
                     // bitfield all zeros, no shift
                     expected_system_index = sec_pal(section);
                 end
                 'h35: begin
                     // Gradient fill replacing color 5 with blend
                     // system_index_primary = main_pal(5) = 5, (5 & 0xF) == 5 → gradient
                     section = src_y / 8;
                     bf_byte = get_bf_byte(src_y);
                     bf_bit_idx = src_y & 7;
                     if (bf_byte[bf_bit_idx])
                         section = (section + 1) & 15;
                     expected_system_index = sec_pal(section);
                 end
                 default: begin
                     expected_system_index = main_pal(expected_screen_index);
                 end
             endcase
         end

         expected_colour = SCREEN_PALETTE[expected_system_index];

         if (video_r != expected_colour[23:16] || video_g != expected_colour[15:8] || video_b != expected_colour[7:0]) begin
            $display("ERROR at time %t: x=%0d, y=%0d, px=%0d, py=%0d, src_x=%0d, src_y=%0d",
                     $time, x, y, px, py, src_x, src_y);
            $display("  screen_index=%0d, system_index=%0d, hc_mode=0x%02h",
                     expected_screen_index, expected_system_index, HIGH_COLOR_MODE);
            $display("  Expected RGB: %02h %02h %02h", expected_colour[23:16], expected_colour[15:8], expected_colour[7:0]);
            $display("  Got RGB:      %02h %02h %02h", video_r, video_g, video_b);
            $fatal(1);
         end else begin
            if ((px % 32 == 0) && (py % 32 == 0)) begin
                $display("OK at time %t: x=%0d, y=%0d, px=%0d, py=%0d, index=%0d",
                         $time, x, y, px, py, expected_system_index);
            end
         end
     end

    iblank_prev <= iblank;
end

endmodule

