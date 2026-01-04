`timescale 1ns/1ns

//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2025 Chris January
//////////////////////////////////////////////////////////////////////////////////

module p8video_tb #(
    parameter ENABLE_OVERLAY = 0
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


vram vram_main (
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

vram vram_overlay (
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

reg [4:0] screen_palette [0:15] = {
    0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30
};

p8video p8video (
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
	.VSB(video_vs),
	.HS(video_hs),
	.iblank (iblank),
	.VR(video_r),
	.VG(video_g),
	.VB(video_b)
	);

integer x, y;
reg init_done = 0;

initial begin
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

    // Initialize palette through MMIO (write to palette registers)
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

    // Write test pattern to main vram (using mclk to avoid collision)
    for (y = 0; y < 128; y = y + 1) begin
        for (x = 0; x < 128; x = x + 4) begin
            vw1_main <= 2'b11;
            vaddr1_main <= y * 32 + x / 4;
            vdin1_main <= ((y + x) & 4'hf) << 8 | (((y + x + 1) & 4'hf) << 12) | ((y + x + 2) & 4'hf) | (((y + x + 3) & 4'hf) << 4);
            @(posedge mclk);  // Write on mclk to avoid collision with video reads
        end
    end

    if (ENABLE_OVERLAY) begin
        overlay_enable <= 1'b1;
        overlay_key_colour <= 4'd0;

        for (y = 0; y < 128; y = y + 1) begin
            for (x = 0; x < 128; x = x + 4) begin
                vw1_overlay <= 2'b11;
                vaddr1_overlay <= y * 32 + x / 4;

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
    // Wait a bit before starting validation
    repeat(10) begin
        @(posedge mclk);
        @(posedge clk_video);
    end
    init_done <= 1;
end

vidout_check #(.ENABLE_OVERLAY(ENABLE_OVERLAY)) check(
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
    parameter ENABLE_OVERLAY = 0
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
reg iblank_prev;
reg video_vs_prev;
integer frame_count = 0;

always @(posedge clk_video) begin
    // Detect vsync falling edge (end of frame)
    if (video_vs_prev && !video_vs) begin
        frame_count <= frame_count + 1;
        $display("Frame %0d complete at time %t", frame_count, $time);
        if (frame_count >= 2) begin
            $display("SUCCESS: Two frames completed successfully");
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
             x <= x + 6;
    end

    if (!iblank && init_done) begin
         px = x / 6;
         py = y / 6;

         expected_screen_index = (py + px) & 4'hf;

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
                 expected_system_index = expected_screen_index * 2;
             end
         end else begin
             expected_system_index = expected_screen_index * 2;
         end

         expected_colour = SCREEN_PALETTE[expected_system_index];

         if (video_r != expected_colour[23:16] || video_g != expected_colour[15:8] || video_b != expected_colour[7:0]) begin
            $display("ERROR at time %t: x=%0d, y=%0d, px=%0d, py=%0d",
                     $time, x, y, px, py);
            if (ENABLE_OVERLAY && overlay_enable) begin
                $display("  Main index=%0d, overlay index=%0d, transparent=%0d, final index=%0d",
                         expected_screen_index, expected_overlay_index, is_overlay_transparent, expected_system_index);
            end else begin
                $display("  Expected index=%0d", expected_screen_index);
            end
            $display("  Expected RGB: %02h %02h %02h", expected_colour[23:16], expected_colour[15:8], expected_colour[7:0]);
            $display("  Got RGB:      %02h %02h %02h", video_r, video_g, video_b);
            $stop(1);
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

