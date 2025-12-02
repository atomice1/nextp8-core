//
// zx8301.v
//
// ZX8301 ULA for Sinclair QL for the MiST
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

module zx8301min (
	input  reset,

	// CPU interface to access $18063
	input  clk_bus,
	input  cpu_cs,
	input  [7:0] cpu_data,
	output mode, 
	output membase,
	output blank
);

/* ----------------------------------------------------------------- */
/* -------------------------- CPU register ------------------------- */
/* ----------------------------------------------------------------- */

assign membase = mc_stat[7];      // 0 = $20000, 1 = $28000
assign mode = mc_stat[3];         // 0 = 512*256*2bpp, 1=256*256*4bpp
assign blank = mc_stat[1];        // 0 = normal video, 1 = blanked video

reg [7:0] mc_stat;

always @(negedge clk_bus) begin
	if(reset)   
		mc_stat <= 8'h00;
	else if(cpu_cs)	
		mc_stat <= cpu_data;
end
	
endmodule
