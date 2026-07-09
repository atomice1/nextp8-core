// Keyboard event queue module
// nextp8 core for the ZX Spectrum Next
//
// Implements a circular buffer for keyboard events (key press/release)
// following the specification in KEYBOARD_QUEUE.md
//
// Event format (32 bits):
//   [31]   0: press, 1: release
//   [30]   membrane mode
//   [16] lshift [17] rshift [18] lctrl [19] rctrl [20] lalt [21] ralt [22] lgui [23] rgui
//   [24] num lock [25] caps lock [26] scroll lock [27] mode
//   [15:0]  scancode
//
// Memory map:
//   $8000a8 | key event queue [r] [32] - pops from queue, returns 0 if empty
//
// Notes:
// - The queue can store up to 7 events (MAX_KEY_EVENTS - 1)
// - Write position is incremented by hardware on push
// - Read position is incremented by software on read (pop)
// - Queue is full when (write_pos + 1) % 8 == read_pos
// - Queue is empty when write_pos == read_pos

module kbd_queue (
    input wire clk,
    input wire reset,

    // Queue data output (32 bits)
    output wire [31:0] queue_data,

    // Push interface (from keyboard detection - hardware)
    input wire [31:0]  push_data,
    input wire         push_req,

    // Pop interface (from software - MMIO read)
    input wire         pop_req,

    // Clear queue (write any value to the event register)
    input wire         clear_req
);

localparam MAX_KEY_EVENTS = 8;

// Queue buffer - uses (MAX_KEY_EVENTS - 1) elements to distinguish full/empty
reg [31:0] queue_buffer [0:MAX_KEY_EVENTS-1];

// Position counters (0 to MAX_KEY_EVENTS-1)
reg [2:0] write_pos_reg;
reg [2:0] read_pos_reg;

// Internal signals
wire [2:0] next_write_pos = (write_pos_reg + 1'b1);
wire [2:0] next_read_pos  = (read_pos_reg  + 1'b1);

// Full condition: (write_pos + 1) % N == read_pos
wire is_full = (next_write_pos == read_pos_reg);

// Empty condition: write_pos == read_pos
wire is_empty = (write_pos_reg == read_pos_reg);

// Output assignments - return 0 if empty, otherwise 16-bit event
assign queue_data = is_empty ? 32'd0 : queue_buffer[read_pos_reg];

// Push logic - only push if not full
always @(posedge clk) begin
    if (reset) begin
        write_pos_reg <= 3'd0;
        read_pos_reg  <= 3'd0;
        // Initialize queue buffer to 0
        queue_buffer[0] <= 32'd0;
        queue_buffer[1] <= 32'd0;
        queue_buffer[2] <= 32'd0;
        queue_buffer[3] <= 32'd0;
        queue_buffer[4] <= 32'd0;
        queue_buffer[5] <= 32'd0;
        queue_buffer[6] <= 32'd0;
        queue_buffer[7] <= 32'd0;
    end else if (clear_req) begin
        // Clear queue: reset positions
        write_pos_reg <= 3'd0;
        read_pos_reg  <= 3'd0;
    end else begin
        // Handle pop (software read) - must be checked before push to avoid overflow
        if (pop_req && !is_empty) begin
            read_pos_reg <= next_read_pos;
        end

        // Push event to queue (hardware) - only if not full
        if (push_req && !is_full) begin
            queue_buffer[write_pos_reg] <= push_data;
            write_pos_reg <= next_write_pos;
        end
    end
end

endmodule
