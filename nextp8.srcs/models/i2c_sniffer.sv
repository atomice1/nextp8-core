// I2C Protocol Sniffer
// Passively monitors and logs I2C communication between master and slave
// Reports SCL/SDA transitions, frame contents, and protocol violations
// Monitor-only module - does not drive any signals

module i2c_sniffer #(
    parameter bit MASTER_IS_TRISTATE = 1'b0,
    parameter bit SLAVE_IS_TRISTATE = 1'b0,
    parameter bit VERBOSE = 1'b0,
    parameter integer I2C_MODE = 0  // 0=Standard(100kHz), 1=Fast(400kHz), 2=Fast-Plus(1MHz), 3=High-Speed(3.4MHz)
) (
    input  logic master_i2c_scl_in_i,
    input  logic master_i2c_sda_in_i,
    input  logic master_i2c_scl_out_i,
    input  logic master_i2c_sda_out_i,

    input  logic slave_i2c_scl_in_i,
    input  logic slave_i2c_sda_in_i,
    input  logic slave_i2c_scl_out_i,
    input  logic slave_i2c_sda_out_i
);

    // Signal state derivation logic
    // =============================
    // Bus signal = either party pulling low, or both released (high)
    // Who is driving low is determined by observing explicit drive and signal levels
    //
    // Master tristate:
    //   - in_i & out_i: same shared bus wire (tristate observation)
    //   - master_*_in_i shows bus state
    // Master non-tristate:
    //   - in_i: bus state (shared with slave)
    //   - out_i: master's explicit drive (0 = driving low, 1 = released)
    //
    // Slave: same conventions
    //
    
    // Bus state (what we observe on the wires)
    logic bus_scl, bus_sda;
    
    // Who is explicitly or implicitly driving low?
    // These are combinatorial based on config and current signal levels.
    logic master_driving_scl_low, master_driving_sda_low;
    logic slave_driving_scl_low, slave_driving_sda_low;
    
    // Derive bus state
    // Bus signal is low if master input is low OR slave input is low
    generate
        if (MASTER_IS_TRISTATE && SLAVE_IS_TRISTATE) begin
            // Both tristate: master_i2c_*_in_i and slave_i2c_*_in_i are both the shared bus
            assign bus_scl  = master_i2c_scl_in_i;   // Same as slave_i2c_scl_in_i
            assign bus_sda = master_i2c_sda_in_i;  // Same as slave_i2c_sda_in_i
        end else if (MASTER_IS_TRISTATE) begin
            // Master tristate, slave non-tristate
            assign bus_scl  = master_i2c_scl_in_i  | slave_i2c_scl_in_i;
            assign bus_sda = master_i2c_sda_in_i | slave_i2c_sda_in_i;
        end else if (SLAVE_IS_TRISTATE) begin
            // Master non-tristate, slave tristate
            assign bus_scl  = master_i2c_scl_in_i  | slave_i2c_scl_in_i;
            assign bus_sda = master_i2c_sda_in_i | slave_i2c_sda_in_i;
        end else begin
            // Both non-tristate (unusual but supported)
            assign bus_scl  = master_i2c_scl_in_i  | slave_i2c_scl_in_i;
            assign bus_sda = master_i2c_sda_in_i | slave_i2c_sda_in_i;
        end
    endgenerate
    
    // Derive who is driving signals low
    // ================================
    // master_driving_scl_low =
    //   (master NOT tristate AND master explicitly driving low) OR
    //   (bus_scl is low AND master IS tristate AND slave NOT tristate AND slave NOT explicitly driving low)
    //
    // slave_driving_scl_low =
    //   (slave NOT tristate AND slave explicitly driving low) OR
    //   (bus_scl is low AND slave IS tristate AND master NOT tristate AND master NOT explicitly driving low)
    
    generate
        if (!MASTER_IS_TRISTATE) begin
            // Master non-tristate: explicit drive signal
            assign master_driving_scl_low  = (master_i2c_scl_out_i == 1'b0);
            assign master_driving_sda_low = (master_i2c_sda_out_i == 1'b0);
        end else begin
            // Master tristate: infer from bus level and slave state
            // master_driving_scl_low = (master_scl is low AND slave NOT tristate AND slave not explicitly driving low)
            //                      OR (master_scl is low AND slave IS tristate)  -- ambiguous, but master could be driving
            assign master_driving_scl_low = bus_scl == 1'b0 && 
                ((SLAVE_IS_TRISTATE) ||
                 (!SLAVE_IS_TRISTATE && slave_i2c_scl_out_i != 1'b0));
            assign master_driving_sda_low = bus_sda == 1'b0 &&
                ((SLAVE_IS_TRISTATE) ||
                 (!SLAVE_IS_TRISTATE && slave_i2c_sda_out_i != 1'b0));
        end
        
        if (!SLAVE_IS_TRISTATE) begin
            // Slave non-tristate: explicit drive signal
            assign slave_driving_scl_low  = (slave_i2c_scl_out_i == 1'b0);
            assign slave_driving_sda_low = (slave_i2c_sda_out_i == 1'b0);
        end else begin
            // Slave tristate: infer from bus level and master state
            // slave_driving_scl_low = (slave_scl is low AND master NOT tristate AND master not explicitly driving low)
            //                        OR (slave_scl is low AND master IS tristate)  -- ambiguous, but slave could be driving
            assign slave_driving_scl_low = bus_scl == 1'b0 &&
                ((MASTER_IS_TRISTATE) ||
                 (!MASTER_IS_TRISTATE && master_i2c_scl_out_i != 1'b0));
            assign slave_driving_sda_low = bus_sda == 1'b0 &&
                ((MASTER_IS_TRISTATE) ||
                 (!MASTER_IS_TRISTATE && master_i2c_sda_out_i != 1'b0));
        end
    endgenerate
    
    // State tracking
    logic bus_scl_prev, bus_sda_prev;
    logic master_driving_scl_low_prev, master_driving_sda_low_prev;
    logic slave_driving_scl_low_prev, slave_driving_sda_low_prev;
    
    // I2C byte-level tracking
    logic [7:0] current_byte;       // Current byte being received (8 bits)
    logic [3:0] bit_count;          // Bit position (0-7 for data, 8 for ACK)
    logic [7:0] address_byte;       // Captured address byte
    logic       rw_bit;             // Read(1) or Write(0) from address byte
    logic       in_ack_bit;         // Currently in ACK bit phase
    logic       ack_received;       // ACK bit value (0=ACK, 1=NACK)
    logic [7:0] byte_count;         // Count of bytes in transaction
    
    typedef enum logic [2:0] {
        PHASE_IDLE = 3'b000,
        PHASE_ADDRESS = 3'b001,
        PHASE_ADDRESS_ACK = 3'b010,
        PHASE_DATA = 3'b011,
        PHASE_DATA_ACK = 3'b100
    } bus_phase_t;
    
    // Track which phase we're in (master controls this)
    bus_phase_t bus_phase = PHASE_IDLE;
    
    // Track who is transmitting the current byte (master or slave)
    logic master_is_transmitter;    // 1=master sends data, 0=slave sends data
    
    // Clock stretching tracking
    logic slave_stretching_clock;
    time  clock_stretch_start_time;
    
    // I2C timing parameters - mode dependent
    // Standard mode (100kHz), Fast mode (400kHz), Fast-Plus (1MHz), High-Speed (3.4MHz)
    time T_LOW_MIN;
    time T_HIGH_MIN;
    time T_SU_DAT_MIN;
    time T_HD_DAT_MIN;
    time T_SU_STA_MIN;
    time T_HD_STA_MIN;
    time T_SU_STO_MIN;
    string I2C_MODE_NAME;
    
    localparam time FRAME_TIMEOUT = 100_000_000;   // 100ms in ns
    localparam time CLOCK_STRETCH_TIMEOUT = 10_000_000;  // 10ms max stretch

    // Timing tracking
    time last_scl_rise_time;
    time last_scl_fall_time;
    time last_sda_change_time;
    time last_start_time;
    time last_activity_time;  // Last bus activity (any edge)
    time transaction_start_time;
    time master_scl_low_start_time;
    
    // Timeout and error tracking
    logic transaction_timeout_detected;
    logic incomplete_transaction;
    integer total_timeouts;
    integer total_incomplete;
    
    // Timing statistics
    time min_scl_low_period;
    time max_scl_low_period;
    time min_scl_high_period;
    time max_scl_high_period;
    integer timing_violations;
    
    // Transaction statistics
    integer total_transactions;
    integer total_bytes;
    integer total_acks;
    integer total_nacks;
    integer total_addr_nacks;
    integer total_data_nacks;
    integer total_repeated_starts;
    
    // Arbitration detection (multi-master support)
    logic arbitration_lost;
    logic master_lost_arbitration;

    // Initialize state tracking registers
    initial begin
        // Set timing parameters based on I2C mode
        case (I2C_MODE)
            0: begin  // Standard mode (100 kHz)
                T_LOW_MIN = 4700;      // 4.7 µs
                T_HIGH_MIN = 4000;     // 4.0 µs
                T_SU_DAT_MIN = 250;    // 250 ns
                T_HD_DAT_MIN = 0;      // 0 ns (max 3.45µs)
                T_SU_STA_MIN = 4700;   // 4.7 µs
                T_HD_STA_MIN = 4000;   // 4.0 µs
                T_SU_STO_MIN = 4000;   // 4.0 µs
                I2C_MODE_NAME = "Standard (100 kHz)";
            end
            1: begin  // Fast mode (400 kHz)
                T_LOW_MIN = 1300;      // 1.3 µs
                T_HIGH_MIN = 600;      // 600 ns
                T_SU_DAT_MIN = 100;    // 100 ns
                T_HD_DAT_MIN = 0;      // 0 ns (max 900ns)
                T_SU_STA_MIN = 600;    // 600 ns
                T_HD_STA_MIN = 600;    // 600 ns
                T_SU_STO_MIN = 600;    // 600 ns
                I2C_MODE_NAME = "Fast (400 kHz)";
            end
            2: begin  // Fast-mode Plus (1 MHz)
                T_LOW_MIN = 500;       // 500 ns
                T_HIGH_MIN = 260;      // 260 ns
                T_SU_DAT_MIN = 50;     // 50 ns
                T_HD_DAT_MIN = 0;      // 0 ns (max 450ns)
                T_SU_STA_MIN = 260;    // 260 ns
                T_HD_STA_MIN = 260;    // 260 ns
                T_SU_STO_MIN = 260;    // 260 ns
                I2C_MODE_NAME = "Fast-Plus (1 MHz)";
            end
            3: begin  // High-Speed mode (3.4 MHz)
                T_LOW_MIN = 160;       // 160 ns
                T_HIGH_MIN = 60;       // 60 ns
                T_SU_DAT_MIN = 10;     // 10 ns
                T_HD_DAT_MIN = 0;      // 0 ns (max 70ns)
                T_SU_STA_MIN = 160;    // 160 ns
                T_HD_STA_MIN = 160;    // 160 ns
                T_SU_STO_MIN = 160;    // 160 ns
                I2C_MODE_NAME = "High-Speed (3.4 MHz)";
            end
            default: begin  // Default to Standard mode
                T_LOW_MIN = 4700;
                T_HIGH_MIN = 4000;
                T_SU_DAT_MIN = 250;
                T_HD_DAT_MIN = 0;
                T_SU_STA_MIN = 4700;
                T_HD_STA_MIN = 4000;
                T_SU_STO_MIN = 4000;
                I2C_MODE_NAME = "Standard (100 kHz)";
            end
        endcase
        
        $display("I2C Sniffer: Mode = %s", I2C_MODE_NAME);
        
        bus_scl_prev = 1'b1;
        bus_sda_prev = 1'b1;
        master_driving_scl_low_prev = 1'b0;
        master_driving_sda_low_prev = 1'b0;
        slave_driving_scl_low_prev = 1'b0;
        slave_driving_sda_low_prev = 1'b0;
        current_byte = 8'h00;
        bit_count = 4'h0;
        address_byte = 8'h00;
        rw_bit = 1'b0;
        in_ack_bit = 1'b0;
        ack_received = 1'b0;
        byte_count = 8'h00;
        master_is_transmitter = 1'b1;
        slave_stretching_clock = 1'b0;
        clock_stretch_start_time = 0;
        last_scl_rise_time = 0;
        last_scl_fall_time = 0;
        last_sda_change_time = 0;
        last_start_time = 0;
        last_activity_time = 0;
        transaction_start_time = 0;
        master_scl_low_start_time = 0;
        transaction_timeout_detected = 1'b0;
        incomplete_transaction = 1'b0;
        total_timeouts = 0;
        total_incomplete = 0;
        min_scl_low_period = 999999999;
        max_scl_low_period = 0;
        min_scl_high_period = 999999999;
        max_scl_high_period = 0;
        timing_violations = 0;
        total_transactions = 0;
        total_bytes = 0;
        total_acks = 0;
        total_nacks = 0;
        total_addr_nacks = 0;
        total_data_nacks = 0;
        total_repeated_starts = 0;
        arbitration_lost = 1'b0;
        master_lost_arbitration = 1'b0;
    end

    // Monitor all relevant signals for changes
    always @(*) begin
        // Track any bus activity for timeout detection
        last_activity_time = $time;
        
        // Check for transaction timeout
        check_transaction_timeout();
        
        // SCL transitions
        if (bus_scl !== bus_scl_prev) begin
            // Bus SCL state changed
            if (bus_scl == 1'b1) begin
                // SCL rising edge: I2C samples data on rising edge
                last_scl_rise_time = $time;
                if (VERBOSE) $display("%t BUS SCL 0 -> 1 (SDA=%b)", $time, bus_sda);
                
                // Check SCL LOW period timing
                if (last_scl_fall_time > 0) begin
                    check_scl_low_period($time - last_scl_fall_time);
                end
                
                // Check data setup time (tSU:DAT)
                if (bus_phase != PHASE_IDLE && last_sda_change_time > 0) begin
                    check_data_setup_time($time - last_sda_change_time);
                end
                
                check_sda_validity_scl_high();
                
                // Check for arbitration loss (multi-master)
                check_arbitration();
                
                // Sample data bit or ACK bit on rising edge
                if (bus_phase != PHASE_IDLE) begin
                    sample_bit_on_scl_rising_edge();
                end
                
                // Check if slave released clock stretch
                if (slave_stretching_clock) begin
                    slave_stretching_clock = 1'b0;
                    if (VERBOSE) $display("%t SLAVE released clock stretch (duration=%0t)", 
                                         $time, $time - clock_stretch_start_time);
                end
            end else begin
                // SCL falling edge: data can change after this
                last_scl_fall_time = $time;
                
                // Check SCL HIGH period timing
                if (last_scl_rise_time > 0) begin
                    check_scl_high_period($time - last_scl_rise_time);
                end
                
                if (VERBOSE) $display("%t BUS SCL 1 -> 0 (SDA=%b)", $time, bus_sda);
            end
        end
        
        // Report who is driving SCL low (drive state transitions)
        if (master_driving_scl_low !== master_driving_scl_low_prev) begin
            if (master_driving_scl_low) begin
                if (VERBOSE) $display("%t MASTER starts driving SCL low (bus SCL=%b)", $time, bus_scl);
                check_master_drive_valid_scl();
                master_scl_low_start_time = $time;
            end else begin
                if (VERBOSE) $display("%t MASTER releases SCL (bus SCL=%b)", $time, bus_scl);
            end
        end
        
        if (slave_driving_scl_low !== slave_driving_scl_low_prev) begin
            if (slave_driving_scl_low) begin
                if (VERBOSE) $display("%t SLAVE starts driving SCL low (bus SCL=%b)", $time, bus_scl);
                check_slave_drive_valid_scl();
            end else begin
                if (VERBOSE) $display("%t SLAVE releases SCL (bus SCL=%b)", $time, bus_scl);
            end
        end
        
        // SDA transitions
        if (bus_sda !== bus_sda_prev) begin
            last_sda_change_time = $time;
            
            // Check data hold time (tH:DAT) - SDA should not change too soon after SCL falling
            if (bus_scl == 1'b0 && last_scl_fall_time > 0 && bus_phase != PHASE_IDLE) begin
                check_data_hold_time($time - last_scl_fall_time);
            end
            
            if (VERBOSE) $display("%t BUS SDA %b -> %b (SCL=%b)", $time, bus_sda_prev, bus_sda, bus_scl);
            check_sda_validity();
        end
        
        // Report who is driving SDA low (drive state transitions)
        if (master_driving_sda_low !== master_driving_sda_low_prev) begin
            if (master_driving_sda_low) begin
                if (VERBOSE) $display("%t MASTER starts driving SDA low (bus SDA=%b)", $time, bus_sda);
                check_master_drive_valid_sda();
            end else begin
                if (VERBOSE) $display("%t MASTER releases SDA (bus SDA=%b)", $time, bus_sda);
            end
        end
        
        if (slave_driving_sda_low !== slave_driving_sda_low_prev) begin
            if (slave_driving_sda_low) begin
                if (VERBOSE) $display("%t SLAVE starts driving SDA low (bus SDA=%b)", $time, bus_sda);
                check_slave_drive_valid_sda();
            end else begin
                if (VERBOSE) $display("%t SLAVE releases SDA (bus SDA=%b)", $time, bus_sda);
            end
        end
    end
    
    // Update previous state values on any input change
    always @(master_i2c_scl_in_i, master_i2c_sda_in_i, master_i2c_scl_out_i, master_i2c_sda_out_i,
             slave_i2c_scl_in_i, slave_i2c_sda_in_i, slave_i2c_scl_out_i, slave_i2c_sda_out_i) begin
        #0;  // Delay to allow combinatorial logic to settle
        bus_scl_prev <= bus_scl;
        bus_sda_prev <= bus_sda;
        master_driving_scl_low_prev <= master_driving_scl_low;
        master_driving_sda_low_prev <= master_driving_sda_low;
        slave_driving_scl_low_prev <= slave_driving_scl_low;
        slave_driving_sda_low_prev <= slave_driving_sda_low;
    end
    
    task check_sda_validity();
        // I2C rule: SDA changes only when SCL is LOW
        // Exception: START (SDA HIGH->LOW while SCL HIGH) and STOP (SDA LOW->HIGH while SCL HIGH)
        
        // Check for START condition
        if (bus_sda == 1'b0 && bus_sda_prev == 1'b1 && bus_scl == 1'b1) begin
            if (bus_phase == PHASE_IDLE) begin
                $display("%t I2C START CONDITION DETECTED (SDA: 1->0, SCL=1)", $time);
                last_start_time = $time;
                transaction_start_time = $time;
                transaction_timeout_detected = 1'b0;
                incomplete_transaction = 1'b0;
                total_transactions++;
            end else begin
                $display("%t I2C REPEATED START CONDITION DETECTED (SDA: 1->0, SCL=1)", $time);
                total_repeated_starts++;
                
                // Check tSU:STA - setup time before repeated START
                if (last_scl_fall_time > 0) begin
                    automatic time setup_time = $time - last_scl_fall_time;
                    if (setup_time < T_SU_STA_MIN) begin
                        $display("%t ERROR: START setup time violation (tSU:STA = %0t ns < %0t ns min)",
                                $time, setup_time, T_SU_STA_MIN);
                        timing_violations++;
                    end else if (VERBOSE) begin
                        $display("%t Timing OK: START setup time tSU:STA = %0t ns", $time, setup_time);
                    end
                end
                
                last_start_time = $time;
            end
            
            // Initialize for address byte reception
            bus_phase = PHASE_ADDRESS;
            current_byte = 8'h00;
            bit_count = 4'h0;
            in_ack_bit = 1'b0;
            byte_count = 8'h00;
            master_is_transmitter = 1'b1;  // Master sends address
            master_lost_arbitration = 1'b0;  // Reset arbitration flag for new transaction
        end
        
        // Check for STOP condition
        else if (bus_sda == 1'b1 && bus_sda_prev == 1'b0 && bus_scl == 1'b1) begin
            // Check tSU:STO - setup time before STOP
            if (last_scl_rise_time > 0) begin
                automatic time setup_time = $time - last_scl_rise_time;
                if (setup_time < T_SU_STO_MIN) begin
                    $display("%t ERROR: STOP setup time violation (tSU:STO = %0t ns < %0t ns min)",
                            $time, setup_time, T_SU_STO_MIN);
                    timing_violations++;
                end else if (VERBOSE) begin
                    $display("%t Timing OK: STOP setup time tSU:STO = %0t ns", $time, setup_time);
                end
            end
            
            $display("%t I2C STOP CONDITION DETECTED (SDA: 0->1, SCL=1) - Transaction complete with %0d bytes", 
                     $time, byte_count);
            
            // Check if this was an incomplete/error transaction
            if (arbitration_lost || transaction_timeout_detected) begin
                $display("%t   WARNING: Transaction ended with errors (arb_lost=%b, timeout=%b)",
                        $time, arbitration_lost, transaction_timeout_detected);
                incomplete_transaction = 1'b1;
                total_incomplete++;
            end
            
            // Print timing statistics summary for this transaction
            if (byte_count > 0) begin
                $display("%t   Transaction Timing: SCL_LOW [%0t - %0t] ns, SCL_HIGH [%0t - %0t] ns, Violations=%0d",
                        $time, min_scl_low_period, max_scl_low_period, 
                        min_scl_high_period, max_scl_high_period, timing_violations);
            end
            
            // Print overall statistics summary
            $display("%t   Overall Stats: Transactions=%0d, Bytes=%0d, ACKs=%0d, NACKs=%0d (Addr=%0d, Data=%0d), Rep.START=%0d",
                    $time, total_transactions, total_bytes, total_acks, total_nacks, 
                    total_addr_nacks, total_data_nacks, total_repeated_starts);
            
            // Reset to idle state
            bus_phase = PHASE_IDLE;
            current_byte = 8'h00;
            bit_count = 4'h0;
            in_ack_bit = 1'b0;
            byte_count = 8'h00;
            arbitration_lost = 1'b0;
            transaction_timeout_detected = 1'b0;
        end
        
        // Regular SDA transitions: only allowed when SCL is LOW
        else if (bus_scl == 1'b1) begin
            $display("%t ERROR: SDA changed (%b->%b) while SCL is HIGH (not START/STOP)", 
                     $time, bus_sda_prev, bus_sda);
            timing_violations++;
        end
    endtask
    
    task check_sda_validity_scl_high();
        // SDA should be stable while SCL is HIGH (except during START/STOP)
        // This is a sanity check
        if (VERBOSE) $display("%t SDA valid during SCL HIGH (SDA=%b)", $time, bus_sda);
    endtask
    
    task check_master_drive_valid_scl();
        // Error if master non-tristate is driving SCL low but slave doesn't see it low
        if (!MASTER_IS_TRISTATE && master_driving_scl_low && slave_i2c_scl_in_i != 1'b0) begin
            $display("%t ERROR: MASTER driving SCL low but SLAVE doesn't see it low", $time);
        end
    endtask
    
    task check_slave_drive_valid_scl();
        // Error if slave non-tristate is driving SCL low but master doesn't see it low
        if (!SLAVE_IS_TRISTATE && slave_driving_scl_low && master_i2c_scl_in_i != 1'b0) begin
            $display("%t ERROR: SLAVE driving SCL low but MASTER doesn't see it low", $time);
        end
        
        // Clock stretching detection: slave holds SCL low after master tries to release it
        // This is allowed in I2C when master releases SCL but slave keeps it low
        if (slave_driving_scl_low && !slave_stretching_clock) begin
            if (master_driving_scl_low) begin
                // Master also driving low - normal operation
                if (VERBOSE) $display("%t SLAVE driving SCL low (master also driving)", $time);
            end else begin
                // Master released SCL but slave holds it - clock stretching
                $display("%t I2C CLOCK STRETCHING: Slave holding SCL low", $time);
                slave_stretching_clock = 1'b1;
                clock_stretch_start_time = $time;
            end
        end
    endtask
    
    task check_master_drive_valid_sda();
        // Error if master non-tristate is driving SDA low but slave doesn't see it low
        if (!MASTER_IS_TRISTATE && master_driving_sda_low && slave_i2c_sda_in_i != 1'b0) begin
            $display("%t ERROR: MASTER driving SDA low but SLAVE doesn't see it low", $time);
        end
    endtask
    
    task check_slave_drive_valid_sda();
        // Error if slave non-tristate is driving SDA low but master doesn't see it low
        if (!SLAVE_IS_TRISTATE && slave_driving_sda_low && master_i2c_sda_in_i != 1'b0) begin
            $display("%t ERROR: SLAVE driving SDA low but MASTER doesn't see it low", $time);
        end
    endtask

    task check_scl_low_period(input time period);
        // Check tLOW - SCL low period
        if (period < min_scl_low_period) min_scl_low_period = period;
        if (period > max_scl_low_period) max_scl_low_period = period;
        
        if (period < T_LOW_MIN && !slave_stretching_clock) begin
            $display("%t ERROR: SCL LOW period violation (tLOW = %0t ns < %0t ns min)",
                    $time, period, T_LOW_MIN);
            timing_violations++;
        end else if (VERBOSE) begin
            $display("%t Timing OK: SCL LOW period tLOW = %0t ns", $time, period);
        end
    endtask

    task check_scl_high_period(input time period);
        // Check tHIGH - SCL high period
        if (period < min_scl_high_period) min_scl_high_period = period;
        if (period > max_scl_high_period) max_scl_high_period = period;
        
        if (period < T_HIGH_MIN) begin
            $display("%t ERROR: SCL HIGH period violation (tHIGH = %0t ns < %0t ns min)",
                    $time, period, T_HIGH_MIN);
            timing_violations++;
        end else if (VERBOSE) begin
            $display("%t Timing OK: SCL HIGH period tHIGH = %0t ns", $time, period);
        end
    endtask

    task check_data_setup_time(input time setup_time);
        // Check tSU:DAT - data setup time before SCL rising edge
        if (setup_time < T_SU_DAT_MIN) begin
            $display("%t ERROR: Data setup time violation (tSU:DAT = %0t ns < %0t ns min)",
                    $time, setup_time, T_SU_DAT_MIN);
            timing_violations++;
        end else if (VERBOSE) begin
            $display("%t Timing OK: Data setup time tSU:DAT = %0t ns", $time, setup_time);
        end
    endtask

    task check_data_hold_time(input time hold_time);
        // Check tH:DAT - data hold time after SCL falling edge
        // Note: Maximum hold time is 3.45µs, but we only check minimum (0ns)
        if (hold_time < T_HD_DAT_MIN) begin
            $display("%t ERROR: Data hold time violation (tH:DAT = %0t ns < %0t ns min)",
                    $time, hold_time, T_HD_DAT_MIN);
            timing_violations++;
        end else if (VERBOSE) begin
            $display("%t Timing OK: Data hold time tH:DAT = %0t ns", $time, hold_time);
        end
    endtask

    task check_arbitration();
        // Multi-master arbitration: If master tries to drive SDA high but bus is low,
        // another master is driving it low and this master loses arbitration
        if (bus_phase != PHASE_IDLE && bus_phase != PHASE_ADDRESS_ACK && bus_phase != PHASE_DATA_ACK) begin
            // Only check during data transmission, not during ACK (slave drives)
            if (master_is_transmitter && !master_driving_sda_low && bus_sda == 1'b0) begin
                if (!master_lost_arbitration) begin
                    $display("%t ARBITRATION LOST: Master tried to drive SDA=1 but bus is LOW", $time);
                    $display("%t   (Another master is transmitting a dominant bit)", $time);
                    master_lost_arbitration = 1'b1;
                    arbitration_lost = 1'b1;
                end
            end
        end
    endtask

    task check_ack_drive_conflict();
        // Check for drive conflicts during ACK bit phase
        // Transmitter must release SDA (drive high or tristate)
        // Receiver must pull SDA low for ACK or leave high for NACK
        //
        // NOTE: When both master and slave are tristate, we cannot reliably
        // determine who is driving SDA low. The inference logic will show
        // BOTH master_driving_sda_low and slave_driving_sda_low as true
        // whenever SDA is low. Skip checks in this ambiguous case.
        
        if (MASTER_IS_TRISTATE && SLAVE_IS_TRISTATE) begin
            // Both tristate: cannot determine who is driving, skip conflict checks
            // Just report ACK/NACK based on bus state
            return;
        end
        
        if (master_is_transmitter) begin
            // Master transmitting, slave should ACK
            // Check if master is properly releasing SDA
            if (master_driving_sda_low) begin
                $display("%t ERROR: Master still driving SDA low during ACK bit (should release)", $time);
            end
            
            // Check if slave is driving the ACK
            if (bus_sda == 1'b0 && !slave_driving_sda_low) begin
                $display("%t WARNING: SDA is low (ACK) but slave doesn't appear to be driving it", $time);
            end
        end else begin
            // Slave transmitting, master should ACK
            // Check if slave is properly releasing SDA
            if (slave_driving_sda_low) begin
                $display("%t ERROR: Slave still driving SDA low during ACK bit (should release)", $time);
            end
            
            // Check if master is driving the ACK
            if (bus_sda == 1'b0 && !master_driving_sda_low) begin
                $display("%t WARNING: SDA is low (ACK) but master doesn't appear to be driving it", $time);
            end
        end
    endtask

    task print_frame_progress();
        string frame_str;
        string direction_str;
        
        if (VERBOSE) begin
            // Determine direction based on phase and transmitter
            if (bus_phase == PHASE_ADDRESS || bus_phase == PHASE_ADDRESS_ACK) begin
                direction_str = "ADDR";
            end else if (master_is_transmitter) begin
                direction_str = "M->S";
            end else begin
                direction_str = "S->M";
            end
            
            // Build up the frame string bit by bit (MSB first, as transmitted)
            frame_str = "";
            for (int i = 7; i >= 0 && i >= (8 - bit_count); i--) begin
                if (i < 7) frame_str = {frame_str, " "};
                frame_str = {frame_str, (current_byte[i] ? "1" : "0")};
            end
            
            $display("%t I2C %s | %s (0x%02h incomplete)", 
                     $time, direction_str, frame_str, current_byte);
        end
    endtask

    task check_special_address(input logic [7:0] addr);
        // Check for special I2C addresses
        case (addr[7:1])
            7'h00: begin
                if (addr[0] == 1'b0) begin
                    $display("%t SPECIAL ADDRESS: General Call (0x00)", $time);
                end else begin
                    $display("%t SPECIAL ADDRESS: START byte (0x01)", $time);
                end
            end
            7'h01: $display("%t SPECIAL ADDRESS: CBUS address (0x02/0x03)", $time);
            7'h02: $display("%t SPECIAL ADDRESS: Different bus format (0x04/0x05)", $time);
            7'h03: $display("%t SPECIAL ADDRESS: Future use (0x06/0x07)", $time);
            7'h04: $display("%t SPECIAL ADDRESS: Hs-mode master code (0x08)", $time);
            7'h05: $display("%t SPECIAL ADDRESS: Hs-mode master code (0x0A)", $time);
            7'h06: $display("%t SPECIAL ADDRESS: Hs-mode master code (0x0C)", $time);
            7'h07: $display("%t SPECIAL ADDRESS: Hs-mode master code (0x0E)", $time);
            7'h78: begin
                $display("%t SPECIAL ADDRESS: 10-bit addressing (0x%02h)", $time, addr);
                if (addr[0] == 1'b0) begin
                    $display("%t   10-bit write address (first byte)", $time);
                end else begin
                    $display("%t   10-bit read address (first byte)", $time);
                end
            end
            7'h79: $display("%t SPECIAL ADDRESS: 10-bit addressing (0x%02h)", $time, addr);
            7'h7A: $display("%t SPECIAL ADDRESS: 10-bit addressing (0x%02h)", $time, addr);
            7'h7B: $display("%t SPECIAL ADDRESS: 10-bit addressing (0x%02h)", $time, addr);
            7'h7C: $display("%t RESERVED ADDRESS: Device ID (0x%02h)", $time, addr);
            7'h7D: $display("%t RESERVED ADDRESS: Reserved (0x%02h)", $time, addr);
            7'h7E: $display("%t RESERVED ADDRESS: Reserved (0x%02h)", $time, addr);
            7'h7F: $display("%t RESERVED ADDRESS: Reserved (0x%02h)", $time, addr);
            default: begin
                // Normal 7-bit address
                if (VERBOSE) $display("%t Standard 7-bit address: 0x%02h", $time, addr[7:1]);
            end
        endcase
    endtask

    task check_transaction_timeout();
        automatic time elapsed;
        
        // Only check timeout if transaction is active
        if (bus_phase != PHASE_IDLE && transaction_start_time > 0) begin
            elapsed = $time - last_activity_time;
            
            // If no activity for FRAME_TIMEOUT, flag as timeout
            if (elapsed > FRAME_TIMEOUT && !transaction_timeout_detected) begin
                $display("%t ERROR: Transaction TIMEOUT - No activity for %0t ns", $time, elapsed);
                $display("%t   Transaction started at %0t, current phase=%0d", 
                        $time, transaction_start_time, bus_phase);
                transaction_timeout_detected = 1'b1;
                total_timeouts++;
                incomplete_transaction = 1'b1;
                total_incomplete++;
            end
        end
        
        // Check for excessive clock stretching
        if (slave_stretching_clock) begin
            elapsed = $time - clock_stretch_start_time;
            if (elapsed > CLOCK_STRETCH_TIMEOUT) begin
                $display("%t ERROR: Clock stretch TIMEOUT - Slave holding SCL for %0t ns", 
                        $time, elapsed);
            end
        end
    endtask

    // Public task to print overall statistics summary
    task print_statistics();
        $display("================================================================================");
        $display("I2C Sniffer Statistics Summary - Mode: %s", I2C_MODE_NAME);
        $display("================================================================================");
        $display("Transaction Statistics:");
        $display("  Total Transactions:     %0d", total_transactions);
        $display("  Total Repeated STARTs:  %0d", total_repeated_starts);
        $display("  Total Bytes:            %0d", total_bytes);
        $display("  Total ACKs:             %0d", total_acks);
        $display("  Total NACKs:            %0d (Address: %0d, Data: %0d)", 
                total_nacks, total_addr_nacks, total_data_nacks);
        $display("");
        $display("Error Statistics:");
        $display("  Timing Violations:      %0d", timing_violations);
        $display("  Timeouts:               %0d", total_timeouts);
        $display("  Incomplete Transactions:%0d", total_incomplete);
        $display("  Arbitration Events:     %0d", arbitration_lost ? 1 : 0);
        $display("");
        $display("Timing Statistics:");
        $display("  SCL LOW period:         %0t - %0t ns (min: %0t ns)", 
                min_scl_low_period, max_scl_low_period, T_LOW_MIN);
        $display("  SCL HIGH period:        %0t - %0t ns (min: %0t ns)", 
                min_scl_high_period, max_scl_high_period, T_HIGH_MIN);
        $display("================================================================================");
    endtask

    task sample_bit_on_scl_rising_edge();
        // I2C samples data on SCL rising edge
        if (in_ack_bit) begin
            // 9th bit: ACK bit (receiver drives SDA low for ACK)
            ack_received = bus_sda;
            
            // Check for drive conflicts during ACK
            check_ack_drive_conflict();
            
            if (bus_sda == 1'b0) begin
                // Print ACK with appropriate context
                if (bus_phase == PHASE_ADDRESS_ACK) begin
                    $display("%t I2C ACK for address 0x%02h (addr=0x%02h, R/W=%b)", 
                            $time, current_byte, current_byte[7:1], current_byte[0]);
                end else begin
                    $display("%t I2C ACK received for byte 0x%02h", $time, current_byte);
                end
                total_acks++;
            end else begin
                // Print NACK with appropriate context
                if (bus_phase == PHASE_ADDRESS_ACK) begin
                    $display("%t I2C NACK for address 0x%02h (addr=0x%02h, R/W=%b)", 
                            $time, current_byte, current_byte[7:1], current_byte[0]);
                end else begin
                    $display("%t I2C NACK received for byte 0x%02h", $time, current_byte);
                end
                total_nacks++;
                
                // Track address vs data NACKs separately
                if (bus_phase == PHASE_ADDRESS_ACK) begin
                    total_addr_nacks++;
                    $display("%t   Address not acknowledged - slave may not be present", $time);
                end else begin
                    total_data_nacks++;
                end
            end
            
            // Transition to next state after ACK
            in_ack_bit = 1'b0;
            bit_count = 4'h0;
            current_byte = 8'h00;
            
            case (bus_phase)
                PHASE_ADDRESS_ACK: begin
                    // After address ACK, move to data phase
                    if (rw_bit == 1'b0) begin
                        // Write: master continues transmitting
                        bus_phase = PHASE_DATA;
                        master_is_transmitter = 1'b1;
                        if (VERBOSE) $display("%t Entering WRITE data phase (master->slave)", $time);
                    end else begin
                        // Read: slave will transmit
                        bus_phase = PHASE_DATA;
                        master_is_transmitter = 1'b0;
                        if (VERBOSE) $display("%t Entering READ data phase (slave->master)", $time);
                    end
                end
                PHASE_DATA_ACK: begin
                    // Stay in data phase for next byte
                    bus_phase = PHASE_DATA;
                    if (VERBOSE) $display("%t Ready for next data byte", $time);
                end
                default: begin
                    $display("%t ERROR: Unexpected ACK in phase %0d", $time, bus_phase);
                end
            endcase
            
        end else if (bit_count < 8) begin
            // Data bits 0-7: sample into current_byte (MSB first)
            current_byte = {current_byte[6:0], bus_sda};
            bit_count = bit_count + 1;
            
            // Show frame buildup progress
            print_frame_progress();
            
            // After 8th bit, prepare for ACK
            if (bit_count == 8) begin
                byte_count = byte_count + 1;
                total_bytes++;
                
                // Handle complete byte based on phase
                case (bus_phase)
                    PHASE_ADDRESS: begin
                        address_byte = current_byte;
                        rw_bit = current_byte[0];
                        $display("%t I2C ADDRESS BYTE: 0x%02h (addr=0x%02h, R/W=%b)", 
                                $time, current_byte, current_byte[7:1], current_byte[0]);
                        
                        // Check for special addresses
                        check_special_address(current_byte);
                        
                        bus_phase = PHASE_ADDRESS_ACK;
                        in_ack_bit = 1'b1;
                    end
                    PHASE_DATA: begin
                        if (master_is_transmitter) begin
                            $display("%t I2C DATA BYTE (master->slave): 0x%02h", $time, current_byte);
                        end else begin
                            $display("%t I2C DATA BYTE (slave->master): 0x%02h", $time, current_byte);
                        end
                        bus_phase = PHASE_DATA_ACK;
                        in_ack_bit = 1'b1;
                    end
                    default: begin
                        $display("%t ERROR: Byte complete in unexpected phase %0d", $time, bus_phase);
                    end
                endcase
            end
        end
    endtask

endmodule
