// VGA Display Model for Testbench
// Captures VGA signals into a pixel buffer and allows pixel readback

module vga_display_model (
    // VGA input signals (outputs from DUT)
    input  wire        vgaclk_i,      // VGA pixel clock
    input  wire [3:0]  rgb_r_i,       // Red channel
    input  wire [3:0]  rgb_g_i,       // Green channel
    input  wire [3:0]  rgb_b_i,       // Blue channel
    input  wire        hsync_i,       // Horizontal sync
    input  wire        vsync_i,       // Vertical sync

    // Pixel lookup interface
    input  wire [9:0]  x_i,           // X coordinate (0..1023)
    input  wire [9:0]  y_i,           // Y coordinate (0..767)

    // Pixel readback outputs (combinatorial)
    output wire [3:0]  rgb_r_o,
    output wire [3:0]  rgb_g_o,
    output wire [3:0]  rgb_b_o,

    // Debug enable
    input  wire        debug_enable = 1'b1
);

    localparam H_SYNC       = 136;
    localparam H_BACKPORCH  = 160;
    localparam H_ACTIVE     = 1024;
    localparam H_FRONTPORCH = 24;
    localparam H_TOTAL      = H_SYNC + H_BACKPORCH + H_ACTIVE + H_FRONTPORCH;

    localparam V_SYNC       = 6;
    localparam V_BACKPORCH  = 29;
    localparam V_ACTIVE     = 768;
    localparam V_FRONTPORCH = 3;
    localparam V_TOTAL      = V_SYNC + V_BACKPORCH + V_ACTIVE + V_FRONTPORCH;

    // Pixel buffer: 1024x768 to match active region
    reg [11:0] pixel_buffer [0:767][0:1023]; // {r[3:0], g[3:0], b[3:0]}

    // Position counters
    reg [10:0] hcount;
    reg [9:0]  vcount;

    // Sync edge detection
    reg hsync_prev;
    reg vsync_prev;

    // Active region flags
    wire h_active = (hcount >= (H_SYNC + H_BACKPORCH)) &&
                    (hcount < (H_SYNC + H_BACKPORCH + H_ACTIVE));
    wire v_active = (vcount >= (V_SYNC + V_BACKPORCH)) &&
                    (vcount < (V_SYNC + V_BACKPORCH + V_ACTIVE));
    wire in_active_region = h_active && v_active;

    // Pixel coordinates within active region
    wire [9:0] pixel_x = hcount - (H_SYNC + H_BACKPORCH);
    wire [9:0] pixel_y = vcount - (V_SYNC + V_BACKPORCH);

    // Initialize pixel buffer
    integer i, j;
    initial begin
        for (i = 0; i < 768; i = i + 1) begin
            for (j = 0; j < 1024; j = j + 1) begin
                pixel_buffer[i][j] = 12'h000;
            end
        end
        hcount = 0;
        vcount = 0;
        hsync_prev = 1'b1;
        vsync_prev = 1'b1;
    end

    reg seen_pixel = 1'b0;

    // VGA signal capture
    always @(posedge vgaclk_i) begin
        hsync_prev <= hsync_i;
        vsync_prev <= vsync_i;

        // Detect hsync falling edge (start of line)
        if (!hsync_i && hsync_prev) begin
            hcount = 0;
        end else begin
            hcount = hcount + 1;
        end

        // Detect vsync falling edge (start of frame)
        if (!vsync_i && vsync_prev) begin
            vcount = 0;
        end else if (!hsync_i && hsync_prev) begin
            // Increment line counter on hsync edge
            vcount = vcount + 1;
        end

        // Capture pixel data during active region
        if (in_active_region && pixel_x < 1024 && pixel_y < 768) begin
            if (!seen_pixel && (rgb_r_i != 0 || rgb_g_i != 0 || rgb_b_i != 0)) begin
                seen_pixel <= 1'b1;
                if (debug_enable) $display("First non-zero pixel captured at (%0d, %0d) = R:%0h G:%0h B:%0h", pixel_x, pixel_y, rgb_r_i, rgb_g_i, rgb_b_i);
            end
            pixel_buffer[pixel_y][pixel_x] <= {rgb_r_i, rgb_g_i, rgb_b_i};
        end
    end

    // Combinatorial pixel readback
    wire [11:0] pixel_data = (x_i < 1024 && y_i < 768) ? pixel_buffer[y_i][x_i] : 12'h000;

    assign rgb_r_o = pixel_data[11:8];
    assign rgb_g_o = pixel_data[7:4];
    assign rgb_b_o = pixel_data[3:0];

endmodule
