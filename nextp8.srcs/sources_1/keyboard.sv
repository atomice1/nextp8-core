//
// keyboard.sv
//
// nextp8 core for the ZX Spectrum Next
// Copyright (C) 2025-2026 Chris January
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

`timescale 1ns/1ns

module keyboard #(
    parameter SIM     = 0,  // Set to 1 in simulation to reduce delays
    parameter VERBOSE = 0   // Set to 1 to enable $display debug output
) (
    input wire clk,
    input wire reset,

    // ps2 interface
    input  wire ps2_clk_in,
    input  wire ps2_data_in,
    output wire ps2_clk_out,
    output wire ps2_data_out,

    // Keyboard matrix output
    output wire [255:0] matrix
);

reg [255:0] p8matrix;

wire [7:0] rx_byte;
wire valid;
wire error;

reg key_released;
reg key_extended;

assign matrix = p8matrix;

// PS/2 transmit interface
reg [7:0] tx_data;
reg tx_start;
reg [1:0] tx_mode = 2'b00;  // Normal mode
wire tx_busy;

// Keyboard initialization state machine
localparam INIT_IDLE         = 5'd0;
localparam INIT_POWERON_WAIT = 5'd1;
localparam INIT_SEND_FF      = 5'd2;
localparam INIT_WAIT_ACK_FF  = 5'd3;
localparam INIT_WAIT_BAT_FF  = 5'd4;
localparam INIT_POST_BAT_DELAY=5'd5;
localparam INIT_SEND_ED      = 5'd6;
localparam INIT_WAIT_ACK_ED  = 5'd7;
localparam INIT_SEND_LED     = 5'd8;
localparam INIT_WAIT_ACK_LED = 5'd9;
localparam INIT_SEND_F4      = 5'd14;
localparam INIT_WAIT_ACK_F4  = 5'd15;
localparam INIT_DONE         = 5'd16;

localparam [7:0] RESP_ACK     = 8'hFA;
localparam [7:0] RESP_RESEND  = 8'hFE;
localparam [7:0] RESP_BAT_OK  = 8'hAA;
localparam [7:0] RESP_BAT_ERR1= 8'hFC;
localparam [7:0] RESP_BAT_ERR2= 8'hFD;
localparam [7:0] CMD_RESET       = 8'hFF;
localparam [7:0] CMD_SET_LED     = 8'hED;
localparam [7:0] CMD_LED_OFF     = 8'h00;
localparam [7:0] CMD_SET_SCANSET = 8'hF0;
localparam [7:0] CMD_SCANSET_2   = 8'h02;
localparam [7:0] CMD_ENABLE      = 8'hF4;

localparam [19:0] POWERON_WAIT_TIME = SIM ? 20'd7500 : 20'd750000;  // 750us in sim, 750ms in hardware
localparam [19:0] POST_BAT_DELAY = SIM ? 20'd500 : 20'd50000;  // 50us in sim, 50ms in hardware

reg [4:0] init_state;
reg [19:0] init_counter;

// Keyboard initialization process: reset, set LEDs off, enable scanning
always @(posedge clk) begin
    if (reset) begin
        init_state <= INIT_IDLE;
        init_counter <= 20'd0;
        tx_start <= 1'b0;
    end else begin
        tx_start <= 1'b0;  // Default

        case (init_state)
            INIT_IDLE: begin
                // Wait for power-on BAT or timeout
                init_counter <= POWERON_WAIT_TIME;
                init_state <= INIT_POWERON_WAIT;
            end

            INIT_POWERON_WAIT: begin
                // Wait for power-on BAT (0xAA, 0xFC, 0xFD) or timeout
                if (valid) begin
                    if (rx_byte == RESP_BAT_OK || rx_byte == RESP_BAT_ERR1 || rx_byte == RESP_BAT_ERR2) begin
                        if (VERBOSE) $display("Keyboard init: received power-on BAT 0x%02x, skipping reset", rx_byte);
                        // Power-on BAT received, delay before next command
                        init_counter <= POST_BAT_DELAY;
                        init_state <= INIT_POST_BAT_DELAY;
                    end else begin
                        // Unexpected byte, keep waiting
                        if (VERBOSE) $display("Keyboard init: unexpected byte 0x%02x during power-on wait", rx_byte);
                    end
                end else if (init_counter == 20'd0) begin
                    // Timeout, send reset command
                    if (VERBOSE) $display("Keyboard init: power-on wait timeout, sending reset");
                    init_state <= INIT_SEND_FF;
                end else begin
                    init_counter <= init_counter - 20'd1;
                end
            end

            INIT_SEND_FF: begin
                // Send 0xFF (Reset)
                if (!tx_busy) begin
                    if (VERBOSE) $display("Keyboard init: sending Reset command");
                    tx_data <= CMD_RESET;
                    tx_start <= 1'b1;
                    init_state <= INIT_WAIT_ACK_FF;
                end
            end

            INIT_WAIT_ACK_FF: begin
                // Wait for ACK after reset command
                if (valid) begin
                    if (VERBOSE) $display("Keyboard init: received byte 0x%02x after reset", rx_byte);
                    if (rx_byte == RESP_ACK) begin
                        init_state <= INIT_WAIT_BAT_FF;
                    end else if (rx_byte == RESP_RESEND) begin
                        init_state <= INIT_SEND_FF;  // Resend reset
                    end else begin
                        // Ignore other bytes during init
                    end
                end
            end

            INIT_WAIT_BAT_FF: begin
                // Wait for BAT (0xAA) after ACK
                if (valid) begin
                    if (VERBOSE) $display("Keyboard init: received byte 0x%02x waiting for BAT", rx_byte);
                    if (rx_byte == RESP_BAT_OK) begin
                        init_counter <= POST_BAT_DELAY;
                        init_state <= INIT_POST_BAT_DELAY;
                    end else begin
                        // Ignore unexpected bytes, keep waiting for BAT
                    end
                end
            end

            INIT_POST_BAT_DELAY: begin
                // Delay after BAT result before sending next command
                if (init_counter == 20'd0) begin
                    if (VERBOSE) $display("Keyboard init: POST_BAT_DELAY complete, transitioning to SEND_ED @ %0t", $time);
                    init_state <= INIT_SEND_ED;
                end else begin
                    init_counter <= init_counter - 20'd1;
                end
            end

            INIT_SEND_ED: begin
                // Send 0xED (Set Status Indicators)
                if (!tx_busy) begin
                    if (VERBOSE) $display("Keyboard init: sending Set LED command (tx_busy=0) @ %0t", $time);
                    tx_data <= CMD_SET_LED;
                    tx_start <= 1'b1;
                    init_state <= INIT_WAIT_ACK_ED;
                end else begin
                    if (VERBOSE) $display("Keyboard init: waiting in SEND_ED (tx_busy=1) @ %0t", $time);
                end
            end

            INIT_WAIT_ACK_ED: begin
                if (valid) begin
                    if (rx_byte == RESP_ACK) begin
                        init_state <= INIT_SEND_LED;
                    end else if (rx_byte == RESP_RESEND) begin
                        init_state <= INIT_SEND_ED;  // Resend command
                    end else begin
                        // Ignore other bytes during init
                    end
                end
            end

            INIT_SEND_LED: begin
                // Send 0x00 (all LEDs off)
                if (!tx_busy) begin
                    tx_data <= CMD_LED_OFF;
                    tx_start <= 1'b1;
                    init_state <= INIT_WAIT_ACK_LED;
                end
            end

            INIT_WAIT_ACK_LED: begin
                if (valid) begin
                    if (rx_byte == RESP_ACK) begin
                        init_state <= INIT_SEND_F4;
                    end else if (rx_byte == RESP_RESEND) begin
                        init_state <= INIT_SEND_LED;  // Resend data rx_byte
                    end else begin
                        // Ignore other bytes during init
                    end
                end
            end

            INIT_SEND_F4: begin
                // Send 0xF4 (Enable scanning)
                if (!tx_busy) begin
                    tx_data <= CMD_ENABLE;
                    tx_start <= 1'b1;
                    init_state <= INIT_WAIT_ACK_F4;
                end
            end

            INIT_WAIT_ACK_F4: begin
                if (valid) begin
                    if (rx_byte == RESP_ACK) begin
                        init_state <= INIT_DONE;
                    end else if (rx_byte == RESP_RESEND) begin
                        init_state <= INIT_SEND_F4;  // Resend enable
                    end else begin
                        // Ignore other bytes during init
                    end
                end
            end

            INIT_DONE: begin
                // Initialization complete, stay here
            end

            default: begin
                init_state <= INIT_IDLE;
            end
        endcase
    end
end

// Scan code decoder
always @(posedge clk) begin
    if (reset) begin
        key_released <= 1'b0;
        key_extended <= 1'b0;
        p8matrix <= 256'd0;
    end else begin
        if (valid) begin
            // Ignore incoming bytes until initialization completes so ACKs do not
            // disturb the matrix state.
            if (init_state == INIT_DONE) begin
                if (VERBOSE) $display("Keyboard received byte: 0x%02x (extended=%b released=%b) @ %0t", rx_byte, key_extended, key_released, $time);
                // Track prefix bytes and apply them once the actual key code arrives.
                if (rx_byte == 8'he0) begin
                    key_extended <= 1'b1;
                end else if (rx_byte == 8'hf0) begin
                    key_released <= 1'b1;
                end else begin
                    key_extended <= 1'b0;
                    key_released <= 1'b0;

                    p8matrix[rx_byte | (key_extended ? 8'h80 : 8'd0)] <= key_released ? 1'b0 : 1'b1;
                end
            end else begin
                // Still initializing, ignore incoming bytes
                if (VERBOSE) $display("Keyboard init: ignoring byte 0x%02x", rx_byte);
            end
        end
    end
end

ps2_interface #(
    .FILTER_BITS(8)
) ps2_keyboard (
    .CLK        ( clk             ),
    .nRESET     ( !reset          ),
    .PS2_CLK_IN ( ps2_clk_in      ),
    .PS2_DATA_IN( ps2_data_in     ),
    .PS2_CLK_OUT( ps2_clk_out     ),
    .PS2_DATA_OUT( ps2_data_out   ),
    .DATA       ( rx_byte         ),
    .VALID      ( valid           ),
    .ERROR      ( error           ),
    .TX_DATA    ( tx_data         ),
    .TX_START   ( tx_start        ),
    .TX_MODE    ( tx_mode         ),
    .TX_BUSY    ( tx_busy         ),
    .TX_DONE    ( )
);

endmodule
