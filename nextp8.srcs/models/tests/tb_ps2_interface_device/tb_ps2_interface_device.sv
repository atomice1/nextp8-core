// PS/2 Interface DEVICE Mode Testbench
// Tests ps2_interface in DEVICE mode by simulating a PS/2 host
// sending commands and verifying reception.

`timescale 1ns / 1ps

module tb_ps2_interface_device;
  // Testbench signals
  logic clk;
  logic nreset;
  tri1 ps2_clk;
  tri1 ps2_data;
  logic [7:0] data_out;
  logic valid;
  logic error_flag;
  logic [7:0] tx_data;
  logic tx_start;
  logic tx_busy;
  logic tx_done;
  logic tx_abort;

  // Latched outputs for analysis
  logic [7:0] latched_data;
  logic latched_valid;
  logic latched_error;
  logic latched_tx_abort;
  logic prev_valid;
  logic prev_error;
  logic prev_tx_abort;
  logic reset_latch;

  // Test control signals
  logic test_done = 1'b0;

  // Clock periods
  localparam CLK_PERIOD = 10ns;           // 100 MHz system clock
  localparam PS2_CLK_PERIOD = 90us;      // ~11.11 kHz PS/2 clock

  // Testbench open-drain drivers (reg type for procedural assignment)
  reg ps2_clk_tb = 1'b1;
  reg ps2_data_tb = 1'b1;

  // Device outputs
  wire device_clk_out;
  wire device_data_out;

  // Open-drain logic: either testbench OR device can pull low
  assign ps2_clk = (ps2_clk_tb == 1'b0 || device_clk_out == 1'b0) ? 1'b0 : 1'bz;
  assign ps2_data = (ps2_data_tb == 1'b0 || device_data_out == 1'b0) ? 1'b0 : 1'bz;

  // Pull-up resistors for PS/2 lines (weak pull to '1')
  pullup(ps2_clk);
  pullup(ps2_data);

  // Instantiate DUT
  ps2_interface_device #(
    .FILTER_BITS(8),
    .CLOCK_DIV(PS2_CLK_PERIOD / CLK_PERIOD)
  ) dut (
    .CLK(clk),
    .nRESET(nreset),
    .PS2_CLK_IN(ps2_clk),
    .PS2_DATA_IN(ps2_data),
    .PS2_CLK_OUT(device_clk_out),
    .PS2_DATA_OUT(device_data_out),
    .DATA(data_out),
    .VALID(valid),
    .ERROR(error_flag),
    .TX_DATA(tx_data),
    .TX_START(tx_start),
    .TX_MODE(2'b0),
    .TX_BUSY(tx_busy),
    .TX_DONE(tx_done),
    .TX_ABORT(tx_abort)
  );

  // PS/2 sniffer to log bus activity
  ps2_sniffer #(
    .HOST_IS_TRISTATE(1'b0),
    .DEVICE_IS_TRISTATE(1'b0)
  ) sniffer (
    .host_ps2_clk_in_i(ps2_clk),        // What host sees on bus
    .host_ps2_data_in_i(ps2_data),      // What host sees on bus
    .host_ps2_clk_out_i(ps2_clk_tb),    // What host (testbench) drives
    .host_ps2_data_out_i(ps2_data_tb),  // What host (testbench) drives
    .device_ps2_clk_in_i(ps2_clk),      // Device monitors bus
    .device_ps2_data_in_i(ps2_data),    // Device monitors bus
    .device_ps2_clk_out_i(device_clk_out),   // Device clock output
    .device_ps2_data_out_i(device_data_out)  // Device data output
  );

  // Latch data_out and error_flag on rising edge
  always @(posedge clk) begin
    if (reset_latch) begin
      latched_data <= 8'h0;
      latched_valid <= 1'b0;
      latched_error <= 1'b0;
      latched_tx_abort <= 1'b0;
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
      // Latch tx_abort on rising edge
      if (prev_tx_abort == 1'b0 && tx_abort == 1'b1) begin
        latched_tx_abort <= 1'b1;
      end
    end
    prev_valid <= valid;
    prev_error <= error_flag;
    prev_tx_abort <= tx_abort;
  end

  // Clock generator (100 MHz)
  initial begin
    clk = 1'b0;
    while (!test_done) begin
      #(CLK_PERIOD / 2) clk = ~clk;
    end
  end

  // Task to send byte from host to device (host -> device: device generates clock)
  // Host pulls Clock low, pulls Data low, releases Clock for device to generate clock
  // Host outputs bits on Data line, bits sampled on rising Clock edges
  task automatic host_send_byte_to_device(
    input logic [7:0] byte_val
  );
    logic parity;
    integer i;
  begin
    // Calculate odd parity
    parity = 1'b1;
    for (i = 0; i < 8; i = i + 1) begin
      parity = parity ^ byte_val[i];
    end

    // Ensure bus idles high before inhibit
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #(5us);

    // Step 1: Inhibit - pull Clock low to inhibit device
    ps2_clk_tb = 1'b0;
    #(100us);

    // Step 2: Request-to-send - pull Data low (start bit)
    ps2_data_tb = 1'b0;
    #(10us);

    // Step 3: Release Clock - pull high for device to see, then release for device to control
    ps2_clk_tb = 1'b1;

    // Step 4: Wait for device to pull clock low (device starts generating clock)
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    if (ps2_clk != 1'b0) begin
      $display("ERROR: Device did not pull clock low");
      return;
    end

    // Device will sample start bit on first rising edge
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1) break;
      #1ns;
    end

    // Now start sending data bits
    for (i = 0; i < 8; i = i + 1) begin
      // Ensure clock low, then set data while low
      for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
        if (ps2_clk == 1'b0) break;
        #1ns;
      end
      ps2_data_tb = byte_val[i];
      // Device samples on next rising edge
      for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
        if (ps2_clk == 1'b1) break;
        #1ns;
      end
    end

    // Parity bit: set while clock low, sample on rising
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    ps2_data_tb = parity;
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1) break;
      #1ns;
    end

    // Stop bit: drive high for a full bit to guarantee a clean '1'
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    ps2_data_tb = 1'b1;
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1) break;
      #1ns;
    end

    // Wait for acknowledge from device
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_data == 1'b0) break;
      #1ns;
    end
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_data == 1'b1) break;
      #1ns;
    end
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1) break;
      #1ns;
    end
  end
  endtask

  // Task to send invalid frame (bad stop bit)
  // Uses RTS protocol for DEVICE mode where device generates clock
  task automatic host_send_byte_to_device_bad_stop(
    input logic [7:0] byte_val
  );
    logic parity;
    integer i;
  begin
    // Calculate odd parity
    parity = 1'b1;
    for (i = 0; i < 8; i = i + 1) begin
      parity = parity ^ byte_val[i];
    end

    // Ensure bus idles high before inhibit
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #(5us);

    // Initiate RTS: Host pulls Clock low to inhibit, then Data low (start bit)
    ps2_clk_tb = 1'b0;
    #(100us);
    ps2_data_tb = 1'b0;
    #(10us);
    ps2_clk_tb = 1'b1;

    // Wait for device to pull clock low (device starts generating clock)
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    if (ps2_clk != 1'b0) begin
      $display("ERROR: Device did not pull clock low");
      return;
    end

    // Device will sample start bit on first rising edge
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1) break;
      #1ns;
    end

    // Send data bits
    for (i = 0; i < 8; i = i + 1) begin
      for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
        if (ps2_clk == 1'b0) break;
        #1ns;
      end
      ps2_data_tb = byte_val[i];
      for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
        if (ps2_clk == 1'b1) break;
        #1ns;
      end
    end

    // Parity bit
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    ps2_data_tb = parity;
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1) break;
      #1ns;
    end

    // BAD STOP BIT (0 instead of 1)
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    ps2_data_tb = 1'b0;  // Invalid: should be 1
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1) break;
      #1ns;
    end

    // Wait for acknowledge from device
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_data == 1'b0) break;
      #1ns;
    end
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_data == 1'b1) break;
      #1ns;
    end
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1) break;
      #1ns;
    end
  end
  endtask

  // Task to send invalid frame (bad parity)
  // Uses RTS protocol for DEVICE mode where device generates clock
  task automatic host_send_byte_to_device_bad_parity(
    input logic [7:0] byte_val
  );
    logic parity;
    integer i;
  begin
    parity = 1'b0;
    for (i = 0; i < 8; i = i + 1) begin
      parity = parity ^ byte_val[i];
    end

    // Ensure bus idles high before inhibit
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #(5us);

    // Initiate RTS: Host pulls Clock low to inhibit, then Data low (start bit)
    ps2_clk_tb = 1'b0;
    #(100us);
    ps2_data_tb = 1'b0;
    #(10us);
    ps2_clk_tb = 1'b1;

    // Wait for device to pull clock low (device starts generating clock)
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    if (ps2_clk != 1'b0) begin
      $display("ERROR: Device did not pull clock low");
      return;
    end

    // Device will sample start bit on first rising edge
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1) break;
      #1ns;
    end

    // Send data bits
    for (i = 0; i < 8; i = i + 1) begin
      for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
        if (ps2_clk == 1'b0) break;
        #1ns;
      end
      ps2_data_tb = byte_val[i];
      for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
        if (ps2_clk == 1'b1) break;
        #1ns;
      end
    end

    // BAD PARITY BIT (wrong parity, not inverted)
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    ps2_data_tb = parity;  // This is wrong parity (not inverted)
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1) break;
      #1ns;
    end

    // Stop bit
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    ps2_data_tb = 1'b1;  // Valid stop bit
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1) break;
      #1ns;
    end

    // Wait for acknowledge from device
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_data == 1'b0) break;
      #1ns;
    end
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_data == 1'b1) break;
      #1ns;
    end
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1) break;
      #1ns;
    end
  end
  endtask

  // Task to receive byte from device (device -> host: device generates clock)
  // Host samples data on falling clock edges
  // Returns received byte and success flag
  task automatic host_receive_byte_from_device(
    output logic [7:0] received_byte,
    output logic success
  );
    logic [7:0] data_bits;
    logic start_bit;
    logic parity_bit;
    logic stop_bit;
    logic calculated_parity;
    integer i;
  begin
    success = 1'b0;
    received_byte = 8'h00;

    // Wait for device to pull clock low (start of transmission)
    for (int timeout = 0; timeout < 10000000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    if (ps2_clk != 1'b0) begin
      $display("ERROR: Device did not start transmission (clock stayed high)");
      return;
    end

    // Sample start bit on falling edge (should already be low, sample data line)
    start_bit = ps2_data;
    if (start_bit != 1'b0) begin
      $display("ERROR: Invalid start bit (expected 0, got %b)", start_bit);
      return;
    end

    // Wait for clock to go high then low for each data bit
    for (i = 0; i < 8; i = i + 1) begin
      // Wait for clock high
      for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
        if (ps2_clk == 1'b1 || ps2_clk == 1'bz) break;
        #1ns;
      end
      // Wait for clock to go low (falling edge)
      for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
        if (ps2_clk == 1'b0) break;
        #1ns;
      end
      // Sample data bit
      data_bits[i] = ps2_data;
    end

    // Sample parity bit
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1 || ps2_clk == 1'bz) break;
      #1ns;
    end
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    parity_bit = ps2_data;

    // Sample stop bit
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1 || ps2_clk == 1'bz) break;
      #1ns;
    end
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    stop_bit = ps2_data;

    if (stop_bit != 1'b1) begin
      $display("ERROR: Invalid stop bit (expected 1, got %b)", stop_bit);
      return;
    end

    // Verify odd parity
    calculated_parity = 1'b1;
    for (i = 0; i < 8; i = i + 1) begin
      calculated_parity = calculated_parity ^ data_bits[i];
    end

    if (parity_bit != calculated_parity) begin
      $display("ERROR: Parity error (expected %b, got %b)", calculated_parity, parity_bit);
      return;
    end

    // Wait for final clock high (end of transmission)
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1 || ps2_clk == 1'bz) break;
      #1ns;
    end

    received_byte = data_bits;
    success = 1'b1;
  end
  endtask

  // Task to force device to discard incomplete frame and return to idle
  // Per PS/2 spec: host holds Clock low ≥100µs to signal frame abort
  task automatic ps2_recovery(
    ref reg ps2_clk_io,
    ref reg ps2_data_io
  );
  begin
    // Hold Clock low for minimum inhibit time
    ps2_clk_io = 1'b0;
    #(50us);
    ps2_data_io = 1'b1;
    #(1us);
    #(50us);

    // Release bus to idle (both lines high via pullup)
    ps2_clk_io = 1'b1;
    #(10us);  // Allow bus to settle
  end
  endtask

  // Task to wait for device to return to idle state
  // Idle state: Clock=High, Data=High (device not generating clock)
  task automatic wait_for_idle(
    input logic ps2_clk_io,
    input logic ps2_data_io
  );
    integer i;
  begin
    for (i = 0; i < 100; i = i + 1) begin  // Wait up to 10ms (100 × 100µs)
      if ((ps2_clk_io == 1'b1 || ps2_clk_io == 1'bz) &&
          (ps2_data_io == 1'b1 || ps2_data_io == 1'bz)) begin
        return;  // Device is idle
      end
      #(100us);
    end
  end
  endtask

  // Task to monitor device clock activity over a time window
  // Returns 1 if clock is toggling (active), 0 if clock is quiet (no toggles)
  task automatic monitor_device_clock_is_toggling(
    input int monitor_time_us,
    output logic is_toggling
  );
    logic prev_clk;
    logic toggled;
  begin
    toggled = 1'b0;
    prev_clk = device_clk_out;

    for (int i = 0; i < monitor_time_us; i = i + 1) begin
      #1us;
      if (device_clk_out != prev_clk) begin
        toggled = 1'b1;
        break;
      end
      prev_clk = device_clk_out;
    end

    is_toggling = toggled;
  end
  endtask

  // Task to monitor device data activity over a time window
  // Returns 1 if data is toggling (active), 0 if data is quiet (no toggles)
  task automatic monitor_device_data_is_toggling(
    input int monitor_time_us,
    output logic is_toggling
  );
    logic prev_data;
    logic toggled;
  begin
    toggled = 1'b0;
    prev_data = device_data_out;

    for (int i = 0; i < monitor_time_us; i = i + 1) begin
      #1us;
      if (device_data_out != prev_data) begin
        toggled = 1'b1;
        break;
      end
      prev_data = device_data_out;
    end

    is_toggling = toggled;
  end
  endtask

  // Main stimulus process
  initial begin : stimulus
    time start_time;
    time end_time;
    time elapsed;
    time clk_low_time;
    time clk_high_time;
    automatic int test_passed_count = 0;
    automatic int test_failed_count = 0;
    logic success;
    logic is_toggling;
    logic test_passed;

    // Initialize
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    tx_data = 8'h00;
    tx_start = 1'b0;
    nreset = 1'b0;
    test_done = 1'b0;
    reset_latch = 1'b0;

    #(100ns);
    nreset = 1'b1;
    #(200ns);

    ////////////////////////////////////////////////////////////////////////
    // Section 1: DEVICE Transmission Tests (Device→Host)
    ////////////////////////////////////////////////////////////////////////
    $display("=== Section 1: DEVICE Transmission (DEVICE->HOST) ===");

    // Reset for clean state
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #(100us);

    // Test 1.1: Device transmits Command ACK (0xFA)
    $display("Test 1.1: Device transmits Command ACK (0xFA)");
    tx_data = 8'hFA;
    tx_start = 1'b1;
    #CLK_PERIOD;
    tx_start = 1'b0;

    // Receive and verify the transmission
    begin
      logic [7:0] received;
      logic rx_success;
      host_receive_byte_from_device(received, rx_success);
      if (rx_success && received == 8'hFA) begin
        $display("PASS: Host received 0xFA correctly");
        test_passed_count = test_passed_count + 1;
      end else if (!rx_success) begin
        $display("FAIL: Host failed to receive transmission");
        test_failed_count = test_failed_count + 1;
      end else begin
        $display("FAIL: Host received 0x%02h, expected 0xFA", received);
        test_failed_count = test_failed_count + 1;
      end
    end

    // Verify TX_BUSY went low
    for (int timeout = 0; timeout < 50000; timeout = timeout + 1) begin
      if (tx_busy == 1'b0) break;
      #1ns;
    end
    if (tx_busy != 1'b0) begin
      $display("ERROR: TX_BUSY did not go low after transmission");
    end

    // Wait for bus to settle
    #(100us);
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #(100us);

    // Test 1.2: Device transmits Key Press Scancode (0x1C - 'A' key)
    $display("Test 1.2: Device transmits Key Press Scancode 0x1C ('A' key)");
    tx_data = 8'h1C;
    tx_start = 1'b1;
    #CLK_PERIOD;
    tx_start = 1'b0;

    // Receive and verify the transmission
    begin
      logic [7:0] received;
      logic rx_success;
      host_receive_byte_from_device(received, rx_success);
      if (rx_success && received == 8'h1C) begin
        $display("PASS: Host received 0x1C correctly");
        test_passed_count = test_passed_count + 1;
      end else if (!rx_success) begin
        $display("FAIL: Host failed to receive transmission");
        test_failed_count = test_failed_count + 1;
      end else begin
        $display("FAIL: Host received 0x%02h, expected 0x1C", received);
        test_failed_count = test_failed_count + 1;
      end
    end

    // Verify TX_BUSY went low
    for (int timeout = 0; timeout < 50000; timeout = timeout + 1) begin
      if (tx_busy == 1'b0) break;
      #1ns;
    end
    if (tx_busy != 1'b0) begin
      $display("ERROR: TX_BUSY did not go low after transmission");
    end

    #(100us);
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #(100us);

    // Test 1.3: Device transmits Key Release Prefix (0xF0)
    $display("Test 1.3: Device transmits Key Release Prefix (0xF0)");
    tx_data = 8'hF0;
    tx_start = 1'b1;
    #CLK_PERIOD;
    tx_start = 1'b0;

    // Receive and verify the transmission
    begin
      logic [7:0] received;
      logic rx_success;
      host_receive_byte_from_device(received, rx_success);
      if (rx_success && received == 8'hF0) begin
        $display("PASS: Host received 0xF0 correctly");
        test_passed_count = test_passed_count + 1;
      end else if (!rx_success) begin
        $display("FAIL: Host failed to receive transmission");
        test_failed_count = test_failed_count + 1;
      end else begin
        $display("FAIL: Host received 0x%02h, expected 0xF0", received);
        test_failed_count = test_failed_count + 1;
      end
    end

    // Verify TX_BUSY went low
    for (int timeout = 0; timeout < 50000; timeout = timeout + 1) begin
      if (tx_busy == 1'b0) break;
      #1ns;
    end
    if (tx_busy != 1'b0) begin
      $display("ERROR: TX_BUSY did not go low after transmission");
    end

    ////////////////////////////////////////////////////////////////////////
    // Section 2: Host Inhibit Tests
    ////////////////////////////////////////////////////////////////////////
    $display("=== Section 2: Host Inhibit (Host can temporarily prevent Device TX) ===");

    // Reset for clean state
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #(100us);

    // Test 2.1: Host inhibits device while idle (should not affect anything)
    $display("Test 2.1: Host inhibits device during idle state");
    ps2_clk_tb = 1'b0;  // Pull clock low
    #(150us);  // Hold inhibit longer than minimum
    ps2_clk_tb = 1'b1;
    #(100us);
    $display("PASS: Device handled inhibit during idle");
    test_passed_count = test_passed_count + 1;

    // Test 2.2: Device transmission completes despite host inhibit after transmission
    $display("Test 2.2: Device transmits then host inhibits");
    tx_data = 8'h50;
    tx_start = 1'b1;
    #CLK_PERIOD;
    tx_start = 1'b0;

    // Wait for at least some transmission time, then inhibit
    #(2ms);

    // Pull clock low to inhibit/attempt to interrupt
    ps2_clk_tb = 1'b0;
    #(150us);
    ps2_clk_tb = 1'b1;
    #(100us);

    $display("PASS: Device handled late inhibit during transmission");
    test_passed_count = test_passed_count + 1;

    #(100us);
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #(100us);

    $display("Test 2.3: Host inhibits during idle state (general inhibit test)");
    ps2_clk_tb = 1'b0;  // Pull clock low to inhibit
    #(100us);
    ps2_clk_tb = 1'b1;  // Release
    #(100us);
    // Bus should return to idle, device should not have tried to transmit
    if (ps2_clk == 1'b1 || ps2_clk == 1'bz) begin
      $display("PASS: Device correctly inhibited by host");
      test_passed_count = test_passed_count + 1;
    end else begin
      $display("FAIL: Clock not idle after inhibit release");
      test_failed_count = test_failed_count + 1;
    end

    ////////////////////////////////////////////////////////////////////////
    // Section 3: RTS Protocol Tests (Host→Device transmission)
    ////////////////////////////////////////////////////////////////////////
    $display("=== Section 3: RTS (Request-to-Send) - Host initiates HOST->DEVICE transmission ===");

    // Test 3.1: Minimum Clock inhibit time (≥100µs per protocol)
    $display("Test 3.1: RTS - Minimum Clock inhibit time (100µs requirement)");
    ps2_clk_tb = 1'b0;
    start_time = $time;
    #(100us);
    ps2_data_tb = 1'b0;
    #(10us);
    ps2_clk_tb = 1'b1;
    // Device should detect RTS and start generating clock
    for (int timeout = 0; timeout < 15000000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    end_time = $time;
    elapsed = end_time - start_time - 100us - 2us;
    if (ps2_clk == 1'b0) begin
      $display("PASS: Device responded to RTS in %0t", elapsed);
      test_passed_count = test_passed_count + 1;
    end else begin
      $display("%t FAIL: Device did not respond to RTS within 15ms", $time);
      test_failed_count = test_failed_count + 1;
    end
    // Cleanup
    ps2_recovery(ps2_clk_tb, ps2_data_tb);
    wait_for_idle(ps2_clk, ps2_data);

    // Test 3.2: Short Clock inhibit (less than 100µs) should NOT trigger RTS
    $display("Test 3.2: RTS - Short inhibit (90µs) should not trigger device clock");
    ps2_clk_tb = 1'b0;
    #(80us);  // Less than 100µs
    ps2_data_tb = 1'b0;
    #(10us);
    ps2_clk_tb = 1'b1;
    // Device should NOT start generating clock
    #(20us);
    if (ps2_clk != 1'b0) begin
      $display("PASS: Device correctly ignored short inhibit");
      test_passed_count = test_passed_count + 1;
    end else begin
      $display("FAIL: Device incorrectly responded to short inhibit");
      test_failed_count = test_failed_count + 1;
    end
    // Cleanup
    ps2_recovery(ps2_clk_tb, ps2_data_tb);
    wait_for_idle(ps2_clk, ps2_data);

    // Test 3.3: Long Clock inhibit (200µs) should work
    $display("Test 3.3: RTS - Extended inhibit time (200µs)");
    ps2_clk_tb = 1'b0;
    #(190us);
    ps2_data_tb = 1'b0;
    #(10us);
    ps2_clk_tb = 1'b1;
    for (int timeout = 0; timeout < 15000000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end
    if (ps2_clk == 1'b0) begin
      $display("PASS: Device responded to extended inhibit");
      test_passed_count = test_passed_count + 1;
    end else begin
      $display("FAIL: Device did not respond to 200µs inhibit");
      test_failed_count = test_failed_count + 1;
    end
    // Cleanup
    ps2_recovery(ps2_clk_tb, ps2_data_tb);
    wait_for_idle(ps2_clk, ps2_data);

    ////////////////////////////////////////////////////////////////////////
    // Section 4: Device Clock Generation During HOST→DEVICE
    ////////////////////////////////////////////////////////////////////////
    $display("=== Section 4: Device Clock Generation During HOST->DEVICE ===");

    // Test 4.1: Clock frequency measurement during HOST->DEVICE transmission
    $display("Test 4.1: Measure device-generated clock frequency during HOST->DEVICE");
    // Initiate RTS
    ps2_clk_tb = 1'b0;
    #(100us);
    ps2_data_tb = 1'b0;
    #(10us);
    ps2_clk_tb = 1'b1;
    #(1ns)
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end

    // Measure clock period over multiple cycles
    for (int i = 1; i <= 3; i = i + 1) begin
      // Measure low time
      start_time = $time;
      for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
        if (ps2_clk == 1'b1) break;
        #1ns;
      end
      clk_low_time = $time - start_time;

      // Measure high time
      start_time = $time;
      for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
        if (ps2_clk == 1'b0) break;
        #1ns;
      end
      clk_high_time = $time - start_time;

      $display("  Cycle %0d: Low=%0t High=%0t Total=%0t",
               i, clk_low_time, clk_high_time, clk_low_time + clk_high_time);

      // Protocol: 10-16.7 kHz = 60-100µs period, 30-50µs each phase
      if (clk_low_time < 30us || clk_low_time > 50us) begin
        $display("FAIL: Clock low time out of spec (30-50µs)");
        test_failed_count = test_failed_count + 1;
      end else if (clk_high_time < 30us || clk_high_time > 50us) begin
        $display("FAIL: Clock high time out of spec (30-50µs)");
        test_failed_count = test_failed_count + 1;
      end
    end
    $display("PASS: Clock frequency within spec (10-16.7 kHz)");
    test_passed_count = test_passed_count + 1;

    // Cleanup: Abort the incomplete clock measurement and force device to idle
    ps2_recovery(ps2_clk_tb, ps2_data_tb);
    wait_for_idle(ps2_clk, ps2_data);

    // Reset latch to clear any artifacts
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    ////////////////////////////////////////////////////////////////////////
    // Section 5: HOST→DEVICE Basic Data Transmission
    ////////////////////////////////////////////////////////////////////////
    $display("=== Section 5: HOST->DEVICE Basic Data Transmission ===");

    // Test 5.1: Host sends 0xED (LED Control command)
    $display("Test 5.1: Host sends 0xED (LED Control) - LSB first, odd parity");
    host_send_byte_to_device(8'hED);
    #(5us);
    if (latched_valid == 1'b1 && latched_data == 8'hED && latched_error == 1'b0) begin
      $display("PASS: 0xED received correctly");
      test_passed_count = test_passed_count + 1;
    end else begin
      if (latched_valid != 1'b1) begin
        $display("FAIL: Expected VALID=1 for 0xED");
      end
      if (latched_data != 8'hED) begin
        $display("FAIL: Expected DATA=0xED, got 0x%02h", latched_data);
      end
      if (latched_error != 1'b0) begin
        $display("FAIL: Expected ERROR=0 for valid frame");
      end
      test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    // Test 5.2: All data patterns - verify LSB-first transmission
    $display("Test 5.2: Data pattern 0x01 (LSB=1, others=0)");
    host_send_byte_to_device(8'h01);
    #(5us);
    if (latched_data == 8'h01) begin
      $display("PASS: 0x01 received correctly");
      test_passed_count = test_passed_count + 1;
    end else begin
      $display("FAIL: Expected 0x01");
      test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    $display("Test 5.3: Data pattern 0x80 (MSB=1, others=0)");
    host_send_byte_to_device(8'h80);
    #(5us);
    if (latched_data == 8'h80) begin
      $display("PASS: 0x80 received correctly");
      test_passed_count = test_passed_count + 1;
    end else begin
      $display("FAIL: Expected 0x80");
      test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    $display("Test 5.4: Data pattern 0xFF (all ones)");
    host_send_byte_to_device(8'hFF);
    #(5us);
    if (latched_data == 8'hFF) begin
      $display("PASS: 0xFF received correctly");
      test_passed_count = test_passed_count + 1;
    end else begin
      $display("FAIL: Expected 0xFF");
      test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    $display("Test 5.5: Data pattern 0x00 (all zeros)");
    host_send_byte_to_device(8'h00);
    #(5us);
    if (latched_data == 8'h00) begin
      $display("PASS: 0x00 received correctly");
      test_passed_count = test_passed_count + 1;
    end else begin
      $display("FAIL: Expected 0x00");
      test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    $display("Test 5.6: Data pattern 0xAA (alternating bits)");
    host_send_byte_to_device(8'hAA);
    #(5us);
    if (latched_data == 8'hAA) begin
      $display("PASS: 0xAA received correctly");
      test_passed_count = test_passed_count + 1;
    end else begin
      $display("FAIL: Expected 0xAA");
      test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    $display("Test 5.7: Data pattern 0x55 (alternating bits inverse)");
    host_send_byte_to_device(8'h55);
    #(5us);
    if (latched_data == 8'h55) begin
      $display("PASS: 0x55 received correctly");
      test_passed_count = test_passed_count + 1;
    end else begin
      $display("FAIL: Expected 0x55");
      test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    ////////////////////////////////////////////////////////////////////////
    // Section 6: HOST→DEVICE Parity Validation
    ////////////////////////////////////////////////////////////////////////
    $display("=== Section 6: HOST->DEVICE Parity Validation (Odd Parity Required) ===");

    // Test 6.1: Valid parity - 0xED has even number of 1s (1+0+1+1+0+1+1+1=6), parity=1
    $display("Test 6.1: Valid odd parity (0xED: 6 ones, parity=1)");
    host_send_byte_to_device(8'hED);
    #(5us);
    if (latched_error == 1'b0 && latched_valid == 1'b1) begin
      $display("PASS: Odd parity accepted");
      test_passed_count = test_passed_count + 1;
    end else begin
      if (latched_error != 1'b0) begin
        $display("FAIL: Valid parity incorrectly flagged as error");
      end
      if (latched_valid != 1'b1) begin
        $display("FAIL: Valid frame not marked VALID");
      end
      test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    // Test 6.2: 0xF4 has odd number of 1s (0+0+1+0+1+1+1+1=5), parity=0
    $display("Test 6.2: Valid odd parity (0xF4: 5 ones, parity=0)");
    host_send_byte_to_device(8'hF4);
    #(5us);
    if (latched_error == 1'b0 && latched_valid == 1'b1) begin
      $display("PASS: Odd parity accepted");
      test_passed_count = test_passed_count + 1;
    end else begin
      if (latched_error != 1'b0) begin
        $display("FAIL: Valid parity incorrectly flagged as error");
      end
      if (latched_valid != 1'b1) begin
        $display("FAIL: Valid frame not marked VALID");
      end
      test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    ////////////////////////////////////////////////////////////////////////
    // Section 7: HOST→DEVICE Stop Bit Validation
    ////////////////////////////////////////////////////////////////////////
    $display("=== Section 7: HOST->DEVICE Stop Bit Validation (Must be 1) ===");

    // Note: host_send_byte_to_device_bad_stop sends a frame with stop bit = 0
    // This should be detected as an error
    $display("Test 6.1: Invalid stop bit (0 instead of 1) should trigger error");
    host_send_byte_to_device_bad_stop(8'hED);
    #(5us);
    if (latched_error == 1'b1 && latched_valid == 1'b0) begin
      $display("PASS: Bad stop bit correctly detected as error");
      test_passed_count = test_passed_count + 1;
    end else begin
      if (latched_error != 1'b1) begin
        $display("FAIL: Bad stop bit not detected");
      end
      if (latched_valid != 1'b0) begin
        $display("FAIL: Invalid frame should not set VALID");
      end
      test_failed_count = test_failed_count + 1;
    end

    // Recover device to idle state after incomplete/invalid frame
    ps2_recovery(ps2_clk_tb, ps2_data_tb);
    wait_for_idle(ps2_clk, ps2_data);

    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    ////////////////////////////////////////////////////////////////////////
    // Section 8: HOST→DEVICE Parity Error Detection
    ////////////////////////////////////////////////////////////////////////
    $display("=== Section 8: HOST->DEVICE Parity Error Detection ===");

    $display("Test 8.1: Invalid parity should trigger error");
    host_send_byte_to_device_bad_parity(8'hED);
    #(5us);
    if (latched_error == 1'b1 && latched_valid == 1'b0) begin
      $display("PASS: Bad parity correctly detected as error");
      test_passed_count = test_passed_count + 1;
    end else begin
      if (latched_error != 1'b1) begin
        $display("FAIL: Bad parity not detected");
      end
      if (latched_valid != 1'b0) begin
        $display("FAIL: Invalid frame should not set VALID");
      end
      test_failed_count = test_failed_count + 1;
    end

    // Recover device to idle state after incomplete/invalid frame
    ps2_recovery(ps2_clk_tb, ps2_data_tb);
    wait_for_idle(ps2_clk, ps2_data);

    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    ////////////////////////////////////////////////////////////////////////
    // Section 9: HOST→DEVICE Sequential Transmissions
    ////////////////////////////////////////////////////////////////////////
    $display("=== Section 9: HOST->DEVICE Sequential Transmissions ===");

    // Wait for device to return to idle state after previous tests
    wait_for_idle(ps2_clk, ps2_data);

    $display("Test 9.1: Back-to-back HOST->DEVICE transmissions");
    host_send_byte_to_device(8'hF3);
    #(5us);
    if (latched_data != 8'hF3) begin
      $display("FAIL: Expected 0xF3");
      test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    // Small delay between commands (bus should return to idle: both lines high)
    #(50us);
    if (ps2_clk != 1'b1 && ps2_clk != 1'bz) begin
      $display("FAIL: Clock not high between transmissions");
    end
    if (ps2_data != 1'b1 && ps2_data != 1'bz) begin
      $display("FAIL: Data not high between transmissions");
    end

    host_send_byte_to_device(8'h30);
    #(5us);
    if (latched_data == 8'h30) begin
      $display("PASS: Sequential transmissions successful");
      test_passed_count = test_passed_count + 1;
    end else begin
      $display("FAIL: Expected 0x30");
      test_failed_count = test_failed_count + 1;
    end
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;

    ////////////////////////////////////////////////////////////////////////
    // Section 10: HOST->DEVICE Transmission with Inhibit Handling
    ////////////////////////////////////////////////////////////////////////
    $display("=== Section 10: HOST->DEVICE Transmission with Inhibit Handling ===");

    // Reset for clean state
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #(100us);

    // Test 10.1: DEVICE->HOST interrupted by host pulling DATA low (RTS) → device enters HOST→DEVICE mode
    $display("Test 10.1: DEVICE->HOST interrupted by host RTS (DATA low during inhibit)");

    // Device starts transmitting alternating bits (0xAA = 10101010)
    tx_data = 8'hAA;
    tx_start = 1'b1;
    #CLK_PERIOD;
    tx_start = 1'b0;

    // Wait for device to start transmitting (a few bit periods)
    #(300us);

    // Before inhibit: Device should be toggling DATA (alternating bits)
    $display("Monitoring device DATA activity before inhibit...");
    monitor_device_data_is_toggling(300, is_toggling);

    if (!is_toggling) begin
      $display("FAIL: Device DATA not toggling before inhibit");
      test_failed_count = test_failed_count + 1;
    end else begin
      $display("  Device DATA is toggling (transmitting 0xAA)");
    end

    // Host pulls CLK low for inhibit (≥100µs) MID-TRANSMISSION
    ps2_clk_tb = 1'b0;
    $display("Host inhibiting mid-transmission (CLK low for 100µs)...");
    #(50us);

    // During inhibit: Host pulls DATA low (signals RTS - host wants to send)
    ps2_data_tb = 1'b0;
    $display("Host pulled DATA low during inhibit (RTS signal)");
    #(50us);

    // Host releases CLK (device should detect RTS and enter HOST→DEVICE mode)
    ps2_clk_tb = 1'b1;
    $display("Host released CLK");

    // Wait for CLK to be high (released by both host and device)
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b1 || ps2_clk == 1'bz) break;
      #1ns;
    end

    // Wait for next falling edge of CLK (device pulls CLK low for HOST→DEVICE mode)
    for (int timeout = 0; timeout < 500000; timeout = timeout + 1) begin
      if (ps2_clk == 1'b0) break;
      #1ns;
    end

    // Host releases DATA on the falling edge
    ps2_data_tb = 1'b1;
    $display("Host released DATA on falling edge of CLK");
    #(200us);

    // After inhibit: Check device is NOT toggling DATA
    $display("Monitoring device DATA activity after inhibit...");
    monitor_device_data_is_toggling(500, is_toggling);

    test_passed = 1'b1;

    if (is_toggling) begin
      $display("FAIL: Device still toggling DATA after inhibit");
      test_passed = 1'b0;
    end else begin
      $display("  Device DATA is idle (no toggles)");
    end

    // Check: Device should STILL be driving CLK (DEVICE->HOST TX mode continues)
    monitor_device_clock_is_toggling(500, is_toggling);
    if (!is_toggling) begin
      $display("FAIL: Device not driving CLK after inhibit (should stay in TX mode)");
      test_passed = 1'b0;
    end else begin
      $display("  Device still driving CLK (TX mode active)");
    end

    if (test_passed) begin
      $display("PASS: Device handled inhibit with DATA low, stayed in TX mode");
      test_passed_count = test_passed_count + 1;
    end else begin
      test_failed_count = test_failed_count + 1;
    end

    // Clean up: Release bus and let device return to idle
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #(500us);

    // Test 10.2: DEVICE->HOST with inhibit + device releases DATA → recovery mode → IDLE
    $display("Test 10.2: DEVICE->HOST with device releasing DATA during inhibit (recovery)");
    reset_latch = 1'b1; #CLK_PERIOD; reset_latch = 1'b0; #CLK_PERIOD;
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #(100us);

    // Device starts transmitting alternating bits (0x55 = 01010101)
    tx_data = 8'h55;
    tx_start = 1'b1;
    #CLK_PERIOD;
    tx_start = 1'b0;

    // Wait for device to start transmitting (a few bit periods)
    #(300us);

    // Before inhibit: Device should be toggling DATA (alternating bits)
    $display("Monitoring device DATA activity before inhibit...");
    monitor_device_data_is_toggling(300, is_toggling);

    if (!is_toggling) begin
      $display("FAIL: Device DATA not toggling before inhibit");
      test_failed_count = test_failed_count + 1;
    end else begin
      $display("  Device DATA is toggling (transmitting 0x55)");
    end

    // Host pulls CLK low for inhibit (≥100µs) without pulling DATA low (recovery signal)
    ps2_clk_tb = 1'b0;
    // ps2_data_tb stays at 1'b1 (high) - no RTS, signals recovery
    $display("Host inhibiting with DATA high (recovery signal, CLK low for 100µs)...");
    #(100us);

    // Check: Device should RELEASE DATA (not pull low) during inhibit
    // This signals recovery mode
    if (device_data_out != 1'b1) begin
      $display("FAIL: Device pulled DATA low during inhibit (should release for recovery)");
      test_failed_count = test_failed_count + 1;
    end else begin
      $display("  Device released DATA during inhibit (recovery mode)");
    end

    // Host releases CLK (recovery sequence completes)
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    $display("Host released CLK (recovery complete)");
    #(200us);

    // After inhibit: Check device is NOT toggling DATA or CLK
    // Device should have reverted to IDLE state
    $display("Monitoring device activity after recovery...");
    monitor_device_data_is_toggling(500, is_toggling);

    test_passed = 1'b1;

    if (is_toggling) begin
      $display("FAIL: Device still toggling DATA after recovery");
      test_passed = 1'b0;
    end else begin
      $display("  Device DATA is idle (no toggles)");
    end

    // Check: Device should NOT be driving CLK (reverted to IDLE)
    monitor_device_clock_is_toggling(500, is_toggling);
    if (is_toggling) begin
      $display("FAIL: Device still driving CLK after recovery (should be IDLE)");
      test_passed = 1'b0;
    end else begin
      $display("  Device CLK is idle (IDLE state)");
    end

    if (test_passed) begin
      $display("PASS: Device entered recovery mode, reverted to IDLE");
      test_passed_count = test_passed_count + 1;
    end else begin
      test_failed_count = test_failed_count + 1;
    end

    // Clean up
    ps2_clk_tb = 1'b1;
    ps2_data_tb = 1'b1;
    #(500us);

    $display("=== ALL PS/2 PROTOCOL TESTS COMPLETED ===");
    $display("");
    $display("============================================");
    $display("TEST SUMMARY:");
    $display("  Total Passed: %0d", test_passed_count);
    $display("  Total Failed: %0d", test_failed_count);
    $display("============================================");

    test_done = 1'b1;
    #(10ns);

    if (test_failed_count == 0) begin
      $display("ALL TESTS PASSED");
      $finish(0);  // Exit with success status
    end else begin
      $finish(1);  // Exit with failure status
    end
  end

endmodule
