////////////////////////////////////////////////////////////////////////////////// 
// Copyright (C) 2025 Chris January  
//////////////////////////////////////////////////////////////////////////////////

module exec_tb(
    );

//Clock
reg clock_50_i = 0;
always #1 clock_50_i = ~clock_50_i;

//SRAM (AS7C34096)
wire [19:0] ram_addr_o;
wire [15:0] ram_data_io;
wire ram_lb_n_o;
wire ram_ub_n_o;
wire ram_oe_n_o;
wire ram_we_n_o;
wire ram_cs_n_o;

// PS2
wire ps2_clk_io;
wire ps2_data_io;
wire ps2_pin6_io;
wire ps2_pin2_io;

// SD Card
wire sd_cs0_n_o;
wire sd_cs1_n_o;
wire sd_sclk_o;
wire sd_mosi_o;
wire sd_miso_i;

// Flash
wire flash_cs_n_o;
wire flash_sclk_o;
wire flash_mosi_o;
wire flash_miso_i;
wire flash_wp_o;
wire flash_hold_o;

// Joystick
wire joyp1_i;
wire joyp2_i;
wire joyp3_i;
wire joyp4_i;
wire joyp6_i;
wire joyp7_o;
wire joyp9_i;
wire joysel_o;

// Audio
wire audioext_l_o;
wire audioext_r_o;
wire audioint_o;

// K7
wire ear_port_i;
wire mic_port_o;

// Buttons
wire btn_divmmc_n_i;
wire btn_multiface_n_i;
wire btn_reset_n_i;

// Matrix keyboard
wire [7:0] keyb_row_o;
wire [6:0] keyb_col_i;

// Bus
wire bus_rst_n_io;
wire bus_clk35_o;
wire [15:0] bus_addr_o;
wire [7:0] bus_data_io;
wire bus_int_n_io;
wire bus_nmi_n_i;
wire bus_ramcs_i;
wire bus_romcs_i;
wire bus_wait_n_i;
wire bus_halt_n_o;
wire bus_iorq_n_o;
wire bus_m1_n_o;
wire bus_mreq_n_o;
wire bus_rd_n_io;
wire bus_wr_n_o;
wire bus_rfsh_n_o;
wire bus_busreq_n_i;
wire bus_busack_n_o;
wire bus_iorqula_n_i;
wire bus_y_o;

// VGA
wire [2:0] rgb_r_o;
wire [2:0] rgb_g_o;
wire [2:0] rgb_b_o;
wire hsync_o;
wire vsync_o;
//wwire csync_o,

// HDMI
wire [3:0] hdmi_p_o;
wire [3:0] hdmi_n_o;

// I2C (RTC and HDMI)
wire i2c_scl_io;
wire i2c_sda_io;

// ESP
wire esp_gpio0_io;
wire esp_gpio2_io;
wire esp_rx_i;
wire esp_tx_o;
wire esp_rtr_n_i;
wire esp_cts_n_o;

// PI GPIO
wire [27:0] accel_io;

// XADC Analog to Digital Conversion

wire XADC_VP;
wire XADC_VN;

wire XADC_15P;
wire XADC_15N;

wire XADC_7P;
wire XADC_7N;

wire adc_control_o;

// Vacant pins
wire extras_o;
wire extras_2_io;
wire extras_3_io;

wire read_en1_i;
wire write_en1_i;
wire [19:0] addr1_i;
wire lb1_i;
wire ub1_i;
wire [15:0] data_in1_i;
wire [15:0] data_out1_o;

wire read_en2_i;
wire write_en2_i;
wire [19:0] addr2_i;
wire lb2_i;
wire ub2_i;
wire [15:0] data_in2_i;
wire [15:0] data_out2_o;

wire sram_clk_i;

assign sram_clk_i = clock_50_i;

/*
sram sram1(sram_clk_i,
    read_en1_i,
    write_en1_i,
    addr1_i,
    lb1_i,
    ub1_i,
    data_in1_i,
    data_out1_o);
sram sram2(sram_clk_i,
    read_en2_i,
    write_en2_i,
    addr2_i,
    lb2_i,
    ub2_i,
    data_in2_i,
    data_out2_o);

assign addr1_i = ~ram_cs_n_o ? ram_addr_o : 20'h0;
assign addr2_i = ram_cs_n_o ? ram_addr_o : 20'h0;
assign data_in1_i = (~ram_cs_n_o && ~ram_we_n_o) ? ram_data_io : 16'h0;
assign data_in2_i = (ram_cs_n_o && ~ram_we_n_o) ? ram_data_io : 16'h0;
assign ram_data_io = ram_we_n_o ? (~ram_cs_n_o ? data_in1_i : data_in2_i) : 16'bZZZZZZZZZZZZZZZZ;
assign lb1_i = ~ram_cs_n_o ? ~ram_lb_n_o : 1'b0;
assign ub1_i = ~ram_cs_n_o ? ~ram_ub_n_o : 1'b0;
assign lb2_i = ram_cs_n_o ? ~ram_lb_n_o : 1'b0;
assign ub2_i = ram_cs_n_o ? ~ram_ub_n_o : 1'b0;
assign read_en1_i = ~ram_cs_n_o ? ~ram_oe_n_o : 1'b0;
assign read_en2_i =~ram_cs_n_o ? ~ram_oe_n_o : 1'b0;
assign write_en1_i = ~ram_cs_n_o ? ~ram_we_n_o : 1'b0;
assign write_en2_i =~ram_cs_n_o ? ~ram_we_n_o : 1'b0; 
*/

wire read_en_i;
wire write_en_i;
wire [19:0] addr_i;
wire lb_i;
wire ub_i;
wire [15:0] data_in_i;
wire [15:0] data_out_o;

sram sram(sram_clk_i,
    read_en_i,
    write_en_i,
    addr_i,
    lb_i,
    ub_i,
    data_in_i,
    data_out_o);

assign addr_i = ram_addr_o;
assign data_in_i = ~ram_we_n_o ? ram_data_io : 16'h0;
assign ram_data_io = ram_we_n_o ? data_out_o : 'bz;
assign lb_i = ~ram_lb_n_o;
assign ub_i = ~ram_ub_n_o;
assign read_en_i = ~ram_oe_n_o && ~ram_cs_n_o;
assign write_en_i = ~ram_we_n_o && ~ram_cs_n_o;

nextp8 nextp8(
    // Clock
    clock_50_i,
    
    //SRAM (AS7C34096)
    ram_addr_o,
    ram_data_io,
    ram_lb_n_o,
    ram_ub_n_o,
    ram_oe_n_o,
    ram_we_n_o,
    ram_cs_n_o,

    // PS2
    ps2_clk_io,
    ps2_data_io,
    ps2_pin6_io,
    ps2_pin2_io,

    // SD Card
    sd_cs0_n_o,
    sd_cs1_n_o,
    sd_sclk_o,
    sd_mosi_o,
    sd_miso_i,

    // Flash
    flash_cs_n_o,
    flash_sclk_o,
    flash_mosi_o,
    flash_miso_i,
    flash_wp_o,
    flash_hold_o,

    // Joystick
    joyp1_i,
    joyp2_i,
    joyp3_i,
    joyp4_i,
    joyp6_i,
    joyp7_o,
    joyp9_i,
    joysel_o,

    // Audio
    audioext_l_o,
    audioext_r_o,
    audioint_o,

    // K7
    ear_port_i,
    mic_port_o,

    // Buttons
    btn_divmmc_n_i,
    btn_multiface_n_i,
    btn_reset_n_i,

    // Matrix keyboard
    keyb_row_o,
    keyb_col_i,

    // Bus
    bus_rst_n_io,
    bus_clk35_o,
    bus_addr_o,
    bus_data_io,
    bus_int_n_io,
    bus_nmi_n_i,
    bus_ramcs_i,
    bus_romcs_i,
    bus_wait_n_i,
    bus_halt_n_o,
    bus_iorq_n_o,
    bus_m1_n_o,
    bus_mreq_n_o,
    bus_rd_n_io,
    bus_wr_n_o,
    bus_rfsh_n_o,
    bus_busreq_n_i,
    bus_busack_n_o,
    bus_iorqula_n_i,
    bus_y_o,

    // VGA
    rgb_r_o,
    rgb_g_o,
    rgb_b_o,
    hsync_o,
    vsync_o,
    //output     csync_o,

    // HDMI
    hdmi_p_o,
    hdmi_n_o,

    // I2C (RTC and HDMI)
    i2c_scl_io,
    i2c_sda_io,

    // ESP
    esp_gpio0_io,
    esp_gpio2_io,
    esp_rx_i,
    esp_tx_o,
    esp_rtr_n_i,
    esp_cts_n_o,

    // PI GPIO
    accel_io,

    // XADC Analog to Digital Conversion

    XADC_VP,
    XADC_VN,

    XADC_15P,
    XADC_15N,

    XADC_7P,
    XADC_7N,

    adc_control_o,


    // Vacant pins
    extras_o,
    extras_2_io,
    extras_3_io
);

wire [5:0] post_code;

assign post_code = accel_io[27:22];

initial begin
    $monitor ("[$monitor] time=%0t ", $time, post_code);
end 

endmodule

module sram #(
    parameter ADDR_WIDTH = 20,
    parameter DATA_WIDTH = 16
) (
    input  wire                       clk_i,
    input  wire                       read_en_i,
    input  wire                       write_en_i,
    input  wire [ADDR_WIDTH-1:0]      addr_i,
    input  wire                       lb_i,
    input  wire                       ub_i,
    input  wire [DATA_WIDTH-1:0]      data_in_i,
    output reg  [DATA_WIDTH-1:0]      data_out_o
);

    // Declare the memory array
    reg [DATA_WIDTH-1:0] mem [2**ADDR_WIDTH-1:0];

    // Behavioral model for read and write
    always @(posedge clk_i) begin
        if (write_en_i) begin
            // Write operation
            if (lb_i)
                mem[addr_i][7:0] <= data_in_i[7:0];
            if (ub_i)
                mem[addr_i][15:7] <= data_in_i[15:7];
        end
    end

    // Read operation (combinational or sequential)
    always @(*) begin
        if (read_en_i && ~write_en_i) begin
            //$displayh(addr_i);
            //$displayh(mem[addr_i]);
            data_out_o = mem[addr_i];
        end else begin
            data_out_o = 'bz; // High impedance
        end
    end

    integer i;
    initial begin
        $display("Loading rom 1...");
        $readmemh("femto8-rom1.mem", mem);
        $display("Loading rom 2...");
        $readmemh("femto8-rom2.mem", mem, 'h40000);
        $display("Loading cart...");
        $readmemh("testcard.mem", mem, 'h80000);
    end

endmodule
