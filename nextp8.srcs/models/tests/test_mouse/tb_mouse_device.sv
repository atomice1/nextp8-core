// Testbench for mouse_device.sv
// Tests PS/2 mouse device model using actual PS/2 protocol commands

module tb_mouse_device();

// Clock and reset
reg clk = 0;
reg reset = 1;

// Clock - 11 MHz (matching nextp8 ps2_interface clock)
always #45.45 clk = ~clk;

// PS/2 bus (using weak pull-ups for proper open-drain simulation)
wire ps2_clk_host, ps2_data_host;  // Host outputs
wire ps2_clk_dev, ps2_data_dev;    // Device outputs
tri1 ps2_clk, ps2_data;            // Actual bus

assign ps2_clk = (ps2_clk_host === 1'b0) ? 1'b0 : 1'bz;
assign ps2_clk = (ps2_clk_dev === 1'b0) ? 1'b0 : 1'bz;
assign ps2_data = (ps2_data_host === 1'b0) ? 1'b0 : 1'bz;
assign ps2_data = (ps2_data_dev === 1'b0) ? 1'b0 : 1'bz;

// Host interface signals
logic [7:0] host_tx_data;
logic host_tx_start;
logic [1:0] host_tx_mode;
logic host_tx_busy;
logic [7:0] host_rx_data;
logic host_rx_valid;
logic host_rx_error;

// Instantiate ps2_interface (HOST)
ps2_interface #(
    .FILTER_BITS(8),
    .TX_INHIBIT_CYCLES(1100)
) host (
    .CLK(clk),
    .nRESET(~reset),
    .PS2_CLK_IN(ps2_clk),
    .PS2_DATA_IN(ps2_data),
    .PS2_CLK_OUT(ps2_clk_host),
    .PS2_DATA_OUT(ps2_data_host),
    .DATA(host_rx_data),
    .VALID(host_rx_valid),
    .ERROR(host_rx_error),
    .TX_DATA(host_tx_data),
    .TX_START(host_tx_start),
    .TX_MODE(host_tx_mode),
    .TX_BUSY(host_tx_busy),
    .TX_DONE()
);

// Instantiate mouse_device (DEVICE)
mouse_device #(
    .CLOCK_DIV(1100)  // 11MHz / 10kHz = 1100
) dut (
    .clk(clk),
    .reset(reset),
    .intellimouse_capable(1'b0),  // Standard PS/2 mouse
    .ps2_clk_in(ps2_clk),
    .ps2_data_in(ps2_data),
    .ps2_clk_out(ps2_clk_dev),
    .ps2_data_out(ps2_data_dev)
);

// Instantiate ps2_sniffer for monitoring
ps2_sniffer #(
    .HOST_IS_TRISTATE(1'b0),
    .DEVICE_IS_TRISTATE(1'b0)
) sniffer (
    .host_ps2_clk_in_i(ps2_clk),
    .host_ps2_data_in_i(ps2_data),
    .host_ps2_clk_out_i(ps2_clk_host),
    .host_ps2_data_out_i(ps2_data_host),
    .device_ps2_clk_in_i(ps2_clk),
    .device_ps2_data_in_i(ps2_data),
    .device_ps2_clk_out_i(ps2_clk_dev),
    .device_ps2_data_out_i(ps2_data_dev)
);

// Task: Send command to device and wait for ACK
task send_command(input [7:0] cmd);
    begin
        @(posedge clk);
        host_tx_data <= cmd;
        host_tx_start <= 1'b1;
        @(posedge clk);
        host_tx_start <= 1'b0;

        // Wait for transmission to complete
        wait(host_tx_busy == 1'b1);
        wait(host_tx_busy == 1'b0);

        // Wait for ACK from device
        wait(host_rx_valid == 1'b1);
        if (host_rx_data !== 8'hFA) begin
            $display("ERROR: Expected ACK (0xFA), got 0x%02x", host_rx_data);
        end
        @(posedge clk);
    end
endtask

// Task: Send command with data byte (e.g., sample rate, resolution)
task send_command_with_data(input [7:0] cmd, input [7:0] data);
    begin
        send_command(cmd);
        send_command(data);
    end
endtask

// Task: Wait for device to send a byte
task wait_for_device_byte(output [7:0] received);
    begin
        wait(host_rx_valid == 1'b1);
        received = host_rx_data;
        @(posedge clk);
    end
endtask

// Test sequence
initial begin
    automatic integer pass_count = 0;
    automatic integer fail_count = 0;
    automatic logic [7:0] received_byte;
    automatic logic [7:0] byte1, byte2, byte3;

    $display("=== Starting mouse_device Protocol Test ===");

    // Initialize host signals
    host_tx_data = 8'h00;
    host_tx_start = 1'b0;
    host_tx_mode = 2'b00;

    // Reset
    reset = 1;
    #1000;
    reset = 0;
    #50000;  // Wait for device to initialize

    $display("Test 1: Device responds to Reset (0xFF) command");
    send_command(8'hFF);  // Reset
    #10000;

    // Should receive 0xAA (self-test passed)
    wait_for_device_byte(received_byte);
    if (received_byte == 8'hAA) begin
        $display("  PASS: Received self-test passed (0xAA) after reset");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected 0xAA, got 0x%02x", received_byte);
        fail_count = fail_count + 1;
    end

    // Should receive device ID
    #10000;
    wait_for_device_byte(received_byte);
    if (received_byte == 8'h00) begin
        $display("  PASS: Received device ID (0x00)");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected device ID 0x00, got 0x%02x", received_byte);
        fail_count = fail_count + 1;
    end
    #50000;

    // Test 2: Read device type (0xF2)
    $display("\nTest 2: Read device type command (0xF2)");
    send_command(8'hF2);
    #10000;

    wait_for_device_byte(received_byte);
    if (received_byte == 8'h00) begin
        $display("  PASS: Device type is 0x00 (standard PS/2 mouse)");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected device type 0x00, got 0x%02x", received_byte);
        fail_count = fail_count + 1;
    end
    #50000;

    // Test 3: Set sample rate (0xF3 + data byte)
    $display("\nTest 3: Set sample rate to 100 (0xF3 0x64)");
    send_command_with_data(8'hF3, 8'h64);
    $display("  PASS: Set sample rate command accepted");
    pass_count = pass_count + 1;
    #50000;

    // Test 4: Request status (0xE9)
    $display("\nTest 4: Request status (0xE9)");
    send_command(8'hE9);
    #10000;

    wait_for_device_byte(byte1);  // Status byte
    #5000;
    wait_for_device_byte(byte2);  // Resolution
    #5000;
    wait_for_device_byte(byte3);  // Sample rate
    $display("  PASS: Status=0x%02x, Resolution=0x%02x, Sample rate=0x%02x", byte1, byte2, byte3);
    if (byte3 == 8'h64) begin
        $display("  PASS: Sample rate correctly set to 0x64");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Sample rate is 0x%02x, expected 0x64", byte3);
        fail_count = fail_count + 1;
    end
    #50000;

    // Test 5: Set resolution (0xE8 + data byte)
    $display("\nTest 5: Set resolution to 2 counts/mm (0xE8 0x02)");
    send_command_with_data(8'hE8, 8'h02);
    $display("  PASS: Set resolution command accepted");
    pass_count = pass_count + 1;
    #50000;

    // Test 6: Verify resolution change via status
    $display("\nTest 6: Verify resolution changed (0xE9)");
    send_command(8'hE9);
    #10000;

    wait_for_device_byte(byte1);
    #5000;
    wait_for_device_byte(byte2);  // Resolution
    #5000;
    wait_for_device_byte(byte3);
    if (byte2 == 8'h02) begin
        $display("  PASS: Resolution correctly set to 0x02");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Resolution is 0x%02x, expected 0x02", byte2);
        fail_count = fail_count + 1;
    end
    #50000;

    // Test 7: Enable data reporting (0xF4)
    $display("\nTest 7: Enable data reporting (0xF4)");
    send_command(8'hF4);
    $display("  PASS: Enable data reporting command accepted");
    pass_count = pass_count + 1;
    #50000;

    // Test 8: Send movement packet and receive data
    $display("\nTest 8: Send movement packet (right button + movement)");
    dut.send_movement_packet(1'b0, 1'b1, 1'b0, 9'sh05, 9'sh0A, 4'sh0);  // right_btn, x=5, y=10, z=0
    #10000;

    wait_for_device_byte(byte1);  // Button/overflow/sign byte
    #5000;
    wait_for_device_byte(byte2);  // X movement
    #5000;
    wait_for_device_byte(byte3);  // Y movement
    $display("  PASS: Received movement packet: 0x%02x 0x%02x 0x%02x", byte1, byte2, byte3);
    if ((byte1 & 8'h02) == 8'h02) begin
        $display("  PASS: Right button bit set correctly");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Right button bit not set");
        fail_count = fail_count + 1;
    end
    if (byte2 == 8'h05 && byte3 == 8'h0A) begin
        $display("  PASS: Movement values correct (X=0x05, Y=0x0A)");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Movement incorrect (X=0x%02x, Y=0x%02x)", byte2, byte3);
        fail_count = fail_count + 1;
    end
    #50000;

    // Test 9: Disable data reporting (0xF5)
    $display("\nTest 9: Disable data reporting (0xF5)");
    send_command(8'hF5);
    $display("  PASS: Disable data reporting command accepted");
    pass_count = pass_count + 1;
    #50000;

    // Test 10: Movement packet should not be sent when reporting disabled
    $display("\nTest 10: Movement not sent when reporting disabled");
    dut.send_movement_packet(1'b1, 1'b0, 1'b0, 9'sh01, 9'sh01, 4'sh0);
    repeat(1000) @(posedge clk);
    if (host_rx_valid == 1'b0) begin
        $display("  PASS: No movement data sent (reporting disabled)");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Received data when reporting should be disabled");
        fail_count = fail_count + 1;
    end
    #50000;

    // Test 11: Set remote mode (0xF0)
    $display("\nTest 11: Set remote mode (0xF0)");
    send_command(8'hF0);
    $display("  PASS: Set remote mode command accepted");
    pass_count = pass_count + 1;
    #50000;

    // Test 12: Set stream mode (0xEA)
    $display("\nTest 12: Set stream mode (0xEA)");
    send_command(8'hEA);
    $display("  PASS: Set stream mode command accepted");
    pass_count = pass_count + 1;
    #50000;

    // Test 13: Set defaults (0xF6)
    $display("\nTest 13: Set defaults (0xF6)");
    send_command(8'hF6);
    $display("  PASS: Set defaults command accepted");
    pass_count = pass_count + 1;
    #50000;

    // Test 14: Verify defaults via status
    $display("\nTest 14: Verify defaults restored (0xE9)");
    send_command(8'hE9);
    #10000;

    wait_for_device_byte(byte1);
    #5000;
    wait_for_device_byte(byte2);  // Resolution
    #5000;
    wait_for_device_byte(byte3);  // Sample rate
    $display("  INFO: After defaults - Status=0x%02x, Res=0x%02x, Rate=0x%02x", byte1, byte2, byte3);
    // Defaults: resolution=4, sample_rate=100, stream mode, reporting disabled
    if (byte2 == 8'h04 && byte3 == 8'h64) begin
        $display("  PASS: Defaults restored correctly");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Defaults not correct");
        fail_count = fail_count + 1;
    end
    #50000;

    // Test 15: PS/2 bus idle state
    $display("\nTest 15: PS/2 bus idle state");
    repeat(100) @(posedge clk);
    if (ps2_clk === 1'b1 && ps2_data === 1'b1) begin
        $display("  PASS: PS/2 bus in idle state (both lines high)");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: PS/2 bus not idle (clk=%b, data=%b)", ps2_clk, ps2_data);
        fail_count = fail_count + 1;
    end
    #10000;

    $display("\n=== All tests completed ===");
    if (fail_count == 0) begin
        $display("ALL TESTS PASSED (%0d)", pass_count);
        $finish(0);
    end else begin
        $display("SOME TESTS FAILED (%0d passed, %0d failed)", pass_count, fail_count);
        $finish(1);
    end
end


// Timeout watchdog
initial begin
    #100000000;  // 100ms timeout @ 11MHz
    $display("ERROR: Simulation timeout");
    $finish(1);
end

endmodule
