//-----------------------------------------------------
//------- Copyright (C) Chris January 2025 ------------
//------- Copyright (c) Theodoulos Liontakis  2024 ----
//-----------------------------------------------------
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

module mkeyboard ( 
	input wire clk,
	input wire reset,
	output wire [7:0] rows_o,
	input wire [6:0] cols_i,
	output wire [255:0] omatrix
);



function [7:0] m;
	input [7:0] col, row;
	begin
		m = col * 8'd8 + row;
	end
endfunction

reg [63:0] matrix;
reg [255:0] p8matrix;
reg [12:0] i;
reg [7:0] rows;
reg [6:0] ncols;

assign omatrix=p8matrix;
assign rows_o=rows;

always @(posedge clk)
begin
if (reset) 
    begin
        matrix <= 64'd0;
        p8matrix <= 256'd0;
    end
else
    begin
        i<=i+13'd1;
        ncols= ~cols_i;
        case(i)
              0: rows<=8'b???????0;  //row 0
            398: matrix[7:0]<= {1'b0,ncols}; //read row 0
            400: rows<=8'b??????0?;
            798: matrix[15:8]<= {1'b0,ncols};
            800: rows<=8'b?????0??;
            1198: matrix[23:16]<={1'b0,ncols};
            1200: rows<=8'b????0???;
            1598: matrix[31:24]<= {1'b0,ncols};
            1600: rows<=8'b???0????;
            1998: matrix[39:32]<={1'b0,ncols};
            2000: rows<=8'b??0?????;
            2398: matrix[47:40]<={1'b0,ncols};
            2400: rows<=8'b?0??????;
            2798: matrix[55:48]<={1'b0,ncols};
            2800: rows<=8'b0???????;
            3198: matrix[63:56]<= {1'b0,ncols};
            3600: rows<=8'b????????;
            4000: begin
                // indexes in p8matrix are the PS/2 scan code
                // extended scan codes are OR'ed with 'h80

                // ---------- Row 0 ----------
                // bit6=UP, bit5=EXTEND, bit4=V, bit3=C, bit2=X, bit1=Z, bit0=CapsShift
                p8matrix['h12] <= matrix[0];   // Caps Shift (Left Shift)
                p8matrix['h1A] <= matrix[1];   // Z
                p8matrix['h22] <= matrix[2];   // X
                p8matrix['h21] <= matrix[3];   // C
                p8matrix['h2A] <= matrix[4];   // V
                // No mapping for Extended Mode
                p8matrix['hF5] <= matrix[6];   // Up arrow

                // ---------- Row 1 ----------
                // bit6=GRAPH, bit5=CAPS LOCK, bit4=G, bit3=F, bit2=D, bit1=S, bit0=A
                p8matrix['h1C] <= matrix[8];   // A
                p8matrix['h1B] <= matrix[9];   // S
                p8matrix['h23] <= matrix[10];  // D
                p8matrix['h2B] <= matrix[11];  // F
                p8matrix['h34] <= matrix[12];  // G
                p8matrix['h58] <= matrix[13];  // Caps Lock

                // ---------- Row 2 ----------
                // bit6=INV VIDEO, bit5=TRUE VIDEO, bit4=T, bit3=R, bit2=E, bit1=W, bit0=Q
                p8matrix['h15] <= matrix[16];  // Q
                p8matrix['h1D] <= matrix[17];  // W
                p8matrix['h24] <= matrix[18];  // E
                p8matrix['h2D] <= matrix[19];  // R
                p8matrix['h2C] <= matrix[20];  // T

                // ---------- Row 3 ----------
                // bit6=EDIT, bit5=BREAK, bit4=5, bit3=4, bit2=3, bit1=2, bit0=1
                p8matrix['h16] <= matrix[24];  // 1
                p8matrix['h1E] <= matrix[25];  // 2
                p8matrix['h26] <= matrix[26];  // 3
                p8matrix['h25] <= matrix[27];  // 4
                p8matrix['h2E] <= matrix[28];  // 5
                p8matrix['h76] <= matrix[29];  // Break (ESC)

                // ---------- Row 4 ----------
                // bit6=" , bit5=; , bit4=6, bit3=7, bit2=8, bit1=9, bit0=0
                p8matrix['h45] <= matrix[32];  // 0
                p8matrix['h46] <= matrix[33];  // 9
                p8matrix['h3E] <= matrix[34];  // 8
                p8matrix['h3D] <= matrix[35];  // 7
                p8matrix['h36] <= matrix[36];  // 6
                p8matrix['h4C] <= matrix[37];  // ;
                p8matrix['h52] <= matrix[38];  // " (' and
                p8matrix['h59] <= matrix[38];  //    Right Shift)

                // ---------- Row 5 ----------
                // bit6=., bit5=,, bit4=Y, bit3=U, bit2=I, bit1=O, bit0=P
                p8matrix['h4D] <= matrix[40];  // P
                p8matrix['h44] <= matrix[41];  // O
                p8matrix['h43] <= matrix[42];  // I
                p8matrix['h3C] <= matrix[43];  // U
                p8matrix['h35] <= matrix[44];  // Y
                p8matrix['h41] <= matrix[45];  // ,
                p8matrix['h49] <= matrix[46];  // .

                // ---------- Row 6 ----------
                // bit6=RIGHT, bit5=DELETE, bit4=H, bit3=J, bit2=K, bit1=L, bit0=Enter
                p8matrix['h5A] <= matrix[48];  // Enter
                p8matrix['h4B] <= matrix[49];  // L
                p8matrix['h42] <= matrix[50];  // K
                p8matrix['h3B] <= matrix[51];  // J
                p8matrix['h33] <= matrix[52];  // H
                p8matrix['h71] <= matrix[53];  // Delete
                p8matrix['hF4] <= matrix[54];  // Right arrow

                // ---------- Row 7 ----------
                // bit6=DOWN, bit5=LEFT, bit4=B, bit3=N, bit2=M, bit1=SymShift, bit0=Space
                p8matrix['h29] <= matrix[56];  // Space
                p8matrix['h11] <= matrix[57];  // Symbol Shift (Left Alt)
                p8matrix['h3A] <= matrix[58];  // M
                p8matrix['h31] <= matrix[59];  // N
                p8matrix['h32] <= matrix[60];  // B
                p8matrix['hEB] <= matrix[61];  // Left arrow
                p8matrix['hF2] <= matrix[62];  // Down arrow
			end
		endcase
	end
end

endmodule
