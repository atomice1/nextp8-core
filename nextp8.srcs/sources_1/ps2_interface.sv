`timescale 1ns/1ps

// ps2_interface.sv
// PS/2 protocol handler
// Provides debounced sampling, frame decode, and transmit sequencing.

module ps2_interface #(
    parameter FILTER_BITS       = 8,      // Debounce filter depth
    parameter TX_INHIBIT_CYCLES = 1100    // Clock-low duration before host transmission (~100us @ 11MHz)
) (
    // System signals
    input  logic CLK,               // System clock (11 MHz default)
    input  logic nRESET,            // Active-low asynchronous reset

    // PS/2 bus (bidirectional, open-drain)
    input  logic PS2_CLK_IN,        // PS/2 clock line (sampled)
    input  logic PS2_DATA_IN,       // PS/2 data line (sampled)
    output logic PS2_CLK_OUT,       // PS/2 clock drive (0 or 1)
    output logic PS2_DATA_OUT,      // PS/2 data drive (0 or 1)

    // Receiver outputs
    output logic [7:0] DATA,        // Received byte (valid for one cycle)
    output logic VALID,             // One-cycle pulse when DATA valid
    output logic ERROR,             // One-cycle pulse on framing/parity error

    // Transmitter inputs
    input  logic [7:0] TX_DATA,     // Byte to transmit
    input  logic TX_START,          // Pulse to initiate transmission
    input  logic [1:0] TX_MODE,     // Test modes (00=normal, 01=bad_parity, 10=bad_stop)

    // Transmitter outputs
    output logic TX_BUSY,           // High when transmission in progress
    output logic TX_DONE            // Not used (ties low)
);

    // State machine types
    typedef enum logic {PS2_IDLE, PS2_TX} ps2_state_t;
    typedef enum logic [4:0] {
        TX_ST_IDLE,
        TX_ST_INHIBIT,
        TX_ST_RTS,
        TX_ST_START,
        TX_ST_BIT0, TX_ST_BIT1, TX_ST_BIT2, TX_ST_BIT3,
        TX_ST_BIT4, TX_ST_BIT5, TX_ST_BIT6, TX_ST_BIT7,
        TX_ST_PARITY,
        TX_ST_STOP,
        TX_ST_ACK_WAIT_DATA,
        TX_ST_ACK_WAIT_CLK,
        TX_ST_ACK_WAIT_RELEASE,
        TX_ST_ACK_DONE
    } tx_state_t;

    localparam RTS_HOLD_CYCLES = 64; // Ensure DATA stays low while CLK is held low

    // Synchronizers (2-FF chains, identical latency for clock and data)
    logic [1:0] ps2c_sync;
    logic [1:0] ps2d_sync;

    // Debounce filters
    logic [FILTER_BITS-1:0] clk_filter;
    logic [FILTER_BITS-1:0] data_filter;

    // Filtered outputs and edge detection
    logic ps2c_filt;
    logic ps2d_filt;
    logic ps2c_filt_d;
    logic ps2d_filt_d;
    logic ps2c_fall_p;
    logic ps2c_rise_p;

    // Unfiltered edge detection (used for TX state sequencing)
    logic ps2c_sync_d;
    logic ps2c_sync_fall_p;
    logic ps2c_sync_rise_p;

    // RX datapath
    logic [3:0] bit_state;
    logic [7:0] shift;
    logic parity_acc;
    logic parity_ok;
    logic stop_bit_ok;
    logic [7:0] data_reg;
    logic valid_pulse;
    logic error_pulse;

    // TX datapath
    logic [7:0] tx_shift;
    logic tx_parity;
    logic [$clog2(TX_INHIBIT_CYCLES + RTS_HOLD_CYCLES):0] tx_counter;
    logic [7:0] tx_data_latched;
    logic tx_wait_high;

    // Bidirectional line control
    logic ps2_clk_drive;   // '0'=drive low, '1'=release
    logic ps2_data_drive;  // '0'=drive low, '1'=release

    // State machine signals
    ps2_state_t ps2_state;
    tx_state_t tx_state;

    // Temporary variables for logic operations
    logic clk_all_high, clk_all_low, data_all_high, data_all_low;
    logic sampled_bit;
    logic p;

    // Output drive values ('0'=pull low, '1'=release to pullup)
    assign PS2_CLK_OUT  = ps2_clk_drive;
    assign PS2_DATA_OUT = ps2_data_drive;

    // Output assignments
    assign DATA    = data_reg;
    assign VALID   = valid_pulse;
    assign ERROR   = error_pulse;
    assign TX_BUSY = (ps2_state == PS2_TX) ? 1'b1 : 1'b0;
    assign TX_DONE = 1'b0;

    function logic to_ps2_level(logic val);
        return (val == 1'b0) ? 1'b0 : 1'b1;
    endfunction

    //----------------------------------------------------------------
    // Two-stage synchronizers for PS/2 clock/data
    //----------------------------------------------------------------
    always_ff @(posedge CLK or negedge nRESET) begin
        if (~nRESET) begin
            ps2c_sync <= 2'b11;
            ps2d_sync <= 2'b11;
        end else begin
            ps2c_sync <= {ps2c_sync[0], to_ps2_level(PS2_CLK_IN)};
            ps2d_sync <= {ps2d_sync[0], to_ps2_level(PS2_DATA_IN)};
        end
    end

    //----------------------------------------------------------------
    // Debounce filters and edge detection
    //----------------------------------------------------------------
    always_ff @(posedge CLK or negedge nRESET) begin
        if (~nRESET) begin
            clk_filter   <= {FILTER_BITS{1'b1}};
            data_filter  <= {FILTER_BITS{1'b1}};
            ps2c_filt    <= 1'b1;
            ps2d_filt    <= 1'b1;
            ps2c_filt_d  <= 1'b1;
            ps2d_filt_d  <= 1'b1;
            ps2c_sync_d  <= 1'b1;
            ps2c_fall_p  <= 1'b0;
            ps2c_rise_p  <= 1'b0;
            ps2c_sync_fall_p <= 1'b0;
            ps2c_sync_rise_p <= 1'b0;
        end else begin
            clk_filter   <= {clk_filter[FILTER_BITS-2:0], ps2c_sync[1]};
            data_filter  <= {data_filter[FILTER_BITS-2:0], ps2d_sync[1]};

            clk_all_high  = 1'b1;
            clk_all_low   = 1'b1;
            data_all_high = 1'b1;
            data_all_low  = 1'b1;

            for (int i = 0; i < FILTER_BITS; i++) begin
                if (clk_filter[i] == 1'b0) clk_all_high = 1'b0;
                if (clk_filter[i] == 1'b1) clk_all_low = 1'b0;
                if (data_filter[i] == 1'b0) data_all_high = 1'b0;
                if (data_filter[i] == 1'b1) data_all_low = 1'b0;
            end

            if (clk_all_high)
                ps2c_filt <= 1'b1;
            else if (clk_all_low)
                ps2c_filt <= 1'b0;

            if (data_all_high)
                ps2d_filt <= 1'b1;
            else if (data_all_low)
                ps2d_filt <= 1'b0;

            ps2c_filt_d  <= ps2c_filt;
            ps2d_filt_d  <= ps2d_filt;
            ps2c_fall_p  <= ps2c_filt_d & ~ps2c_filt;
            ps2c_rise_p  <= ~ps2c_filt_d & ps2c_filt;

            ps2c_sync_d      <= ps2c_sync[1];
            ps2c_sync_fall_p <= ps2c_sync_d & ~ps2c_sync[1];
            ps2c_sync_rise_p <= ~ps2c_sync_d & ps2c_sync[1];
        end
    end

    //----------------------------------------------------------------
    // Unified HOST FSM (RX + TX)
    //----------------------------------------------------------------
    always_ff @(posedge CLK or negedge nRESET) begin
        if (~nRESET) begin
            ps2_state      <= PS2_IDLE;

            bit_state   <= 4'd0;
            shift       <= 8'b0;
            parity_ok   <= 1'b0;
            stop_bit_ok <= 1'b0;
            parity_acc  <= 1'b0;
            data_reg    <= 8'b0;
            valid_pulse <= 1'b0;
            error_pulse <= 1'b0;

            tx_state        <= TX_ST_IDLE;
            tx_shift        <= 8'b0;
            tx_parity       <= 1'b0;
            tx_counter      <= 0;
            tx_data_latched <= 8'b0;
            tx_wait_high    <= 1'b0;

            ps2_clk_drive  <= 1'b1;
            ps2_data_drive <= 1'b1;
        end else begin
            valid_pulse    <= 1'b0;
            error_pulse    <= 1'b0;

            ps2_clk_drive  <= 1'b1;
            ps2_data_drive <= 1'b1;

            if (TX_START) begin
                tx_data_latched <= TX_DATA;
            end

            //--------------------------------------------------
            // RX frame reception (always listens in IDLE)
            //--------------------------------------------------
            if (ps2_state == PS2_IDLE) begin
                if (ps2c_fall_p) begin
                    sampled_bit = ps2d_filt;

                    case (bit_state)
                        4'd0: begin
                            if (sampled_bit == 1'b0) begin
                                bit_state  <= 4'd1;
                                parity_acc <= 1'b0;
                                parity_ok  <= 1'b0;
                                shift      <= 8'b0;
                            end
                        end
                        4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7, 4'd8: begin
                            shift[bit_state-1] <= sampled_bit;
                            parity_acc <= parity_acc ^ sampled_bit;
                            bit_state   <= bit_state + 1;
                        end
                        4'd9: begin
                            p = parity_acc ^ sampled_bit;
                            parity_acc <= p;
                            parity_ok  <= p;
                            bit_state  <= 4'd10;
                        end
                        4'd10: begin
                            data_reg <= shift;
                            stop_bit_ok <= (sampled_bit == 1'b1);
                            // Wait for rising edge to generate pulse
                            bit_state <= 4'd11;
                        end
                    endcase
                end else if (ps2c_rise_p && bit_state == 4'd11) begin
                    // Wait for rising edge, then generate valid/error pulse
                    if (parity_ok == 1'b1 && stop_bit_ok == 1'b1) begin
                        valid_pulse <= 1'b1;
                    end else begin
                        error_pulse <= 1'b1;
                    end
                    bit_state <= 4'd0;
                end
            end else begin
                bit_state  <= 4'd0;
                parity_acc <= 1'b0;
                parity_ok  <= 1'b0;
            end

            //--------------------------------------------------
            // TX state machine
            //--------------------------------------------------
            case (tx_state)
                TX_ST_IDLE: begin
                    if (ps2_state == PS2_TX) begin
                        tx_shift <= tx_data_latched;
                        p = 1'b1;
                        for (int i = 0; i < 8; i++) begin
                            p = p ^ tx_data_latched[i];
                        end
                        tx_parity <= p;
                        tx_state <= TX_ST_INHIBIT;
                        tx_counter <= 0;
                    end
                end

                TX_ST_INHIBIT: begin
                    ps2_clk_drive <= 1'b0;
                    if (tx_counter >= TX_INHIBIT_CYCLES) begin
                        tx_state   <= TX_ST_RTS;
                        tx_counter <= 0;
                    end else begin
                        tx_counter <= tx_counter + 1;
                    end
                end

                TX_ST_RTS: begin
                    ps2_clk_drive  <= 1'b0;
                    ps2_data_drive <= 1'b0;
                    if (tx_counter >= RTS_HOLD_CYCLES) begin
                        tx_state   <= TX_ST_START;
                        tx_counter <= 0;
                    end else begin
                        tx_counter <= tx_counter + 1;
                    end
                end

                TX_ST_START: begin
                    ps2_data_drive <= 1'b0;
                    if (ps2c_sync_fall_p) begin
                        tx_state <= TX_ST_BIT0;
                        tx_wait_high <= 1'b1;
                    end
                end

                TX_ST_BIT0, TX_ST_BIT1, TX_ST_BIT2, TX_ST_BIT3,
                TX_ST_BIT4, TX_ST_BIT5, TX_ST_BIT6, TX_ST_BIT7: begin
                    if (tx_shift[0] == 1'b0) begin
                        ps2_data_drive <= 1'b0;
                    end
                    if (tx_wait_high) begin
                        if (ps2c_sync_rise_p) begin
                            tx_wait_high <= 1'b0;
                        end
                    end else if (ps2c_sync_fall_p) begin
                        tx_shift <= {1'b0, tx_shift[7:1]};
                        tx_wait_high <= 1'b1;
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
                        if (tx_parity == 1'b1) begin
                            ps2_data_drive <= 1'b0;
                        end
                    end else begin
                        if (tx_parity == 1'b0) begin
                            ps2_data_drive <= 1'b0;
                        end
                    end
                    if (tx_wait_high) begin
                        if (ps2c_sync_rise_p) begin
                            tx_wait_high <= 1'b0;
                        end
                    end else if (ps2c_sync_fall_p) begin
                        tx_state <= TX_ST_STOP;
                        tx_wait_high <= 1'b1;
                    end
                end

                TX_ST_STOP: begin
                    if (TX_MODE == 2'b10) begin
                        ps2_data_drive <= 1'b0;
                    end
                    if (tx_wait_high) begin
                        if (ps2c_sync_rise_p) begin
                            tx_wait_high <= 1'b0;
                            tx_state <= TX_ST_ACK_WAIT_DATA;
                        end
                    end else if (ps2c_sync_fall_p) begin
                        tx_state <= TX_ST_ACK_WAIT_DATA;
                        tx_wait_high <= 1'b1;
                    end
                end

                TX_ST_ACK_WAIT_DATA: begin
                    // Step 1: Wait for device to bring DATA low
                    if (ps2d_filt == 1'b0) begin
                        tx_state <= TX_ST_ACK_WAIT_CLK;
                    end
                end

                TX_ST_ACK_WAIT_CLK: begin
                    // Step 2: Wait for device to bring CLK low
                    if (ps2c_filt == 1'b0) begin
                        tx_state <= TX_ST_ACK_WAIT_RELEASE;
                    end
                end

                TX_ST_ACK_WAIT_RELEASE: begin
                    // Step 3: Wait for device to release both DATA and CLK
                    if (ps2d_filt == 1'b1 && ps2c_filt == 1'b1) begin
                        tx_state <= TX_ST_ACK_DONE;
                    end
                end

                TX_ST_ACK_DONE: begin
                    // Transmission complete
                    tx_state  <= TX_ST_IDLE;
                end
            endcase

            if (ps2_state != PS2_TX) begin
                tx_state <= TX_ST_IDLE;
                tx_wait_high <= 1'b0;
            end

            //--------------------------------------------------
            // Top-level state transitions
            //--------------------------------------------------
            case (ps2_state)
                PS2_IDLE: begin
                    if (TX_START) begin
                        ps2_state <= PS2_TX;
                    end else begin
                        ps2_state <= PS2_IDLE;
                    end
                end

                PS2_TX: begin
                    if (tx_state == TX_ST_ACK_DONE) begin
                        ps2_state <= PS2_IDLE;
                    end else begin
                        ps2_state <= PS2_TX;
                    end
                end
            endcase
        end
    end

endmodule
