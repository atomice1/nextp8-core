// PS/2 Interface HOST Mode Testbench
// Tests ps2_interface in HOST mode by simulating a PS/2 device
// sending frames with various scan codes and verifying VALID/ERROR outputs.
// Copyright (C) 2026 Chris January

`timescale 1ns/1ns

module tb_ps2_interface();

// Constants
localparam CLK_PERIOD = 10;  // 10 ns -> 100 MHz system clock
localparam PS2_CLK_PERIOD = 100000;  // 100 us -> ~10 kHz PS/2 clock (typical range 10-16.7 kHz)

// Clock and reset
reg clk = 0;
reg nreset = 0;

// PS/2 bus signals with open-drain resolution using weak pullups
wire ps2_clk_bus;
wire ps2_data_bus;
reg ps2_clk_tb = 1;
reg ps2_data_tb = 1;
wire ps2_clk_out;
wire ps2_data_out;

// Weak pullups for PS/2 open-drain bus (any driver pulling low wins)
assign (weak1, weak0) ps2_clk_bus = 1'b1;
assign (weak1, weak0) ps2_data_bus = 1'b1;

// Open-drain resolution: any driver pulling low wins
assign ps2_clk_bus = (ps2_clk_out == 1'b0 || ps2_clk_tb == 1'b0) ? 1'b0 : 1'bz;
assign ps2_data_bus = (ps2_data_out == 1'b0 || ps2_data_tb == 1'b0) ? 1'b0 : 1'bz;

// DUT signals
wire [7:0] data_out;
wire valid;
wire error_flag;
reg [7:0] tx_data = 8'h00;
reg tx_start = 0;
wire tx_busy;
wire tx_done;

// Latched outputs for analysis
reg reset_latch = 0;
reg [7:0] latched_data = 8'h00;
reg latched_valid = 0;
reg latched_error = 0;
reg prev_valid = 0;
reg prev_error = 0;

// Test control
reg test_done = 0;

// Latch data_out and error_flag on rising edges
always @(posedge clk) begin
    if (reset_latch) begin
        latched_data <= 8'h00;
        latched_valid <= 1'b0;
        latched_error <= 1'b0;
    end else begin
        // Latch data_out on valid rising edge
        if (prev_valid == 1'b0 && valid == 1'b1) begin
            latched_data <= data_out;
            latched_valid <= 1'b1;
        end
        // Latch error_flag on rising edge
        if (prev_error == 1'b0 && error_flag == 1'b1) begin
            latched_error <= 1'b1;
        end
    end
    prev_valid <= valid;
    prev_error <= error_flag;
end

// Instantiate DUT
ps2_interface #(
    .FILTER_BITS(8),
    .TX_INHIBIT_CYCLES(10000)  // 100MHz clock → 100us inhibit window
) dut (
    .CLK(clk),
    .nRESET(nreset),
    .PS2_CLK_IN(ps2_clk_bus),
    .PS2_DATA_IN(ps2_data_bus),
    .PS2_CLK_OUT(ps2_clk_out),
    .PS2_DATA_OUT(ps2_data_out),
    .DATA(data_out),
    .VALID(valid),
    .ERROR(error_flag),
    .TX_DATA(tx_data),
    .TX_START(tx_start),
    .TX_BUSY(tx_busy),
    .TX_MODE(2'b00),
    .TX_DONE(tx_done)
);

// PS/2 sniffer to log bus activity
ps2_sniffer #(
    .HOST_IS_TRISTATE(1'b0),
    .DEVICE_IS_TRISTATE(1'b0)
) sniffer (
    .host_ps2_clk_in_i(ps2_clk_bus),
    .host_ps2_data_in_i(ps2_data_bus),
    .host_ps2_clk_out_i(ps2_clk_out),
    .host_ps2_data_out_i(ps2_data_out),
    .device_ps2_clk_in_i(ps2_clk_bus),
    .device_ps2_data_in_i(ps2_data_bus),
    .device_ps2_clk_out_i(ps2_clk_tb),
    .device_ps2_data_out_i(ps2_data_tb)
);

// Clock generator
always begin
    if (test_done) begin
        #(CLK_PERIOD/2);
    end else begin
        #(CLK_PERIOD/2) clk = ~clk;
    end
end

// Task to send a PS/2 byte with configurable clock period (device-driven clock)
task automatic send_ps2_byte_with_period(
    input [7:0] byte_val,
    input integer bit_period
);
    reg parity;
    integer i;
begin
    // Calculate odd parity
    parity = 1'b1;
    for (i = 0; i < 8; i = i + 1) begin
        parity = parity ^ byte_val[i];
    end

    // Start bit (0)
    ps2_data_tb = 1'b0;
    #(bit_period / 4);
    ps2_clk_tb = 1'b0;
    #(bit_period / 2);
    ps2_clk_tb = 1'b1;
    #(bit_period / 4);

    // Data bits (LSB first)
    for (i = 0; i < 8; i = i + 1) begin
        ps2_data_tb = byte_val[i];
        #(bit_period / 4);
        ps2_clk_tb = 1'b0;
        #(bit_period / 2);
        ps2_clk_tb = 1'b1;
        #(bit_period / 4);
    end

    // Parity bit
    ps2_data_tb = parity;
    #(bit_period / 4);
    ps2_clk_tb = 1'b0;
    #(bit_period / 2);
    ps2_clk_tb = 1'b1;
    #(bit_period / 4);

    // Stop bit (1)
    ps2_data_tb = 1'b1;
    #(bit_period / 4);
    ps2_clk_tb = 1'b0;
    #(bit_period / 2);
    ps2_clk_tb = 1'b1;
    #(bit_period / 4);
end
endtask

// Task to send one PS/2 frame (11 bits: start, 8 data LSB-first, parity, stop)
task automatic send_ps2_byte(input [7:0] byte_val);
begin
    send_ps2_byte_with_period(byte_val, PS2_CLK_PERIOD);
end
endtask

// Task to simulate the device generating clock pulses while the HOST drives data
task automatic drive_device_clock(input integer periods = 10);
    integer i;
begin
    for (i = 0; i < periods; i = i + 1) begin
        #(PS2_CLK_PERIOD / 2);
        ps2_clk_tb = 1'b0;
        #(PS2_CLK_PERIOD / 2);
        ps2_clk_tb = 1'b1;
    end
end
endtask

// Task to send device ACK sequence after HOST->DEVICE transmission
task automatic send_device_ack();
begin
    // Step 1: Device brings DATA low
    ps2_data_tb = 1'b0;
    #(PS2_CLK_PERIOD);

    // Step 2: Device brings CLK low
    ps2_clk_tb = 1'b0;
    #(PS2_CLK_PERIOD);

    // Step 3: Hold CLK low for half period
    #(PS2_CLK_PERIOD / 2);

    // Step 4 & 5: Release CLK and DATA
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #(PS2_CLK_PERIOD);
end
endtask

// Task to send invalid frame (bad stop bit)
task automatic send_ps2_byte_bad_stop(input [7:0] byte_val);
    reg parity;
    integer i;
begin
    // Calculate parity
    parity = 1'b1;
    for (i = 0; i < 8; i = i + 1) begin
        parity = parity ^ byte_val[i];
    end

    // Start bit
    ps2_data_tb = 1'b0;
    #(PS2_CLK_PERIOD / 4);
    ps2_clk_tb = 1'b0;
    #(PS2_CLK_PERIOD / 2);
    ps2_clk_tb = 1'b1;
    #(PS2_CLK_PERIOD / 4);

    // Data bits
    for (i = 0; i < 8; i = i + 1) begin
        ps2_data_tb = byte_val[i];
        #(PS2_CLK_PERIOD / 4);
        ps2_clk_tb = 1'b0;
        #(PS2_CLK_PERIOD / 2);
        ps2_clk_tb = 1'b1;
        #(PS2_CLK_PERIOD / 4);
    end

    // Parity bit
    ps2_data_tb = parity;
    #(PS2_CLK_PERIOD / 4);
    ps2_clk_tb = 1'b0;
    #(PS2_CLK_PERIOD / 2);
    ps2_clk_tb = 1'b1;
    #(PS2_CLK_PERIOD / 4);

    // Bad stop bit (0 instead of 1)
    ps2_data_tb = 1'b0;
    #(PS2_CLK_PERIOD / 4);
    ps2_clk_tb = 1'b0;
    #(PS2_CLK_PERIOD / 2);
    ps2_clk_tb = 1'b1;
    #(PS2_CLK_PERIOD / 4);
end
endtask

// Task to send invalid frame (bad parity)
task automatic send_ps2_byte_bad_parity(input [7:0] byte_val);
    reg parity;
    integer i;
begin
    // Calculate parity
    parity = 1'b0;
    for (i = 0; i < 8; i = i + 1) begin
        parity = parity ^ byte_val[i];
    end

    // Start bit
    ps2_data_tb = 1'b0;
    #(PS2_CLK_PERIOD / 4);
    ps2_clk_tb = 1'b0;
    #(PS2_CLK_PERIOD / 2);
    ps2_clk_tb = 1'b1;
    #(PS2_CLK_PERIOD / 4);

    // Data bits
    for (i = 0; i < 8; i = i + 1) begin
        ps2_data_tb = byte_val[i];
        #(PS2_CLK_PERIOD / 4);
        ps2_clk_tb = 1'b0;
        #(PS2_CLK_PERIOD / 2);
        ps2_clk_tb = 1'b1;
        #(PS2_CLK_PERIOD / 4);
    end

    // Bad parity bit
    ps2_data_tb = parity;
    #(PS2_CLK_PERIOD / 4);
    ps2_clk_tb = 1'b0;
    #(PS2_CLK_PERIOD / 2);
    ps2_clk_tb = 1'b1;
    #(PS2_CLK_PERIOD / 4);

    // Stop bit
    ps2_data_tb = 1'b1;
    #(PS2_CLK_PERIOD / 4);
    ps2_clk_tb = 1'b0;
    #(PS2_CLK_PERIOD / 2);
    ps2_clk_tb = 1'b1;
    #(PS2_CLK_PERIOD / 4);
end
endtask

// Stimulus process
initial begin
    automatic integer test_failed_count = 0;
    automatic integer test_passed_count = 0;

    // Dump waves for debugging
    $dumpfile("tb_ps2_interface.vcd");
    $dumpvars(0, tb_ps2_interface);

    // Initialize
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    nreset = 1'b0;
    #100;
    nreset = 1'b1;
    #200;

    // Test 1
    $display("Test 1: Send valid scan code 0xF0 (break code)");
    send_ps2_byte(8'hF0);
    #5000;
    if (latched_valid !== 1'b1) begin
        $display("ERROR: Expected VALID=1 for 0xF0");
        test_failed_count = test_failed_count + 1;
    end
    if (latched_data !== 8'hF0) begin
        $display("ERROR: Expected DATA=0xF0");
        test_failed_count = test_failed_count + 1;
    end
    if (latched_error !== 1'b0) begin
        $display("ERROR: Expected ERROR=0 for valid frame");
        test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    // Test 2
    $display("Test 2: Send valid scan code 0x1C (A key make)");
    send_ps2_byte(8'h1C);
    #5000;
    if (latched_valid !== 1'b1) begin
        $display("ERROR: Expected VALID=1 for 0x1C");
        test_failed_count = test_failed_count + 1;
    end
    if (latched_data !== 8'h1C) begin
        $display("ERROR: Expected DATA=0x1C");
        test_failed_count = test_failed_count + 1;
    end
    if (latched_error !== 1'b0) begin
        $display("ERROR: Expected ERROR=0 for valid frame");
        test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    // Test 3
    $display("Test 3: Send valid scan code 0x5A (Enter key)");
    send_ps2_byte(8'h5A);
    #5000;
    if (latched_valid !== 1'b1) begin
        $display("ERROR: Expected VALID=1 for 0x5A");
        test_failed_count = test_failed_count + 1;
    end
    if (latched_data !== 8'h5A) begin
        $display("ERROR: Expected DATA=0x5A");
        test_failed_count = test_failed_count + 1;
    end
    if (latched_error !== 1'b0) begin
        $display("ERROR: Expected ERROR=0 for valid frame");
        test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    // Test 4
    $display("Test 4: Send frame with bad stop bit");
    send_ps2_byte_bad_stop(8'hAA);
    #5000;
    if (latched_error !== 1'b1) begin
        $display("ERROR: Expected ERROR=1 for bad stop bit");
        test_failed_count = test_failed_count + 1;
    end
    if (latched_valid !== 1'b0) begin
        $display("ERROR: Expected VALID=0 for bad stop bit");
        test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    // Test 5
    $display("Test 5: Send frame with bad parity");
    send_ps2_byte_bad_parity(8'h55);
    #5000;
    if (latched_error !== 1'b1) begin
        $display("ERROR: Expected ERROR=1 for bad parity");
        test_failed_count = test_failed_count + 1;
    end
    if (latched_valid !== 1'b0) begin
        $display("ERROR: Expected VALID=0 for bad parity");
        test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    // Test 6
    $display("Test 6: Send sequence (0xF0, 0x1C - A key break)");
    send_ps2_byte(8'hF0);
    #5000;
    if (latched_valid !== 1'b1) begin
        $display("ERROR: Expected VALID=1 for 0xF0 in sequence");
        test_failed_count = test_failed_count + 1;
    end
    if (latched_data !== 8'hF0) begin
        $display("ERROR: Expected DATA=0xF0 in sequence");
        test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;
    send_ps2_byte(8'h1C);
    #5000;
    if (latched_valid !== 1'b1) begin
        $display("ERROR: Expected VALID=1 for 0x1C in sequence");
        test_failed_count = test_failed_count + 1;
    end
    if (latched_data !== 8'h1C) begin
        $display("ERROR: Expected DATA=0x1C in sequence");
        test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    // Test 7
    $display("Test 7: Send all zeros (0x00)");
    send_ps2_byte(8'h00);
    #5000;
    if (latched_valid !== 1'b1) begin
        $display("ERROR: Expected VALID=1 for 0x00");
        test_failed_count = test_failed_count + 1;
    end
    if (latched_data !== 8'h00) begin
        $display("ERROR: Expected DATA=0x00");
        test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    // Test 8
    $display("Test 8: Send all ones (0xFF)");
    send_ps2_byte(8'hFF);
    #5000;
    if (latched_valid !== 1'b1) begin
        $display("ERROR: Expected VALID=1 for 0xFF");
        test_failed_count = test_failed_count + 1;
    end
    if (latched_data !== 8'hFF) begin
        $display("ERROR: Expected DATA=0xFF");
        test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    // Test 9
    $display("Test 9: Fast device clock (~16.7 kHz, 60us period)");
    send_ps2_byte_with_period(8'h3C, 60000);
    #5000;
    if (latched_valid !== 1'b1 || latched_data !== 8'h3C) begin
        $display("ERROR: Expected VALID=1 and DATA=0x3C with fast clock");
        test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    // Test 10
    $display("Test 10: Slow device clock (~6.7 kHz, 150us period)");
    send_ps2_byte_with_period(8'h4D, 150000);
    #5000;
    if (latched_valid !== 1'b1 || latched_data !== 8'h4D) begin
        $display("ERROR: Expected VALID=1 and DATA=0x4D with slow clock");
        test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    // Test 11
    $display("Test 11: Recovery after error (bad stop followed by good frame)");
    send_ps2_byte_bad_stop(8'hA5);
    #5000;
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;
    send_ps2_byte(8'h2A);
    #5000;
    if (latched_valid !== 1'b1 || latched_data !== 8'h2A || latched_error !== 1'b0) begin
        $display("ERROR: Expected recovery: VALID=1, DATA=0x2A, ERROR=0 after prior error");
        test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    // Test 12
    $display("Test 12: Back-to-back frames with minimal gap");
    send_ps2_byte(8'hAB);
    #1000;
    send_ps2_byte(8'hCD);
    #5000;
    if (latched_valid !== 1'b1 || latched_data !== 8'hCD) begin
        $display("ERROR: Expected last frame DATA=0xCD with valid asserted");
        test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    // Section 8: HOST Transmission Tests
    $display("=== Section 8: HOST Transmission (HOST->DEVICE) ===");

    // Test 8.1
    $display("Test 8.1: HOST transmits LED control command (0xED)");
    tx_data = 8'hED;
    tx_start = 1'b1;
    #CLK_PERIOD;
    tx_start = 1'b0;
    wait(ps2_clk_bus == 1'b0);  // Wait for HOST inhibit
    wait(ps2_clk_bus == 1'b1);  // Wait for HOST to release clock
    drive_device_clock(11);
    send_device_ack();          // Send device ACK sequence
    #50000;  // Allow time for transmission
    if (tx_done === 1'b1) begin
        $display("ERROR: Expected TX_DONE to remain 0 in HOST mode during 0xED TX");
        test_failed_count = test_failed_count + 1;
    end
    $display("INFO: LED control command (0xED) transmitted");
    test_passed_count = test_passed_count + 1;
    #100000;

    // Test 8.2
    $display("Test 8.2: HOST transmits SET REPEAT RATE (0xF3)");
    tx_data = 8'hF3;
    tx_start = 1'b1;
    #CLK_PERIOD;
    tx_start = 1'b0;
    wait(ps2_clk_bus == 1'b0);  // Wait for HOST inhibit
    wait(ps2_clk_bus == 1'b1);  // Wait for HOST to release clock
    drive_device_clock(11);
    send_device_ack();          // Send device ACK sequence
    #50000;  // Allow time for transmission
    if (tx_done === 1'b1) begin
        $display("ERROR: Expected TX_DONE to remain 0 in HOST mode during 0xF3 TX");
        test_failed_count = test_failed_count + 1;
    end
    $display("INFO: Set repeat rate command (0xF3) transmitted");
    test_passed_count = test_passed_count + 1;
    #100000;

    // Test 8.3
    $display("Test 8.3: HOST transmits RESET (0xFF)");
    tx_data = 8'hFF;
    tx_start = 1'b1;
    #CLK_PERIOD;
    tx_start = 1'b0;
    wait(ps2_clk_bus == 1'b0);  // Wait for HOST inhibit
    wait(ps2_clk_bus == 1'b1);  // Wait for HOST to release clock
    drive_device_clock(11);
    send_device_ack();          // Send device ACK sequence
    #50000;  // Allow time for transmission
    if (tx_done === 1'b1) begin
        $display("ERROR: Expected TX_DONE to remain 0 in HOST mode during 0xFF TX");
        test_failed_count = test_failed_count + 1;
    end
    $display("INFO: Reset command (0xFF) transmitted");
    test_passed_count = test_passed_count + 1;

    // Section 9: Retransmission Test
    $display("=== Section 9: Retransmission on 0xFE Response ===");

    // Test 9.1
    $display("Test 9.1: HOST retransmission after 0xFE Resend response");

    // Initialize bus for fresh transaction
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #100000;
    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    // HOST transmits 0xED (LED control command)
    $display("Sending 0xED from HOST...");
    tx_data = 8'hED;
    tx_start = 1'b1;
    #CLK_PERIOD;
    tx_start = 1'b0;
    wait(ps2_clk_bus == 1'b0);  // Wait for HOST inhibit
    wait(ps2_clk_bus == 1'b1);  // Wait for HOST to release clock
    drive_device_clock(11);
    send_device_ack();          // Send device ACK sequence
    #100000;  // Wait for transmission to complete

    // Now simulate DEVICE responding with 0xFE (Resend)
    $display("Simulating device response: 0xFE (Resend)");
    send_ps2_byte(8'hFE);
    #50000;

    // After receiving 0xFE, HOST should retransmit the original byte (0xED)
    $display("Waiting for HOST to retransmit 0xED...");
    #100000;

    if (latched_valid == 1'b1 && latched_data == 8'hFE) begin
        $display("PASS: HOST correctly received 0xFE resend request");
        test_passed_count = test_passed_count + 1;
    end else begin
        if (latched_valid !== 1'b1) begin
            $display("FAIL: HOST did not register 0xFE as VALID");
        end
        if (latched_data !== 8'hFE) begin
            $display("FAIL: HOST received wrong data instead of 0xFE");
        end
        test_failed_count = test_failed_count + 1;
    end

    reset_latch = 1'b1;
    #CLK_PERIOD;
    reset_latch = 1'b0;
    #CLK_PERIOD;

    #100;
    if (test_failed_count == 0) begin
        $display("ALL TESTS PASSED");
        $finish(0);
    end else begin
        $display("SOME TESTS FAILED (%0d)", test_failed_count);
        $finish(1);
    end
end

endmodule
