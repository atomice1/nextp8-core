// PS/2 Mouse Device Model
// Simulates a PS/2 mouse device with command handling and movement packet transmission

module mouse_device #(
    parameter integer CLOCK_DIV = 5000  // For 50MHz: 50MHz / 10kHz = 5000
) (
    input  logic clk,
    input  logic reset,
    input  logic debug_enable = 1'b1,
    input  logic intellimouse_capable,  // 1 = support Intellimouse mode, 0 = standard only
    input  wire  ps2_clk_in,
    input  wire  ps2_data_in,
    output logic ps2_clk_out,
    output logic ps2_data_out
);

    // PS/2 Interface signals
    logic [7:0] ps2_rx_data;
    logic       ps2_rx_valid;
    logic       ps2_rx_error;
    logic [7:0] ps2_tx_data;
    logic       ps2_tx_start;
    logic       ps2_tx_busy;
    logic [1:0] ps2_tx_mode;
    logic       ps2_tx_done;
    logic       ps2_tx_abort;
    logic       ps2_force_idle;

    // Internal state
    typedef enum logic [4:0] {
        ST_IDLE,
        ST_SEND_ACK,
        ST_SEND_SELF_TEST_OK,
        ST_SEND_DEVICE_ID,
        ST_SEND_STATUS,
        ST_SEND_RESOLUTION,
        ST_SEND_SAMPLE_RATE,
        ST_WAIT_SAMPLE_RATE,
        ST_WAIT_RESOLUTION,
        ST_SEND_MOVEMENT_BYTE1,
        ST_SEND_MOVEMENT_BYTE2,
        ST_SEND_MOVEMENT_BYTE3,
        ST_SEND_MOVEMENT_BYTE4,
        ST_SEND_RESEND
    } state_t;

    state_t state, next_state;

    // Mouse state registers
    logic       reporting_enabled_reg;
    logic       stream_mode_reg;
    logic [7:0] sample_rate_reg;
    logic [7:0] resolution_reg;
    logic [7:0] device_id_reg;
    logic [7:0] last_cmd_reg;
    logic [7:0] last_tx_byte;  // For resend functionality

    // Intellimouse detection (magic sequence: 200, 100, 80)
    logic [7:0] sample_rate_history [0:1];  // Last 2 sample rates
    logic       intellimouse_mode;

    // Movement packet queue (status, X, Y, Z)
    logic [7:0] packet_queue [0:63];  // 16 packets × 4 bytes
    logic [5:0] queue_write_ptr;
    logic [5:0] queue_read_ptr;
    logic [4:0] packet_count;  // Number of complete packets
    logic [1:0] current_byte;  // Which byte of current packet (0=status, 1=X, 2=Y, 3=Z)

    // Enqueue request from task (single pulse, processed each clock)
    logic       task_enqueue;
    logic [7:0] task_packet [0:3];  // 4-byte packet from task (Z=0 for 3-byte mode)

    // Command constants
    localparam CMD_SET_SCALING_1_1  = 8'hE6;
    localparam CMD_SET_SCALING_2_1  = 8'hE7;
    localparam CMD_SET_RESOLUTION   = 8'hE8;
    localparam CMD_REQUEST_STATUS   = 8'hE9;
    localparam CMD_SET_STREAM_MODE  = 8'hEA;
    localparam CMD_READ_DATA        = 8'hEB;
    localparam CMD_RESET_WRAP_MODE  = 8'hEC;
    localparam CMD_SET_WRAP_MODE    = 8'hEE;
    localparam CMD_SET_REMOTE_MODE  = 8'hF0;
    localparam CMD_READ_DEVICE_TYPE = 8'hF2;
    localparam CMD_SET_SAMPLE_RATE  = 8'hF3;
    localparam CMD_ENABLE_REPORTING = 8'hF4;
    localparam CMD_DISABLE_REPORTING= 8'hF5;
    localparam CMD_SET_DEFAULTS     = 8'hF6;
    localparam CMD_RESEND           = 8'hFE;
    localparam CMD_RESET            = 8'hFF;

    localparam RESP_ACK             = 8'hFA;
    localparam RESP_SELF_TEST_OK    = 8'hAA;
    localparam RESP_DEVICE_ID       = 8'h00;  // Standard PS/2 mouse
    localparam RESP_INTELLIMOUSE_ID = 8'h03;  // Microsoft Intellimouse

    // Instantiate ps2_interface_device for DEVICE behavior
    ps2_interface_device #(
        .FILTER_BITS(8),
        .CLOCK_DIV(CLOCK_DIV)
    ) ps2_dev (
        .CLK(clk),
        .nRESET(~reset),
        .debug_enable(debug_enable),
        .PS2_CLK_IN(ps2_clk_in),
        .PS2_DATA_IN(ps2_data_in),
        .PS2_CLK_OUT(ps2_clk_out),
        .PS2_DATA_OUT(ps2_data_out),
        .DATA(ps2_rx_data),
        .VALID(ps2_rx_valid),
        .ERROR(ps2_rx_error),
        .TX_DATA(ps2_tx_data),
        .TX_START(ps2_tx_start),
        .TX_MODE(ps2_tx_mode),
        .TX_BUSY(ps2_tx_busy),
        .TX_DONE(ps2_tx_done),
        .TX_ABORT(ps2_tx_abort),
        .FORCE_IDLE(ps2_force_idle)
    );

    // State machine
    // Debug: Monitor stream_mode changes
    logic prev_stream_mode;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            reporting_enabled_reg <= 1'b1;  // Enable reporting by default in sim
            stream_mode_reg <= 1'b1;  // Default to stream mode
            sample_rate_reg <= 8'd100;  // Default 100 samples/sec
            resolution_reg <= 8'd4;     // Default 4 counts/mm
            device_id_reg <= RESP_DEVICE_ID;
            last_cmd_reg <= 8'h00;
            last_tx_byte <= 8'h00;
            queue_write_ptr <= 6'h0;
            queue_read_ptr <= 6'h0;
            packet_count <= 5'h0;
            current_byte <= 2'h0;
            task_enqueue <= 1'b0;
            prev_stream_mode <= 1'b1;
            intellimouse_mode <= 1'b0;
            sample_rate_history[0] <= 8'd0;
            sample_rate_history[1] <= 8'd0;
            if (debug_enable) $display("Time %t: mouse_model RESET: stream_mode=1, reporting=1", $time);
        end else begin
            // Track stream_mode changes
            if (stream_mode_reg != prev_stream_mode) begin
                if (debug_enable) $display("Time %t: mouse_model stream_mode changed: %b -> %b", $time, prev_stream_mode, stream_mode_reg);
                prev_stream_mode <= stream_mode_reg;
            end
            state <= next_state;

            // Debug state transitions
            if (state != next_state) begin
                if (debug_enable) $display("Time %t: mouse_model STATE %0d -> %0d", $time, state, next_state);
            end

            // Capture received commands
            if (ps2_rx_valid) begin
                if (debug_enable) $display("Time %t: mouse_model RX_VALID data=0x%h state=%0d", $time, ps2_rx_data, state);
                last_cmd_reg <= ps2_rx_data;
            end

            // Report errors
            if (ps2_rx_error) begin
                $display("ERROR Time %t: mouse_model RX_ERROR - parity or framing error detected", $time);
            end

            if (ps2_force_idle) begin
                if (debug_enable) $display("Time %t: mouse_model FORCE_IDLE - resetting to IDLE state", $time);
                state <= ST_IDLE;  // Reset to IDLE when host releases inhibit
            end

            // Track last transmitted byte for resend
            if (ps2_tx_start) begin
                last_tx_byte <= ps2_tx_data;
            end

            // Update state based on commands
            if (state == ST_SEND_ACK && ps2_tx_done) begin
                case (last_cmd_reg)
                    CMD_ENABLE_REPORTING: begin
                        reporting_enabled_reg <= 1'b1;
                        if (debug_enable) $display("Time %t: mouse_model: Reporting ENABLED", $time);
                    end
                    CMD_DISABLE_REPORTING: begin
                        reporting_enabled_reg <= 1'b0;
                        if (debug_enable) $display("Time %t: mouse_model: Reporting DISABLED", $time);
                    end
                    CMD_SET_STREAM_MODE: begin
                        stream_mode_reg <= 1'b1;
                        if (debug_enable) $display("Time %t: mouse_model: Stream mode ENABLED", $time);
                    end
                    CMD_SET_REMOTE_MODE: begin
                        stream_mode_reg <= 1'b0;
                        if (debug_enable) $display("Time %t: mouse_model: Remote mode ENABLED (stream disabled)", $time);
                    end
                    CMD_RESET: begin
                        reporting_enabled_reg <= 1'b0;
                        stream_mode_reg <= 1'b1;
                        sample_rate_reg <= 8'd100;
                        resolution_reg <= 8'd4;
                        if (debug_enable) $display("Time %t: mouse_model: RESET - reporting disabled", $time);
                    end
                    CMD_SET_DEFAULTS: begin
                        reporting_enabled_reg <= 1'b0;
                        stream_mode_reg <= 1'b1;
                        sample_rate_reg <= 8'd100;
                        resolution_reg <= 8'd4;
                    end
                endcase
            end

            // Handle sample rate updates and Intellimouse magic sequence detection
            if (state == ST_WAIT_SAMPLE_RATE && ps2_rx_valid) begin
                sample_rate_reg <= ps2_rx_data;

                if (debug_enable) $display("Time %t: mouse_device received sample rate %0d, history=[%0d, %0d, %0d], capable=%0d",
                         $time, ps2_rx_data, ps2_rx_data, sample_rate_history[0], sample_rate_history[1], intellimouse_capable);

                // Shift sample rate history
                sample_rate_history[1] <= sample_rate_history[0];
                sample_rate_history[0] <= ps2_rx_data;

                // Check for Intellimouse magic sequence: 200, 100, 80
                // Only activate if device is Intellimouse-capable
                if (intellimouse_capable &&
                    sample_rate_history[1] == 8'd200 &&
                    sample_rate_history[0] == 8'd100 &&
                    ps2_rx_data == 8'd80) begin
                    intellimouse_mode <= 1'b1;
                    device_id_reg <= RESP_INTELLIMOUSE_ID;
                    if (debug_enable) $display("Time %t: Intellimouse mode ENABLED (magic sequence detected)", $time);
                end
            end

            // Handle resolution updates
            if (state == ST_WAIT_RESOLUTION && ps2_rx_valid) begin
                resolution_reg <= ps2_rx_data;
            end

            // Queue management: enqueue from task (check BEFORE clearing pulse)
            if (task_enqueue && packet_count < 16) begin
                if (intellimouse_mode) begin
                    if (debug_enable) $display("Time %t: mouse_model ENQUEUE (4-byte): bytes=0x%h 0x%h 0x%h 0x%h, new_count=%0d",
                             $time, task_packet[0], task_packet[1], task_packet[2], task_packet[3], packet_count + 1);
                    packet_queue[queue_write_ptr] <= task_packet[0];
                    packet_queue[queue_write_ptr + 1] <= task_packet[1];
                    packet_queue[queue_write_ptr + 2] <= task_packet[2];
                    packet_queue[queue_write_ptr + 3] <= task_packet[3];
                    queue_write_ptr <= queue_write_ptr + 4;
                end else begin
                    if (debug_enable) $display("Time %t: mouse_model ENQUEUE (3-byte): bytes=0x%h 0x%h 0x%h, new_count=%0d",
                             $time, task_packet[0], task_packet[1], task_packet[2], packet_count + 1);
                    packet_queue[queue_write_ptr] <= task_packet[0];
                    packet_queue[queue_write_ptr + 1] <= task_packet[1];
                    packet_queue[queue_write_ptr + 2] <= task_packet[2];
                    queue_write_ptr <= queue_write_ptr + 3;
                end
                packet_count <= packet_count + 1;
            end

            // Clear enqueue pulse AFTER processing
            task_enqueue <= 1'b0;

            // Advance through movement packet bytes
            if (state == ST_SEND_MOVEMENT_BYTE1 && ps2_tx_done) begin
                current_byte <= 2'h1;
            end else if (state == ST_SEND_MOVEMENT_BYTE2 && ps2_tx_done) begin
                current_byte <= 2'h2;
            end else if (state == ST_SEND_MOVEMENT_BYTE3 && ps2_tx_done) begin
                if (intellimouse_mode) begin
                    current_byte <= 2'h3;  // Send byte 4 (Z movement)
                end else begin
                    current_byte <= 2'h0;
                    queue_read_ptr <= queue_read_ptr + 3;
                    packet_count <= packet_count - 1;
                end
            end else if (state == ST_SEND_MOVEMENT_BYTE4 && ps2_tx_done) begin
                current_byte <= 2'h0;
                queue_read_ptr <= queue_read_ptr + 4;
                packet_count <= packet_count - 1;
            end
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;
        ps2_tx_data = 8'h00;
        ps2_tx_start = 1'b0;
        ps2_tx_mode = 2'b00;

        case (state)
            ST_IDLE: begin
                if (ps2_rx_valid) begin
                    case (ps2_rx_data)
                        CMD_RESEND: next_state = ST_SEND_RESEND;
                        CMD_READ_DEVICE_TYPE: next_state = ST_SEND_ACK;
                        CMD_REQUEST_STATUS: next_state = ST_SEND_ACK;
                        CMD_RESET: next_state = ST_SEND_ACK;
                        CMD_SET_SAMPLE_RATE: begin next_state = ST_SEND_ACK; if (debug_enable) $display("Time %t: mouse_model IDLE->SET_SAMPLE_RATE", $time); end
                        CMD_SET_RESOLUTION: next_state = ST_SEND_ACK;
                        CMD_READ_DATA: next_state = ST_SEND_ACK;
                        CMD_ENABLE_REPORTING: next_state = ST_SEND_ACK;
                        CMD_DISABLE_REPORTING: next_state = ST_SEND_ACK;
                        CMD_SET_STREAM_MODE: next_state = ST_SEND_ACK;
                        CMD_SET_REMOTE_MODE: next_state = ST_SEND_ACK;
                        CMD_SET_DEFAULTS: next_state = ST_SEND_ACK;
                        default: next_state = ST_SEND_ACK;
                    endcase
                end else if (packet_count > 0 && reporting_enabled_reg && stream_mode_reg && !ps2_tx_busy) begin
                    // Send queued movement packet in stream mode
                    if (debug_enable) $display("Time %t: mouse_model IDLE->SEND_MOVEMENT: packet_count=%0d reporting=%b stream=%b tx_busy=%b",
                             $time, packet_count, reporting_enabled_reg, stream_mode_reg, ps2_tx_busy);
                    next_state = ST_SEND_MOVEMENT_BYTE1;
                end
            end

            ST_SEND_ACK: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = RESP_ACK;
                    ps2_tx_start = 1'b1;
                    ps2_tx_mode = 2'b00;
                end
                // Determine next state after ACK
                if (ps2_tx_done) begin
                    case (last_cmd_reg)
                        CMD_RESET: next_state = ST_SEND_SELF_TEST_OK;
                        CMD_READ_DEVICE_TYPE: next_state = ST_SEND_DEVICE_ID;
                        CMD_REQUEST_STATUS: next_state = ST_SEND_STATUS;
                        CMD_SET_SAMPLE_RATE: next_state = ST_WAIT_SAMPLE_RATE;
                        CMD_SET_RESOLUTION: next_state = ST_WAIT_RESOLUTION;
                        CMD_READ_DATA: next_state = ST_SEND_MOVEMENT_BYTE1;  // Send one packet
                        default: next_state = ST_IDLE;
                    endcase
                end
            end

            ST_SEND_SELF_TEST_OK: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = RESP_SELF_TEST_OK;
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_SEND_DEVICE_ID;
            end

            ST_SEND_DEVICE_ID: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = device_id_reg;
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_IDLE;
            end

            ST_SEND_STATUS: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    // Status byte: bit 6=remote mode, bit 5=enabled, bit 4=scaling, bits 3-0=reserved
                    ps2_tx_data = {1'b0, ~stream_mode_reg, reporting_enabled_reg, 1'b0, 4'h0};
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_SEND_RESOLUTION;
            end

            ST_SEND_RESOLUTION: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = resolution_reg;
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_SEND_SAMPLE_RATE;
            end

            ST_SEND_SAMPLE_RATE: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = sample_rate_reg;
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_IDLE;
            end

            ST_WAIT_SAMPLE_RATE: begin
                if (ps2_rx_valid) begin
                    next_state = ST_SEND_ACK;
                end
            end

            ST_WAIT_RESOLUTION: begin
                if (ps2_rx_valid) begin
                    next_state = ST_SEND_ACK;
                end
            end

            ST_SEND_RESEND: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = last_tx_byte;
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_IDLE;
            end

            ST_SEND_MOVEMENT_BYTE1: begin
                if (!ps2_tx_busy && !ps2_tx_done && packet_count > 0) begin
                    ps2_tx_data = packet_queue[queue_read_ptr];
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_SEND_MOVEMENT_BYTE2;
            end

            ST_SEND_MOVEMENT_BYTE2: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = packet_queue[queue_read_ptr + 1];
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_SEND_MOVEMENT_BYTE3;
            end

            ST_SEND_MOVEMENT_BYTE3: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = packet_queue[queue_read_ptr + 2];
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) begin
                    if (intellimouse_mode)
                        next_state = ST_SEND_MOVEMENT_BYTE4;
                    else
                        next_state = ST_IDLE;
                end
            end

            ST_SEND_MOVEMENT_BYTE4: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = packet_queue[queue_read_ptr + 3];
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_IDLE;
            end
        endcase
    end

    // Public task to queue a movement packet (3 or 4 bytes: status, X, Y, [Z])
    task send_movement_packet(
        input logic left_btn,
        input logic right_btn,
        input logic middle_btn,
        input logic signed [8:0] x_movement,  // 9-bit signed
        input logic signed [8:0] y_movement,  // 9-bit signed
        input logic signed [3:0] z_movement   // 4-bit signed scroll wheel
    );
        logic [7:0] status_byte;
        logic [7:0] x_byte;
        logic [7:0] y_byte;
        logic [7:0] z_byte;
        logic x_overflow, y_overflow, x_sign, y_sign;
        automatic logic [4:0] temp_count = packet_count;

        // Check for overflow
        x_overflow = (x_movement > 9'sd255 || x_movement < -9'sd256);
        y_overflow = (y_movement > 9'sd255 || y_movement < -9'sd256);
        x_sign = x_movement[8];
        y_sign = y_movement[8];

        // Build status byte: [YOvfl|XOvfl|YSign|XSign|1|MidBtn|RgtBtn|LftBtn]
        status_byte = {y_overflow, x_overflow, y_sign, x_sign, 1'b1, middle_btn, right_btn, left_btn};

        // Movement bytes are 8-bit two's complement
        x_byte = x_movement[7:0];
        y_byte = y_movement[7:0];

        // Z byte is 4-bit signed, sign-extended to 8 bits
        z_byte = {{4{z_movement[3]}}, z_movement[3:0]};

        if (debug_enable) $display("mouse_model: Request to send movement packet (queue count=%0d) state=%0d", temp_count, state);
        // Queue the packet if space available
        if (temp_count < 16) begin
            task_packet[0] = status_byte;
            task_packet[1] = x_byte;
            task_packet[2] = y_byte;
            task_packet[3] = z_byte;  // Always include Z (ignored in 3-byte mode)
            task_enqueue = 1'b1;
            @(posedge clk);  // Wait for the always_ff to sample task_enqueue=1
            @(posedge clk);  // Wait for another clock for task_enqueue to be cleared by always_ff
            task_enqueue = 1'b0;  // Clear the signal (redundant but safe)
        end
    endtask

endmodule
