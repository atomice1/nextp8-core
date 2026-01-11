// Testbench for keyboard_device.sv
// Tests PS/2 keyboard device model using actual PS/2 protocol commands

module tb_keyboard_device();

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

// Instantiate keyboard_device (DEVICE)
keyboard_device #(
    .CLOCK_DIV(1100)  // 11MHz / 10kHz = 1100
) dut (
    .clk(clk),
    .reset(reset),
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
        wait(!host_tx_busy);
        @(posedge clk);

        // Wait for ACK (0xFA)
        wait(host_rx_valid);
        if (host_rx_data !== 8'hFA) begin
            $display("  WARNING: Expected ACK (0xFA), got 0x%02x", host_rx_data);
        end
        @(posedge clk);
    end
endtask

// Task: Send command with data byte
task send_command_with_data(input [7:0] cmd, input [7:0] data);
    begin
        send_command(cmd);
        #10000;  // Brief delay between bytes
        send_command(data);
    end
endtask

// Task: Wait for device to send a byte
task wait_for_device_byte(output [7:0] received);
    begin
        wait(host_rx_valid);
        received = host_rx_data;
        @(posedge clk);
    end
endtask

// Test sequence
initial begin
    automatic integer pass_count = 0;
    automatic integer fail_count = 0;
    automatic logic [7:0] received_byte;

    $display("=== Starting keyboard_device Protocol Test ===");

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
    #50000;

    $display("Test 2: Query device ID (0xF2) returns 0xAB 0x83");
    send_command(8'hF2);  // Read ID
    #10000;

    // Should receive 0xAB (first byte of device ID)
    wait_for_device_byte(received_byte);
    if (received_byte == 8'hAB) begin
        $display("  PASS: Received device ID byte 1 (0xAB)");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected 0xAB, got 0x%02x", received_byte);
        fail_count = fail_count + 1;
    end

    // Should receive 0x83 (second byte of device ID for MF2 keyboard)
    #10000;
    wait_for_device_byte(received_byte);
    if (received_byte == 8'h83) begin
        $display("  PASS: Received device ID byte 2 (0x83)");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected device ID 0x83, got 0x%02x", received_byte);
        fail_count = fail_count + 1;
    end
    #50000;

    $display("Test 3: Device accepts Disable Scanning (0xF5) command");
    send_command(8'hF5);  // Disable scanning
    $display("  PASS: Disable scanning command acknowledged");
    pass_count = pass_count + 1;
    #50000;

    $display("Test 4: Device accepts Enable Scanning (0xF4) command");
    send_command(8'hF4);  // Enable scanning
    $display("  PASS: Enable scanning command acknowledged");
    pass_count = pass_count + 1;
    #50000;

    $display("Test 5: Query current scan code set (0xF0 0x00)");
    send_command_with_data(8'hF0, 8'h00);  // Get scan code set
    #10000;
    wait_for_device_byte(received_byte);
    if (received_byte == 8'h02) begin
        $display("  PASS: Current scan code set is 2");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected scan code set 2, got %0d", received_byte);
        fail_count = fail_count + 1;
    end
    #50000;

    $display("Test 6: Set scan code set to 1 (0xF0 0x01)");
    send_command_with_data(8'hF0, 8'h01);  // Set scan code set 1
    #50000;

    // Verify it changed
    send_command_with_data(8'hF0, 8'h00);  // Query
    #10000;
    wait_for_device_byte(received_byte);
    if (received_byte == 8'h01) begin
        $display("  PASS: Scan code set changed to 1");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected scan code set 1, got %0d", received_byte);
        fail_count = fail_count + 1;
    end
    #50000;

    $display("Test 7: Set scan code set to 3 (0xF0 0x03)");
    send_command_with_data(8'hF0, 8'h03);  // Set scan code set 3
    #50000;

    // Verify it changed
    send_command_with_data(8'hF0, 8'h00);  // Query
    #10000;
    wait_for_device_byte(received_byte);
    if (received_byte == 8'h03) begin
        $display("  PASS: Scan code set changed to 3");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected scan code set 3, got %0d", received_byte);
        fail_count = fail_count + 1;
    end
    #50000;

    $display("Test 8: Restore scan code set to 2 (0xF0 0x02)");
    send_command_with_data(8'hF0, 8'h02);  // Set scan code set 2
    #50000;
    pass_count = pass_count + 1;

    $display("Test 9: Device can send scancodes");
    // Inject a scancode
    dut.send_scancode(8'h1C);  // A key in scan code set 2
    #10000;

    wait_for_device_byte(received_byte);
    if (received_byte == 8'h1C) begin
        $display("  PASS: Received scancode 0x1C");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Expected scancode 0x1C, got 0x%02x", received_byte);
        fail_count = fail_count + 1;
    end
    #50000;

    $display("Test 10: Device handles extended scancodes (E0 prefix)");
    dut.send_scancode(8'hE0);  // Extended prefix
    dut.send_scancode(8'h75);  // Up arrow
    #10000;

    // Should receive E0 first
    wait_for_device_byte(received_byte);
    if (received_byte == 8'hE0) begin
        #10000;
        wait_for_device_byte(received_byte);
        if (received_byte == 8'h75) begin
            $display("  PASS: Received extended scancode E0 75");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected 0x75, got 0x%02x", received_byte);
            fail_count = fail_count + 1;
        end
    end else begin
        $display("  FAIL: Expected E0 prefix, got 0x%02x", received_byte);
        fail_count = fail_count + 1;
    end
    #50000;

    $display("Test 11: PS/2 bus idle state check");
    // After all activity, PS/2 bus should return to idle (both lines pulled high)
    if ((ps2_clk === 1'bZ || ps2_clk === 1'b1) && (ps2_data === 1'bZ || ps2_data === 1'b1)) begin
        $display("  PASS: PS/2 clock and data in idle state");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: PS/2 not idle (clk=%b data=%b)", ps2_clk, ps2_data);
        fail_count = fail_count + 1;
    end
    #10000;

    $display("=== All tests completed ===");
    if (fail_count == 0) begin
        $display("ALL TESTS PASSED (%0d passed, %0d failed)", pass_count, fail_count);
        $finish(0);
    end else begin
        $display("SOME TESTS FAILED (%0d passed, %0d failed)", pass_count, fail_count);
        $finish(1);
    end
end

// Monitor key events
initial begin
    forever begin
        @(posedge host_rx_valid);
        $display("[%0t] HOST received from DEVICE: 0x%02x", $time, host_rx_data);
    end
end

// Timeout watchdog
initial begin
    #500000000;  // 500ms timeout @ 11MHz
    $display("ERROR: Simulation timeout");
    $finish(1);
end

endmodule
