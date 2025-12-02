//
// zx8302.v
//
// ZX8302 for Sinclair QL for the MiST
// https://github.com/mist-devel
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
// adapted for Next keyboard-joystick 2024 Theodoulos Liontakis (Leon)
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

module zx8302 (
		input        clk,       // 21 mhz
		input        clk11,     // 11 mhz
      input          reset,
      input          init,
		
		// interrupts
		output [1:0]   ipl,
		input          xint,
		
		// sdram interface for microdrive emulation
		output [24:0]  mdv_addr,
		input [15:0]   mdv_din,
		output         mdv_read,
		input          mdv_men,
		input          video_cycle,

		input          mdv_reverse,
		output         led,
		output         audio,
		
		// vertical synv 
		input          vs,

		// joysticks
		input [4:0]    js0,
		input [4:0]    js1,
		
		    // Matrix keyboard
      output wire [7:0] keyb_row,
      input  wire [6:0] keyb_col,
		input          mbutton,
		input          gbutton,
		input          ps2_kbd_clk,
		input          ps2_kbd_data,
		output [7:0]	keys_o,
		
      // bus interface
		input			clk_bus,
		input			cpu_sel,
		input			cpu_wr,
		input [1:0] 	cpu_addr,      // a[5,1]
		input [1:0] 	cpu_ds,
		input [15:0]   cpu_din,
		output [15:0]  cpu_dout,
		input [24:0]   mdv_smem,
		input [24:0]   mdv_emem     
);  

// ---------------------------------------------------------------------------------
// ----------------------------- CPU register write --------------------------------
// ---------------------------------------------------------------------------------

reg [7:0] mctrl;

reg ipc_write;
reg [3:0] ipc_write_data;
reg [8:0] div_counter = 9'd0;
reg [47:0] rtc;
reg clk32k = 0;

// cpu is writing io registers
always @(negedge clk_bus) begin
	irq_ack <= 5'd0;
	ipc_write <= 1'b0;
	// rtc
	div_counter <= div_counter + 9'd1;
	if (div_counter >= 9'd155) //168=11mhz
	begin
		div_counter <= 9'd0;
		clk32k <= ~clk32k; 
		if (!(cpu_addr == 2'b00 && cpu_sel && cpu_wr)) rtc <= rtc + 48'd1;
	end
	// cpu writes to 0x18XXX area
	if(cpu_sel && cpu_wr) begin
		// even addresses have cpu_ds[1]=0 and use the higher 8 data bus bits
		if (!cpu_ds[1]) begin
			// cpu writes microdrive control register
			if(cpu_addr == 2'b10)
				mctrl <= cpu_din[15:8];
		end
		//rtc
		if (cpu_addr == 2'b00) begin 
			if (!cpu_ds[1]) rtc[47:16]<=32'd0; else if (!cpu_ds[0]) 
			begin
				if (!cpu_din[4]) rtc[47:40]<=rtc[47:40]+8'd1; //else
				if (!cpu_din[3]) rtc[39:32]<=rtc[39:32]+8'd1; //else
				if (!cpu_din[2]) rtc[31:24]<=rtc[31:24]+8'd1; //else
				if (!cpu_din[1]) rtc[23:16]<=rtc[23:16]+8'd1; //else 
			end
		end

		// odd addresses have cpu_ds[0]=0 and use the lower 8 data bus bits
		if(!cpu_ds[0]) begin
			// 18003 - IPCWR
			// (host sends a single bit to ipc)
			if(cpu_addr == 2'b01) begin
				// data is ----XEDS
				// S = start bit (should be 0)
				// D = data bit (0/1)
				// E = stop bit (should be 1)
            // X = extra stopbit (should be 1)
				ipc_write <= 1'b1;
				ipc_write_data <= cpu_din[3:0];
         end

			// cpu writes interrupt register
			if(cpu_addr == 2'b10) begin
				irq_mask <= cpu_din[7:5];
				irq_ack <= cpu_din[4:0];
			end
		end
	end
end

// ---------------------------------------------------------------------------------
// ----------------------------- CPU register read ---------------------------------
// ---------------------------------------------------------------------------------

// status register read
// bit 0       Network port
// bit 1       Transmit buffer full
// bit 2       Receive buffer full
// bit 3       Microdrive GAP
// bit 4       SER1 DTR
// bit 5       SER2 CTS
// bit 6       IPC busy
// bit 7       COMDATA

wire [7:0] io_status = { zx8302_comdata_in, ipc_busy, 2'b00,
		mdv_gap, mdv_rx_ready, mdv_tx_empty, 1'b0 };

assign cpu_dout =
	// 18020/18021 and 18022/18023
	(cpu_addr == 2'b10)?{io_status, irq_pending}:
	(cpu_addr == 2'b11)?{mdv_byte, mdv_byte}:
	// 18000/18001 and 18002/18003
	(cpu_addr == 2'b00)?rtc[47:32]:
	(cpu_addr == 2'b01)?rtc[31:16]:
	16'h0000;	

// ---------------------------------------------------------------------------------
// -------------------------------------- IPC --------------------------------------
// ---------------------------------------------------------------------------------
	
wire ipc_comctrl;
wire ipc_comdata_out;

// 8302 sees its own comdata as well as the one from the ipc
wire zx8302_comdata_in = ipc_comdata_in && ipc_comdata_out;

// comdata shift register
wire ipc_comdata_in = comdata_reg[0];
reg [3:0] comdata_reg;
reg [1:0] comdata_cnt; 

always @(negedge ipc_comctrl or posedge reset or posedge ipc_write) begin
	if(reset) begin
		comdata_reg <= 4'b0000;
		comdata_cnt <= 2'd0;
	end else if(ipc_write) begin
		comdata_reg <= ipc_write_data;
		comdata_cnt <= 2'd2;
	end else begin
		comdata_reg <= { 1'b0, comdata_reg[3:1] };
		if(comdata_cnt != 0)
			comdata_cnt <= comdata_cnt - 2'd1;
	end
end

// comdata is busy until two bits have been shifted out
wire ipc_busy = (comdata_cnt != 0);

wire [1:0] ipc_ipl;

ipc ipc (	
	.reset    	    ( reset          ),
	.clk11          ( clk11        ),   // direct board clock

	.comctrl        ( ipc_comctrl    ),
	.comdata_in     ( ipc_comdata_in ),
	.comdata_out    ( ipc_comdata_out),

   .audio          ( audio          ),
	.ipl            ( ipc_ipl        ),

	.js0            ( js0            ),
	.js1            ( js1            ),
	    // Matrix keyboard
   .keyb_r 	 ( keyb_row ),
   .keyb_c   ( keyb_col ),
	.mbutton  ( mbutton ),
	.gbutton  (gbutton),
	
	.ps2_kbd_clk    ( ps2_kbd_clk    ),
	.ps2_kbd_data   ( ps2_kbd_data   ),
	.keys_o			 ( keys_o			)
);

// ---------------------------------------------------------------------------------
// -------------------------------------- IRQs -------------------------------------
// ---------------------------------------------------------------------------------

wire [7:0] irq_pending = {1'b0, (mdv_sel == 0), clk32k,
		xint_irq, vsync_irq, 1'b0, 1'b0, gap_irq };
reg [2:0] irq_mask;
reg [4:0] irq_ack;

// any pending irq raises ipl to 2 and the ipc can control both ipl lines
assign ipl = { ipc_ipl[1] && (irq_pending[4:0] == 0), ipc_ipl[0] };

// vsync irq is set whenever vsync rises
reg vsync_irq;
wire vsync_irq_reset = reset || irq_ack[3];
always @(posedge vs or posedge vsync_irq_reset) begin
	if(vsync_irq_reset) 	vsync_irq <= 1'b0;
	else	      	     	vsync_irq <= 1'b1;
end

// toggling the mask will also trigger irqs ...
wire gap_irq_in = mdv_gap && irq_mask[0];
reg gap_irq;
wire gap_irq_reset = reset || irq_ack[0];
always @(posedge gap_irq_in or posedge gap_irq_reset) begin
	if(gap_irq_reset) 	gap_irq <= 1'b0;
	else	      	     	gap_irq <= 1'b1;
end

// toggling the mask will also trigger irqs ...
wire xint_irq_in = xint && irq_mask[2];
reg xint_irq;
wire xint_irq_reset = reset || irq_ack[4];
always @(posedge xint_irq_in or posedge xint_irq_reset) begin
	if(xint_irq_reset) 	xint_irq <= 1'b0;
	else	      	     	xint_irq <= 1'b1;
end


// ---------------------------------------------------------------------------------
// ----------------------------------- microdrive ----------------------------------
// ---------------------------------------------------------------------------------

wire mdv_gap;
wire mdv_tx_empty;
wire mdv_rx_ready;
wire [7:0] mdv_byte;

assign led = !mdv_sel[0];

mdv  mdv //#(.BASE_ADDR (BASE_ADDR) )
(
   .clk      ( clk11          ),
	.reset    ( reset         ),
	
	.sel      ( mdv_sel[0]   ),

	.reverse  ( mdv_reverse  ),

   // control bits	
	.gap      ( mdv_gap      ),
	.tx_empty ( mdv_tx_empty ),
	.rx_ready ( mdv_rx_ready ),
	.dout     ( mdv_byte     ),

	// ram interface to read image
   .mem_ena  ( mdv_men      ),
	.mem_clk  ( clk_bus      ),
	.mem_addr ( mdv_addr     ),
	.mem_read ( mdv_read     ),  
	.mem_din  ( mdv_din      ),
	.mdv_smem     (mdv_smem),
	.mdv_end      (mdv_emem)
);

// the microdrive control register mctrl generates the drive selection
reg [7:0] mdv_sel;

always @(negedge mctrl[1])
	mdv_sel <= { mdv_sel[6:0], mctrl[0] };

// ---------------------------------------------------------------------------------
// -------------------------------------- RTC clock --------------------------------------
// ---------------------------------------------------------------------------------

//reg [7:0] div_counter2 = 8'd0;


//always @(posedge clk11)
//begin
//	div_counter2 <= div_counter2 + 8'd1;
	
//	if (div_counter2 > 8'd167)
//	begin
//		div_counter2 <= 8'd0;
//		clk32k <= ~clk32k; 
//	end
//end
	
endmodule
