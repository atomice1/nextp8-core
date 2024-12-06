`timescale 1ns/1ns

////////////////////////////////////////////////////////////////////////////////// 
// Copyright (C) 2025 Chris January  
//////////////////////////////////////////////////////////////////////////////////

module p8video_tb();

//Clock
reg clk325 = 0;
always #31 clk325 = ~clk325;

// ---------------------------------------------------------------------------------
// -------------------------------------- video ------------------------------------
// ---------------------------------------------------------------------------------

reg  [12:0] vaddr1;
wire [12:0] vaddr2;
wire [15:0] vdout1;
wire [15:0] vdout2;
reg [15:0] vdin1=16'd0;
reg [15:0] vdin2=16'd0;
reg [1:0] vw1,vw2=2'b00;
reg vfrontreq=1'b0;


// dual bus video ram
vram vram (
  .clka(clk325),    // input clka
  .wea(vw1),       // input [0 : 0] wea
  .addra(vaddr1),   // input [12 : 0] addra
  .dina(vdin1),    // input [15 : 0] dina
  .douta(vdout1),   // output [15 : 0] douta
  .clkb(clk325),   // input clkb
  .web(2'b00),    // input [0 : 0] web
  .addrb(vaddr2), // input [12 : 0] addrb
  .dinb(vdin2),   // input [15 : 0] dinb
  .doutb(vdout2) // output [15 : 0] doutb
);


wire [7:0] video_r, video_g, video_b;

wire video_hs, video_vs;
wire iblank;
wire vfront;

reg reset = 0;

reg [4:0] screen_palette [0:15] = {
    0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30
};

p8video p8video (
	.clk325(clk325),
	.reset(reset),
	.vaddress(vaddr2),
	.vdin(vdout2),
    .vfronto(vfront),
    .vfrontreq(vfrontreq),
	.VSB(video_vs),
	.HS(video_hs),
	.iblank (iblank),
	.VR(video_r),
	.VG(video_g),
	.VB(video_b),
	.screen_palette(screen_palette)
	);

integer x, y;
reg init_done = 0;

initial begin
    @(posedge clk325);
    for (y = 0; y < 128; y = y + 1) begin
        for (x = 0; x < 128; x = x + 4) begin
            vw1 <= 2'b11;
            vaddr1 <= y * 32 + x / 4;
            vdin1 <= ((y + x) & 4'hf) << 8 | (((y + x + 1) & 4'hf) << 12) | ((y + x + 2) & 4'hf) | (((y + x + 3) & 4'hf) << 4); 
            @(posedge clk325);
        end
    end
    vw1 <= 0;
    init_done <= 1;
end

vidout_check check(clk325,
                   video_vs,
                   video_hs,
                   iblank,
                   video_r,
                   video_g,
                   video_b,
                   init_done);

endmodule

module vidout_check(input wire clk325,
                    input wire video_vs,
                    input wire video_hs,
                    input wire iblank,
                    input wire [7:0] video_r,
                    input wire [7:0] video_g,
                    input wire [7:0] video_b,
                    input wire init_done);

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
integer index, colour;
reg iblank_prev;

always @(posedge clk325) begin 
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
    if (!iblank && init_done) begin
         px = x / 6;
         py = y / 6;
         index = (py + px) & 4'hf;
         colour = SCREEN_PALETTE[index * 2];
     end
    iblank_prev <= iblank;
end
always @(negedge clk325) begin
    if (!iblank && init_done) begin
        assert (video_r == colour[23:16]);
        assert (video_g == colour[15:8]);
        assert (video_b == colour[7:0]);
        assert (video_r == colour[23:16] && video_g == colour[15:8] && video_b == colour[7:0]) else $stop(1);
    end
end

endmodule

