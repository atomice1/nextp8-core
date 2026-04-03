// PS/2 Keyboard Testbench
// Tests keyboard.sv (HOST) with keyboard_device.sv (DEVICE simulator)

`timescale 1ns/1ns

module tb_keyboard();

// Clock - 11 MHz system clock
reg clk = 0;
always #45.45 clk = ~clk;  // ~11 MHz

// Reset
reg reset = 1;

// PS/2 signals (shared between device and host) with pullups
tri1 ps2_clk;
tri1 ps2_data;

// Sniffer intercepts between keyboard DUT and shared bus
wire host_clk_from_dut;  // keyboard DUT ps2_clk_out
wire host_data_from_dut; // keyboard DUT ps2_data_out

// Device model outputs
wire device_clk_out;
wire device_data_out;

// Connect host outputs directly to bus (open-drain)
assign ps2_clk = (host_clk_from_dut === 1'b0) ? 1'b0 : 1'bz;
assign ps2_data = (host_data_from_dut === 1'b0) ? 1'b0 : 1'bz;

// Connect device outputs to bus (open-drain)
assign ps2_clk = (device_clk_out === 1'b0) ? 1'b0 : 1'bz;
assign ps2_data = (device_data_out === 1'b0) ? 1'b0 : 1'bz;

// Keyboard matrix output from DUT
wire [255:0] matrix;

// Pullup resistors for open-drain PS/2 lines (simulate 10k pullups)
pullup(ps2_clk);
pullup(ps2_data);

// Instantiate keyboard device model (PS/2 DEVICE)
keyboard_device #(
    .CLOCK_DIV(1100)  // 11MHz / 10kHz = 1100
) kbd_model (
    .clk(clk),
    .reset(reset),
    .ps2_clk_in(ps2_clk),
    .ps2_data_in(ps2_data),
    .ps2_clk_out(device_clk_out),
    .ps2_data_out(device_data_out)
);

// Instantiate keyboard module (PS/2 HOST - DUT)
keyboard #(
    .SIM(1),
    .VERBOSE(1)
) dut (
    .clk(clk),
    .reset(reset),
    .ps2_clk_in(ps2_clk),
    .ps2_data_in(ps2_data),
    .ps2_clk_out(host_clk_from_dut),
    .ps2_data_out(host_data_from_dut),
    .matrix(matrix)
);

// Instantiate PS/2 protocol sniffer (host intercept, device monitor-only)
ps2_sniffer #(
    .HOST_IS_TRISTATE(0),      // Host uses separate in/out (non-tristate)
    .DEVICE_IS_TRISTATE(0)     // Device uses separate in/out (non-tristate)
) sniffer (
    // Host side (non-tristate): separate in/out monitoring
    .host_ps2_clk_in_i(ps2_clk),              // Monitor shared bus CLK
    .host_ps2_data_in_i(ps2_data),            // Monitor shared bus DATA
    .host_ps2_clk_out_i(host_clk_from_dut),   // Monitor DUT CLK output (0=driving low, 1=released)
    .host_ps2_data_out_i(host_data_from_dut), // Monitor DUT DATA output (0=driving low, 1=released)

    // Device side (non-tristate): separate in/out monitoring
    .device_ps2_clk_in_i(ps2_clk),            // Monitor shared bus CLK
    .device_ps2_data_in_i(ps2_data),          // Monitor shared bus DATA
    .device_ps2_clk_out_i(device_clk_out),    // Monitor device CLK output
    .device_ps2_data_out_i(device_data_out)   // Monitor device DATA output
);

// Helper task to display set matrix bits
task display_matrix_bits(input [255:0] m);
    integer i;
    $display("  Matrix bits set:");
    for (i = 0; i < 256; i = i + 1) begin
        if (m[i]) $display("    [0x%02X]", i);
    end
endtask

// Test sequence
initial begin
    automatic integer pass_count = 0;
    automatic integer fail_count = 0;

    $display("=== Starting Keyboard Interface Test ===");

    // Reset
    reset = 1;
    #1000;
    reset = 0;
    #10000;

    // Wait for initialization to complete
    repeat(1000000) @(posedge clk);

    // Check that initialization actually completed
    if (dut.init_state != 5'd16) begin  // 5'd16 = INIT_DONE
        $display("FAIL: Keyboard initialization not complete. init_state=%0d (expected 15)", dut.init_state);
        $fatal(1);
    end
    $display("Keyboard initialization verified: init_state=INIT_DONE");

    // Test 1: Send make code and verify matrix bit is set
    $display("Test 1: Send make code 0x1C (A key) and verify matrix[0x1C] is set");
    kbd_model.send_scancode(8'h1C);
    repeat(50000) @(posedge clk);

    if (matrix[8'h1C] == 1'b1) begin
        $display("  PASS: Matrix bit [0x1C] set correctly");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Matrix bit [0x1C] = %b (expected 1)", matrix[8'h1C]);
        display_matrix_bits(matrix);
        fail_count = fail_count + 1;
    end
    #10000;

    // Test 2: Send break code and verify matrix bit is cleared
    $display("Test 2: Send break code 0xF0 0x1C and verify matrix[0x1C] is cleared");
    kbd_model.send_scancode(8'hF0);
    kbd_model.send_scancode(8'h1C);
    repeat(50000) @(posedge clk);

    if (matrix[8'h1C] == 1'b0) begin
        $display("  PASS: Matrix bit [0x1C] cleared correctly");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Matrix bit [0x1C] = %b (expected 0)", matrix[8'h1C]);
        display_matrix_bits(matrix);
        fail_count = fail_count + 1;
    end
    #10000;

    // Test 3: Send extended make code and verify matrix bit at 0x80|scancode
    $display("Test 3: Send extended code 0xE0 0x74 (Right Arrow) and verify matrix[0xF4] is set");
    kbd_model.send_scancode(8'hE0);
    kbd_model.send_scancode(8'h74);
    repeat(50000) @(posedge clk);

    if (matrix[8'h80 | 8'h74] == 1'b1) begin
        $display("  PASS: Matrix bit [0xF4] set correctly for extended code");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Matrix bit [0xF4] = %b (expected 1)", matrix[8'h80 | 8'h74]);
        display_matrix_bits(matrix);
        fail_count = fail_count + 1;
    end
    #10000;

    // Test 4: Send extended break code and verify matrix bit is cleared
    $display("Test 4: Send extended break 0xE0 0xF0 0x74 and verify matrix[0xF4] is cleared");
    kbd_model.send_scancode(8'hE0);
    kbd_model.send_scancode(8'hF0);
    kbd_model.send_scancode(8'h74);
    repeat(50000) @(posedge clk);

    if (matrix[8'h80 | 8'h74] == 1'b0) begin
        $display("  PASS: Matrix bit [0xF4] cleared correctly for extended break");
        pass_count = pass_count + 1;
    end else begin
        $display("  FAIL: Matrix bit [0xF4] = %b (expected 0)", matrix[8'h80 | 8'h74]);
        display_matrix_bits(matrix);
        fail_count = fail_count + 1;
    end
    #10000;

    $display("=== All tests completed ===");
    if (fail_count == 0) begin
        $display("ALL TESTS PASSED (%0d)", pass_count);
        $finish(0);
    end else begin
        $display("SOME TESTS FAILED (%0d passed, %0d failed)", pass_count, fail_count);
        $fatal(1);
    end
end

endmodule
