// PS/2 Interface Communication Test (HOST <-> DEVICE)
// Tests bidirectional communication between HOST and DEVICE ps2_interface instances
// Both instances share the same PS/2 bus (open-drain, pulled up)

module tb_ps2_interface_comms;

    // System clock
    logic clk = 0;
    logic nreset = 0;
    localparam time CLK_PERIOD = 91ns;        // ~11 MHz system clock
    localparam int TIMEOUT_CYCLES = 2000000;  // Generous timeout for RX/TX completion
    localparam int BUS_IDLE_CYCLES = 16;      // Idle samples required before HOST TX

    // Shared PS/2 bus (open-drain with pullups)
    tri1 ps2_clk;
    tri1 ps2_data;
    wire host_ps2_clk_out;
    wire host_ps2_data_out;
    wire device_clk_out;
    wire device_data_out;
    assign ps2_clk  = (host_ps2_clk_out === 1'b0) ? 1'b0 : 1'bz;
    assign ps2_data = (host_ps2_data_out === 1'b0) ? 1'b0 : 1'bz;
    assign ps2_clk  = (device_clk_out === 1'b0) ? 1'b0 : 1'bz;
    assign ps2_data = (device_data_out === 1'b0) ? 1'b0 : 1'bz;

    // HOST instance signals
    logic host_tx_start = 0;
    logic [7:0] host_tx_data = 8'h00;
    logic host_tx_busy;
    logic host_tx_done;
    logic [7:0] host_rx_data;
    logic host_rx_valid;
    logic host_rx_error;

    // DEVICE instance signals
    logic device_tx_start = 0;
    logic [7:0] device_tx_data = 8'h00;
    logic device_tx_busy;
    logic device_tx_done;
    logic [7:0] device_rx_data;
    logic device_rx_valid;
    logic device_rx_error;

    // Weak pullups on PS/2 lines (open-drain simulation)
    pullup(ps2_clk);
    pullup(ps2_data);

    // Instantiate HOST instance
    ps2_interface #(
        .FILTER_BITS(8),
        .TX_INHIBIT_CYCLES(1100)
    ) host_inst (
        .CLK(clk),
        .nRESET(nreset),
        .PS2_CLK_IN(ps2_clk),
        .PS2_DATA_IN(ps2_data),
        .PS2_CLK_OUT(host_ps2_clk_out),
        .PS2_DATA_OUT(host_ps2_data_out),
        .DATA(host_rx_data),
        .VALID(host_rx_valid),
        .ERROR(host_rx_error),
        .TX_DATA(host_tx_data),
        .TX_START(host_tx_start),
        .TX_MODE(2'b00),
        .TX_BUSY(host_tx_busy),
        .TX_DONE(host_tx_done)
    );

    // Instantiate DEVICE instance
    ps2_interface_device #(
        .FILTER_BITS(8),
        .CLOCK_DIV(1100)
    ) device_inst (
        .CLK(clk),
        .nRESET(nreset),
        .PS2_CLK_IN(ps2_clk),
        .PS2_DATA_IN(ps2_data),
        .PS2_CLK_OUT(device_clk_out),
        .PS2_DATA_OUT(device_data_out),
        .DATA(device_rx_data),
        .VALID(device_rx_valid),
        .ERROR(device_rx_error),
        .TX_DATA(device_tx_data),
        .TX_START(device_tx_start),
        .TX_MODE(2'b00),
        .TX_BUSY(device_tx_busy),
        .TX_DONE(device_tx_done)
    );

    // PS/2 Sniffer
    ps2_sniffer #(
        .HOST_IS_TRISTATE(0),
        .DEVICE_IS_TRISTATE(0)
    ) sniffer_inst (
        // Host side (non-tristate)
        .host_ps2_clk_in_i(ps2_clk),           // Monitor shared bus CLK
        .host_ps2_data_in_i(ps2_data),         // Monitor shared bus DATA
        .host_ps2_clk_out_i(host_ps2_clk_out), // Monitor host's CLK drive
        .host_ps2_data_out_i(host_ps2_data_out), // Monitor host's DATA drive

        // Device side (non-tristate)
        .device_ps2_clk_in_i(ps2_clk),       // Device monitors bus
        .device_ps2_data_in_i(ps2_data),     // Device monitors bus
        .device_ps2_clk_out_i(device_clk_out),   // Device CLK output
        .device_ps2_data_out_i(device_data_out)  // Device DATA output
    );

    // Clock generator: ~11 MHz (matches ps2_interface default assumptions)
    always #(CLK_PERIOD/2) clk = ~clk;

    // Test control: reset signal driven by initial block
    logic test_reset = 0;

    // Monitor outputs: driven only by capture always block, reset via test_reset
    logic host_valid_seen;
    logic device_valid_seen;
    logic host_error_seen;
    logic device_error_seen;
    logic [7:0] host_latched_data;
    logic [7:0] device_latched_data;

    // Capture VALID/ERROR pulses on every clock cycle
    always @(posedge clk) begin
        if (test_reset) begin
            host_valid_seen <= 0;
            device_valid_seen <= 0;
            host_error_seen <= 0;
            device_error_seen <= 0;
            host_latched_data <= 0;
            device_latched_data <= 0;
        end else begin
            if (host_rx_valid) begin
                host_latched_data <= host_rx_data;
                host_valid_seen <= 1;
            end
            if (host_rx_error) begin
                host_error_seen <= 1;
            end
            if (device_rx_valid) begin
                device_latched_data <= device_rx_data;
                device_valid_seen <= 1;
            end
            if (device_rx_error) begin
                device_error_seen <= 1;
            end
        end
    end

    task automatic pulse_start(ref logic start_sig);
        start_sig = 1;
        @(posedge clk);
        start_sig = 0;
    endtask

    task automatic reset_monitors();
        test_reset <= 1;
        @(posedge clk);
        test_reset <= 0;
        @(posedge clk);  // Wait for non-blocking assignments to settle
        // Verify that all monitor flags have been reset
        if (host_valid_seen !== 0 || host_error_seen !== 0 ||
            device_valid_seen !== 0 || device_error_seen !== 0 ||
            host_latched_data !== 0 || device_latched_data !== 0) begin
            $display("ERROR: Monitor flags not properly reset!");
            $display("  host_valid_seen=%b, host_error_seen=%b, device_valid_seen=%b, device_error_seen=%b, host_latched_data=0x%02x, device_latched_data=0x%02x",
                     host_valid_seen, host_error_seen, device_valid_seen, device_error_seen, host_latched_data, device_latched_data);
            $finish;
        end
    endtask

    task automatic wait_for_bus_idle();
        int idle_count;
        idle_count = 0;
        while (idle_count < BUS_IDLE_CYCLES) begin
            @(posedge clk);
            if (ps2_clk === 1'b1 && ps2_data === 1'b1) begin
                idle_count++;
            end else begin
                idle_count = 0;
            end
        end
        repeat (4) @(posedge clk);  // allow synchronizers/filters to latch idle
    endtask

    // Test stimulus
    initial begin
        $display("=== PS/2 Interface Communication Test ===");
        $display("Testing bidirectional communication between HOST and DEVICE\n");

        // Initialize
        nreset = 0;
        repeat (20) @(posedge clk);
        nreset = 1;
        repeat (20) @(posedge clk);

        reset_monitors();

        //////////////////////////////////////////////////////////////////////
        // Test 1: DEVICE sends 0x1C (A key make code) to HOST
        //////////////////////////////////////////////////////////////////////
        $display("Test 1: DEVICE sends 0x1C to HOST");
        reset_monitors();
        device_tx_data = 8'h1C;
        pulse_start(device_tx_start);

        wait(device_tx_busy);
        wait(host_valid_seen);

        if (host_valid_seen == 1 && host_latched_data == 8'h1C && host_error_seen == 0) begin
            $display("PASS: HOST received 0x1C from DEVICE");
        end else begin
            $display("FAIL: HOST did not receive correct data");
            $display("  host_valid_seen=%b, host_latched_data=0x%02x, host_rx_error=%b",
                     host_valid_seen, host_latched_data, host_error_seen);
            $finish;
        end

        // Wait for device to finish transmitting before next test
        wait(!device_tx_busy);
        repeat (50) @(posedge clk);

        //////////////////////////////////////////////////////////////////////
        // Test 2: DEVICE sends 0xF0 (break prefix) to HOST
        //////////////////////////////////////////////////////////////////////
        $display("\nTest 2: DEVICE sends 0xF0 to HOST");
        reset_monitors();
        device_tx_data = 8'hF0;
        pulse_start(device_tx_start);

        wait(device_tx_busy);
        wait(host_valid_seen);

        if (host_valid_seen == 1 && host_latched_data == 8'hF0 && host_error_seen == 0) begin
            $display("PASS: HOST received 0xF0 from DEVICE");
        end else begin
            $display("FAIL: HOST did not receive correct data");
            $display("  host_valid_seen=%b, host_latched_data=0x%02x, host_rx_error=%b",
                     host_valid_seen, host_latched_data, host_error_seen);
            $finish;
        end

        // Wait for device to finish transmitting before next test
        wait(!device_tx_busy);
        repeat (50) @(posedge clk);

        //////////////////////////////////////////////////////////////////////
        // Test 3: DEVICE sends 0xFF (reset command) to HOST
        //////////////////////////////////////////////////////////////////////
        $display("\nTest 3: DEVICE sends 0xFF to HOST");
        reset_monitors();
        device_tx_data = 8'hFF;
        pulse_start(device_tx_start);

        wait(device_tx_busy);
        wait(host_valid_seen);

        if (host_valid_seen == 1 && host_latched_data == 8'hFF && host_error_seen == 0) begin
            $display("PASS: HOST received 0xFF from DEVICE");
        end else begin
            $display("FAIL: HOST did not receive correct data");
            $display("  host_valid_seen=%b, host_latched_data=0x%02x, host_rx_error=%b",
                     host_valid_seen, host_latched_data, host_error_seen);
            $finish;
        end

        // Wait for device to finish transmitting before next test
        wait(!device_tx_busy);
        repeat (50) @(posedge clk);

        //////////////////////////////////////////////////////////////////////
        // Test 4: HOST sends 0xED (LED control) to DEVICE
        //////////////////////////////////////////////////////////////////////
        $display("\nTest 4: HOST sends 0xED to DEVICE");
        reset_monitors();
        wait_for_bus_idle();
        host_tx_data = 8'hED;
        pulse_start(host_tx_start);

        wait(host_tx_busy);
        wait(!host_tx_busy);
        wait(device_valid_seen);

        if (device_valid_seen == 1 && device_latched_data == 8'hED && device_error_seen == 0) begin
            $display("PASS: DEVICE received 0xED from HOST");
        end else begin
            $display("FAIL: DEVICE did not receive correct data");
            $display("  device_valid_seen=%b, device_latched_data=0x%02x, device_rx_error=%b",
                     device_valid_seen, device_latched_data, device_error_seen);
            $finish;
        end

        repeat (50) @(posedge clk);

        //////////////////////////////////////////////////////////////////////
        // Test 5: HOST sends 0xF4 (enable scanning) to DEVICE
        //////////////////////////////////////////////////////////////////////
        $display("\nTest 5: HOST sends 0xF4 to DEVICE");
        reset_monitors();
        wait_for_bus_idle();
        host_tx_data = 8'hF4;
        pulse_start(host_tx_start);

        wait(host_tx_busy);
        wait(!host_tx_busy);
        wait(device_valid_seen);

        if (device_valid_seen == 1 && device_latched_data == 8'hF4 && device_error_seen == 0) begin
            $display("PASS: DEVICE received 0xF4 from HOST");
        end else begin
            $display("FAIL: DEVICE did not receive correct data");
            $display("  device_valid_seen=%b, device_latched_data=0x%02x, device_rx_error=%b",
                     device_valid_seen, device_latched_data, device_error_seen);
            $finish;
        end

        repeat (50) @(posedge clk);

        $display("\n=== ALL TESTS PASSED ===");
        $finish;
    end

endmodule
