// PS/2 Keyboard Device Model
// Simulates a PS/2 keyboard device with command handling and scan code transmission

module keyboard_device #(
    parameter integer CLOCK_DIV = 5000  // For 50MHz: 50MHz / 10kHz = 5000
) (
    input  logic clk,
    input  logic reset,
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

    // Local TX activity monitors
    logic last_ps2_tx_start;
    logic last_ps2_tx_busy;
    logic last_ps2_tx_done;

    // Internal state
    typedef enum logic [3:0] {
        ST_IDLE,
        ST_SEND_ACK,
        ST_SEND_SELF_TEST_OK,
        ST_SEND_ID_BYTE1,
        ST_SEND_ID_BYTE2,
        ST_WAIT_SCAN_SET,
        ST_SEND_SCAN_SET,
        ST_SEND_ECHO,
        ST_SEND_RESEND,
        ST_SEND_SCANCODE
    } state_t;

    state_t state, next_state;

    // Keyboard state registers
    logic [1:0] scan_code_set_reg;
    logic       scanning_enabled_reg;
    logic       self_test_passed_reg;
    logic [7:0] last_cmd_reg;
    logic [7:0] last_tx_byte;  // For resend functionality


    // Scan code queue (simple FIFO)
    logic [7:0] scancode_queue [0:15];
    logic [3:0] queue_write_ptr;
    logic [3:0] queue_read_ptr;
    logic [3:0] queue_count;

    // Enqueue request from task (single pulse, processed each clock)
    logic       task_enqueue;
    logic [7:0] task_scancode;

    // TX frame capture for debug/parity checks (simulation only)
    logic [10:0] tx_bits_buffer;
    logic [10:0] tx_bits_latched;
    logic [3:0]  tx_bit_idx;
    logic        capturing_tx;
    logic        tx_frame_toggle_async;
    logic        tx_frame_toggle_meta;
    logic        tx_frame_toggle_sync;
    logic [7:0]  tx_frame_byte;
    logic        parity_ok;
    logic        start_ok;
    logic        stop_ok;
    time         tx_last_edge_time;
    time         tx_bit_deltas [0:10];
    time         min_delta;
    time         max_delta;
    time         sum_delta;
    integer      i;

    // Command constants
    localparam CMD_SET_LEDS         = 8'hED;
    localparam CMD_ECHO             = 8'hEE;
    localparam CMD_SET_SCANCODE_SET = 8'hF0;
    localparam CMD_READ_ID          = 8'hF2;
    localparam CMD_SET_TYPEMATIC    = 8'hF3;
    localparam CMD_ENABLE_SCANNING  = 8'hF4;
    localparam CMD_DISABLE_SCANNING = 8'hF5;
    localparam CMD_SET_DEFAULTS     = 8'hF6;
    localparam CMD_RESEND           = 8'hFE;
    localparam CMD_RESET            = 8'hFF;
    localparam CMD_QUERY_SCANCODE_SET = 8'h42;

    localparam RESP_ACK             = 8'hFA;
    localparam RESP_SELF_TEST_OK    = 8'hAA;
    localparam RESP_ID_BYTE1        = 8'hAB;
    localparam RESP_ID_BYTE2        = 8'h83;

    // Instantiate ps2_interface_device for DEVICE behavior
    ps2_interface_device #(
        .FILTER_BITS(8),
        .CLOCK_DIV(CLOCK_DIV)
    ) ps2_dev (
        .CLK(clk),
        .nRESET(~reset),
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
        .TX_ABORT(ps2_tx_abort)
    );

    // State machine and queue management combined
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            scan_code_set_reg <= 2'd2;  // Default to scan code set 2
            scanning_enabled_reg <= 1'b1;
            self_test_passed_reg <= 1'b1;
            last_cmd_reg <= 8'h00;
            last_tx_byte <= 8'h00;
            queue_write_ptr <= 4'h0;
            queue_read_ptr <= 4'h0;
            queue_count <= 4'h0;
            task_enqueue <= 1'b0;
        end else begin
            state <= next_state;

            // Debug state transitions
            if (state != next_state) begin
                $display("Time %t: kbd_model STATE %0d -> %0d", $time, state, next_state);
            end

            // Capture received commands
            if (ps2_rx_valid) begin
                $display("Time %t: kbd_model RX_VALID data=0x%h state=%0d", $time, ps2_rx_data, state);
                last_cmd_reg <= ps2_rx_data;
            end

            // Report errors
            if (ps2_rx_error) begin
                $display("ERROR Time %t: kbd_model RX_ERROR - parity or framing error detected", $time);
            end

            if (ps2_tx_abort) begin
                $display("ERROR Time %t: kbd_model TX_ABORT - transmission aborted by host inhibit", $time);
                state <= ST_IDLE;  // Reset to IDLE so we can receive new command
            end

            // Track last transmitted byte for resend
            if (ps2_tx_start) begin
                last_tx_byte <= ps2_tx_data;
            end

            // Update state based on commands
            if (state == ST_SEND_ACK && ps2_tx_done) begin
                // ACK sent, now process the command
                case (last_cmd_reg)
                    CMD_ENABLE_SCANNING: scanning_enabled_reg <= 1'b1;
                    CMD_DISABLE_SCANNING: scanning_enabled_reg <= 1'b0;
                    CMD_RESET: begin
                        scanning_enabled_reg <= 1'b1;
                        scan_code_set_reg <= 2'd2;
                        self_test_passed_reg <= 1'b1;
                    end
                    CMD_SET_DEFAULTS: begin
                        scanning_enabled_reg <= 1'b1;
                        scan_code_set_reg <= 2'd2;
                    end
                endcase
            end

            // Handle scan code set updates
            if (state == ST_WAIT_SCAN_SET && ps2_rx_valid) begin
                if (ps2_rx_data >= 8'h01 && ps2_rx_data <= 8'h03) begin
                    scan_code_set_reg <= ps2_rx_data[1:0];
                end
                // If query (0x00), respond with current scan code set
                if (ps2_rx_data == 8'h00) begin
                    last_cmd_reg <= CMD_QUERY_SCANCODE_SET;
                end
            end

            // Queue management: dequeue when scan code sent
            if (state == ST_SEND_SCANCODE && ps2_tx_done) begin
                queue_read_ptr <= queue_read_ptr + 1;
                queue_count <= queue_count - 1;
            end

            // Queue management: enqueue from task (check BEFORE clearing pulse)
            if (task_enqueue && queue_count < 16) begin
                scancode_queue[queue_write_ptr] <= task_scancode;
                queue_write_ptr <= queue_write_ptr + 1;
                queue_count <= queue_count + 1;
            end

            // Clear enqueue pulse AFTER processing
            task_enqueue <= 1'b0;
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
                        CMD_ECHO: next_state = ST_SEND_ECHO;
                        CMD_RESEND: next_state = ST_SEND_RESEND;
                        CMD_READ_ID: next_state = ST_SEND_ACK;
                        CMD_RESET: next_state = ST_SEND_ACK;
                        CMD_SET_SCANCODE_SET: next_state = ST_SEND_ACK;
                        default: next_state = ST_SEND_ACK;
                    endcase
                end else if (queue_count > 0 && scanning_enabled_reg && !ps2_tx_busy) begin
                    // Send queued scan code
                    next_state = ST_SEND_SCANCODE;
                end
            end

            ST_SEND_ACK: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = RESP_ACK;
                    ps2_tx_start = 1'b1;
                    ps2_tx_mode = 2'b00;
                end
                // Determine next state after ACK transmission completes
                if (ps2_tx_done) begin
                    $display("Time %t: kbd_model ST_SEND_ACK tx_done, last_cmd=0x%h", $time, last_cmd_reg);
                    case (last_cmd_reg)
                        CMD_RESET: next_state = ST_SEND_SELF_TEST_OK;
                        CMD_READ_ID: next_state = ST_SEND_ID_BYTE1;
                        CMD_SET_SCANCODE_SET: begin
                            next_state = ST_WAIT_SCAN_SET;
                            $display("Time %t: kbd_model Transitioning to ST_WAIT_SCAN_SET", $time);
                        end
                        CMD_QUERY_SCANCODE_SET: begin
                            // Scan code set query (0x00) - send the current value
                            next_state = ST_SEND_SCAN_SET;
                        end
                        default: next_state = ST_IDLE;
                    endcase
                end
            end

            ST_SEND_SELF_TEST_OK: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = RESP_SELF_TEST_OK;
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_IDLE;
            end

            ST_SEND_ID_BYTE1: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = RESP_ID_BYTE1;
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_SEND_ID_BYTE2;
            end

            ST_SEND_ID_BYTE2: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = RESP_ID_BYTE2;
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_IDLE;
            end

            ST_WAIT_SCAN_SET: begin
                if (ps2_rx_valid) begin
                    $display("kbd_model: Received scan code set byte 0x%h", ps2_rx_data);
                    // Send ACK for the scan code set byte
                    next_state = ST_SEND_ACK;
                end
            end

            ST_SEND_SCAN_SET: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = {6'b0, scan_code_set_reg};
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_IDLE;
            end

            ST_SEND_ECHO: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = CMD_ECHO;
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_IDLE;
            end

            ST_SEND_RESEND: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    ps2_tx_data = last_tx_byte;
                    ps2_tx_start = 1'b1;
                end
                if (ps2_tx_done) next_state = ST_IDLE;
            end

            ST_SEND_SCANCODE: begin
                if (!ps2_tx_busy && !ps2_tx_done) begin
                    $display("kbd_model: Sending scan code 0x%02x from queue (count=%0d)", scancode_queue[queue_read_ptr], queue_count);
                    ps2_tx_data = scancode_queue[queue_read_ptr];
                    ps2_tx_start = 1'b1;
                end
                // Wait for transmission to complete
                if (ps2_tx_done) begin
                    next_state = ST_IDLE;
                end
            end
        endcase
    end

    // Public task to queue a scan code for transmission
    // This task works by setting signals that the always_ff block monitors
    task send_scancode(input logic [7:0] scancode);
        automatic logic [3:0] temp_count = queue_count;
        $display("kbd_model: Request to send scancode 0x%02x (queue count=%0d) state=%0d", scancode, temp_count, state);
        if (temp_count < 16) begin
            task_scancode = scancode;
            task_enqueue = 1'b1;
            @(posedge clk);  // Wait for the always_ff to sample task_enqueue=1
            @(posedge clk);  // Wait for another clock for task_enqueue to be cleared by always_ff
            task_enqueue = 1'b0;  // Clear the signal (redundant but safe)
        end
    endtask

    // Capture transmitted frames on the PS/2 bus for parity/format checks (simulation aid)
    always @(negedge ps2_clk_in or posedge reset) begin
        if (reset) begin
            capturing_tx = 1'b0;
            tx_bit_idx = 4'd0;
            tx_bits_buffer = 11'd0;
            tx_bits_latched = 11'd0;
            tx_frame_toggle_async = 1'b0;
            tx_last_edge_time = 0;
        end else begin
            if (!capturing_tx && ps2_tx_busy) begin
                // Start bit is the first falling edge after TX becomes active
                capturing_tx = 1'b1;
                tx_bit_idx = 4'd0;
                tx_bits_buffer = 11'd0;
                tx_bits_buffer[0] = ps2_data_in;
                tx_last_edge_time = $time;
            end else if (capturing_tx) begin
                tx_bit_deltas[tx_bit_idx] = $time - tx_last_edge_time;
                tx_last_edge_time = $time;
                tx_bit_idx = tx_bit_idx + 1'b1;
                if (tx_bit_idx <= 4'd10) begin
                    tx_bits_buffer[tx_bit_idx] = ps2_data_in;
                end
                if (tx_bit_idx == 4'd10) begin
                    capturing_tx = 1'b0;
                    tx_bits_latched = tx_bits_buffer;
                    tx_frame_toggle_async = ~tx_frame_toggle_async;
                end
            end
        end
    end

    // Sync captured frame into clk domain and print parity/format diagnostics
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_frame_toggle_meta <= 1'b0;
            tx_frame_toggle_sync <= 1'b0;
            tx_frame_byte <= 8'h00;
        end else begin
            tx_frame_toggle_meta <= tx_frame_toggle_async;
            tx_frame_toggle_sync <= tx_frame_toggle_meta;

            if (tx_frame_toggle_meta != tx_frame_toggle_sync) begin
                tx_frame_byte <= tx_bits_latched[8:1];
                // start/data/parity/stop layout: [0]=start, [1]=data0 ... [8]=data7, [9]=parity, [10]=stop
                parity_ok = (^ {tx_bits_latched[8:1], tx_bits_latched[9]}) == 1'b1;
                start_ok  = tx_bits_latched[0] == 1'b0;
                stop_ok   = tx_bits_latched[10] == 1'b1;

                // Compute min/max/avg bit spacing (11 edges captured including start->data0 ... data7->parity->stop)
                min_delta = tx_bit_deltas[0];
                max_delta = tx_bit_deltas[0];
                sum_delta = 0;
                for (i = 0; i <= 10; i = i + 1) begin
                    if (tx_bit_deltas[i] < min_delta) min_delta = tx_bit_deltas[i];
                    if (tx_bit_deltas[i] > max_delta) max_delta = tx_bit_deltas[i];
                    sum_delta = sum_delta + tx_bit_deltas[i];
                end
            end
        end
    end

endmodule
