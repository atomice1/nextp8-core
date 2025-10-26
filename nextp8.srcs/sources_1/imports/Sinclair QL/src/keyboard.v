//
// keyboard.v
//
// nextp8 core for the ZX Spectrum Next
// Copyright (C) 2025 Chris January
//
// Derived from Sinclair QL for the MiST
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

module keyboard ( 
	input wire clk,
	input wire reset,

	// ps2 interface	
	input wire ps2_clk,
	input wire ps2_data,
	
	output wire [255:0] matrix
	
);

reg [255:0] p8matrix;

wire [7:0] byte;
wire valid;
wire error;

reg key_released;
reg key_extended;

assign matrix = p8matrix;

always @(posedge clk) begin
	if(reset) 
		begin
            key_released <= 1'b0;
            key_extended <= 1'b0;
			p8matrix <= 256'd0;
		end 
	else 
		begin

		// ps2 decoder has received a valid byte
		if(valid) begin
			if(byte == 8'he0) // extended key code
                key_extended <= 1'b1;
            else if(byte == 8'hf0) // release code
                key_released <= 1'b1;
            else begin
				key_extended <= 1'b0;
				key_released <= 1'b0;
				
				p8matrix[byte | key_extended ? 8'h80 : 8'd0] <= key_released ? 1'b0 : 1'b1;
			end
		end
	end
end

// the ps2 decoder has been taken from the zx spectrum core
ps2_read_keyboard ps2_keyboard (
	.CLK		 ( clk             ),
	.nRESET	 ( !reset          ),
	
	// PS/2 interface
	.PS2_CLK  ( ps2_clk         ),
	.PS2_DATA ( ps2_data        ),
	
	// Byte-wide data interface - only valid for one clock
	// so must be latched externally if required
	.DATA		  ( byte   ),
	.VALID	  ( valid  ),
	.ERROR	  ( error  )
);

endmodule
