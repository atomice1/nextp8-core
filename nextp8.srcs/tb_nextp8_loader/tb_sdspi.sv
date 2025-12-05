//================================================================
// tb_sdspi.sv
// SD Card SPI Mode Model Testbench
//
// Copyright (C) 2025 Chris January
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
//==============================================================

`timescale 1ns / 1ps

module tb_sdspi();

    // System clock - 28 MHz (like Next)
    reg clk = 0;
    always #17.857 clk = ~clk;  // ~28 MHz

    // SPI controller signals
    reg reset = 0;
    reg spi_w = 0;
    wire spi_ready;
    reg [7:0] spi_data_in = 8'hFF;
    wire [7:0] spi_data_out;
    reg [7:0] spi_divider = 8'd2;  // Divide by 2 for ~14 MHz SPI clock

    // SPI physical signals
    wire spi_sclk;
    wire spi_mosi;
    wire spi_miso;
    reg spi_cs_n = 1;

    // Captured response
    reg [7:0] response_byte;
    integer bit_idx;

    // Instantiate SPI controller (VHDL)
    SPI spi_inst (
        .clk(clk),
        .reset(reset),
        .w(spi_w),
        .readyo(spi_ready),
        .data_in(spi_data_in),
        .data_out(spi_data_out),
        .divider(spi_divider),
        .SCLKo(spi_sclk),
        .MOSI(spi_mosi),
        .MISO(spi_miso)
    );

    // Instantiate SDSPI model
    sdspi_model #(
        .LGMEMSZ(20),              // 1 MB card
        .CARDIMAGE("sdcard.img"),
        .CCS(1),                   // SDHC mode
        .DEBUG(1)                  // Enable debug
    ) sd_model (
        .clk(clk),
        .reset(reset),
        .spi_cs_n(spi_cs_n),
        .spi_clk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );

    // Task to send a byte over SPI using the SPI controller
    task send_byte(input [7:0] data);
        begin
            // Wait for SPI controller to be idle (ready low)
            while (spi_ready == 1) @(posedge clk);

            // Load data and pulse w signal
            spi_data_in = data;
            @(posedge clk);
            spi_w = 1;
            @(posedge clk);
            spi_w = 0;

            // Wait for transfer to start (ready goes high)
            while (spi_ready == 0) @(posedge clk);

            // Wait for transfer to complete (ready goes back low)
            while (spi_ready == 1) @(posedge clk);
        end
    endtask

    // Task to receive a byte over SPI using the SPI controller
    task receive_byte(output [7:0] data);
        begin
            // Send 0xFF while receiving
            send_byte(8'hFF);
            // Data is captured in spi_data_out
            data = spi_data_out;
            $display("[TB] Received byte: 0x%02x (from SPI controller data_out)", data);
        end
    endtask

    // Task to send an SD command
    task send_cmd(input [5:0] cmd, input [31:0] arg);
        reg [7:0] crc;
        begin
            $display("\n[TB] Sending CMD%0d, arg=0x%08x", cmd, arg);

            // Start bit (0) + transmission bit (1) + 6-bit command
            send_byte({2'b01, cmd});

            // 32-bit argument
            send_byte(arg[31:24]);
            send_byte(arg[23:16]);
            send_byte(arg[15:8]);
            send_byte(arg[7:0]);

            // CRC + stop bit (for CMD0 and CMD8, CRC matters)
            if (cmd == 0)
                crc = 8'h95;  // Valid CRC for CMD0
            else if (cmd == 8)
                crc = 8'h87;  // Valid CRC for CMD8 with arg 0x000001AA
            else
                crc = 8'hFF;  // Dummy CRC
            send_byte(crc);

            $display("[TB] Command sent, waiting for response...");
        end
    endtask

    // Task to wait for R1 response (poll for non-FF byte)
    task wait_r1_response(output [7:0] r1);
        integer timeout;
        begin
            timeout = 0;
            r1 = 8'hFF;
            while (r1 == 8'hFF && timeout < 100) begin
                receive_byte(r1);
                timeout = timeout + 1;
                if (r1 == 8'hFF) begin
                    $display("[TB] Still waiting... (timeout=%0d)", timeout);
                end
            end
            if (timeout >= 100) begin
                $display("[TB] ERROR: Response timeout!");
            end else begin
                $display("[TB] Received R1 response: 0x%02x", r1);
            end
        end
    endtask

    // Main test sequence
    initial begin
        // Variable declarations for CMD17 test
        reg [7:0] block_data [0:511];
        logic [15:0] calculated_crc;
        logic [15:0] received_crc;
        integer crc_bit;

        $display("=== SDSPI Model Testbench ===");
        $display("Testing basic SPI communication with SD card model\n");

        // Reset SPI controller
        reset = 1;
        spi_cs_n = 1;
        #200;
        reset = 0;
        #1000;

        // Send 80 dummy clocks with CS high (power-up sequence)
        $display("[TB] Sending 80 dummy clocks for power-up...");
        repeat(10) send_byte(8'hFF);
        #1000;

        // Test 1: CMD0 (GO_IDLE_STATE)
        $display("\n=== Test 1: CMD0 (GO_IDLE_STATE) ===");
        spi_cs_n = 0;  // Assert CS
        #100;
        send_cmd(0, 32'h00000000);
        wait_r1_response(response_byte);
        if (response_byte == 8'h01) begin
            $display("[TB] PASS: CMD0 returned 0x01 (idle state)");
        end else begin
            $display("[TB] FAIL: CMD0 returned 0x%02x (expected 0x01)", response_byte);
        end
        spi_cs_n = 1;  // Deassert CS
        #1000;

        // Test 2: CMD8 (SEND_IF_COND)
        $display("\n=== Test 2: CMD8 (SEND_IF_COND) ===");
        spi_cs_n = 0;
        #100;
        send_cmd(8, 32'h000001AA);
        wait_r1_response(response_byte);
        if (response_byte == 8'h01) begin
            $display("[TB] PASS: CMD8 returned 0x01");
            // Read the 4-byte R7 response
            receive_byte(response_byte);
            $display("[TB] R7 byte 1: 0x%02x", response_byte);
            receive_byte(response_byte);
            $display("[TB] R7 byte 2: 0x%02x", response_byte);
            receive_byte(response_byte);
            $display("[TB] R7 byte 3 (VHS): 0x%02x", response_byte);
            receive_byte(response_byte);
            $display("[TB] R7 byte 4 (pattern): 0x%02x", response_byte);
        end else begin
            $display("[TB] FAIL: CMD8 returned 0x%02x (expected 0x01)", response_byte);
        end
        spi_cs_n = 1;
        #1000;

        // Test 3: CMD55 (APP_CMD)
        $display("\n=== Test 3: CMD55 (APP_CMD) ===");
        spi_cs_n = 0;
        #100;
        send_cmd(55, 32'h00000000);
        wait_r1_response(response_byte);
        if (response_byte == 8'h01) begin
            $display("[TB] PASS: CMD55 returned 0x01");
        end else begin
            $display("[TB] FAIL: CMD55 returned 0x%02x (expected 0x01)", response_byte);
        end
        spi_cs_n = 1;
        #1000;

        // Test 4: ACMD41 (SD_SEND_OP_COND)
        $display("\n=== Test 4: ACMD41 (SD_SEND_OP_COND) ===");
        spi_cs_n = 0;
        #100;
        send_cmd(41, 32'h40000000);  // HCS bit set
        wait_r1_response(response_byte);
        if (response_byte == 8'h00) begin
            $display("[TB] PASS: ACMD41 returned 0x00 (ready)");
        end else begin
            $display("[TB] FAIL: ACMD41 returned 0x%02x (expected 0x00)", response_byte);
        end
        spi_cs_n = 1;
        #1000;

        // Test 5: CMD58 (READ_OCR)
        $display("\n=== Test 5: CMD58 (READ_OCR) ===");
        spi_cs_n = 0;
        #100;
        send_cmd(58, 32'h00000000);
        wait_r1_response(response_byte);
        if (response_byte == 8'h00) begin
            $display("[TB] PASS: CMD58 returned 0x00");
            // Read OCR (4 bytes)
            receive_byte(response_byte);
            if (response_byte[7] && response_byte[6]) begin
                $display("[TB] PASS: OCR byte 0: 0x%02x (power up complete + CCS/SDHC)", response_byte);
            end else begin
                $display("[TB] FAIL: OCR byte 0: 0x%02x (expected bit 7=power up, bit 6=CCS)", response_byte);
            end
            receive_byte(response_byte);
            $display("[TB] OCR byte 1: 0x%02x", response_byte);
            receive_byte(response_byte);
            $display("[TB] OCR byte 2: 0x%02x", response_byte);
            receive_byte(response_byte);
            $display("[TB] OCR byte 3: 0x%02x", response_byte);
        end else begin
            $display("[TB] FAIL: CMD58 returned 0x%02x (expected 0x00)", response_byte);
        end
        spi_cs_n = 1;
        #1000;

        // Test 6: CMD9 (SEND_CSD)
        $display("\n=== Test 6: CMD9 (SEND_CSD) ===");
        spi_cs_n = 0;
        #100;
        send_cmd(9, 32'h00000000);
        wait_r1_response(response_byte);
        if (response_byte == 8'h00) begin
            $display("[TB] PASS: CMD9 returned 0x00");
            // Read data token
            receive_byte(response_byte);
            if (response_byte == 8'hFE) begin
                $display("[TB] PASS: Received data token 0xFE");
                // Read 16 CSD bytes
                for (int i = 0; i < 16; i++) begin
                    receive_byte(response_byte);
                    $display("[TB] CSD[%0d]: 0x%02x", i, response_byte);
                end
                // Read CRC16 (2 bytes)
                receive_byte(response_byte);
                $display("[TB] CRC high byte: 0x%02x", response_byte);
                receive_byte(response_byte);
                $display("[TB] CRC low byte: 0x%02x", response_byte);
            end else begin
                $display("[TB] FAIL: Expected data token 0xFE, got 0x%02x", response_byte);
            end
        end else begin
            $display("[TB] FAIL: CMD9 returned 0x%02x (expected 0x00)", response_byte);
        end
        spi_cs_n = 1;
        #1000;

        // Test 7: CMD10 (SEND_CID)
        $display("\n=== Test 7: CMD10 (SEND_CID) ===");
        spi_cs_n = 0;
        #100;
        send_cmd(10, 32'h00000000);
        wait_r1_response(response_byte);
        if (response_byte == 8'h00) begin
            $display("[TB] PASS: CMD10 returned 0x00");
            // Read data token
            receive_byte(response_byte);
            if (response_byte == 8'hFE) begin
                $display("[TB] PASS: Received data token 0xFE");
                // Read 16 CID bytes
                for (int i = 0; i < 16; i++) begin
                    receive_byte(response_byte);
                    $display("[TB] CID[%0d]: 0x%02x", i, response_byte);
                end
                // Read CRC16 (2 bytes)
                receive_byte(response_byte);
                $display("[TB] CRC high byte: 0x%02x", response_byte);
                receive_byte(response_byte);
                $display("[TB] CRC low byte: 0x%02x", response_byte);
            end else begin
                $display("[TB] FAIL: Expected data token 0xFE, got 0x%02x", response_byte);
            end
        end else begin
            $display("[TB] FAIL: CMD10 returned 0x%02x (expected 0x00)", response_byte);
        end
        spi_cs_n = 1;
        #1000;

        // Test 8: CMD16 (SET_BLOCKLEN)
        $display("\n=== Test 8: CMD16 (SET_BLOCKLEN) ===");
        spi_cs_n = 0;
        #100;
        send_cmd(16, 32'd512);
        wait_r1_response(response_byte);
        if (response_byte == 8'h00) begin
            $display("[TB] PASS: CMD16 with 512 bytes returned 0x00");
        end else begin
            $display("[TB] FAIL: CMD16 returned 0x%02x (expected 0x00)", response_byte);
        end
        spi_cs_n = 1;
        #1000;

        // Test invalid block length
        $display("\n=== Test 8b: CMD16 with invalid length ===");
        spi_cs_n = 0;
        #100;
        send_cmd(16, 32'd256);
        wait_r1_response(response_byte);
        if (response_byte == 8'h40) begin
            $display("[TB] PASS: CMD16 with 256 bytes returned 0x40 (error)");
        end else begin
            $display("[TB] FAIL: CMD16 returned 0x%02x (expected 0x40)", response_byte);
        end
        spi_cs_n = 1;
        #1000;

        // Test 9: CMD13 (SEND_STATUS)
        $display("\n=== Test 9: CMD13 (SEND_STATUS) ===");
        spi_cs_n = 0;
        #100;
        send_cmd(13, 32'h00000000);
        wait_r1_response(response_byte);
        if (response_byte == 8'h00) begin
            $display("[TB] PASS: CMD13 returned R1=0x00");
            // Read status byte (R2 response)
            receive_byte(response_byte);
            if (response_byte == 8'h00) begin
                $display("[TB] PASS: Status byte: 0x00 (no errors)");
            end else begin
                $display("[TB] FAIL: Status byte: 0x%02x (expected 0x00)", response_byte);
            end
        end else begin
            $display("[TB] FAIL: CMD13 returned 0x%02x (expected 0x00)", response_byte);
        end
        spi_cs_n = 1;
        #1000;

        // Test 10: CMD17 (READ_SINGLE_BLOCK)
        $display("\n=== Test 10: CMD17 (READ_SINGLE_BLOCK) ===");
        spi_cs_n = 0;
        #100;
        send_cmd(17, 32'h00000000);  // Block 0
        wait_r1_response(response_byte);
        if (response_byte == 8'h00) begin
            $display("[TB] PASS: CMD17 returned 0x00");
            // Read data token
            receive_byte(response_byte);
            if (response_byte == 8'hFE) begin
                $display("[TB] PASS: Received data token 0xFE");

                // Read 512 data bytes and verify
                for (int i = 0; i < 512; i++) begin
                    receive_byte(response_byte);
                    block_data[i] = response_byte;
                end

                // Calculate CRC16-CCITT
                calculated_crc = 16'h0000;
                for (int byte_idx = 0; byte_idx < 512; byte_idx++) begin
                    for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
                        crc_bit = calculated_crc[15] ^ block_data[byte_idx][bit_idx];
                        calculated_crc = {calculated_crc[14:0], 1'b0};
                        if (crc_bit)
                            calculated_crc = calculated_crc ^ 16'h1021;
                    end
                end

                // Read CRC16
                receive_byte(response_byte);
                received_crc[15:8] = response_byte;
                receive_byte(response_byte);
                received_crc[7:0] = response_byte;

                // Verify CRC
                if (calculated_crc == received_crc) begin
                    $display("[TB] PASS: CRC16 matches (0x%04x)", calculated_crc);
                end else begin
                    $display("[TB] FAIL: CRC16 mismatch - calculated 0x%04x, received 0x%04x",
                             calculated_crc, received_crc);
                end

                // Verify FAT12 signature at offset 0x36
                if (block_data[8'h36] == 8'h46 &&  // 'F'
                    block_data[8'h37] == 8'h41 &&  // 'A'
                    block_data[8'h38] == 8'h54 &&  // 'T'
                    block_data[8'h39] == 8'h31 &&  // '1'
                    block_data[8'h3A] == 8'h32) begin  // '2'
                    $display("[TB] PASS: FAT12 signature found at offset 0x36");
                end else begin
                    $display("[TB] FAIL: FAT12 signature not found at offset 0x36");
                    $display("[TB]       Got: 0x%02x 0x%02x 0x%02x 0x%02x 0x%02x",
                             block_data[8'h36], block_data[8'h37], block_data[8'h38],
                             block_data[8'h39], block_data[8'h3A]);
                    $display("[TB]       Expected: 0x46 0x41 0x54 0x31 0x32 (FAT12)");
                end

                // Display some interesting bytes
                $display("[TB] Block 0 data samples:");
                $display("[TB]   [0x000]: 0x%02x (boot jump)", block_data[0]);
                $display("[TB]   [0x036-0x03A]: %c%c%c%c%c (filesystem type)",
                         block_data[8'h36], block_data[8'h37], block_data[8'h38],
                         block_data[8'h39], block_data[8'h3A]);
                $display("[TB]   [0x1FE-0x1FF]: 0x%02x 0x%02x (boot signature)",
                         block_data[9'h1FE], block_data[9'h1FF]);

            end else begin
                $display("[TB] FAIL: Expected data token 0xFE, got 0x%02x", response_byte);
            end
        end else begin
            $display("[TB] FAIL: CMD17 returned 0x%02x (expected 0x00)", response_byte);
        end
        spi_cs_n = 1;
        #1000;

        // Test 11: CMD18 + CMD12 (READ_MULTIPLE_BLOCK + STOP_TRANSMISSION)
        $display("\n=== Test 11: CMD18 (READ_MULTIPLE_BLOCK) ===");
        spi_cs_n = 0;
        #100;
        send_cmd(18, 32'h00000000);  // Start at block 0
        wait_r1_response(response_byte);
        if (response_byte == 8'h00) begin
            $display("[TB] PASS: CMD18 returned 0x00");

            // Read first block
            receive_byte(response_byte);
            if (response_byte == 8'hFE) begin
                $display("[TB] PASS: Received first block token 0xFE");
                // Skip block data + CRC
                for (int i = 0; i < 514; i++) begin
                    receive_byte(response_byte);
                end
            end

            // Read second block (should auto-send)
            receive_byte(response_byte);
            if (response_byte == 8'hFE) begin
                $display("[TB] PASS: Received second block token 0xFE");
                // Skip block data + CRC
                for (int i = 0; i < 514; i++) begin
                    receive_byte(response_byte);
                end
            end

            // Send CMD12 to stop
            $display("\n=== Test 11b: CMD12 (STOP_TRANSMISSION) ===");
            send_cmd(12, 32'h00000000);
            wait_r1_response(response_byte);
            if (response_byte == 8'h00) begin
                $display("[TB] PASS: CMD12 returned R1=0x00");
                // Read stuff byte
                receive_byte(response_byte);
                $display("[TB] Stuff byte: 0x%02x", response_byte);
                // Read busy token
                receive_byte(response_byte);
                $display("[TB] Busy token: 0x%02x", response_byte);
            end else begin
                $display("[TB] FAIL: CMD12 returned 0x%02x (expected 0x00)", response_byte);
            end
        end else begin
            $display("[TB] FAIL: CMD18 returned 0x%02x (expected 0x00)", response_byte);
        end
        spi_cs_n = 1;
        #1000;

        $display("\n=== Test Complete ===");
        $display("Check MISO signal behavior above.");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000000; // 100ms timeout
        $display("[TB] ERROR: Simulation timeout!");
        $finish;
    end

endmodule
