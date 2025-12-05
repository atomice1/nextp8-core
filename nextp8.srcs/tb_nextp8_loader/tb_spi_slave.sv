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

module tb_spi_slave();

    // System clock - 28 MHz (fast clock for slave synchronization)
    reg clk = 0;
    reg reset = 1;
    always #17.857 clk = ~clk;

    // SPI signals
    reg spi_cs_n = 1;
    reg spi_clk = 0;
    reg spi_mosi = 1;
    wire spi_miso;

    // Slave parallel interface
    wire [7:0] rx_data;
    wire rx_valid;
    reg [7:0] tx_data = 8'hA5;
    reg tx_dv = 0;

    // Test data
    reg [7:0] test_byte;
    reg [7:0] received_byte;
    reg [7:0] received_bytes [0:7];  // Buffer for multiple received bytes
    integer received_count;
    integer i;

    // Instantiate SPI slave
    spi_slave #(.SPI_MODE(0)) dut (
        .i_Rst_L(~reset),
        .i_Clk(clk),
        .o_RX_DV(rx_valid),
        .o_RX_Byte(rx_data),
        .i_TX_DV(tx_dv),
        .i_TX_Byte(tx_data),
        .i_SPI_Clk(spi_clk),
        .o_SPI_MISO(spi_miso),
        .i_SPI_MOSI(spi_mosi),
        .i_SPI_CS_n(spi_cs_n)
    );

    // SPI clock generation (7 MHz - 4x slower than 28 MHz system clock)
    always #71.428 spi_clk = ~spi_clk;

    // Capture received bytes
    always @(posedge clk) begin
        if (rx_valid) begin
            received_byte = rx_data;
            received_bytes[received_count] = rx_data;
            received_count = received_count + 1;
            $display("[%0t] Slave received byte: 0x%02x", $time, rx_data);
        end
    end

    // Initialize received count
    initial begin
        received_count = 0;
    end

    // Task to send a byte as SPI master
    task send_byte_master(input [7:0] data);
        integer j;
        begin
            $display("[%0t] Master sending: 0x%02x", $time, data);
            for (j = 7; j >= 0; j = j - 1) begin
                @(negedge spi_clk);
                spi_mosi = data[j];
            end
            // After last bit, wait for it to be sampled and add guard time
            @(posedge spi_clk);  // Let the last bit be sampled
            @(negedge spi_clk);  // Move to next negedge
            spi_mosi = 1'b1;     // Return MOSI to idle high
        end
    endtask

    // Task to receive a byte as SPI master
    task receive_byte_master(output [7:0] data);
        integer j;
        begin
            data = 8'h00;
            // Send 0xFF while receiving
            for (j = 7; j >= 0; j = j - 1) begin
                @(negedge spi_clk);
                spi_mosi = 1'b1;
                @(posedge spi_clk);
                #1;  // Small delay after edge
                data[j] = spi_miso;
            end
            $display("[%0t] Master received: 0x%02x", $time, data);
        end
    endtask

    // Main test
    initial begin
        $display("=== SPI Slave Module Test ===\n");

        // Initialize
        reset = 1;
        spi_cs_n = 1;
        spi_mosi = 1;
        #200;
        reset = 0;
        #1000;

        // Test 1: Send byte to slave
        $display("Test 1: Master sends 0x42 to slave");
        spi_cs_n = 0;
        #100;
        send_byte_master(8'h42);
        #500;
        if (received_byte == 8'h42) begin
            $display("PASS: Slave correctly received 0x42\n");
        end else begin
            $display("FAIL: Expected 0x42, got 0x%02x\n", received_byte);
        end
        spi_cs_n = 1;
        #1000;

        // Test 2: Receive byte from slave
        $display("Test 2: Master receives from slave (slave TX=0xA5)");
        tx_data = 8'hA5;
        tx_dv = 1;
        @(posedge clk);
        tx_dv = 0;
        #100;
        spi_cs_n = 0;
        #100;
        receive_byte_master(test_byte);
        if (test_byte == 8'hA5) begin
            $display("PASS: Master correctly received 0xA5\n");
        end else begin
            $display("FAIL: Expected 0xA5, got 0x%02x\n", test_byte);
        end
        spi_cs_n = 1;
        #1000;

        // Test 3: Simultaneous TX/RX (full duplex)
        $display("Test 3: Full duplex - Master sends 0x55, Slave sends 0xAA");
        tx_data = 8'hAA;
        tx_dv = 1;
        @(posedge clk);
        tx_dv = 0;
        #100;
        spi_cs_n = 0;
        #100;

        // Send and receive simultaneously
        test_byte = 8'h00;
        $display("[%0t] Starting full duplex transfer", $time);
        test_byte = 8'h55;
        for (i = 7; i >= 0; i = i - 1) begin
            @(negedge spi_clk);
            spi_mosi = test_byte[i];
            @(posedge spi_clk);
            #1;
            test_byte[i] = spi_miso;
        end

        #500;
        $display("[%0t] Master sent 0x55, received 0x%02x", $time, test_byte);
        $display("[%0t] Slave received 0x%02x", $time, received_byte);

        if (received_byte == 8'h55 && test_byte == 8'hAA) begin
            $display("PASS: Full duplex successful\n");
        end else begin
            $display("FAIL: Full duplex error\n");
        end
        spi_cs_n = 1;
        #1000;

        // Test 4: Multiple consecutive bytes
        // Note: Must toggle CS between bytes for proper operation
        $display("Test 4: Send three consecutive bytes (with CS toggle)");
        received_count = 0;  // Reset counter for this test
        spi_cs_n = 0;
        #100;
        send_byte_master(8'h11);
        #200;  // Wait for byte to be fully processed
        spi_cs_n = 1;
        #200;
        spi_cs_n = 0;
        #100;
        send_byte_master(8'h22);
        #200;
        spi_cs_n = 1;
        #200;
        spi_cs_n = 0;
        #100;
        send_byte_master(8'h33);
        #200;
        spi_cs_n = 1;
        #500;
        #100;

        // Validate received bytes
        if (received_count == 3 &&
            received_bytes[0] == 8'h11 &&
            received_bytes[1] == 8'h22 &&
            received_bytes[2] == 8'h33) begin
            $display("PASS: All three bytes received correctly\n");
        end else begin
            $display("FAIL: Expected 3 bytes [0x11, 0x22, 0x33], got %0d bytes:", received_count);
            for (i = 0; i < received_count; i = i + 1) begin
                $display("  Byte %0d: 0x%02x", i, received_bytes[i]);
            end
            $display("");
        end

        #1000;
        $display("=== All tests complete ===");
        $finish;
    end

    // Timeout
    initial begin
        #100000;
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule
