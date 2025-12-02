//
// ipc.v
//
// Sinclair QL for the MiST
// https://github.com/mist-devel
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
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



module ipc (
	input 		 reset,
	input        clk11, //8049 clock

	// synchronous serial connection
	output       comctrl,
	input        comdata_in,
	output       comdata_out,

	output       audio,
	output [1:0] ipl,

	input [4:0]  js0,
	input [4:0]  js1,
	
	// Matrix keyboard
   output wire [7:0] keyb_r,
   input  wire [6:0] keyb_c,
	input        mbutton,
	input        gbutton,
	 
	input 		 ps2_kbd_clk,
	input 		 ps2_kbd_data,
	output [7:0] keys_o
);

// ---------------------------------------------------------------------------------
// -------------------------------------- KBD --------------------------------------
// ---------------------------------------------------------------------------------

wire [63:0] ps2_kbd_matrix;
wire [63:0] meb_kbd_matrix;
wire [7:0] p_keys_o;
wire [7:0] m_keys_o;

keyboard keyboard (
    .reset    ( reset        ),
    .clk      ( clk11        ),

    .ps2_clk  ( ps2_kbd_clk  ),
    .ps2_data ( ps2_kbd_data ),
    .keys_o	  ( p_keys_o     ),

    .js0      ( js0          ),
    .js1      ( js1          ),
      
    .matrix   ( ps2_kbd_matrix  )
);

//------------------------------Membrane Keyboard---------------------

mkeyboard mkeyb (
.clk      ( clk11 ),
.reset    ( reset ),
.rows_o   ( keyb_r ),
.cols_i   ( keyb_c ),
.mbutton  ( mbutton ),
.gbutton  ( gbutton ),
.omatrix  ( meb_kbd_matrix ),
.keys_o	  ( m_keys_o 		),
.js0      ( js0          ),
.js1      ( js1          )
);
//-------------------------------------------------------------------

wire [63:0] kbd_matrix;

assign keys_o = p_keys_o & m_keys_o;

// make sure IPC clock is stable before it starts
wire ipc_reset = reset;


// ---------------------------------------------------------------------------------
// -------------------------------------- 8049 -------------------------------------
// ---------------------------------------------------------------------------------

assign audio = t8049_p2_o[1];
assign ipl = t8049_p2_o[3:2];

wire [7:0] t8049_p1_o;
wire [7:0] t8049_db_i;

wire [7:0] t8049_p2_o;
wire [7:0] t8049_p2_i = { comdata_out && comdata_in, 7'b0000000 };

assign comdata_out = t8049_p2_o[7];

t8049_notri #(0) t8049 (
	.xtal_i    ( clk11      ),
   .xtal_en_i ( 1'b1       ),
   .reset_n_i ( !ipc_reset ),
   .t0_i      ( 1'b0       ),
   .t1_i      ( 1'b0       ),
   .int_n_i   ( 1'b1       ),
   .wr_n_o    ( comctrl    ),
   .ea_i      ( 1'b0       ),
   .db_i      ( t8049_db_i ),
   .p1_i      ( 8'h00      ),
   .p1_o      ( t8049_p1_o ),
   .p2_i      ( t8049_p2_i ),
   .p2_o      ( t8049_p2_o )
);

assign kbd_matrix = ps2_kbd_matrix | meb_kbd_matrix;

assign t8049_db_i = 
	(t8049_p1_o[0]?kbd_matrix[ 7: 0]:8'h00)|
	(t8049_p1_o[1]?kbd_matrix[15: 8]:8'h00)|
	(t8049_p1_o[2]?kbd_matrix[23:16]:8'h00)|
	(t8049_p1_o[3]?kbd_matrix[31:24]:8'h00)|
	(t8049_p1_o[4]?kbd_matrix[39:32]:8'h00)|
	(t8049_p1_o[5]?kbd_matrix[47:40]:8'h00)|
	(t8049_p1_o[6]?kbd_matrix[55:48]:8'h00)|
	(t8049_p1_o[7]?kbd_matrix[63:56]:8'h00);

endmodule
