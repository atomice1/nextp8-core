`timescale 1ns/1ps

// ps2_interface_device.sv
// PS/2 protocol handler implementing the DEVICE role (keyboard/mouse emulation).
// Handles host-driven inhibit detect, framed RX, ACK generation, and device-driven TX sequencing.

module ps2_interface_device #(
    parameter FILTER_BITS = 8,      // Debounce filter depth
    parameter CLOCK_DIV   = 1100    // Clock divider for DEVICE mode (11MHz/1100 ≈ 10kHz)
) (
    input logic         CLK,
    input logic         nRESET,

    input wire          PS2_CLK_IN,
    input wire          PS2_DATA_IN,
    output logic        PS2_CLK_OUT,
    output logic        PS2_DATA_OUT,

    output logic [7:0]  DATA,
    output logic        VALID,
    output logic        ERROR,

    input logic [7:0]   TX_DATA,
    input logic         TX_START,
    input logic [1:0]   TX_MODE,

    output logic        TX_BUSY,
    output logic        TX_DONE,
    output logic        TX_ABORT,
    output logic        FORCE_IDLE
);

    localparam MIN_INHIBIT_CYCLES   = CLOCK_DIV;
    localparam RX_STOP_GUARD_CYCLES = 16;

    typedef enum logic [2:0] {
        PS2_IDLE,
        PS2_INHIBIT,
        PS2_RX,
        PS2_RX_ACK,
        PS2_TX
    } ps2_state_t;

    typedef enum logic [3:0] {
        TX_ST_IDLE,
        TX_ST_START0,
        TX_ST_START1,
        TX_ST_BIT0,
        TX_ST_BIT1,
        TX_ST_BIT2,
        TX_ST_BIT3,
        TX_ST_BIT4,
        TX_ST_BIT5,
        TX_ST_BIT6,
        TX_ST_BIT7,
        TX_ST_PARITY,
        TX_ST_STOP,
        TX_ST_RELEASE
    } tx_state_t;

    typedef enum logic [2:0] {
        RX_ACK_IDLE,
        RX_ACK_DATA_LOW,
        RX_ACK_CLK_LOW,
        RX_ACK_HOLD,
        RX_ACK_RELEASE
    } rx_ack_state_t;

    rx_ack_state_t rx_ack_state;

    ps2_state_t ps2_state;
    ps2_state_t ps2_state_prev;

    tx_state_t tx_state;

    logic [1:0] ps2c_sync;
    logic [1:0] ps2d_sync;

    logic [FILTER_BITS-1:0] clk_filter;
    logic [FILTER_BITS-1:0] data_filter;

    logic ps2c_filt;
    logic ps2d_filt;
    logic ps2c_filt_d;
    logic ps2d_filt_d;

    logic ps2c_sync_d;
    logic ps2c_sync_fall_p;
    logic ps2c_sync_rise_p;

    logic [3:0] bit_state;
    logic [7:0] shift;
    logic parity_acc;
    logic [7:0] data_reg;
    logic valid_pulse;
    logic error_pulse;
    logic rx_wait_low;
    logic rx_sampled_bit;
    logic rx_sampled_valid;
    logic rx_stop_low_seen;
    logic [4:0] rx_stop_guard_cnt;
    logic [15:0] rx_ack_counter;

    logic [7:0] tx_shift;
    logic tx_parity;
    logic [7:0] tx_data_latched;

    logic [15:0] inhibit_counter;
    logic [15:0] dev_clk_counter;
    logic dev_clk_toggle;
    logic ps2_clk_out;
    logic ps2_data_out;
    logic host_was_inhibiting;
    logic tx_aborted;
    logic force_idle_pulse;

    // Temporary variables for logic operations
    logic clk_all_high, clk_all_low, data_all_high, data_all_low;
    logic sampled_bit;
    logic p;

    // Direct output assignments (tri-state handled externally)
    assign PS2_CLK_OUT  = ps2_clk_out;
    assign PS2_DATA_OUT = ps2_data_out;

    assign DATA    = data_reg;
    assign VALID   = valid_pulse;
    assign ERROR   = error_pulse;
    assign TX_BUSY = (ps2_state == PS2_TX) ? 1'b1 : 1'b0;
    assign TX_DONE = (ps2_state_prev == PS2_TX && ps2_state != PS2_TX) ? 1'b1 : 1'b0;
    assign TX_ABORT = tx_aborted;
    assign FORCE_IDLE = force_idle_pulse;

    // Synchronizer process
    always_ff @(posedge CLK or negedge nRESET) begin
        if (nRESET == 1'b0) begin
            ps2c_sync <= 2'b11;
            ps2d_sync <= 2'b11;
        end else begin
            ps2c_sync <= {ps2c_sync[0], PS2_CLK_IN};
            ps2d_sync <= {ps2d_sync[0], PS2_DATA_IN};
        end
    end

    // Filter process
    always_ff @(posedge CLK or negedge nRESET) begin
        if (nRESET == 1'b0) begin
            clk_filter  <= {FILTER_BITS{1'b1}};
            data_filter <= {FILTER_BITS{1'b1}};
            ps2c_filt   <= 1'b1;
            ps2d_filt   <= 1'b1;
            ps2c_filt_d <= 1'b1;
            ps2d_filt_d <= 1'b1;
            ps2c_sync_d <= 1'b1;
            ps2c_sync_fall_p <= 1'b0;
            ps2c_sync_rise_p <= 1'b0;
        end else begin
            clk_filter  <= {clk_filter[FILTER_BITS-2:0], ps2c_sync[1]};
            data_filter <= {data_filter[FILTER_BITS-2:0], ps2d_sync[1]};

            clk_all_high = 1'b1;
            clk_all_low = 1'b1;
            data_all_high = 1'b1;
            data_all_low = 1'b1;

            for (int i = 0; i < FILTER_BITS; i++) begin
                if (clk_filter[i] == 1'b0) begin
                    clk_all_high = 1'b0;
                end
                if (clk_filter[i] == 1'b1) begin
                    clk_all_low = 1'b0;
                end
                if (data_filter[i] == 1'b0) begin
                    data_all_high = 1'b0;
                end
                if (data_filter[i] == 1'b1) begin
                    data_all_low = 1'b0;
                end
            end

            if (clk_all_high == 1'b1) begin
                ps2c_filt <= 1'b1;
            end else if (clk_all_low == 1'b1) begin
                ps2c_filt <= 1'b0;
            end

            if (data_all_high == 1'b1) begin
                ps2d_filt <= 1'b1;
            end else if (data_all_low == 1'b1) begin
                ps2d_filt <= 1'b0;
            end

            ps2c_filt_d <= ps2c_filt;
            ps2d_filt_d <= ps2d_filt;

            ps2c_sync_d <= ps2c_sync[1];
            ps2c_sync_fall_p <= ps2c_sync_d & ~ps2c_sync[1];
            ps2c_sync_rise_p <= ~ps2c_sync_d & ps2c_sync[1];
        end
    end

    // PS/2 FSM process
    always_ff @(posedge CLK or negedge nRESET) begin
        if (nRESET == 1'b0) begin
            ps2_state      <= PS2_IDLE;
            ps2_state_prev <= PS2_IDLE;
            inhibit_counter <= 16'h0000;

            bit_state        <= 4'h0;
            shift            <= 8'h00;
            parity_acc       <= 1'b0;
            data_reg         <= 8'h00;
            valid_pulse      <= 1'b0;
            error_pulse      <= 1'b0;
            // No per-bit ACK state machine (PS/2 ACK is a full frame)
            rx_wait_low      <= 1'b0;
            rx_sampled_bit   <= 1'b1;
            rx_sampled_valid <= 1'b0;
            rx_stop_low_seen <= 1'b0;
            rx_stop_guard_cnt <= RX_STOP_GUARD_CYCLES;

            tx_state        <= TX_ST_IDLE;
            rx_ack_state  <= RX_ACK_IDLE;
            rx_ack_counter <= 16'h0000;
            tx_shift        <= 8'h00;
            tx_parity       <= 1'b0;
            tx_data_latched <= 8'h00;

            dev_clk_counter <= 16'h0000;
            dev_clk_toggle  <= 1'b0;

            ps2_clk_out  <= 1'b1;
            ps2_data_out <= 1'b1;
            host_was_inhibiting <= 1'b0;
            tx_aborted <= 1'b0;
            force_idle_pulse <= 1'b0;
        end else begin
            ps2_state_prev <= ps2_state;
            valid_pulse    <= 1'b0;
            error_pulse    <= 1'b0;
            ps2_clk_out    <= 1'b1;
            ps2_data_out   <= 1'b1;
            tx_aborted     <= 1'b0;
            force_idle_pulse <= 1'b0;

            // Track if host is driving CLK low (only when device is not driving it)
            // Use previous cycle's ps2_clk_out to determine if device was driving
            host_was_inhibiting   <= (PS2_CLK_IN == 1'b0 && dev_clk_toggle == 1'b1) ? 1'b1 : 1'b0;

            if (TX_START == 1'b1) begin
                tx_data_latched <= TX_DATA;
            end

            if (ps2c_sync[1] == 1'b0) begin
                if (inhibit_counter < MIN_INHIBIT_CYCLES) begin
                    inhibit_counter <= inhibit_counter + 1;
                    if (inhibit_counter == 0 || inhibit_counter == 100 || inhibit_counter == 500 ||
                        inhibit_counter == MIN_INHIBIT_CYCLES - 1) begin
                    end
                end
            end else begin
                inhibit_counter <= 16'h0000;
            end

            // Device clock generation: runs when in RX/TX mode AND host not pulling CLK low
            if ((ps2_state == PS2_RX || (ps2_state == PS2_TX && tx_state != TX_ST_IDLE))) begin
                // Host not pulling CLK low - run clock counter
                if (host_was_inhibiting) begin
                    // After inhibit, reset counter to start clock cycle afresh
                    dev_clk_counter <= 16'h0000;
                    dev_clk_toggle  <= 1'b1;
                end else if (dev_clk_counter >= (CLOCK_DIV / 2) - 1) begin
                    dev_clk_counter <= 16'h0000;
                    dev_clk_toggle  <= ~dev_clk_toggle;
                end else begin
                    dev_clk_counter <= dev_clk_counter + 1;
                end
                // else: host pulling CLK low - freeze counter (keep current values)
            end else begin
                // Not in RX/TX mode - reset counter
                dev_clk_counter <= 16'h0000;
                dev_clk_toggle  <= 1'b1;
            end

            if (ps2_state == PS2_RX) begin
                if (ps2c_sync_fall_p == 1'b1) begin
                    rx_wait_low <= 1'b0;
                end

                if (ps2c_sync[1] == 1'b0) begin
                    if (ps2d_sync[0] == 1'b0) begin
                        rx_sampled_bit <= 1'b0;
                    end else begin
                        rx_sampled_bit <= 1'b1;
                    end
                    rx_sampled_valid <= 1'b1;
                end

                if (bit_state == 4'hA) begin
                    if (ps2c_sync[1] == 1'b0) begin
                        if (rx_stop_guard_cnt > 5'h00) begin
                            rx_stop_guard_cnt <= rx_stop_guard_cnt - 1;
                        end else if (ps2d_sync[0] == 1'b0) begin
                            rx_stop_low_seen <= 1'b1;
                        end
                    end
                end else begin
                    rx_stop_low_seen <= 1'b0;
                    rx_stop_guard_cnt <= RX_STOP_GUARD_CYCLES;
                end

                if (ps2c_sync_rise_p == 1'b1 && rx_wait_low == 1'b0) begin
                    rx_wait_low <= 1'b1;

                    // Sample the bit value
                    if (rx_sampled_valid == 1'b1) begin
                        sampled_bit = rx_sampled_bit;
                    end else if (ps2d_sync[0] == 1'b0) begin
                        sampled_bit = 1'b0;
                    end else begin
                        sampled_bit = 1'b1;
                    end
                    rx_sampled_valid <= 1'b0;

                    case (bit_state)
                        4'h0: begin
                            if (sampled_bit == 1'b0) begin
                                bit_state  <= 4'h1;
                                parity_acc <= 1'b0;
                                shift      <= 8'h00;
                            end
                        end
                        4'h1, 4'h2, 4'h3, 4'h4, 4'h5, 4'h6, 4'h7, 4'h8: begin
                            shift[bit_state - 1] <= sampled_bit;
                            parity_acc <= parity_acc ^ sampled_bit;
                            bit_state   <= bit_state + 1;
                        end
                        4'h9: begin
                            parity_acc <= parity_acc ^ sampled_bit;
                            bit_state  <= bit_state + 1;
                        end
                        4'hA: begin
                            data_reg <= shift;
                            if (sampled_bit == 1'b1 && parity_acc == 1'b1) begin
                                valid_pulse <= 1'b1;
                            end else begin
                                error_pulse <= 1'b1;
                            end
                            bit_state <= 4'h0;
                        end
                    endcase
                end
            end else begin
                bit_state        <= 4'h0;
                parity_acc       <= 1'b0;
                rx_wait_low      <= 1'b0;
                rx_sampled_valid <= 1'b0;
                rx_stop_low_seen <= 1'b0;
                rx_stop_guard_cnt <= RX_STOP_GUARD_CYCLES;
            end

            //--------------------------------------------------
            // RX Acknowledgment sequence (device responds to host)
            //--------------------------------------------------
            if (ps2_state == PS2_RX_ACK) begin
                case (rx_ack_state)
                    RX_ACK_IDLE: begin
                        // Should not reach here
                    end
                    RX_ACK_DATA_LOW: begin
                        // Step 1: Bring DATA low
                        ps2_data_out <= 1'b0;
                        rx_ack_state <= RX_ACK_CLK_LOW;
                    end
                    RX_ACK_CLK_LOW: begin
                        // Step 2: Bring CLK low
                        ps2_clk_out <= 1'b0;
                        ps2_data_out <= 1'b0;
                        rx_ack_counter <= (CLOCK_DIV / 2);  // Half clock period
                        rx_ack_state <= RX_ACK_HOLD;
                    end
                    RX_ACK_HOLD: begin
                        // Step 3: Hold CLK low for half period
                        ps2_clk_out <= 1'b0;
                        ps2_data_out <= 1'b0;
                        if (rx_ack_counter > 16'h0000) begin
                            rx_ack_counter <= rx_ack_counter - 1;
                        end else begin
                            rx_ack_state <= RX_ACK_RELEASE;
                        end
                    end
                    RX_ACK_RELEASE: begin
                        // Step 4 & 5: Release CLK and DATA (handled by top-level state transition)
                        ps2_clk_out <= 1'b1;
                        ps2_data_out <= 1'b1;
                    end
                endcase
            end else begin
                rx_ack_state <= RX_ACK_IDLE;
                rx_ack_counter <= 16'h0000;
            end

            //--------------------------------------------------
            // TX Handling and Abort Detection
            //--------------------------------------------------
            if (inhibit_counter >= MIN_INHIBIT_CYCLES) begin
                // Full inhibit - abort transmission entirely
            end else if (ps2c_sync[1] == 1'b0 && tx_state != TX_ST_IDLE) begin
                // Host pulling CLK low but < 100us - freeze TX state machine
                // Keep ps2_data_out at current value but don't drive clock
                case (tx_state)
                    TX_ST_START1: ps2_data_out <= 1'b0;
                    TX_ST_BIT0, TX_ST_BIT1, TX_ST_BIT2, TX_ST_BIT3,
                    TX_ST_BIT4, TX_ST_BIT5, TX_ST_BIT6, TX_ST_BIT7: begin
                        if (tx_shift[0] == 1'b0) begin
                            ps2_data_out <= 1'b0;
                        end
                    end
                    TX_ST_PARITY: begin
                        if (tx_parity == 1'b0) begin
                            ps2_data_out <= 1'b0;
                        end
                    end
                    TX_ST_STOP: begin
                        if (TX_MODE == 2'b10) begin
                            ps2_data_out <= 1'b0;
                        end
                    end
                    default: ;
                endcase
            end else begin
                case (tx_state)
                    TX_ST_IDLE: begin
                        if (ps2_state == PS2_TX) begin
                            tx_shift <= tx_data_latched;
                            p = 1'b0;
                            for (int i = 0; i < 8; i++) begin
                                p = p ^ tx_data_latched[i];
                            end
                            tx_parity <= ~p;
                            tx_state  <= TX_ST_START0;
                        end
                    end
                    TX_ST_START0: begin
                        if (dev_clk_toggle == 1'b1 && dev_clk_counter == (CLOCK_DIV / 4)) begin
                            tx_state <= TX_ST_START1;
                        end
                    end
                    TX_ST_START1: begin
                        ps2_data_out <= 1'b0;
                        if (dev_clk_toggle == 1'b1 && dev_clk_counter == (CLOCK_DIV / 4)) begin
                            tx_state <= TX_ST_BIT0;
                        end
                    end
                    TX_ST_BIT0, TX_ST_BIT1, TX_ST_BIT2, TX_ST_BIT3,
                    TX_ST_BIT4, TX_ST_BIT5, TX_ST_BIT6, TX_ST_BIT7: begin
                        if (tx_shift[0] == 1'b0) begin
                            ps2_data_out <= 1'b0;
                        end
                        if (dev_clk_toggle == 1'b1 && dev_clk_counter == (CLOCK_DIV / 4)) begin
                            tx_shift <= {1'b0, tx_shift[7:1]};
                            case (tx_state)
                                TX_ST_BIT0: tx_state <= TX_ST_BIT1;
                                TX_ST_BIT1: tx_state <= TX_ST_BIT2;
                                TX_ST_BIT2: tx_state <= TX_ST_BIT3;
                                TX_ST_BIT3: tx_state <= TX_ST_BIT4;
                                TX_ST_BIT4: tx_state <= TX_ST_BIT5;
                                TX_ST_BIT5: tx_state <= TX_ST_BIT6;
                                TX_ST_BIT6: tx_state <= TX_ST_BIT7;
                                TX_ST_BIT7: tx_state <= TX_ST_PARITY;
                                default: ;
                            endcase
                        end
                    end
                    TX_ST_PARITY: begin
                        if (TX_MODE == 2'b01) begin
                            if (tx_parity == 1'b0) begin
                                ps2_data_out <= 1'b0;
                            end
                        end else begin
                            if (tx_parity == 1'b0) begin
                                ps2_data_out <= 1'b0;
                            end
                        end
                        if (dev_clk_toggle == 1'b1 && dev_clk_counter == (CLOCK_DIV / 4)) begin
                            tx_state <= TX_ST_STOP;
                        end
                    end
                    TX_ST_STOP: begin
                        if (TX_MODE == 2'b10) begin
                            ps2_data_out <= 1'b0;
                        end
                        if (dev_clk_toggle == 1'b1 && dev_clk_counter <= 1) begin
                            tx_state <= TX_ST_RELEASE;
                        end
                    end
                    TX_ST_RELEASE: begin
                        tx_state <= TX_ST_IDLE;
                    end
                endcase
            end

            // Detect abort before resetting tx_state
            if (ps2_state == PS2_TX && inhibit_counter >= MIN_INHIBIT_CYCLES && tx_state != TX_ST_IDLE) begin
                tx_aborted <= 1'b1;
            end

            if (ps2_state != PS2_TX || inhibit_counter >= MIN_INHIBIT_CYCLES) begin
                tx_state <= TX_ST_IDLE;
            end

            case (ps2_state)
                PS2_IDLE: begin
                    if (TX_START == 1'b1) begin
                        $display("Time %t: ps2_interface_device: PS2_IDLE->PS2_TX (TX_START)", $time);
                        ps2_state <= PS2_TX;
                    end else if (inhibit_counter >= MIN_INHIBIT_CYCLES) begin
                        $display("Time %t: ps2_interface_device: PS2_IDLE->PS2_INHIBIT (inhibit_counter=%0d >= MIN=%0d)",
                                 $time, inhibit_counter, MIN_INHIBIT_CYCLES);
                        ps2_state <= PS2_INHIBIT;
                    end else begin
                        ps2_state <= PS2_IDLE;
                    end
                end
                PS2_INHIBIT: begin
                    if (ps2c_sync[1] == 1'b0) begin
                        ps2_state <= PS2_INHIBIT;
                    end else if (ps2d_sync[1] == 1'b0) begin
                        $display("Time %t: ps2_interface_device: PS2_INHIBIT->PS2_RX (CLK released, DATA=0)", $time);
                        ps2_state <= PS2_RX;
                    end else begin
                        $display("Time %t: ps2_interface_device: PS2_INHIBIT->PS2_IDLE (CLK released, DATA=1)", $time);
                        force_idle_pulse <= 1'b1;
                        ps2_state <= PS2_IDLE;
                    end
                end
                PS2_RX: begin
                    if (valid_pulse == 1'b1) begin
                        $display("Time %t: ps2_interface_device: PS2_RX->PS2_RX_ACK (valid byte received, sending ACK)", $time);
                        ps2_state <= PS2_RX_ACK;
                        rx_ack_state <= RX_ACK_DATA_LOW;
                        rx_ack_counter <= 16'h0000;
                    end else if (error_pulse == 1'b1) begin
                        $display("Time %t: ps2_interface_device: PS2_RX->PS2_IDLE (error=%b data=0x%h)",
                                 $time, error_pulse, data_reg);
                        ps2_state <= PS2_IDLE;
                    end else if (inhibit_counter >= MIN_INHIBIT_CYCLES) begin
                        $display("Time %t: ps2_interface_device: PS2_RX->PS2_INHIBIT (host inhibit during RX)", $time);
                        ps2_state <= PS2_INHIBIT;
                    end else begin
                        ps2_state <= PS2_RX;
                    end
                end
                PS2_RX_ACK: begin
                    // RX acknowledgment state machine runs below
                    if (rx_ack_state == RX_ACK_RELEASE) begin
                        $display("Time %t: ps2_interface_device: PS2_RX_ACK->PS2_IDLE (ACK sequence complete)", $time);
                        ps2_state <= PS2_IDLE;
                        rx_ack_state <= RX_ACK_IDLE;
                    end else if (inhibit_counter >= MIN_INHIBIT_CYCLES) begin
                        $display("Time %t: ps2_interface_device: PS2_RX_ACK->PS2_INHIBIT (host inhibit during ACK)", $time);
                        ps2_state <= PS2_INHIBIT;
                        rx_ack_state <= RX_ACK_IDLE;
                    end
                end
                PS2_TX: begin
                    if (inhibit_counter >= MIN_INHIBIT_CYCLES) begin
                        $display("Time %t: ps2_interface_device: PS2_TX->PS2_INHIBIT (host inhibit during TX)", $time);
                        ps2_state <= PS2_INHIBIT;
                    end else if (tx_state == TX_ST_RELEASE) begin
                        $display("Time %t: ps2_interface_device: PS2_TX->PS2_IDLE (TX complete)", $time);
                        ps2_state <= PS2_IDLE;
                    end else begin
                        ps2_state <= PS2_TX;
                    end
                end
            endcase

            if (ps2_state == PS2_RX || (ps2_state == PS2_TX && tx_state != TX_ST_IDLE)) begin
                if (dev_clk_toggle == 1'b0) begin
                    ps2_clk_out <= 1'b0;
                end else begin
                    ps2_clk_out <= 1'b1;
                end
            end
        end
    end

endmodule
