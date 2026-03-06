//================================================================
// sdspi_model.sv
// SD Card SPI Mode Model
//
// Copyright (C) 2025 Chris January
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//==============================================================

`timescale 1ns / 1ps

module sdspi_model #(
    parameter LGMEMSZ = 24,         // Log2(Memory size in bytes) - 16MB default
    parameter string CARDIMAGE = "sdcard.img",
    parameter CCS = 1,               // 1=SDHC/SDXC (block address), 0=SDSC (byte address)
    parameter DEBUG = 0
) (
    input  wire clk,                // Fast clock for SPI slave synchronization
    input  wire reset,              // Reset signal
    input  wire debug_enable = 1'b1, // Runtime debug enable (overrides DEBUG parameter)
    input  wire spi_cs_n,           // Active-low chip select
    input  wire spi_clk,            // SPI clock
    input  wire spi_mosi,           // Master Out Slave In
    output wire spi_miso            // Master In Slave Out
);

    localparam SECTOR_SIZE = 512;
    localparam MEMSZ = (1 << LGMEMSZ);
    localparam NBLOCKS = MEMSZ / SECTOR_SIZE;

    // Reset states
    typedef enum logic [2:0] {
        SDSPI_POWERUP_RESET,
        SDSPI_CMD0_IDLE,
        SDSPI_RCVD_CMD8,
        SDSPI_RCVD_ACMD41,
        SDSPI_RESET_COMPLETE,
        SDSPI_IN_OPERATION
    } reset_state_t;

    // Memory backend
    logic [7:0] card_memory [0:MEMSZ-1];

    // SPI interface state
    logic [5:0] cmd;
    logic [31:0] cmd_arg;
    logic [6:0] cmd_crc;
    logic [7:0] cmd_buf [0:5];  // Command buffer (6 bytes)
    integer cmd_idx;            // Command byte index (0-6)

    // SPI slave interface
    wire [7:0] spi_rx_data;
    wire spi_rx_valid;
    reg [7:0] spi_tx_data;
    reg spi_tx_dv;

    // Card state
    reset_state_t reset_state;
    logic block_address_mode;
    logic host_supports_hcs;
    logic powerup_busy;
    logic crc_on;
    logic reading_data;
    logic writing_data;
    logic have_token;
    logic reading_multiblock;
    integer current_block_addr;

    // Write state machine states
    localparam WRITE_IDLE       = 2'd0;
    localparam WRITE_WAIT_TOKEN = 2'd1;
    localparam WRITE_RECV_DATA  = 2'd2;
    localparam WRITE_RECV_CRC   = 2'd3;
    logic [1:0] write_rx_state;
    logic writing_multiblock;
    integer write_block_addr;
    integer write_rx_idx;
    logic [7:0] write_blk_buf [0:511];  // Receive buffer for write data
    logic sending_busy;                 // Card is busy after write
    integer busy_bytes_remaining;

    // CSD and CID registers (16 bytes each)
    logic [7:0] m_csd [0:15];
    logic [7:0] m_cid [0:15];

    // Response generation
    logic [7:0] rsp_buf [0:16];
    integer rsp_idx;
    integer rsp_len;
    logic sending_response;
    integer rsp_delay;  // Delay (in bytes) before starting response

    // Data transfer
    logic [7:0] data_buf [0:515];  // 512 bytes + token + CRC16
    integer data_idx;
    integer data_len;
    logic sending_data;

    // Busy signaling
    integer busy_count;

    // Response buffer state
    logic [7:0] tx_byte_buffer [0:16];  // Buffer for multi-byte responses
    integer tx_buffer_len;
    integer tx_buffer_idx;

    // CRC7 calculation (for commands)
    function automatic logic [6:0] crc7(input logic [39:0] data);
        logic [6:0] crc;
        logic bit_val;
        crc = 7'h00;
        for (int i = 39; i >= 0; i--) begin
            bit_val = crc[6] ^ data[i];
            crc = {crc[5:0], 1'b0};
            if (bit_val)
                crc = crc ^ 7'h09;
        end
        return crc;
    endfunction

    // CRC16 calculation (for data)
    function automatic logic [15:0] crc16(input logic [7:0] data[], input integer len);
        logic [15:0] crc;
        logic bit_val;
        crc = 16'h0000;
        for (int byte_idx = 0; byte_idx < len; byte_idx++) begin
            for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
                bit_val = crc[15] ^ data[byte_idx][bit_idx];
                crc = {crc[14:0], 1'b0};
                if (bit_val)
                    crc = crc ^ 16'h1021;
            end
        end
        return crc;
    endfunction

    // Instantiate SPI slave module
    spi_slave #(.SPI_MODE(0)) spi_slave_inst (
        .i_Rst_L(~reset),
        .i_Clk(clk),
        .o_RX_DV(spi_rx_valid),
        .o_RX_Byte(spi_rx_data),
        .i_TX_DV(spi_tx_dv),
        .i_TX_Byte(spi_tx_data),
        .i_SPI_Clk(spi_clk),
        .o_SPI_MISO(spi_miso),
        .i_SPI_MOSI(spi_mosi),
        .i_SPI_CS_n(spi_cs_n)
    );

    // Initialize card state
    initial begin
        cmd_idx = 0;
        reset_state = SDSPI_POWERUP_RESET;
        block_address_mode = (CCS == 1);
        host_supports_hcs = 0;
        powerup_busy = 1;
        crc_on = 0;
        reading_data = 0;
        writing_data = 0;
        have_token = 0;
        reading_multiblock = 0;
        current_block_addr = 0;
        writing_multiblock = 0;
        write_block_addr = 0;
        write_rx_state = WRITE_IDLE;
        write_rx_idx = 0;
        write_block_addr = 0;
        writing_multiblock = 0;
        sending_busy = 0;
        busy_bytes_remaining = 0;
        for (int i = 0; i < 512; i++)
            write_blk_buf[i] = 8'h00;
        sending_response = 0;
        sending_data = 0;
        rsp_idx = 0;
        rsp_len = 0;
        rsp_delay = 0;
        data_idx = 0;
        data_len = 0;
        busy_count = 0;
        spi_tx_data = 8'hFF;
        spi_tx_dv = 0;
        tx_buffer_len = 0;
        tx_buffer_idx = 0;

        // Initialize CSD register (from LEXAR_CSD in sdspisim.cpp)
        m_csd[0]  = 8'h40; // CSD_STRUCTURE=1.0 (SDHC), reserved
        m_csd[1]  = 8'h0e;
        m_csd[2]  = 8'h00;
        m_csd[3]  = 8'h32;
        m_csd[4]  = 8'h5b;
        m_csd[5]  = 8'h59; // READ_BL_LEN=9 (512 bytes)
        m_csd[6]  = 8'h00;
        m_csd[7]  = 8'h00; // C_SIZE bits [21:16]
        m_csd[8]  = 8'h1d; // C_SIZE bits [15:8] - calculated for card size
        m_csd[9]  = 8'hc7; // C_SIZE bits [7:0]
        m_csd[10] = 8'h7f;
        m_csd[11] = 8'h80;
        m_csd[12] = 8'h0a;
        m_csd[13] = 8'h40;
        m_csd[14] = 8'h00;
        m_csd[15] = 8'h00; // CRC will be calculated

        // Calculate proper C_SIZE for card capacity
        // C_SIZE = (capacity / 512KB) - 1
        // For MEMSZ bytes: C_SIZE = (MEMSZ / 524288) - 1
        begin
            integer c_size;
            c_size = (MEMSZ / 524288) - 1;
            m_csd[7] = (c_size >> 16) & 8'h3f;
            m_csd[8] = (c_size >> 8) & 8'hff;
            m_csd[9] = c_size & 8'hff;
        end

        // Calculate CSD CRC7
        begin
            logic [6:0] csd_crc;
            logic [119:0] csd_bits;
            // Pack CSD into 120 bits for CRC calculation
            for (int i = 0; i < 15; i++) begin
                csd_bits[119 - i*8 -: 8] = m_csd[i];
            end
            csd_crc = crc7(csd_bits[119:80]); // CRC over first 40 bits
            // Actually, CRC7 should be over full 120 bits, but reference uses simple approach
            m_csd[15] = {csd_crc, 1'b1};
        end

        // Initialize CID register (from LEXAR_CID in sdspisim.cpp)
        m_cid[0]  = 8'h9c; // Manufacturer ID
        m_cid[1]  = 8'h53; // 'S'
        m_cid[2]  = 8'h4f; // 'O'
        m_cid[3]  = 8'h4c; // 'L'
        m_cid[4]  = 8'h58; // 'X'
        m_cid[5]  = 8'h36; // '6'
        m_cid[6]  = 8'h34; // '4'
        m_cid[7]  = 8'h47; // 'G'
        m_cid[8]  = 8'h10; // Product revision
        m_cid[9]  = 8'h29; // Serial number
        m_cid[10] = 8'h80;
        m_cid[11] = 8'h03;
        m_cid[12] = 8'h7b; // Manufacturing date
        m_cid[13] = 8'h01;
        m_cid[14] = 8'h38;
        m_cid[15] = 8'h00; // CRC will be calculated

        // Calculate CID CRC7
        begin
            logic [6:0] cid_crc;
            logic [119:0] cid_bits;
            for (int i = 0; i < 15; i++) begin
                cid_bits[119 - i*8 -: 8] = m_cid[i];
            end
            cid_crc = crc7(cid_bits[119:80]);
            m_cid[15] = {cid_crc, 1'b1};
        end

        // Load card image if it exists
        if (CARDIMAGE != "") begin
            integer fd;
            integer bytes_read;
            $display("[SDSPI] Loading card image: %s", CARDIMAGE);
            fd = $fopen(CARDIMAGE, "rb");
            if (fd) begin
                bytes_read = $fread(card_memory, fd);
                $fclose(fd);
                $display("[SDSPI] Loaded %0d bytes from card image", bytes_read);
            end else begin
                $display("[SDSPI] WARNING: Could not open %s", CARDIMAGE);
            end
            $display("[SDSPI] Card size: %0d MB (%0d blocks)", MEMSZ/(1024*1024), NBLOCKS);
        end
    end

    // Protocol layer: Process received bytes from SPI slave
    always @(posedge spi_cs_n) begin
        // CS deasserted - reset protocol state
        cmd_idx <= 0;
        sending_response <= 0;
        sending_data <= 0;
        tx_buffer_idx <= 0;
        tx_buffer_len <= 0;
        rsp_delay <= 0;
        // Reset write state machine so a new CS assertion starts clean
        write_rx_state <= WRITE_IDLE;
        writing_data <= 0;
        writing_multiblock <= 0;
        sending_busy <= 0;
        busy_bytes_remaining <= 0;
        if (DEBUG || debug_enable) $display("[SDSPI] CS deasserted at time %0t", $time);
    end

    // CS edge detection (synchronous to clk)
    logic spi_cs_n_q;
    always @(posedge clk) begin
        spi_cs_n_q <= spi_cs_n;

        // CS asserted (negedge): preload idle byte
        if (spi_cs_n_q && !spi_cs_n) begin
            if (DEBUG || debug_enable) $display("[SDSPI] *** CS asserted (goes low) at time %0t ***", $time);
            spi_tx_data = 8'hFF;
            spi_tx_dv <= 1;
        end
    end

    // Byte reception handler (synchronous to clk)
    logic spi_rx_valid_q;
    always @(posedge clk) begin
        spi_rx_valid_q <= spi_rx_valid;

        // Detect rising edge of spi_rx_valid
        if (spi_rx_valid && !spi_rx_valid_q && !spi_cs_n) begin
            if (spi_rx_data != 8'hff || cmd_idx != 0)
                if (debug_enable || DEBUG) $display("[SDSPI] <<< Received byte: 0x%02x (binary: %08b), cmd_idx=%0d, write_rx_state=%0d", spi_rx_data, spi_rx_data, cmd_idx, write_rx_state);

            // Write data reception takes priority over command parsing
            if (write_rx_state != WRITE_IDLE) begin
                case (write_rx_state)
                    WRITE_WAIT_TOKEN: begin
                        if (spi_rx_data == 8'hFF) begin
                            // Waiting pad byte, ignore
                        end else if ((!writing_multiblock && spi_rx_data == 8'hFE) ||
                                     (writing_multiblock  && spi_rx_data == 8'hFC)) begin
                            if (DEBUG || debug_enable) $display("[SDSPI] Write data start token received");
                            write_rx_state <= WRITE_RECV_DATA;
                            write_rx_idx   <= 0;
                        end else if (writing_multiblock && spi_rx_data == 8'hFD) begin
                            // CMD25 stop-transmission token
                            if (debug_enable || DEBUG) $display("[SDSPI] CMD25: Stop token received, multi-block write complete");
                            writing_data   <= 0;
                            write_rx_state <= WRITE_IDLE;
                        end else begin
                            $display("[SDSPI] ERROR: Unexpected write token 0x%02x", spi_rx_data);
                        end
                    end
                    WRITE_RECV_DATA: begin
                        write_blk_buf[write_rx_idx] = spi_rx_data;  // blocking OK for memory array
                        if (write_rx_idx == SECTOR_SIZE - 1) begin
                            write_rx_state <= WRITE_RECV_CRC;
                            write_rx_idx   <= 0;
                        end else begin
                            write_rx_idx <= write_rx_idx + 1;
                        end
                    end
                    WRITE_RECV_CRC: begin
                        if (write_rx_idx == 0) begin
                            write_rx_idx <= 1;  // Wait for second CRC byte
                        end else begin
                            // Second CRC byte received — commit write to card memory
                            begin : write_commit
                                integer wr_byte_addr;
                                wr_byte_addr = write_block_addr * SECTOR_SIZE;
                                for (int i = 0; i < SECTOR_SIZE; i++)
                                    card_memory[wr_byte_addr + i] = write_blk_buf[i];
                            end
                            if (debug_enable || DEBUG) $display("[SDSPI] Write block %0d committed to card memory", write_block_addr);
                            // Send data response token: 0x05 = data accepted (format 0bxxx00101)
                            tx_byte_buffer[0] = 8'h05;
                            tx_buffer_len     = 1;
                            tx_buffer_idx     = 0;
                            sending_response  = 1;
                            // Card busy while programming
                            sending_busy          <= 1;
                            busy_bytes_remaining  <= 8;
                            if (writing_multiblock) begin
                                // Advance to next block, wait for next start token
                                write_block_addr <= write_block_addr + 1;
                                write_rx_state   <= WRITE_WAIT_TOKEN;
                                write_rx_idx     <= 0;
                            end else begin
                                writing_data   <= 0;
                                write_rx_state <= WRITE_IDLE;
                            end
                        end
                    end
                    default: ;
                endcase

            // Normal command parsing (no active write)
            end else if (cmd_idx == 0 && spi_rx_data == 8'hFF) begin
                // Sync byte, skip it
            end else if (cmd_idx < 6) begin
                // Collecting command bytes
                // First byte must start with '01' pattern
                if (cmd_idx == 0 && spi_rx_data[7:6] != 2'b01) begin
                    if (debug_enable || DEBUG) $display("[SDSPI] ERROR: Invalid command start byte 0x%02x (expected bit[7:6]=01)", spi_rx_data);
                end else begin
                    cmd_buf[cmd_idx] <= spi_rx_data;
                    cmd_idx <= cmd_idx + 1;
                end
            end else if (cmd_idx == 6) begin
                // Command complete, process it
                cmd <= cmd_buf[0][5:0];
                cmd_arg <= {cmd_buf[1], cmd_buf[2], cmd_buf[3], cmd_buf[4]};
                cmd_crc <= cmd_buf[5][7:1];

                if (DEBUG || debug_enable) begin
                    $display("[SDSPI] CMD%0d received, arg=0x%08x", cmd_buf[0][5:0], {cmd_buf[1], cmd_buf[2], cmd_buf[3], cmd_buf[4]});
                end

                // CMD12 during data transmission should stop it
                if (cmd_buf[0][5:0] == 6'd12 && sending_data) begin
                    sending_data <= 0;
                    reading_multiblock <= 0;
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD12 interrupting data transmission");
                end

                // Process command and set up response buffer
                process_command(cmd_buf[0][5:0], {cmd_buf[1], cmd_buf[2], cmd_buf[3], cmd_buf[4]});

                // Reset for next command
                cmd_idx <= 0;
            end
        end
    end

    // Transmit handler: Load next byte when previous byte completes
    // Trigger on rx_valid which indicates a byte was received and slave is ready for next TX byte
    always @(posedge clk) begin
        if (spi_rx_valid && !spi_cs_n) begin
            // Handle response delay (send 0xFF for rsp_delay cycles before actual response)
            if (rsp_delay > 0) begin
                rsp_delay <= rsp_delay - 1;
                spi_tx_data = 8'hFF;  // Send idle during delay (blocking assignment for immediate effect)
                spi_tx_dv <= 1;
                if ((DEBUG || debug_enable) && rsp_delay == 1 || debug_enable && rsp_delay == 1) $display("[SDSPI] Response delay complete, starting response");
            // Response has priority over data (needed for CMD12 during multi-block read)
            end else if (sending_response && tx_buffer_idx < tx_buffer_len) begin
                if (debug_enable || DEBUG) $display("[SDSPI] >>> Loading byte %0d: 0x%02x", tx_buffer_idx, tx_byte_buffer[tx_buffer_idx]);
                spi_tx_data = tx_byte_buffer[tx_buffer_idx];  // Blocking assignment for immediate effect
                spi_tx_dv <= 1;
                tx_buffer_idx <= tx_buffer_idx + 1;

                if (tx_buffer_idx + 1 >= tx_buffer_len) begin
                    sending_response <= 0;
                    if (DEBUG || debug_enable) $display("[SDSPI] Response complete");
                end
            end else if (sending_data && data_idx < data_len && !sending_response) begin
                spi_tx_data = data_buf[data_idx];  // Blocking assignment for immediate effect
                spi_tx_dv <= 1;
                data_idx <= data_idx + 1;
                if (data_idx + 1 >= data_len) begin
                    sending_data <= 0;
                    if (DEBUG || debug_enable) $display("[SDSPI] Data transmission complete");

                    // If in multi-block read mode, prepare next block
                    if (reading_multiblock) begin
                        logic [15:0] next_block_crc;
                        integer next_byte_addr;

                        current_block_addr <= current_block_addr + 1;
                        if (DEBUG || debug_enable) $display("[SDSPI] CMD18: Preparing next block %0d", current_block_addr + 1);

                        // Check if we've reached the end of card
                        if (current_block_addr + 1 < NBLOCKS) begin
                            // Prepare next data packet
                            data_buf[0] = 8'hFE; // Start token
                            next_byte_addr = (current_block_addr + 1) * SECTOR_SIZE;
                            for (int i = 0; i < SECTOR_SIZE; i++) begin
                                data_buf[i+1] = card_memory[next_byte_addr + i];
                            end
                            // Add CRC16
                            next_block_crc = crc16(data_buf[1:512], SECTOR_SIZE);
                            data_buf[513] = next_block_crc[15:8];
                            data_buf[514] = next_block_crc[7:0];
                            data_len = 515;
                            data_idx = 0;
                            sending_data = 1;
                        end else begin
                            // End of card reached
                            reading_multiblock <= 0;
                        end
                    end
                end
            end else if (sending_busy && busy_bytes_remaining > 0 && !sending_response) begin
                spi_tx_data = 8'h00;  // Card busy after write
                spi_tx_dv <= 1;
                busy_bytes_remaining <= busy_bytes_remaining - 1;
                if (busy_bytes_remaining == 1)
                    sending_busy <= 0;
            end else begin
                spi_tx_data = 8'hFF;  // Idle (blocking assignment)
                spi_tx_dv <= 1;
            end
        end else if (spi_tx_dv) begin
            // Clear tx_dv pulse after one cycle
            spi_tx_dv <= 0;
        end
    end

    // Command processing task
    task process_command(input logic [5:0] cmd_num, input logic [31:0] arg);
        logic [6:0] calc_crc;
        logic [15:0] block_crc;
        integer block_addr;
        integer byte_addr;

        begin
            case (cmd_num)
                // CMD0: GO_IDLE_STATE
                6'd0: begin
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD0: GO_IDLE_STATE");
                    reset_state <= SDSPI_CMD0_IDLE;
                    powerup_busy <= 1;
                    send_r1_response(8'h01); // In idle state
                end

                // CMD8: SEND_IF_COND
                6'd8: begin
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD8: SEND_IF_COND, VHS=%0d, pattern=0x%02x",
                                       arg[11:8], arg[7:0]);
                    reset_state <= SDSPI_RCVD_CMD8;
                    // R7 response: R1 + 32-bit response
                    tx_byte_buffer[0] = 8'h01; // R1: Still in idle after CMD8
                    tx_byte_buffer[1] = 8'h00;
                    tx_byte_buffer[2] = 8'h00;
                    tx_byte_buffer[3] = arg[11:8]; // VHS echo
                    tx_byte_buffer[4] = arg[7:0];   // Pattern echo
                    tx_buffer_len = 5;
                    tx_buffer_idx = 0;
                    sending_response = 1;
                    // Note: First byte will be loaded when command processing completes
                end

                // CMD55: APP_CMD
                6'd55: begin
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD55: APP_CMD");
                    // Return 0x01 if still in idle state, 0x00 if initialized
                    send_r1_response((reset_state == SDSPI_RESET_COMPLETE) ? 8'h00 : 8'h01);
                end

                // ACMD41: SD_SEND_OP_COND
                6'd41: begin
                    if (DEBUG || debug_enable) $display("[SDSPI] ACMD41: SD_SEND_OP_COND, HCS=%0d", arg[30]);
                    if (arg[30])
                        host_supports_hcs <= 1;

                    reset_state <= SDSPI_RCVD_ACMD41;
                    powerup_busy <= 0; // Initialization complete
                    // R1 response: ready (not idle)
                    send_r1_response(8'h00);

                    if (reset_state == SDSPI_RCVD_ACMD41)
                        reset_state <= SDSPI_RESET_COMPLETE;
                end

                // CMD58: READ_OCR
                6'd58: begin
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD58: READ_OCR");
                    // R3 response: R1 + OCR
                    tx_byte_buffer[0] = 8'h00; // R1: ready
                    // OCR: bit 31=power up complete, bit 30=CCS (SDHC), bits 23-15=voltage
                    tx_byte_buffer[1] = {1'b1, CCS[0], 6'b00_0000}; // Power up done + CCS
                    tx_byte_buffer[2] = 8'b1111_1111; // Voltage range (all supported)
                    tx_byte_buffer[3] = 8'b1100_0000; // Voltage range continued
                    tx_byte_buffer[4] = 8'h00;
                    tx_buffer_len = 5;
                    tx_buffer_idx = 0;
                    sending_response = 1;
                    // Note: First byte will be loaded when command processing completes
                end

                // CMD59: CRC_ON_OFF
                6'd59: begin
                    crc_on <= arg[0];
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD59: CRC_ON_OFF = %0d", arg[0]);
                    send_r1_response(8'h00);
                end

                // CMD9: SEND_CSD
                6'd9: begin
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD9: SEND_CSD");
                    send_r1_response(8'h00); // OK

                    // Prepare data packet with CSD register
                    data_buf[0] = 8'hFE; // Start token
                    for (int i = 0; i < 16; i++) begin
                        data_buf[i+1] = m_csd[i];
                    end
                    // Add CRC16
                    block_crc = crc16(data_buf[1:16], 16);
                    data_buf[17] = block_crc[15:8];
                    data_buf[18] = block_crc[7:0];
                    data_len = 19; // token + 16 bytes + 2 CRC
                    data_idx = 0;
                    sending_data = 1;
                end

                // CMD10: SEND_CID
                6'd10: begin
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD10: SEND_CID");
                    send_r1_response(8'h00); // OK

                    // Prepare data packet with CID register
                    data_buf[0] = 8'hFE; // Start token
                    for (int i = 0; i < 16; i++) begin
                        data_buf[i+1] = m_cid[i];
                    end
                    // Add CRC16
                    block_crc = crc16(data_buf[1:16], 16);
                    data_buf[17] = block_crc[15:8];
                    data_buf[18] = block_crc[7:0];
                    data_len = 19; // token + 16 bytes + 2 CRC
                    data_idx = 0;
                    sending_data = 1;
                end

                // CMD12: STOP_TRANSMISSION
                6'd12: begin
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD12: STOP_TRANSMISSION");
                    reading_multiblock <= 0;
                    // R1b response (stuff byte follows R1)
                    tx_byte_buffer[0] = 8'h00; // R1: OK
                    tx_byte_buffer[1] = 8'h00; // Stuff byte
                    tx_byte_buffer[2] = 8'hFF; // Not busy
                    tx_buffer_len = 3;
                    tx_buffer_idx = 0;
                    rsp_delay = 4;  // Delay before response (matches sdspisim.cpp)
                    sending_response = 1;
                end

                // CMD13: SEND_STATUS
                6'd13: begin
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD13: SEND_STATUS");
                    // R2 response: R1 + status byte
                    tx_byte_buffer[0] = 8'h00; // R1: OK
                    tx_byte_buffer[1] = 8'h00; // Status: no errors
                    tx_buffer_len = 2;
                    tx_buffer_idx = 0;
                    sending_response = 1;
                end

                // CMD16: SET_BLOCKLEN
                6'd16: begin
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD16: SET_BLOCKLEN, len=%0d", arg);
                    if (arg == 512) begin
                        send_r1_response(8'h00); // OK
                    end else begin
                        send_r1_response(8'h40); // Parameter error
                    end
                end

                // CMD17: READ_SINGLE_BLOCK
                6'd17: begin
                    block_addr = block_address_mode ? arg : (arg / SECTOR_SIZE);
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD17: READ_SINGLE_BLOCK, block=%0d", block_addr);

                    if (block_addr >= NBLOCKS) begin
                        send_r1_response(8'h04); // Illegal command
                    end else begin
                        send_r1_response(8'h00); // OK

                        // Prepare data packet
                        data_buf[0] = 8'hFE; // Start token
                        byte_addr = block_addr * SECTOR_SIZE;
                        for (int i = 0; i < SECTOR_SIZE; i++) begin
                            data_buf[i+1] = card_memory[byte_addr + i];
                        end
                        // Add CRC16
                        block_crc = crc16(data_buf[1:512], SECTOR_SIZE);
                        data_buf[513] = block_crc[15:8];
                        data_buf[514] = block_crc[7:0];
                        data_len = 515;
                        data_idx = 0;
                        sending_data = 1;
                        reading_data = 1;
                    end
                end

                // CMD18: READ_MULTIPLE_BLOCK
                6'd18: begin
                    block_addr = block_address_mode ? arg : (arg / SECTOR_SIZE);
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD18: READ_MULTIPLE_BLOCK, start_block=%0d", block_addr);

                    if (block_addr >= NBLOCKS) begin
                        send_r1_response(8'h04); // Illegal command
                    end else begin
                        send_r1_response(8'h00); // OK
                        reading_multiblock <= 1;
                        current_block_addr <= block_addr;

                        // Prepare first data packet
                        data_buf[0] = 8'hFE; // Start token
                        byte_addr = block_addr * SECTOR_SIZE;
                        for (int i = 0; i < SECTOR_SIZE; i++) begin
                            data_buf[i+1] = card_memory[byte_addr + i];
                        end
                        // Add CRC16
                        block_crc = crc16(data_buf[1:512], SECTOR_SIZE);
                        data_buf[513] = block_crc[15:8];
                        data_buf[514] = block_crc[7:0];
                        data_len = 515;
                        data_idx = 0;
                        sending_data = 1;
                        reading_data = 1;
                    end
                end

                // CMD24: WRITE_SINGLE_BLOCK
                6'd24: begin
                    block_addr = block_address_mode ? arg : (arg / SECTOR_SIZE);
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD24: WRITE_SINGLE_BLOCK, block=%0d", block_addr);

                    if (block_addr >= NBLOCKS) begin
                        send_r1_response(8'h04); // Illegal command
                    end else begin
                        send_r1_response(8'h00); // OK
                        writing_data <= 1;
                        writing_multiblock <= 0;
                        write_block_addr <= block_addr;
                        write_rx_state <= WRITE_WAIT_TOKEN;
                        write_rx_idx <= 0;
                    end
                end

                // CMD25: WRITE_MULTIPLE_BLOCK
                6'd25: begin
                    block_addr = block_address_mode ? arg : (arg / SECTOR_SIZE);
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD25: WRITE_MULTIPLE_BLOCK, start_block=%0d", block_addr);

                    if (block_addr >= NBLOCKS) begin
                        send_r1_response(8'h04); // Illegal command
                    end else begin
                        send_r1_response(8'h00); // OK
                        writing_data <= 1;
                        writing_multiblock <= 1;
                        write_block_addr <= block_addr;
                        write_rx_state <= WRITE_WAIT_TOKEN;
                        write_rx_idx <= 0;
                    end
                end

                // ACMD23: SET_WR_BLK_ERASE_COUNT (preceded by CMD55)
                6'd23: begin
                    if (DEBUG || debug_enable) $display("[SDSPI] ACMD23: SET_WR_BLK_ERASE_COUNT, count=%0d", arg[22:0]);
                    send_r1_response(8'h00); // OK
                end

                default: begin
                    if (DEBUG || debug_enable) $display("[SDSPI] CMD%0d: Unknown command", cmd_num);
                    send_r1_response(8'h04); // Illegal command
                end
            endcase
        end
    endtask

    // Send R1 response (1 byte)
    task send_r1_response(input logic [7:0] r1);
        begin
            tx_byte_buffer[0] = r1;
            tx_buffer_len = 1;
            tx_buffer_idx = 0;
            sending_response = 1;
        end
    endtask

endmodule
