////////////////////////////////////////////////////////////////////////////////
// *Unofficial* IS61WV204816BLL High-Speed Asynchronous CMOS SRAM Simulation Model
// Internally-clocked implementation for deterministic timing
//
// 2Mx16 SRAM with configurable speed grades
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module sram #(
    parameter ADDR_WIDTH = 21,      // 2M x 16 = 21 address bits
    parameter DATA_WIDTH = 16,      // 16-bit data bus
    parameter SPEED_GRADE = 10,     // 10ns (default), 12ns available
    parameter VERBOSE = 0,          // Debug output enable
    parameter MEM_FILE = ""         // Memory initialization file (.mem format)
) (
    // Address bus
    input  wire [ADDR_WIDTH-1:0] addr,

    // Bidirectional data bus
    inout  wire [DATA_WIDTH-1:0] dq,

    // Control signals (active low)
    input  wire cs_n,   // Chip select
    input  wire we_n,   // Write enable
    input  wire oe_n,   // Output enable
    input  wire lb_n,   // Lower byte enable
    input  wire ub_n    // Upper byte enable
);

    //==========================================================================
    // TIMING PARAMETERS (from IS61/64WV204816 datasheet)
    //==========================================================================

    // Speed grade -10 timing (ns) - READ CYCLE
    localparam real tRC_10   = 10.0;  // Read cycle time
    localparam real tAA_10   = 10.0;  // Address access time
    localparam real tACE_10  = 10.0;  // CS# access time
    localparam real tDOE_10  = 6.0;   // OE# access time
    localparam real tBA_10   = 6.0;   // Byte enable access time
    localparam real tOHA_10  = 2.5;   // Output hold time
    localparam real tHZOE_10 = 5.0;   // OE# to High-Z output
    localparam real tLZOE_10 = 0.0;   // OE# to Low-Z output
    localparam real tHZCE_10 = 5.0;   // CS# to High-Z output
    localparam real tLZCE_10 = 3.0;   // CS# to Low-Z output
    localparam real tHZB_10  = 5.0;   // UB#/LB# to High-Z output
    localparam real tLZB_10  = 0.0;   // UB#/LB# to Low-Z output

    // Speed grade -10 timing (ns) - WRITE CYCLE
    localparam real tWC_10   = 10.0;  // Write cycle time
    localparam real tSCS_10  = 8.0;   // CS# to write end
    localparam real tAW_10   = 8.0;   // Address setup to write end
    localparam real tPWB_10  = 8.0;   // UB#/LB# to write end
    localparam real tHA_10   = 0.0;   // Address hold from write end
    localparam real tSA_10   = 0.0;   // Address setup time (0ns - address valid when WE# falls)
    localparam real tPWE1_10 = 8.0;   // WE# pulse width (OE# HIGH)
    localparam real tPWE2_10 = 10.0;  // WE# pulse width (OE# LOW)
    localparam real tSD_10   = 6.0;   // Data setup to write end
    localparam real tHD_10   = 0.0;   // Data hold from write end
    localparam real tHZWE_10 = 4.0;   // WE# LOW to High-Z
    localparam real tLZWE_10 = 2.0;   // WE# HIGH to Low-Z

    // Speed grade -12 timing (ns) - READ CYCLE
    localparam real tRC_12   = 12.0;
    localparam real tAA_12   = 12.0;
    localparam real tACE_12  = 12.0;
    localparam real tDOE_12  = 7.0;
    localparam real tBA_12   = 7.0;
    localparam real tOHA_12  = 2.5;
    localparam real tHZOE_12 = 6.0;
    localparam real tLZOE_12 = 0.0;
    localparam real tHZCE_12 = 6.0;
    localparam real tLZCE_12 = 3.0;
    localparam real tHZB_12  = 6.0;
    localparam real tLZB_12  = 0.0;

    // Speed grade -12 timing (ns) - WRITE CYCLE
    localparam real tWC_12   = 12.0;
    localparam real tSCS_12  = 9.0;
    localparam real tAW_12   = 9.0;
    localparam real tPWB_12  = 9.0;
    localparam real tHA_12   = 0.0;
    localparam real tSA_12   = 0.0;
    localparam real tPWE1_12 = 9.0;
    localparam real tPWE2_12 = 12.0;
    localparam real tSD_12   = 7.0;
    localparam real tHD_12   = 0.0;
    localparam real tHZWE_12 = 5.0;
    localparam real tLZWE_12 = 2.0;

    // Select timing based on speed grade - READ CYCLE
    localparam real tRC   = (SPEED_GRADE == 10) ? tRC_10   : tRC_12;
    localparam real tAA   = (SPEED_GRADE == 10) ? tAA_10   : tAA_12;
    localparam real tACE  = (SPEED_GRADE == 10) ? tACE_10  : tACE_12;
    localparam real tDOE  = (SPEED_GRADE == 10) ? tDOE_10  : tDOE_12;
    localparam real tBA   = (SPEED_GRADE == 10) ? tBA_10   : tBA_12;
    localparam real tOHA  = (SPEED_GRADE == 10) ? tOHA_10  : tOHA_12;
    localparam real tHZOE = (SPEED_GRADE == 10) ? tHZOE_10 : tHZOE_12;
    localparam real tLZOE = (SPEED_GRADE == 10) ? tLZOE_10 : tLZOE_12;
    localparam real tHZCE = (SPEED_GRADE == 10) ? tHZCE_10 : tHZCE_12;
    localparam real tLZCE = (SPEED_GRADE == 10) ? tLZCE_10 : tLZCE_12;
    localparam real tHZB  = (SPEED_GRADE == 10) ? tHZB_10  : tHZB_12;
    localparam real tLZB  = (SPEED_GRADE == 10) ? tLZB_10  : tLZB_12;

    // Select timing based on speed grade - WRITE CYCLE
    localparam real tWC   = (SPEED_GRADE == 10) ? tWC_10   : tWC_12;
    localparam real tSCS  = (SPEED_GRADE == 10) ? tSCS_10  : tSCS_12;
    localparam real tAW   = (SPEED_GRADE == 10) ? tAW_10   : tAW_12;
    localparam real tPWB  = (SPEED_GRADE == 10) ? tPWB_10  : tPWB_12;
    localparam real tHA   = (SPEED_GRADE == 10) ? tHA_10   : tHA_12;
    localparam real tSA   = (SPEED_GRADE == 10) ? tSA_10   : tSA_12;
    localparam real tPWE1 = (SPEED_GRADE == 10) ? tPWE1_10 : tPWE1_12;
    localparam real tPWE2 = (SPEED_GRADE == 10) ? tPWE2_10 : tPWE2_12;
    localparam real tSD   = (SPEED_GRADE == 10) ? tSD_10   : tSD_12;
    localparam real tHD   = (SPEED_GRADE == 10) ? tHD_10   : tHD_12;
    localparam real tHZWE = (SPEED_GRADE == 10) ? tHZWE_10 : tHZWE_12;
    localparam real tLZWE = (SPEED_GRADE == 10) ? tLZWE_10 : tLZWE_12;

    //==========================================================================
    // INTERNAL CLOCK - 1ns period for timing resolution
    //==========================================================================

    reg clk = 0;
    always #0.5 clk = ~clk;  // 1ns period (500ps high, 500ps low)

    //==========================================================================
    // MEMORY ARRAY
    //==========================================================================

    reg [DATA_WIDTH-1:0] mem [0:(2**ADDR_WIDTH)-1];

    //==========================================================================
    // INTERNAL STATE
    //==========================================================================

    // Sampled inputs (registered on internal clock)
    reg [ADDR_WIDTH-1:0] addr_s, addr_prev;
    reg cs_n_s, cs_n_prev;
    reg we_n_s, we_n_prev;
    reg oe_n_s, oe_n_prev;
    reg lb_n_s, lb_n_prev;
    reg ub_n_s, ub_n_prev;
    reg [DATA_WIDTH-1:0] dq_in_s, dq_in_prev;

    // Timing event timestamps (in ns)
    real time_addr_change;
    real time_cs_n_fall;
    real time_cs_n_rise;
    real time_we_n_fall;
    real time_we_n_rise;
    real time_oe_n_fall;
    real time_oe_n_rise;
    real time_data_change;
    real time_lb_n_fall;
    real time_lb_n_rise;
    real time_ub_n_fall;
    real time_ub_n_rise;
    real time_output_disabled;  // Track when outputs went Hi-Z

    // Read state
    reg [DATA_WIDTH-1:0] read_data;
    reg [DATA_WIDTH-1:0] read_data_hold;  // For tOHA output hold
    reg [DATA_WIDTH-1:0] read_data_pending;  // Data waiting for tLZ delays
    reg output_enabled;
    reg output_hold_active;  // Holding previous data for tOHA
    reg output_enable_pending;  // Waiting for tLZ delays
    integer read_delay_cycles;
    integer read_delay_counter;
    integer output_hold_counter;  // Counter for tOHA hold time
    integer output_enable_delay_counter;  // Counter for tLZOE/tLZCE delays

    // Read address/control capture (captured when read starts, not when it completes)
    reg [ADDR_WIDTH-1:0] read_addr_capture;
    reg read_lb_capture;
    reg read_ub_capture;

    // Write state
    reg [ADDR_WIDTH-1:0] write_addr;
    reg [DATA_WIDTH-1:0] write_data;
    reg write_lb, write_ub;
    real write_start_time;

    //==========================================================================
    // INITIALIZATION
    //==========================================================================

    integer i;
    integer mem_fd;
    initial begin
        // Initialize memory to zero (real SRAM power-on state)
        for (i = 0; i < 2**ADDR_WIDTH; i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'b0}};
        end

        // Load memory initialization file if specified
        if (MEM_FILE != "") begin
            mem_fd = $fopen(MEM_FILE, "r");
            if (mem_fd == 0) begin
                $fatal(1, "[SRAM] ERROR: Memory init file %s not found; aborting simulation", MEM_FILE);
            end
            $fclose(mem_fd);
            $display("[SRAM] Loading memory from %s", MEM_FILE);
            $readmemh(MEM_FILE, mem);
            
            // ROM sanity checks (68K boot vector validation)
            begin
                reg [31:0] initial_sp, initial_pc, third_word;
                reg [15:0] code_at_pc;
                
                initial_sp = {mem[0], mem[1]};  // First 32-bit word: initial SP
                initial_pc = {mem[2], mem[3]};  // Second 32-bit word: initial PC
                third_word = {mem[4], mem[5]};  // Third 32-bit word: should be zero
                
                if (initial_sp == 32'h0) begin
                    $fatal(1, "[SRAM] ERROR: ROM validation failed - Initial SP is zero");
                end
                if (initial_pc == 32'h0) begin
                    $fatal(1, "[SRAM] ERROR: ROM validation failed - Initial PC is zero");
                end
                if (initial_pc >= initial_sp) begin
                    $fatal(1, "[SRAM] ERROR: ROM validation failed - Initial PC (0x%08x) >= Initial SP (0x%08x)", initial_pc, initial_sp);
                end
                if (third_word != 32'h0) begin
                    $fatal(1, "[SRAM] ERROR: ROM validation failed - Third longword is non-zero (0x%08x)", third_word);
                end
                
                // Check that there's actual code at the PC address (word-addressed)
                code_at_pc = mem[initial_pc[20:1]];
                if (code_at_pc == 16'h0) begin
                    $fatal(1, "[SRAM] ERROR: ROM validation failed - Code at PC (0x%08x) is zero", initial_pc);
                end
                
                $display("[SRAM] ROM validation passed: SP=0x%08x PC=0x%08x Code@PC=0x%04x", initial_sp, initial_pc, code_at_pc);
            end
        end

        // Initialize state
        addr_s = 0;
        addr_prev = 0;
        cs_n_s = 1;
        cs_n_prev = 1;
        we_n_s = 1;
        we_n_prev = 1;
        oe_n_s = 1;
        oe_n_prev = 1;
        lb_n_s = 1;
        lb_n_prev = 1;
        ub_n_s = 1;
        ub_n_prev = 1;
        dq_in_s = 0;
        dq_in_prev = 0;

        time_addr_change = 0;
        time_cs_n_fall = 0;
        time_we_n_fall = 0;
        time_we_n_rise = 0;
        time_oe_n_fall = 0;
        time_data_change = 0;

        read_data = {DATA_WIDTH{1'bz}};
        output_enabled = 0;
        read_delay_cycles = 0;
        read_delay_counter = 0;

        write_addr = 0;
        write_data = 0;
        write_lb = 0;
        write_ub = 0;
        write_start_time = 0;

        $display("[SRAM] IS61WV204816BLL-%0d initialized (%0dMx%0d)",
                SPEED_GRADE, 2**ADDR_WIDTH / 1024 / 1024, DATA_WIDTH);
    end

    //==========================================================================
    // SRAM OPERATION - Single unified block for all modes
    //==========================================================================

    always @(posedge clk) begin
        //----------------------------------------------------------------------
        // STEP 1: Sample all inputs
        //----------------------------------------------------------------------
        addr_s <= addr;
        cs_n_s <= cs_n;
        we_n_s <= we_n;
        oe_n_s <= oe_n;
        lb_n_s <= lb_n;
        ub_n_s <= ub_n;
        if (!output_enabled) begin
            dq_in_s <= dq;  // Only sample input when not driving output
        end

        //----------------------------------------------------------------------
        // STEP 2: Detect edges (using OLD _prev values before update)
        //----------------------------------------------------------------------
        if (addr_s !== addr_prev) begin
            time_addr_change = $realtime;
        end

        if (cs_n_s === 1'b0 && cs_n_prev !== 1'b0) begin
            time_cs_n_fall = $realtime;
        end
        if (cs_n_s === 1'b1 && cs_n_prev === 1'b0) begin
            time_cs_n_rise = $realtime;
        end

        if (we_n_s === 1'b0 && we_n_prev !== 1'b0) begin
            time_we_n_fall = $realtime;
        end
        if (we_n_s === 1'b1 && we_n_prev === 1'b0) begin
            time_we_n_rise = $realtime;
        end

        if (oe_n_s === 1'b0 && oe_n_prev !== 1'b0) begin
            time_oe_n_fall = $realtime;
        end
        if (oe_n_s === 1'b1 && oe_n_prev === 1'b0) begin
            time_oe_n_rise = $realtime;
        end

        if (lb_n_s === 1'b0 && lb_n_prev !== 1'b0) begin
            time_lb_n_fall = $realtime;
        end
        if (lb_n_s === 1'b1 && lb_n_prev === 1'b0) begin
            time_lb_n_rise = $realtime;
        end

        if (ub_n_s === 1'b0 && ub_n_prev !== 1'b0) begin
            time_ub_n_fall = $realtime;
        end
        if (ub_n_s === 1'b1 && ub_n_prev === 1'b0) begin
            time_ub_n_rise = $realtime;
        end

        if (dq_in_s !== dq_in_prev && !output_enabled) begin
            time_data_change = $realtime;
        end

        //----------------------------------------------------------------------
        // STEP 3: MODE SELECTION (mutually exclusive)
        //----------------------------------------------------------------------

        if (cs_n_s === 1'b1) begin
            //------------------------------------------------------------------
            // STANDBY MODE: CS# HIGH
            // Outputs tri-stated after tHZCE delay
            //------------------------------------------------------------------
            automatic real time_since_cs_rise;
            time_since_cs_rise = $realtime - time_cs_n_rise;

            // Disable output after tHZCE delay
            if (time_since_cs_rise >= tHZCE || cs_n_prev === 1'b1) begin
                output_enabled = 0;
                output_hold_active = 0;
                output_enable_pending = 0;
                read_data = {DATA_WIDTH{1'bz}};
            end
            // else keep previous output during tHZCE transition

            read_delay_counter = 0;
            output_hold_counter = 0;
            output_enable_delay_counter = 0;

        end else if (we_n_s === 1'b0) begin
            //------------------------------------------------------------------
            // WRITE MODE: CS# LOW && WE# LOW
            // Outputs tri-stated after tHZWE delay (even if OE# LOW)
            //------------------------------------------------------------------
            automatic real time_since_we_fall;
            time_since_we_fall = $realtime - time_we_n_fall;

            // Tri-state outputs after tHZWE delay
            if (time_since_we_fall >= tHZWE || we_n_prev === 1'b0) begin
                output_enabled = 0;
                output_hold_active = 0;
                output_enable_pending = 0;
                read_data = {DATA_WIDTH{1'bz}};
            end
            // else keep previous output during tHZWE transition

            read_delay_counter = 0;
            output_hold_counter = 0;
            output_enable_delay_counter = 0;

            // Capture write address/data/controls at WE# falling edge ONLY
            if (we_n_prev !== 1'b0) begin
                // WE# just went low - capture everything
                write_addr = addr_s;
                write_data = dq_in_s;
                write_lb = (lb_n_s === 1'b0);
                write_ub = (ub_n_s === 1'b0);

                if (VERBOSE) begin
                    $display("[SRAM] Write started: addr=0x%05h data=0x%04h @ %.2f ns",
                            addr_s, dq_in_s, $realtime);
                end
            end else begin
                // WE# still low - check for stability violations
                if (addr_s !== write_addr && VERBOSE) begin
                    $display("ERROR: Address changed during write! Expected 0x%05h, got 0x%05h @ %.2f ns",
                            write_addr, addr_s, $realtime);
                end
                // Update data continuously (as data can change during write until tSD before end)
                write_data = dq_in_s;
            end

            // Detect write cycle completion (WE# rising edge)
            if (we_n_prev === 1'b0 && we_n_s === 1'b1) begin
                // This shouldn't happen in this branch since we_n_s === 1'b0
                // But kept for safety - handled in next cycle
            end

        end else begin
            //------------------------------------------------------------------
            // READ MODE: CS# LOW && WE# HIGH
            // Outputs driven if OE# LOW
            //------------------------------------------------------------------

            if (oe_n_s === 1'b0) begin
                // Output enabled - perform read operation

                // Decrement delay counter if active
                if (read_delay_counter > 0) begin
                    read_delay_counter = read_delay_counter - 1;

                    // Check if delay just completed
                    if (read_delay_counter == 0) begin
                        // Delay complete - prepare data but wait for tLZ delays before enabling output
                        // Check for address stability violation
                        if (addr_s !== read_addr_capture) begin
                            $display("ERROR: Address changed during read access! Expected 0x%05h, got 0x%05h @ %.2f ns",
                                    read_addr_capture, addr_s, $realtime);
                        end

                        // Use CAPTURED address from when read started
                        if (!$isunknown(read_addr_capture) && read_addr_capture < 2**ADDR_WIDTH) begin
                            automatic real time_since_oe_fall;
                            automatic real time_since_cs_fall;
                            automatic integer cycles_for_lzoe;
                            automatic integer cycles_for_lzce;

                            read_data_pending = mem[read_addr_capture];

                            // Apply byte lane masking using CAPTURED values
                            if (!read_lb_capture) read_data_pending[7:0] = 8'hzz;
                            if (!read_ub_capture) read_data_pending[15:8] = 8'hzz;

                            // Calculate tLZ delay (output enable delay)
                            time_since_oe_fall = $realtime - time_oe_n_fall;
                            time_since_cs_fall = $realtime - time_cs_n_fall;
                            cycles_for_lzoe = $ceil(tLZOE - time_since_oe_fall);
                            cycles_for_lzce = $ceil(tLZCE - time_since_cs_fall);

                            // Use maximum delay
                            output_enable_delay_counter = cycles_for_lzoe;
                            if (cycles_for_lzce > output_enable_delay_counter)
                                output_enable_delay_counter = cycles_for_lzce;

                            if (output_enable_delay_counter <= 0) begin
                                // tLZ delays already met - enable immediately
                                read_data = read_data_pending;
                                output_enabled = 1;
                            end else begin
                                // Wait for tLZ delays
                                output_enable_pending = 1;
                            end

                            if (VERBOSE) begin
                                $display("[SRAM] Read complete (delayed): addr=0x%05h data=0x%04h @ %.2f ns",
                                        read_addr_capture, read_data_pending, $realtime);
                            end
                        end else begin
                            read_data = {DATA_WIDTH{1'bx}};
                            output_enabled = 1;
                        end
                    end
                end else if (output_enable_pending) begin
                    // Waiting for tLZ delays to expire before enabling output
                    if (output_enable_delay_counter > 0) begin
                        output_enable_delay_counter = output_enable_delay_counter - 1;
                        if (output_enable_delay_counter == 0) begin
                            read_data = read_data_pending;
                            output_enabled = 1;
                            output_enable_pending = 0;
                        end
                    end
                end else if (!output_enabled && !output_hold_active) begin
                    // No active delay and not outputting - start new read
                    // Calculate delay to model SRAM access time
                    automatic real addr_delay_ns;
                    automatic real cs_delay_ns;
                    automatic real oe_delay_ns;
                    automatic real lb_delay_ns;
                    automatic real ub_delay_ns;
                    automatic integer cycles_for_aa;
                    automatic integer cycles_for_ace;
                    automatic integer cycles_for_doe;
                    automatic integer cycles_for_ba_lb;
                    automatic integer cycles_for_ba_ub;

                    addr_delay_ns = $realtime - time_addr_change;
                    cs_delay_ns = $realtime - time_cs_n_fall;
                    oe_delay_ns = $realtime - time_oe_n_fall;
                    lb_delay_ns = $realtime - time_lb_n_fall;
                    ub_delay_ns = $realtime - time_ub_n_fall;

                    cycles_for_aa = $ceil(tAA - addr_delay_ns);
                    cycles_for_ace = $ceil(tACE - cs_delay_ns);
                    cycles_for_doe = $ceil(tDOE - oe_delay_ns);
                    cycles_for_ba_lb = $ceil(tBA - lb_delay_ns);
                    cycles_for_ba_ub = $ceil(tBA - ub_delay_ns);

                    // Use maximum delay (slowest path determines when data is valid)
                    read_delay_cycles = cycles_for_aa;
                    if (cycles_for_ace > read_delay_cycles) read_delay_cycles = cycles_for_ace;
                    if (cycles_for_doe > read_delay_cycles) read_delay_cycles = cycles_for_doe;
                    if (lb_n_s === 1'b0 && cycles_for_ba_lb > read_delay_cycles) read_delay_cycles = cycles_for_ba_lb;
                    if (ub_n_s === 1'b0 && cycles_for_ba_ub > read_delay_cycles) read_delay_cycles = cycles_for_ba_ub;

                    if (read_delay_cycles <= 0) begin
                        // Access time already met - check tLZ delays before enabling output
                        // Capture address immediately since no delay
                        read_addr_capture = addr_s;
                        read_lb_capture = (lb_n_s === 1'b0);
                        read_ub_capture = (ub_n_s === 1'b0);

                        if (!$isunknown(addr_s) && addr_s < 2**ADDR_WIDTH) begin
                            automatic real time_since_oe_fall;
                            automatic real time_since_cs_fall;
                            automatic integer cycles_for_lzoe;
                            automatic integer cycles_for_lzce;

                            read_data_pending = mem[addr_s];

                            // Apply byte lane masking
                            if (lb_n_s === 1'b1) read_data_pending[7:0] = 8'hzz;
                            if (ub_n_s === 1'b1) read_data_pending[15:8] = 8'hzz;

                            // Calculate tLZ delay (output enable delay)
                            time_since_oe_fall = $realtime - time_oe_n_fall;
                            time_since_cs_fall = $realtime - time_cs_n_fall;
                            cycles_for_lzoe = $ceil(tLZOE - time_since_oe_fall);
                            cycles_for_lzce = $ceil(tLZCE - time_since_cs_fall);

                            // Use maximum delay
                            output_enable_delay_counter = cycles_for_lzoe;
                            if (cycles_for_lzce > output_enable_delay_counter)
                                output_enable_delay_counter = cycles_for_lzce;

                            if (output_enable_delay_counter <= 0) begin
                                // tLZ delays already met - enable immediately
                                read_data = read_data_pending;
                                output_enabled = 1;
                            end else begin
                                // Wait for tLZ delays
                                output_enable_pending = 1;
                            end

                            if (VERBOSE) begin
                                $display("[SRAM] Read complete (immediate): time=%t, addr=0x%05h data=0x%04h @ %.2f ns",
                                        $time, addr_s, read_data_pending, $realtime);
                            end
                        end else begin
                            read_data = {DATA_WIDTH{1'bx}};
                            output_enabled = 1;
                        end
                    end else begin
                        // Start delay counter to model access time
                        read_delay_counter = read_delay_cycles;
                        // CAPTURE address and byte enables when read starts
                        read_addr_capture = addr_s;
                        read_lb_capture = (lb_n_s === 1'b0);
                        read_ub_capture = (ub_n_s === 1'b0);

                        if (VERBOSE) begin
                            $display("[SRAM] Read started: time=%t, addr=0x%05h, delay=%0d cycles @ %.2f ns",
                                    $time, addr_s, read_delay_cycles, $realtime);
                        end
                    end
                end else begin
                    // Already outputting - check if address/control changed
                    if (addr_s !== addr_prev || lb_n_s !== lb_n_prev || ub_n_s !== ub_n_prev) begin
                        // Address or byte enables changed - hold current data for tOHA
                        read_data_hold = read_data;
                        output_hold_active = 1;
                        output_hold_counter = $ceil(tOHA);  // Hold for tOHA ns
                        output_enabled = 0;  // Start new read on next cycle
                    end
                end

                // Handle output hold time (tOHA) - maintain previous data
                if (output_hold_active) begin
                    if (output_hold_counter > 0) begin
                        output_hold_counter = output_hold_counter - 1;
                        read_data = read_data_hold;  // Keep holding old data
                        // Note: output_enabled was set to 0, so new read will start
                    end else begin
                        output_hold_active = 0;
                    end
                end

            end else begin
                // OE# HIGH - tri-state outputs after tHZOE delay
                real time_since_oe_rise = $realtime - time_oe_n_rise;

                if (time_since_oe_rise >= tHZOE || oe_n_prev === 1'b1) begin
                    output_enabled = 0;
                    output_hold_active = 0;
                    output_enable_pending = 0;
                    read_data = {DATA_WIDTH{1'bz}};
                end
                // else keep previous output during tHZOE transition
            end
        end

        //----------------------------------------------------------------------
        // WRITE COMPLETION DETECTION (separate from mode logic above)
        // Detect WE# rising edge (write ending) regardless of current state
        //----------------------------------------------------------------------
        if (we_n_s === 1'b1 && we_n_prev === 1'b0 && cs_n_s === 1'b0) begin
            // Write cycle just ended - perform write using captured values
            automatic real write_pulse_width;
            automatic real addr_setup_to_we_fall;
            automatic real addr_setup_to_we_rise;
            automatic real data_setup;
            automatic real cs_setup;
            automatic real lb_setup;
            automatic real ub_setup;

            write_pulse_width = time_we_n_rise - time_we_n_fall;
            addr_setup_to_we_fall = time_we_n_fall - time_addr_change;
            addr_setup_to_we_rise = time_we_n_rise - time_addr_change;
            data_setup = time_we_n_rise - time_data_change;
            cs_setup = time_we_n_rise - time_cs_n_fall;
            lb_setup = time_we_n_rise - time_lb_n_fall;
            ub_setup = time_we_n_rise - time_ub_n_fall;

            // Timing checks (warnings only in VERBOSE mode)
            if (VERBOSE) begin
                // WE# pulse width check
                if (oe_n_s === 1'b0) begin
                    if (write_pulse_width < tPWE2) begin
                        $display("WARNING: Write pulse width %.2f ns < tPWE2 (%.2f ns) with OE# LOW @ %.2f ns",
                                write_pulse_width, tPWE2, $realtime);
                    end
                end else begin
                    if (write_pulse_width < tPWE1) begin
                        $display("WARNING: Write pulse width %.2f ns < tPWE1 (%.2f ns) @ %.2f ns",
                                write_pulse_width, tPWE1, $realtime);
                    end
                end

                // Address setup time before WE# falls (tSA)
                if (addr_setup_to_we_fall < tSA && addr_setup_to_we_fall >= 0) begin
                    $display("WARNING: Address setup before WE# %.2f ns < tSA (%.2f ns) @ %.2f ns",
                            addr_setup_to_we_fall, tSA, $realtime);
                end

                // Address setup to write end (tAW)
                if (addr_setup_to_we_rise < tAW && addr_setup_to_we_rise >= 0) begin
                    $display("WARNING: Address setup to write end %.2f ns < tAW (%.2f ns) @ %.2f ns",
                            addr_setup_to_we_rise, tAW, $realtime);
                end

                // Data setup to write end (tSD)
                if (data_setup < tSD && data_setup >= 0) begin
                    $display("WARNING: Data setup %.2f ns < tSD (%.2f ns) @ %.2f ns",
                            data_setup, tSD, $realtime);
                end

                // CS# to write end (tSCS)
                if (cs_setup < tSCS && cs_setup >= 0) begin
                    $display("WARNING: CS# setup %.2f ns < tSCS (%.2f ns) @ %.2f ns",
                            cs_setup, tSCS, $realtime);
                end

                // Byte enable to write end (tPWB)
                if (write_lb && lb_setup < tPWB && lb_setup >= 0) begin
                    $display("WARNING: LB# setup %.2f ns < tPWB (%.2f ns) @ %.2f ns",
                            lb_setup, tPWB, $realtime);
                end
                if (write_ub && ub_setup < tPWB && ub_setup >= 0) begin
                    $display("WARNING: UB# setup %.2f ns < tPWB (%.2f ns) @ %.2f ns",
                            ub_setup, tPWB, $realtime);
                end
            end

            // Perform write if address/data valid, using captured values
            if (!$isunknown(write_addr) && write_addr < 2**ADDR_WIDTH && !$isunknown(write_data)) begin
                if (write_lb) begin
                    mem[write_addr][7:0] = write_data[7:0];
                end
                if (write_ub) begin
                    mem[write_addr][15:8] = write_data[15:8];
                end

                if (VERBOSE) begin
                    $display("[SRAM] Write complete: time=%t, addr=0x%05h data=0x%04h lb=%b ub=%b @ %.2f ns",
                            $time, write_addr, write_data, write_lb, write_ub, $realtime);
                end
            end
        end

        // Detect CS# rising edge during write (write terminated by CS# deassert)
        if (cs_n_s === 1'b1 && cs_n_prev === 1'b0 && we_n_s === 1'b0) begin
            // Write terminated by CS# going high - use captured values
            if (!$isunknown(write_addr) && write_addr < 2**ADDR_WIDTH && !$isunknown(write_data)) begin
                if (write_lb) begin
                    mem[write_addr][7:0] = write_data[7:0];
                end
                if (write_ub) begin
                    mem[write_addr][15:8] = write_data[15:8];
                end
            end
        end

        //----------------------------------------------------------------------
        // STEP 4: Check hold times after write completion
        //----------------------------------------------------------------------
        // Check address hold (tHA) and data hold (tHD) after write ends
        if (we_n_s === 1'b1 && we_n_prev === 1'b0) begin
            // WE# just went high - in next cycles check for premature changes
            // These checks happen in subsequent cycles via time comparisons
        end

        if (we_n_prev === 1'b1 && VERBOSE) begin
            // We're in a cycle after write ended - check if signals held long enough
            automatic real time_since_we_rise;

            time_since_we_rise = $realtime - time_we_n_rise;

            if (time_since_we_rise < tHA && addr_s !== write_addr && time_since_we_rise > 0) begin
                $display("WARNING: Address changed %.2f ns after write end < tHA (%.2f ns) @ %.2f ns",
                        time_since_we_rise, tHA, $realtime);
            end

            if (time_since_we_rise < tHD && dq_in_s !== write_data && time_since_we_rise > 0) begin
                $display("WARNING: Data changed %.2f ns after write end < tHD (%.2f ns) @ %.2f ns",
                        time_since_we_rise, tHD, $realtime);
            end
        end

        //----------------------------------------------------------------------
        // STEP 5: Update _prev registers at END (so edge detection uses old values)
        //----------------------------------------------------------------------
        addr_prev = addr_s;
        cs_n_prev = cs_n_s;
        we_n_prev = we_n_s;
        oe_n_prev = oe_n_s;
        dq_in_prev = dq_in_s;
        lb_n_prev = lb_n_s;
        ub_n_prev = ub_n_s;
    end

    //==========================================================================
    // BIDIRECTIONAL BUS DRIVER
    //==========================================================================

    assign dq = output_enabled ? read_data : {DATA_WIDTH{1'bz}};

endmodule
