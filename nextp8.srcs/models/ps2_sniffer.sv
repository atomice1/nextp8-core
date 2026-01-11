// PS/2 Protocol Sniffer
// Passively monitors and logs PS/2 communication between host and device
// Reports CLK/DATA transitions, frame contents, and protocol violations
// Monitor-only module - does not drive any signals

module ps2_sniffer #(
    parameter bit HOST_IS_TRISTATE = 1'b0,
    parameter bit DEVICE_IS_TRISTATE = 1'b0,
    parameter bit VERBOSE = 1'b0
) (
    input  logic host_ps2_clk_in_i,
    input  logic host_ps2_data_in_i,
    input  logic host_ps2_clk_out_i,
    input  logic host_ps2_data_out_i,

    input  logic device_ps2_clk_in_i,
    input  logic device_ps2_data_in_i,
    input  logic device_ps2_clk_out_i,
    input  logic device_ps2_data_out_i
);

    // Signal state derivation logic
    // =============================
    // Bus signal = either party pulling low, or both released (high)
    // Who is driving low is determined by observing explicit drive and signal levels
    //
    // Host tristate:
    //   - in_i & out_i: same shared bus wire (tristate observation)
    //   - host_*_in_i shows bus state
    // Host non-tristate:
    //   - in_i: bus state (shared with device)
    //   - out_i: host's explicit drive (0 = driving low, 1 = released)
    //
    // Device: same conventions
    //

    // Bus state (what we observe on the wires)
    logic bus_clk, bus_data;

    // Who is explicitly or implicitly driving low?
    // These are combinatorial based on config and current signal levels.
    logic host_driving_clk_low, host_driving_data_low;
    logic device_driving_clk_low, device_driving_data_low;

    // Derive bus state
    // Bus signal is low if host input is low OR device input is low
    generate
        if (HOST_IS_TRISTATE && DEVICE_IS_TRISTATE) begin
            // Both tristate: host_ps2_*_in_i and device_ps2_*_in_i are both the shared bus
            assign bus_clk  = host_ps2_clk_in_i;   // Same as device_ps2_clk_in_i
            assign bus_data = host_ps2_data_in_i;  // Same as device_ps2_data_in_i
        end else if (HOST_IS_TRISTATE) begin
            // Host tristate, device non-tristate
            assign bus_clk  = host_ps2_clk_in_i  | device_ps2_clk_in_i;
            assign bus_data = host_ps2_data_in_i | device_ps2_data_in_i;
        end else if (DEVICE_IS_TRISTATE) begin
            // Host non-tristate, device tristate
            assign bus_clk  = host_ps2_clk_in_i  | device_ps2_clk_in_i;
            assign bus_data = host_ps2_data_in_i | device_ps2_data_in_i;
        end else begin
            // Both non-tristate (unusual but supported)
            assign bus_clk  = host_ps2_clk_in_i  | device_ps2_clk_in_i;
            assign bus_data = host_ps2_data_in_i | device_ps2_data_in_i;
        end
    endgenerate

    // Derive who is driving signals low
    // ================================
    // host_driving_clk_low =
    //   (host NOT tristate AND host explicitly driving low) OR
    //   (bus_clk is low AND host IS tristate AND device NOT tristate AND device NOT explicitly driving low)
    //
    // device_driving_clk_low =
    //   (device NOT tristate AND device explicitly driving low) OR
    //   (bus_clk is low AND device IS tristate AND host NOT tristate AND host NOT explicitly driving low)

    generate
        if (!HOST_IS_TRISTATE) begin
            // Host non-tristate: explicit drive signal
            assign host_driving_clk_low  = (host_ps2_clk_out_i == 1'b0);
            assign host_driving_data_low = (host_ps2_data_out_i == 1'b0);
        end else begin
            // Host tristate: infer from bus level and device state
            // host_driving_clk_low = (host_clk is low AND device NOT tristate AND device not explicitly driving low)
            //                      OR (host_clk is low AND device IS tristate)  -- ambiguous, but host could be driving
            assign host_driving_clk_low = bus_clk == 1'b0 &&
                ((DEVICE_IS_TRISTATE) ||
                 (!DEVICE_IS_TRISTATE && device_ps2_clk_out_i != 1'b0));
            assign host_driving_data_low = bus_data == 1'b0 &&
                ((DEVICE_IS_TRISTATE) ||
                 (!DEVICE_IS_TRISTATE && device_ps2_data_out_i != 1'b0));
        end

        if (!DEVICE_IS_TRISTATE) begin
            // Device non-tristate: explicit drive signal
            assign device_driving_clk_low  = (device_ps2_clk_out_i == 1'b0);
            assign device_driving_data_low = (device_ps2_data_out_i == 1'b0);
        end else begin
            // Device tristate: infer from bus level and host state
            // device_driving_clk_low = (device_clk is low AND host NOT tristate AND host not explicitly driving low)
            //                        OR (device_clk is low AND host IS tristate)  -- ambiguous, but device could be driving
            assign device_driving_clk_low = bus_clk == 1'b0 &&
                ((HOST_IS_TRISTATE) ||
                 (!HOST_IS_TRISTATE && host_ps2_clk_out_i != 1'b0));
            assign device_driving_data_low = bus_data == 1'b0 &&
                ((HOST_IS_TRISTATE) ||
                 (!HOST_IS_TRISTATE && host_ps2_data_out_i != 1'b0));
        end
    endgenerate

    // State tracking
    logic bus_clk_prev, bus_data_prev;
    logic host_driving_clk_low_prev, host_driving_data_low_prev;
    logic device_driving_clk_low_prev, device_driving_data_low_prev;

    logic [7:0] host_frame_bits;
    logic [3:0] host_bit_count;
    logic host_parity_bit;
    logic [2:0] host_frame_state;  // 0=idle, 1=start, 2=data, 3=parity, 4=stop, 5=ack
    logic [2:0] host_ack_state;    // 0=idle, 1=wait_data_low, 2=wait_clk_low, 3=wait_release

    logic [7:0] device_frame_bits;
    logic [3:0] device_bit_count;
    logic device_parity_bit;
    logic [2:0] device_frame_state;

    typedef enum logic [1:0] {
        TX_DIRECTION_IDLE = 2'b00,
        TX_DIRECTION_HOST = 2'b01,
        TX_DIRECTION_DEVICE = 2'b10
    } tx_direction_t;

    // Expected direction based on protocol state machine
    // Initial state: DEVICE -> HOST
    // After inhibit (host pulls CLK low): HOST -> DEVICE for one frame, then revert
    tx_direction_t expected_tx_direction = TX_DIRECTION_DEVICE;  // Start with DEVICE -> HOST

    // Actual direction being sampled (may differ from expected if protocol violation)
    tx_direction_t actual_tx_direction = TX_DIRECTION_DEVICE;

    localparam time FRAME_TIMEOUT = 100_000_000;   // 100ms in ns
    localparam time INHIBIT_MIN_TIME = 100_000;   // 100µs minimum inhibit time for recovery

    // Recovery mechanism tracking
    time host_clk_low_start_time;
    logic device_was_transmitting_on_inhibit;

    // Initialize state tracking registers
    initial begin
        bus_clk_prev = 1'b1;
        bus_data_prev = 1'b1;
        host_driving_clk_low_prev = 1'b0;
        host_driving_data_low_prev = 1'b0;
        device_driving_clk_low_prev = 1'b0;
        device_driving_data_low_prev = 1'b0;
        host_frame_state = 0;
        host_bit_count = 0;
        device_frame_state = 0;
        device_bit_count = 0;
        host_clk_low_start_time = 0;
        device_was_transmitting_on_inhibit = 0;
    end

    // Monitor all relevant signals for changes
    always @(*) begin
        // CLK transitions
        if (bus_clk !== bus_clk_prev) begin
            // Bus CLK state changed
            if (bus_clk == 1'b1) begin
                // CLK rising edge
                // HOST->DEVICE: data is sampled on rising edge (when expected)
                if (expected_tx_direction == TX_DIRECTION_HOST) begin
                    if (VERBOSE) $display("%t BUS CLK 0 -> 1 (DATA=%b)", $time, bus_data);
                    // Skip host bit check if recovery is in progress
                    if (host_driving_clk_low == host_driving_clk_low_prev || host_driving_data_low) begin
                        detect_host_bit();
                    end
                end else begin
                    if (VERBOSE) $display("%t BUS CLK 0 -> 1", $time);
                end
            end else begin
                // CLK falling edge
                // Skip frame detection if host is driving CLK low (inhibit in progress)
                if (host_driving_clk_low) begin
                    if (VERBOSE) $display("%t BUS CLK 1 -> 0 (host inhibit in progress)", $time);
                end else if (expected_tx_direction == TX_DIRECTION_DEVICE) begin
                    // DEVICE->HOST: data is sampled on falling edge (when expected)
                    if (VERBOSE) $display("%t BUS CLK 1 -> 0 (DATA=%b)", $time, bus_data);
                    detect_device_bit();
                end else begin
                    if (VERBOSE) $display("%t BUS CLK 1 -> 0", $time);
                end

                // Track HOST->DEVICE ACK: CLK going low
                if (host_frame_state == 5 && host_ack_state == 2) begin  // Waiting for CLK low
                    if (VERBOSE) $display("%t HOST TX ACK: Device brought CLK low", $time);
                    host_ack_state = 3;  // Wait for release
                end
            end
        end
        bus_clk_prev = bus_clk;
    end

    always @(*) begin
        // Report who is driving CLK low (drive state transitions)
        if (host_driving_clk_low !== host_driving_clk_low_prev) begin
            if (host_driving_clk_low) begin
                if (VERBOSE) $display("%t HOST starts driving CLK low (bus CLK=%b)", $time, bus_clk);
                check_host_drive_valid_clk();
                // Track start of inhibit ONLY if we haven't already started tracking
                // (avoids overwriting start time if device was already holding CLK low)
                if (host_clk_low_start_time == 0) begin
                    host_clk_low_start_time = $time;
                end
                // HOST pulling CLK low initiates inhibit; expected direction becomes HOST->DEVICE
                set_expected_tx_direction(TX_DIRECTION_HOST);
            end else begin
                // Host released CLK - check inhibit duration and recovery
                automatic time inhibit_duration;
                inhibit_duration = $time - host_clk_low_start_time;

                if (VERBOSE) $display("%t HOST releases CLK (bus CLK=%b, inhibit duration=%0t)", $time, bus_clk, inhibit_duration);

                // Inhibit timing check: Host should hold CLK low for ≥100µs
                // EXCEPTION: If HOST_IS_TRISTATE and device was transmitting, we can't detect
                // the true start time (only when device releases), so skip the check
                if (inhibit_duration > 0 && inhibit_duration < INHIBIT_MIN_TIME) begin
                    if (!HOST_IS_TRISTATE || !device_was_transmitting_on_inhibit) begin
                        $display("%t ERROR: HOST inhibit too short (%0t < 100µs minimum)", $time, inhibit_duration);
                    end else begin
                        if (VERBOSE) $display("%t NOTE: Inhibit appears short (%0t) but device was TX - actual start may be earlier",
                                            $time, inhibit_duration);
                    end
                end

                // Reset the start time tracker
                host_clk_low_start_time = 0;

                if (!host_driving_data_low) begin
                    if (VERBOSE) $display("%t PS/2 RECOVERY: Host inhibit + release detected, discarding partial frames", $time);
                    // Host held CLK low for ≥100µs and DATA is released
                    // This is a PS/2 recovery operation
                    host_frame_state = 0;
                    host_bit_count = 0;
                    device_frame_state = 0;
                    device_bit_count = 0;
                    // After recovery, revert to device-to-host direction
                    set_expected_tx_direction(TX_DIRECTION_DEVICE);
                end
            end
        end
        host_driving_clk_low_prev = host_driving_clk_low;
    end

    always @(*) begin
        if (device_driving_clk_low !== device_driving_clk_low_prev) begin
            if (device_driving_clk_low) begin
                if (VERBOSE) $display("%t DEVICE starts driving CLK low (bus CLK=%b)", $time, bus_clk);
                check_device_drive_valid_clk();

                // Check for protocol violation: DEVICE driving CLK during inhibit (host already driving it low)
                if (host_driving_clk_low) begin
                    $display("%t ERROR: DEVICE attempting to drive CLK during HOST inhibit (protocol violation)", $time);
                end
            end else begin
                if (VERBOSE) $display("%t DEVICE releases CLK (bus CLK=%b)", $time, bus_clk);
            end
        end
        device_driving_clk_low_prev = device_driving_clk_low;
    end

    always @(*) begin
        // DATA transitions
        if (bus_data !== bus_data_prev) begin
            if (VERBOSE) $display("%t BUS DATA %b -> %b", $time, bus_data_prev, bus_data);
            check_data_validity();

            // Track HOST->DEVICE acknowledgment sequence
            if (host_frame_state == 5) begin  // ACK state
                case (host_ack_state)
                    1: begin  // Wait for DATA low
                        if (bus_data == 1'b0) begin
                            if (VERBOSE) $display("%t HOST TX ACK: Device brought DATA low", $time);
                            host_ack_state = 2;  // Wait for CLK low
                        end
                    end
                    3: begin  // Wait for release
                        if (bus_data == 1'b1 && bus_clk == 1'b1) begin
                            if (VERBOSE) $display("%t HOST TX ACK: Device released DATA and CLK (ACK complete)", $time);
                            host_frame_state = 0;
                            host_ack_state = 0;
                            handle_host_tx_complete();
                        end
                    end
                endcase
            end
        end
        bus_data_prev = bus_data;
    end

    always @(*) begin
        // Report who is driving DATA low (drive state transitions)
        if (host_driving_data_low !== host_driving_data_low_prev) begin
            if (host_driving_data_low) begin
                if (VERBOSE) $display("%t HOST starts driving DATA low (bus DATA=%b)", $time, bus_data);
                check_host_drive_valid_data();
            end else begin
                if (VERBOSE) $display("%t HOST releases DATA (bus DATA=%b)", $time, bus_data);
            end
        end
        host_driving_data_low_prev = host_driving_data_low;
    end

    always @(*) begin
        if (device_driving_data_low !== device_driving_data_low_prev) begin
            if (device_driving_data_low) begin
                if (VERBOSE) $display("%t DEVICE starts driving DATA low (bus DATA=%b)", $time, bus_data);
                check_device_drive_valid_data();

                // Check for protocol violation: DEVICE driving DATA during HOST->DEVICE expected direction
                // Exception: Allow during ACK sequence (host_frame_state == 5)
                if (expected_tx_direction == TX_DIRECTION_HOST && host_frame_state != 5) begin
                    $display("%t ERROR: DEVICE attempting to drive DATA during HOST->DEVICE expected direction (protocol violation)", $time);
                end
            end else begin
                if (VERBOSE) $display("%t DEVICE releases DATA (bus DATA=%b)", $time, bus_data);
            end
        end
        device_driving_data_low_prev = device_driving_data_low;
    end

    task check_data_validity();
        // When DEVICE->HOST expected: DATA must not change when CLK is low
        // When HOST->DEVICE expected: DATA must not change when CLK is high
        // During ACK (host_frame_state == 5): Device drives, DATA changes when CLK is high

        if (expected_tx_direction == TX_DIRECTION_DEVICE) begin
            // DEVICE->HOST: DATA changes are only allowed when CLK is high
            if (bus_clk == 1'b0) begin
                $display("%t ERROR: DATA changed when CLK is low during DEVICE->HOST expected direction", $time);
            end
        end else if (expected_tx_direction == TX_DIRECTION_HOST && host_frame_state == 5) begin
            // HOST->DEVICE ACK: Device drives acknowledgment, DATA changes when CLK is high
            if (bus_clk == 1'b0) begin
                $display("%t ERROR: DATA changed when CLK is low during ACK sequence (should be high)", $time);
            end
        end else if (expected_tx_direction == TX_DIRECTION_HOST) begin
            // HOST->DEVICE: DATA changes are only allowed when CLK is low
            if (bus_clk == 1'b1) begin
                $display("%t ERROR: DATA changed when CLK is high during HOST->DEVICE expected direction", $time);
            end
        end
    endtask

    task check_host_drive_valid_clk();
        // Error if host non-tristate is driving CLK low but device doesn't see it low
        if (!HOST_IS_TRISTATE && host_driving_clk_low && device_ps2_clk_in_i != 1'b0) begin
            $display("%t ERROR: HOST driving CLK low but DEVICE doesn't see it low", $time);
        end
    endtask

    task check_device_drive_valid_clk();
        // Error if device non-tristate is driving CLK low but host doesn't see it low
        if (!DEVICE_IS_TRISTATE && device_driving_clk_low && host_ps2_clk_in_i != 1'b0) begin
            $display("%t ERROR: DEVICE driving CLK low but HOST doesn't see it low", $time);
        end
    endtask

    task check_host_drive_valid_data();
        // Error if host non-tristate is driving DATA low but device doesn't see it low
        if (!HOST_IS_TRISTATE && host_driving_data_low && device_ps2_data_in_i != 1'b0) begin
            $display("%t ERROR: HOST driving DATA low but DEVICE doesn't see it low", $time);
        end
    endtask

    task check_device_drive_valid_data();
        // Error if device non-tristate is driving DATA low but host doesn't see it low
        if (!DEVICE_IS_TRISTATE && device_driving_data_low && host_ps2_data_in_i != 1'b0) begin
            $display("%t ERROR: DEVICE driving DATA low but HOST doesn't see it low", $time);
        end
    endtask

    // Detect frame start and data bits
    task detect_host_bit();
        // HOST->DEVICE: data sampled on rising edge
        // START bit must be 0
        if (host_frame_state == 0) begin
            if (bus_data == 1'b0) begin
                // Valid START bit detected
                host_frame_state = 1;
                host_bit_count = 0;
                if (VERBOSE) $display("%t HOST TX | START (0)", $time);
            end else begin
                // Invalid START bit (expected 0, got 1)
                $display("%t ERROR: HOST invalid START bit (expected 0, got 1)", $time);
            end
        end else if (host_frame_state == 1 || host_frame_state == 2) begin
            // Data bits (8 bits)
            if (host_frame_state == 1) begin
                host_frame_state = 2;
            end
            if (host_bit_count < 8) begin
                host_frame_bits[host_bit_count] = bus_data;
                host_bit_count = host_bit_count + 1;
                print_host_frame_progress();
            end else if (host_bit_count == 8) begin
                // Parity bit
                host_parity_bit = bus_data;
                host_bit_count = host_bit_count + 1;
                check_host_parity();
                print_host_frame_progress();
            end else if (host_bit_count == 9) begin
                // Stop bit (must be 1)
                if (bus_data == 1'b1) begin
                    host_frame_state = 5;  // Enter ACK wait state
                    host_ack_state = 1;     // Wait for device to bring DATA low
                    host_bit_count = 0;
                    if (VERBOSE) $display("%t HOST TX | START (0) | %b (0x%0h) | %b (parity) | STOP (1)",
                             $time, host_frame_bits, host_frame_bits, host_parity_bit);
                    // Don't call handle_host_tx_complete yet - wait for ACK
                end else begin
                    $display("%t ERROR: HOST invalid STOP bit (expected 1, got 0)", $time);
                    host_frame_state = 0;
                    host_bit_count = 0;
                    host_ack_state = 0;
                end
            end
        end
    endtask

    task detect_device_bit();
        // DEVICE->HOST: data sampled on falling edge
        // START bit must be 0
        if (device_frame_state == 0) begin
            if (bus_data == 1'b0) begin
                // Valid START bit detected
                device_frame_state = 1;
                device_bit_count = 0;
                if (VERBOSE) $display("%t DEVICE TX | START (0)", $time);
            end else begin
                // Invalid START bit (expected 0, got 1)
                $display("%t ERROR: DEVICE invalid START bit (expected 0, got 1)", $time);
            end
        end else if (device_frame_state == 1 || device_frame_state == 2) begin
            // Data bits (8 bits)
            if (device_frame_state == 1) begin
                device_frame_state = 2;
            end
            if (device_bit_count < 8) begin
                device_frame_bits[device_bit_count] = bus_data;
                device_bit_count = device_bit_count + 1;
                print_device_frame_progress();
            end else if (device_bit_count == 8) begin
                // Parity bit
                device_parity_bit = bus_data;
                device_bit_count = device_bit_count + 1;
                check_device_parity();
                print_device_frame_progress();
            end else if (device_bit_count == 9) begin
                // Stop bit (must be 1)
                if (bus_data == 1'b1) begin
                    device_frame_state = 0;
                    device_bit_count = 0;
                    if (VERBOSE) $display("%t DEVICE TX | START (0) | %b (0x%0h) | %b (parity) | STOP (1)",
                             $time, device_frame_bits, device_frame_bits, device_parity_bit);
                    handle_device_tx_complete();
                end else begin
                    $display("%t ERROR: DEVICE invalid STOP bit (expected 1, got 0)", $time);
                    device_frame_state = 0;
                    device_bit_count = 0;
                end
            end
        end
    endtask

    task print_host_frame_progress();
        string frame_str;
        if (VERBOSE) begin
            frame_str = "HOST TX | START (0)";
            for (int i = 0; i < host_bit_count && i < 8; i++) begin
                frame_str = {frame_str, " | ", (host_frame_bits[i] ? "1" : "0")};
            end
            if (host_bit_count >= 9) begin
                frame_str = {frame_str, " | ", (host_parity_bit ? "1" : "0"), " (parity)"};
            end
            $display("%t %s", $time, frame_str);
        end
    endtask

    task print_device_frame_progress();
        string frame_str;
        if (VERBOSE) begin
            frame_str = "DEVICE TX | START (0)";
            for (int i = 0; i < device_bit_count && i < 8; i++) begin
                frame_str = {frame_str, " | ", (device_frame_bits[i] ? "1" : "0")};
            end
            if (device_bit_count >= 9) begin
                frame_str = {frame_str, " | ", (device_parity_bit ? "1" : "0"), " (parity)"};
            end
            $display("%t %s", $time, frame_str);
        end
    endtask

    task check_host_parity();
        logic parity;
        parity = ^host_frame_bits;  // XOR all data bits
        // For odd parity: (data_parity XOR parity_bit) should equal 1
        if ((parity ^ host_parity_bit) !== 1'b1) begin
            $display("%t ERROR: HOST PARITY MISMATCH (data=%b, parity=%b, result=%b, expected 1)",
                     $time, host_frame_bits, host_parity_bit, (parity ^ host_parity_bit));
        end
    endtask

    task check_device_parity();
        logic parity;
        parity = ^device_frame_bits;
        // For odd parity: (data_parity XOR parity_bit) should equal 1
        if ((parity ^ device_parity_bit) !== 1'b1) begin
            $display("%t ERROR: DEVICE PARITY MISMATCH (data=%b, parity=%b, result=%b, expected 1)",
                     $time, device_frame_bits, device_parity_bit, (parity ^ device_parity_bit));
        end
    endtask

    task set_expected_tx_direction(input tx_direction_t new_direction);
        if (new_direction !== expected_tx_direction) begin
            if (VERBOSE) begin
                if (new_direction == TX_DIRECTION_HOST) begin
                    $display("%t EXPECTED DIRECTION: HOST -> DEVICE (inhibit initiated)", $time);
                end else if (new_direction == TX_DIRECTION_DEVICE) begin
                    $display("%t EXPECTED DIRECTION: DEVICE -> HOST", $time);
                end
            end
            expected_tx_direction = new_direction;
        end
    endtask

    task handle_host_tx_complete();
        // After HOST frame completes, check the command and update expected direction accordingly
        // Most HOST commands expect a DEVICE response (ACK), so revert to DEVICE->HOST
        case (host_frame_bits)
            8'hF0: begin  // Set Scan Code Set command
                set_expected_tx_direction(TX_DIRECTION_DEVICE);
            end
            8'h02: begin  // Scan code set 2
                set_expected_tx_direction(TX_DIRECTION_DEVICE);
            end
            default: begin
                // Other commands also expect DEVICE response
                set_expected_tx_direction(TX_DIRECTION_DEVICE);
            end
        endcase
    endtask

    task handle_device_tx_complete();
        // After DEVICE frame completes, stay in DEVICE->HOST direction
        // (unless HOST had initiated inhibit, but that would change expected direction)
    endtask

endmodule