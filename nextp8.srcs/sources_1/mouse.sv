//
// mouse.sv
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

module mouse #(
    parameter SIM = 0  // Set to 1 in simulation to reduce delays
) (
    input wire clk,
    input wire reset,

    // ps2 interface
    input  wire ps2_clk_in,
    input  wire ps2_data_in,
    output wire ps2_clk_out,
    output wire ps2_data_out,

    // Mouse state outputs (16-bit absolute accumulators)
    output reg signed [15:0] mouse_x,
    output reg signed [15:0] mouse_y,
    output reg signed [15:0] mouse_z,
    output reg [7:0] mouse_buttons
);

wire [7:0] rbyte;
wire valid;

reg [1:0] packet_cnt;
reg [7:0] status_byte;  // Store byte 0 (status) for sign bits
reg       intellimouse_mode;  // 1 = 4-byte packets, 0 = 3-byte packets

// PS/2 transmit interface
reg [7:0] tx_data;
reg tx_start;
wire tx_busy;
wire [1:0] tx_mode = 2'b00;

// Mouse initialization state machine
localparam INIT_IDLE         = 5'd0;
localparam INIT_POWERON_WAIT = 5'd1;
localparam INIT_SEND_FF      = 5'd2;
localparam INIT_WAIT_ACK_FF  = 5'd3;
localparam INIT_WAIT_BAT_FF  = 5'd4;
localparam INIT_WAIT_00      = 5'd5;   // Wait for device ID (0x00) after BAT
localparam INIT_POST_BAT_DELAY=5'd6;
localparam INIT_SEND_F3_200  = 5'd7;   // Intellimouse detection: Set Sample Rate 200
localparam INIT_WAIT_ACK_F3_200=5'd8;
localparam INIT_SEND_C8      = 5'd9;   // Send rate value 200 (0xC8)
localparam INIT_WAIT_ACK_C8  = 5'd10;
localparam INIT_SEND_F3_100  = 5'd11;  // Set Sample Rate 100
localparam INIT_WAIT_ACK_F3_100=5'd12;
localparam INIT_SEND_64      = 5'd13;  // Send rate value 100 (0x64)
localparam INIT_WAIT_ACK_64  = 5'd14;
localparam INIT_SEND_F3_80   = 5'd15;  // Set Sample Rate 80
localparam INIT_WAIT_ACK_F3_80=5'd16;
localparam INIT_SEND_50      = 5'd17;  // Send rate value 80 (0x50)
localparam INIT_WAIT_ACK_50  = 5'd18;
localparam INIT_SEND_F2      = 5'd19;  // Get Device ID
localparam INIT_WAIT_ACK_F2  = 5'd20;
localparam INIT_WAIT_DEVICE_ID=5'd21;  // Wait for device ID response
localparam INIT_SEND_F4      = 5'd22;  // Enable Data Reporting
localparam INIT_WAIT_ACK_F4  = 5'd23;
localparam INIT_DONE         = 5'd24;

localparam [7:0] RESP_ACK     = 8'hFA;
localparam [7:0] RESP_RESEND  = 8'hFE;
localparam [7:0] RESP_BAT_OK  = 8'hAA;
localparam [7:0] RESP_BAT_ERR1= 8'hFC;
localparam [7:0] RESP_BAT_ERR2= 8'hFD;
localparam [7:0] RESP_DEVICE_ID = 8'h00;  // Standard mouse
localparam [7:0] RESP_INTELLIMOUSE_ID = 8'h03;  // Intellimouse
localparam [7:0] CMD_RESET    = 8'hFF;
localparam [7:0] CMD_ENABLE   = 8'hF4;
localparam [7:0] CMD_SET_SAMPLE_RATE = 8'hF3;
localparam [7:0] CMD_READ_DEVICE_TYPE = 8'hF2;
localparam [7:0] RATE_200     = 8'hC8;  // decimal 200
localparam [7:0] RATE_100     = 8'h64;  // decimal 100
localparam [7:0] RATE_80      = 8'h50;  // decimal 80

localparam [19:0] INIT_CMD_DELAY = SIM ? 20'd20000 : 20'd1000000;  // 20ms in sim, 1s in hardware
localparam [19:0] POWERON_WAIT_TIME = SIM ? 20'd7500 : 20'd750000;  // 750us in sim, 750ms in hardware
localparam [19:0] POST_BAT_DELAY = SIM ? 20'd500 : 20'd50000;  // 50us in sim, 50ms in hardware

reg [4:0] init_state;
reg [19:0] init_counter;

// Mouse initialization process
// Sends 0xF4 (Enable Data Reporting) command after reset
always @(posedge clk) begin
    if (reset) begin
        init_state <= INIT_IDLE;
        init_counter <= 20'd0;
        tx_start <= 1'b0;
        intellimouse_mode <= 1'b0;
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
                    if (rbyte == RESP_BAT_OK || rbyte == RESP_BAT_ERR1 || rbyte == RESP_BAT_ERR2) begin
                        $display("Mouse init: received power-on BAT 0x%02x, skipping reset", rbyte);
                        // Power-on BAT received, delay before next command
                        init_counter <= POST_BAT_DELAY;
                        init_state <= INIT_POST_BAT_DELAY;
                    end else begin
                        // Unexpected byte, keep waiting
                        $display("Mouse init: unexpected byte 0x%02x during power-on wait", rbyte);
                    end
                end else if (init_counter == 20'd0) begin
                    // Timeout, send reset command
                    $display("Mouse init: power-on wait timeout, sending reset");
                    init_state <= INIT_SEND_FF;
                end else begin
                    init_counter <= init_counter - 20'd1;
                end
            end

            INIT_SEND_FF: begin
                // Send 0xFF (Reset)
                if (!tx_busy) begin
                    $display("Mouse init: sending Reset command");
                    tx_data <= CMD_RESET;
                    tx_start <= 1'b1;
                    init_state <= INIT_WAIT_ACK_FF;
                end
            end

            INIT_WAIT_ACK_FF: begin
                // Wait for ACK after reset command
                if (valid) begin
                    $display("Mouse init: received byte 0x%02x after reset", rbyte);
                    if (rbyte == RESP_ACK) begin
                        init_state <= INIT_WAIT_BAT_FF;
                    end else if (rbyte == RESP_RESEND) begin
                        init_state <= INIT_SEND_FF;  // Resend reset
                    end else begin
                        // Ignore other bytes
                    end
                end
            end

            INIT_WAIT_BAT_FF: begin
                // Wait for BAT (0xAA, 0xFC, 0xFD) after ACK
                if (valid) begin
                    $display("Mouse init: received byte 0x%02x waiting for BAT", rbyte);
                    if (rbyte == RESP_BAT_OK || rbyte == RESP_BAT_ERR1 || rbyte == RESP_BAT_ERR2) begin
                        init_state <= INIT_WAIT_00;
                    end else begin
                        // Ignore unexpected bytes, keep waiting for BAT
                    end
                end
            end

            INIT_WAIT_00: begin
                // Wait for device ID (0x00) after BAT
                if (valid) begin
                    $display("Mouse init: received device ID 0x%02x after BAT", rbyte);
                    if (rbyte == RESP_DEVICE_ID) begin
                        init_counter <= POST_BAT_DELAY;
                        init_state <= INIT_POST_BAT_DELAY;
                    end else begin
                        $display("Mouse init: WARNING - unexpected device ID, expected 0x00");
                        // Continue anyway
                        init_counter <= POST_BAT_DELAY;
                        init_state <= INIT_POST_BAT_DELAY;
                    end
                end
            end

            INIT_POST_BAT_DELAY: begin
                // Delay after BAT result before attempting Intellimouse detection
                if (init_counter == 20'd0) begin
                    $display("Mouse init: POST_BAT_DELAY complete, starting Intellimouse detection @ %0t", $time);
                    init_state <= INIT_SEND_F3_200;
                end else begin
                    init_counter <= init_counter - 20'd1;
                end
            end

            // Intellimouse detection sequence: Set Sample Rate 200
            INIT_SEND_F3_200: begin
                if (!tx_busy) begin
                    $display("Mouse init: sending Set Sample Rate command (0xF3)");
                    tx_data <= CMD_SET_SAMPLE_RATE;
                    tx_start <= 1'b1;
                    init_state <= INIT_WAIT_ACK_F3_200;
                end
            end

            INIT_WAIT_ACK_F3_200: begin
                if (valid) begin
                    if (rbyte == RESP_ACK) begin
                        init_state <= INIT_SEND_C8;
                    end else if (rbyte == RESP_RESEND) begin
                        init_state <= INIT_SEND_F3_200;
                    end
                end
            end

            INIT_SEND_C8: begin
                if (!tx_busy) begin
                    $display("Mouse init: sending rate 200 (0xC8)");
                    tx_data <= RATE_200;
                    tx_start <= 1'b1;
                    init_state <= INIT_WAIT_ACK_C8;
                end
            end

            INIT_WAIT_ACK_C8: begin
                if (valid) begin
                    if (rbyte == RESP_ACK) begin
                        init_state <= INIT_SEND_F3_100;
                    end else if (rbyte == RESP_RESEND) begin
                        init_state <= INIT_SEND_C8;
                    end
                end
            end

            // Set Sample Rate 100
            INIT_SEND_F3_100: begin
                if (!tx_busy) begin
                    $display("Mouse init: sending Set Sample Rate command (0xF3)");
                    tx_data <= CMD_SET_SAMPLE_RATE;
                    tx_start <= 1'b1;
                    init_state <= INIT_WAIT_ACK_F3_100;
                end
            end

            INIT_WAIT_ACK_F3_100: begin
                if (valid) begin
                    if (rbyte == RESP_ACK) begin
                        init_state <= INIT_SEND_64;
                    end else if (rbyte == RESP_RESEND) begin
                        init_state <= INIT_SEND_F3_100;
                    end
                end
            end

            INIT_SEND_64: begin
                if (!tx_busy) begin
                    $display("Mouse init: sending rate 100 (0x64)");
                    tx_data <= RATE_100;
                    tx_start <= 1'b1;
                    init_state <= INIT_WAIT_ACK_64;
                end
            end

            INIT_WAIT_ACK_64: begin
                if (valid) begin
                    if (rbyte == RESP_ACK) begin
                        init_state <= INIT_SEND_F3_80;
                    end else if (rbyte == RESP_RESEND) begin
                        init_state <= INIT_SEND_64;
                    end
                end
            end

            // Set Sample Rate 80
            INIT_SEND_F3_80: begin
                if (!tx_busy) begin
                    $display("Mouse init: sending Set Sample Rate command (0xF3)");
                    tx_data <= CMD_SET_SAMPLE_RATE;
                    tx_start <= 1'b1;
                    init_state <= INIT_WAIT_ACK_F3_80;
                end
            end

            INIT_WAIT_ACK_F3_80: begin
                if (valid) begin
                    if (rbyte == RESP_ACK) begin
                        init_state <= INIT_SEND_50;
                    end else if (rbyte == RESP_RESEND) begin
                        init_state <= INIT_SEND_F3_80;
                    end
                end
            end

            INIT_SEND_50: begin
                if (!tx_busy) begin
                    $display("Mouse init: sending rate 80 (0x50)");
                    tx_data <= RATE_80;
                    tx_start <= 1'b1;
                    init_state <= INIT_WAIT_ACK_50;
                end
            end

            INIT_WAIT_ACK_50: begin
                if (valid) begin
                    if (rbyte == RESP_ACK) begin
                        init_state <= INIT_SEND_F2;
                    end else if (rbyte == RESP_RESEND) begin
                        init_state <= INIT_SEND_50;
                    end
                end
            end

            // Get Device ID to check if Intellimouse
            INIT_SEND_F2: begin
                if (!tx_busy) begin
                    $display("Mouse init: sending Get Device ID command (0xF2)");
                    tx_data <= CMD_READ_DEVICE_TYPE;
                    tx_start <= 1'b1;
                    init_state <= INIT_WAIT_ACK_F2;
                end
            end

            INIT_WAIT_ACK_F2: begin
                if (valid) begin
                    if (rbyte == RESP_ACK) begin
                        init_state <= INIT_WAIT_DEVICE_ID;
                    end else if (rbyte == RESP_RESEND) begin
                        init_state <= INIT_SEND_F2;
                    end
                end
            end

            INIT_WAIT_DEVICE_ID: begin
                // Wait for device ID response (0x00 = standard, 0x03 = Intellimouse)
                if (valid) begin
                    $display("Mouse init: received device ID 0x%02x", rbyte);
                    if (rbyte == RESP_INTELLIMOUSE_ID) begin
                        $display("Mouse init: Intellimouse detected (4-byte packets)");
                        intellimouse_mode <= 1'b1;
                    end else begin
                        $display("Mouse init: Standard PS/2 mouse (3-byte packets)");
                        intellimouse_mode <= 1'b0;
                    end
                    init_state <= INIT_SEND_F4;
                end
            end

            INIT_SEND_F4: begin
                // Send 0xF4 (Enable Data Reporting) command
                if (!tx_busy) begin
                    $display("Mouse init: sending Enable Data Reporting command (tx_busy=0) @ %0t", $time);
                    tx_data <= CMD_ENABLE;
                    tx_start <= 1'b1;
                    init_state <= INIT_WAIT_ACK_F4;
                end else begin
                    $display("Mouse init: waiting in SEND_F4 (tx_busy=1) @ %0t", $time);
                end
            end

            INIT_WAIT_ACK_F4: begin
                // Wait for ACK/RESEND
                if (valid) begin
                    if (rbyte == RESP_ACK) begin
                        init_state <= INIT_DONE;
                    end else if (rbyte == RESP_RESEND) begin
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

// Mouse position monitor
always @(mouse_x, mouse_y) begin
    $display("Mouse position updated: X=%0d Y=%0d", mouse_x, mouse_y);
end

// Packet decoder
always @(posedge clk) begin
    if(reset) begin
        mouse_x <= 16'sd0;
        mouse_y <= 16'sd0;
        mouse_z <= 16'sd0;
        mouse_buttons <= 8'd0;
        packet_cnt <= 2'd0;
        status_byte <= 8'd0;
    end else begin

        // ps2 decoder has received a valid byte
        // Only process movement packets when initialization is complete
        if (valid && init_state == INIT_DONE) begin
            // count through all three data bytes in a PS/2 mouse packet
            packet_cnt <= packet_cnt + 2'd1;

            if(packet_cnt == 2'd0) begin
                // Byte 0: YOvfl XOvfl YSign XSign 1 MBtn RBtn LBtn
                // bit 3 must be 1. Stay in state 0 otherwise
                if (rbyte[3]) begin
                    // Store status byte for sign bits
                    status_byte <= rbyte;
                    // Update button state
                    mouse_buttons <= {5'd0, rbyte[2:0]};  // bits [2:0] = middle, right, left
                    // Note: button latching now handled in nextp8_top.v
                end else begin
                    // Invalid packet, reset to state 0
                    packet_cnt <= 2'd0;
                end
                // Display status byte for debugging
                $display("Mouse packet status byte: 0x%02x", rbyte);
                // Decode status byte bits
                // rbyte[0] = Left button
                // rbyte[1] = Right button
                // rbyte[2] = Middle button
                // rbyte[4] = XSign
                // rbyte[5] = YSign
                // rbyte[6] = X overflow
                // rbyte[7] = Y overflow
                $display("  Buttons: L=%b R=%b M=%b, XSign=%b YSign=%b, Xovfl=%b Yovfl=%b",
                         rbyte[0], rbyte[1], rbyte[2],
                         rbyte[4], rbyte[5],
                         rbyte[6], rbyte[7]);
            end else if(packet_cnt == 2'd1) begin
                // Byte 1: X movement (unsigned, sign from status_byte[4])
                // Sign-extend using status byte bit 4 (XSign)
                $display("Mouse packet X movement byte: 0x%02x", rbyte);
                // Sign-extend and accumulate
                $display("  X movement sign-extended: %0d", { {8{status_byte[4]}}, rbyte});
                mouse_x <= mouse_x + { {8{status_byte[4]}}, rbyte};
            end else if(packet_cnt == 2'd2) begin
                // Byte 2: Y movement (unsigned, sign from status_byte[5])
                // Sign-extend using status byte bit 5 (YSign)
                $display("Mouse packet Y movement byte: 0x%02x", rbyte);
                // Sign-extend and accumulate
                $display("  Y movement sign-extended: %0d", { {8{status_byte[5]}}, rbyte});
                mouse_y <= mouse_y + { {8{status_byte[5]}}, rbyte};

                // If 3-byte mode, reset packet counter and print position
                if (!intellimouse_mode) begin
                    packet_cnt <= 2'd0;
                    $display("Mouse accumulated position: X=%0d Y=%0d", mouse_x, mouse_y);
                end
            end else begin
                // Byte 3: Z movement (scroll wheel, 4-bit signed in lower nibble)
                // Only in Intellimouse mode (4-byte packets)
                $display("Mouse packet Z movement byte: 0x%02x", rbyte);
                // Sign-extend from bit 3 (lower 4 bits are 2's complement)
                $display("  Z movement sign-extended: %0d", { {12{rbyte[3]}}, rbyte[3:0]});
                mouse_z <= mouse_z + { {12{rbyte[3]}}, rbyte[3:0]};

                // Reset packet counter
                packet_cnt <= 2'd0;

                // Print out new mouse position
                $display("Mouse accumulated position: X=%0d Y=%0d Z=%0d", mouse_x, mouse_y, mouse_z);
            end
        end
    end
end

ps2_interface #(
    .FILTER_BITS(8)
) ps2_mouse_inst (
    .CLK          ( clk          ),
    .nRESET       ( !reset       ),
    .PS2_CLK_IN   ( ps2_clk_in   ),
    .PS2_DATA_IN  ( ps2_data_in  ),
    .PS2_CLK_OUT  ( ps2_clk_out  ),
    .PS2_DATA_OUT ( ps2_data_out ),
    .DATA         ( rbyte        ),
    .VALID        ( valid        ),
    .ERROR        ( ),  // unused for mouse
    .TX_DATA      ( tx_data      ),
    .TX_START     ( tx_start     ),
    .TX_MODE      ( tx_mode      ),
    .TX_BUSY      ( tx_busy      ),
    .TX_DONE      ( )
);

endmodule
