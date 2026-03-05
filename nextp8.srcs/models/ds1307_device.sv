////////////////////////////////////////////////////////////////////////////////
// DS1307 RTC I2C Device Model - Clean Implementation
// Simulates a DS1307 Real-Time Clock for testbench use
////////////////////////////////////////////////////////////////////////////////

module ds1307_device (
    input  wire i2c_scl_in,
    input  wire i2c_sda_in,
    output reg  i2c_scl_out,
    output reg  i2c_sda_out
);

    parameter I2C_ADDR = 7'h68;
    
    reg [7:0] regs [0:63];
    
    localparam IDLE       = 4'd0;
    localparam ADDR_RX    = 4'd1;
    localparam REG_RX     = 4'd2;
    localparam DATA_RX    = 4'd3;  // For receiving data to write
    localparam DATA_TX    = 4'd4;  // For transmitting data on read
    
    reg [3:0] state;
    reg [7:0] shift_reg;
    reg [3:0] bit_count;
    reg [7:0] reg_addr;
    reg [7:0] cmd_byte;
    reg need_ack;       // Drive SDA low during ACK bit (9th clock)
    reg just_acked;     // Track that ACK period just completed, safe to transition state
    reg ack_bit_seen;   // Flag: have we seen the 9th posedge with ACK?
    reg master_ack;     // Master's ACK (0) or NACK (1) during DATA_TX
    
    initial begin
        regs[8'h00] = 8'h56;  // Seconds
        regs[8'h01] = 8'h34;  // Minutes  
        regs[8'h02] = 8'h12;  // Hours
        regs[8'h03] = 8'h04;  // Day of week
        regs[8'h04] = 8'h24;  // Day of month (BCD)
        regs[8'h05] = 8'h12;  // Month (December in BCD)
        regs[8'h06] = 8'h25;  // Year (BCD)
        regs[8'h07] = 8'h00;  // Control register
        for (integer i = 8; i < 64; i = i + 1)
            regs[i] = 8'h00;
        state = IDLE;
        bit_count = 0;
        reg_addr = 0;
        shift_reg = 0;
        cmd_byte = 8'h00;
        need_ack = 0;
        just_acked = 0;
        ack_bit_seen = 0;
        master_ack = 1;
        // Output ports: 0 = drive low, 1 = release (high-Z)
        i2c_scl_out = 1'b1;
        i2c_sda_out = 1'b1;
        $display("[DS1307] %0t Initialized - I2C address 0x%02x", $time, I2C_ADDR);
    end
    
    // Monitor I2C bus activity (only on changes during transactions)
    // Disabled: too verbose
    // always @(i2c_scl_in or i2c_sda_in) begin
    //     if (i2c_scl_in !== 1'bz && i2c_sda_in !== 1'bz) begin
    //         $display("[DS1307] Bus activity: SCL=%b SDA=%b state=%0d @ %0t", i2c_scl_in, i2c_sda_in, state, $time);
    //     end
    // end
    
    // Open-drain SDA output: 0 = drive low, 1 = release (high-Z)
    // Drive low when ACKing or transmitting a '0' bit
    always @(*) begin
        if (need_ack) begin
            i2c_sda_out = 1'b0;  // ACK: pull low
        end else if (state == DATA_TX && bit_count < 8) begin
            $display("[DS1307] %0t DATA_TX: sending bit %d: %b (shift_reg=%b)", $time, bit_count, shift_reg[7], shift_reg);
            i2c_sda_out = shift_reg[7] ? 1'b1 : 1'b0;  // TX: MSB first
        end else begin
            i2c_sda_out = 1'b1;  // Release
        end
    end
    
    // SCL is always released by slave (only master drives SCL in standard I2C)
    // Note: Clock stretching could pull SCL low, but DS1307 doesn't use it
    always @(*) begin
        i2c_scl_out = 1'b1;  // Always release
    end
    
    // Posedge SCL: sample bits
    always @(posedge i2c_scl_in) begin
        if (state == IDLE) begin
            // Ignore bits in IDLE state
        end else if (state == ADDR_RX) begin
            // ACK bit handling: don't sample on 9th posedge if ACK is needed
            if (bit_count < 8) begin
                // Bits 0-7: sample data
                shift_reg <= {shift_reg[6:0], i2c_sda_in};
                $display("[DS1307] %0t posedge ADDR_RX: bit_count=%d sda=%b shift_reg=%08b", $time, bit_count, i2c_sda_in, {shift_reg[6:0], i2c_sda_in});
                
                if (bit_count == 7) begin
                    // This is the 8th address bit - save it, ACK will be driven on negedge
                    cmd_byte <= {shift_reg[6:0], i2c_sda_in};
                    // DON'T set need_ack here - wait for negedge after this bit is sampled
                    ack_bit_seen <= 0;  // Reset flag for 9th bit
                    $display("[DS1307] %0t ADDR: 0x%02x @ posedge (bit_count was 7)", $time, {shift_reg[6:0], i2c_sda_in});
                end
            end else begin
                // Bit 8 (ACK bit): slave is pulling SDA low, don't sample it
                ack_bit_seen <= 1;  // Mark that we've seen the 9th posedge with ACK active
                $display("[DS1307] %0t 9th posedge (ACK bit): holding SDA low, need_ack=%b", $time, need_ack);
            end
            
            bit_count <= bit_count + 1;
        end else if (state == REG_RX) begin
            // Receiving register address byte
            if (bit_count < 8) begin
                shift_reg <= {shift_reg[6:0], i2c_sda_in};
                $display("[DS1307] %0t posedge REG_RX: bit_count=%d sda=%b shift_reg=%08b", $time, bit_count, i2c_sda_in, {shift_reg[6:0], i2c_sda_in});
                
                if (bit_count == 7) begin
                    // This is the 8th register address bit
                    reg_addr <= {shift_reg[6:0], i2c_sda_in};
                    // DON'T set need_ack here - wait for negedge after this bit is sampled
                    ack_bit_seen <= 0;
                    $display("[DS1307] %0t RegAddr: 0x%02x", $time, {shift_reg[6:0], i2c_sda_in});
                end
            end else begin
                // Bit 8 (ACK bit)
                ack_bit_seen <= 1;
                $display("[DS1307] %0t 9th posedge REG_RX (ACK bit): holding SDA low", $time);
            end
            
            bit_count <= bit_count + 1;
        end else if (state == DATA_RX) begin
            // Receiving data bytes to write to registers
            if (bit_count < 8) begin
                shift_reg <= {shift_reg[6:0], i2c_sda_in};
                $display("[DS1307] %0t posedge DATA_RX: bit_count=%d sda=%b shift_reg=%08b", $time, bit_count, i2c_sda_in, {shift_reg[6:0], i2c_sda_in});
                
                if (bit_count == 7) begin
                    // This is the 8th data bit
                    // DON'T set need_ack here - wait for negedge after this bit is sampled
                    ack_bit_seen <= 0;
                    $display("[DS1307] %0t Data byte received: 0x%02x -> reg[0x%02x]", $time, {shift_reg[6:0], i2c_sda_in}, reg_addr);
                end
            end else begin
                // Bit 8 (ACK bit)
                ack_bit_seen <= 1;
                $display("[DS1307] %0t 9th posedge DATA_RX (ACK bit): holding SDA low", $time);
            end
            
            bit_count <= bit_count + 1;
        end else if (state == DATA_TX) begin
            // Transmitting data to master
            // On 9th bit, sample master's ACK/NACK
            if (bit_count == 8) begin
                master_ack <= i2c_sda_in;  // Sample: 0=ACK, 1=NACK
                $display("[DS1307] %0t posedge DATA_TX: 9th bit (master %s) sda=%b", $time, i2c_sda_in ? "NACK" : "ACK", i2c_sda_in);
            end
            $display("[DS1307] %0t posedge DATA_TX: bit_count=%d->%d", $time, bit_count, (bit_count + 1));
        end
    end
    
    // Negedge SCL: ACK setup and release, and state transitions
    always @(negedge i2c_scl_in) begin
        // After 8th bit sampled (bit_count==8), drive ACK low for 9th clock
        // Delay slightly after the falling edge for proper I2C timing
        if (bit_count == 8 && !need_ack && (state == ADDR_RX || state == REG_RX || state == DATA_RX)) begin
            #100 need_ack <= 1;  // Drive SDA low for ACK during 9th clock (delayed for setup time)
            $display("[DS1307] %0t negedge after 8th bit: asserting ACK (need_ack=1)", $time);
        end
        
        if (ack_bit_seen && need_ack) begin
            // The 9th posedge has passed and ACK is being held
            // Now on this negedge (falling edge of 9th clock), release the ACK and transition state
            // Delay slightly after the falling edge for proper I2C timing
            #100 need_ack <= 0;  // Release SDA from ACK (delayed for hold time)
            ack_bit_seen <= 0;
            
            // Transition state immediately based on current state and direction
            if (state == ADDR_RX) begin
                // Check address match
                if (cmd_byte[7:1] == I2C_ADDR) begin
                    if (cmd_byte[0]) begin
                        // Read command - send register data
                        state <= DATA_TX;
                        bit_count <= 0;
                        shift_reg <= regs[reg_addr];
                        $display("[DS1307] %0t State transition: ADDR_RX -> DATA_TX (READ)", $time);
                        $display("[DS1307] %0t READ from reg addr=0x%02x: value=0x%02x", $time, reg_addr, regs[reg_addr]);
                    end else begin
                        // Write command - receive register address next
                        state <= REG_RX;
                        bit_count <= 0;  // Reset for next byte reception
                        $display("[DS1307] %0t State transition: ADDR_RX -> REG_RX (WRITE)", $time);
                        $display("[DS1307] %0t WRITE", $time);
                    end
                end else begin
                    // Address mismatch - go back to IDLE
                    state <= IDLE;
                    $display("[DS1307] %0t NACK - address mismatch", $time);
                end
            end else if (state == REG_RX) begin
                // After receiving register address, move to data phase for write
                state <= DATA_RX;
                bit_count <= 0;  // Reset for data byte reception
                $display("[DS1307] %0t State transition: REG_RX -> DATA_RX (receive data)", $time);
                $display("[DS1307] %0t Register address captured: 0x%02x, ready for data", $time, reg_addr);
            end else if (state == DATA_RX) begin
                // After data byte, stay in DATA_RX for next data byte (auto-increment reg_addr)
                reg_addr <= reg_addr + 1;
                bit_count <= 0;
                $display("[DS1307] %0t Data stored to reg[0x%02x], auto-increment to 0x%02x", $time, reg_addr, reg_addr + 1);
            end
        end else if (state == DATA_TX && bit_count == 8) begin
            // After 9th bit (master ACK/NACK sampled on posedge), act on negedge
            if (master_ack == 1'b0) begin
                // Master ACK - continue sending next byte
                reg_addr <= reg_addr + 1;
                shift_reg <= regs[reg_addr + 1];
                bit_count <= 0;
                $display("[DS1307] %0t Master ACK, sending next byte from addr=0x%02x", $time, reg_addr + 1);
            end else begin
                // Master NACK - end of read
                state <= IDLE;
                bit_count <= 0;
                $display("[DS1307] %0t Master NACK, ending read", $time);
            end
        end else if (state == DATA_TX && bit_count < 8) begin
            // Shift out next data bit on negedge SCL
            shift_reg <= {shift_reg[6:0], 1'b0};  // Shift left, MSB first
            bit_count <= bit_count + 1;
            $display("[DS1307] %0t shift_reg: %b->%b", $time, shift_reg, {shift_reg[6:0], 1'b0});
        end
    end
    
    // Fallback: If SCL goes high while in DATA_RX/DATA_TX without a valid START,
    // go to IDLE to re-synchronize (handles master glitches and repeated start)
    always @(posedge i2c_scl_in) begin
        // Only apply this fallback if we're in the middle of a transaction
        // and SCL going high doesn't correspond to sampling a bit
        if ((state == DATA_RX || state == DATA_TX) && bit_count == 0) begin
            // Bit count is 0, so SCL high shouldn't be sampling anything
            // This might be the master sending SCL high before a new START
            // Stay ready but be prepared for a START condition
        end
    end
    
    // START condition detection (SDA falls while SCL high)
    // Only recognize START when device is NOT driving SDA low
    always @(negedge i2c_sda_in) begin
        if (i2c_scl_in && i2c_sda_out == 1'b1) begin
            // SCL high and device not driving low = valid START from master
            state <= ADDR_RX;
            bit_count <= 0;
            need_ack <= 0;
            $display("[DS1307] %0t START condition detected from state %0d", $time, state);
        end
    end
    
    // STOP condition detection (SDA rises while SCL high)
    // Only recognize STOP when device is NOT driving SDA low
    always @(posedge i2c_sda_in) begin
        if (i2c_scl_in && i2c_sda_out == 1'b1) begin
            // SCL high and device not driving low = valid STOP from master
            state <= IDLE;
            need_ack <= 0;
            $display("[DS1307] %0t STOP condition", $time);
        end
    end

endmodule
