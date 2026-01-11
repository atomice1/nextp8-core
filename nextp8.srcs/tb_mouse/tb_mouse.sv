//////////////////////////////////////////////////////////////////////////////////
// tb_mouse.sv
// Mouse relative movement testbench
// Copyright (C) 2026 Chris January
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ns

module tb_mouse();

// Clock - 11 MHz system clock (matches nextp8 clk_sys)
reg clk = 0;
always #45.45 clk = ~clk;  // ~11 MHz

// Reset
reg reset = 1;

// PS/2 signals (shared between device and host) with pullups
tri1 ps2_clk;
tri1 ps2_data;

// Sniffer intercepts between mouse DUT and shared bus
wire host_clk_from_dut;  // mouse DUT ps2_clk_out
wire host_data_from_dut; // mouse DUT ps2_data_out

// Device model outputs
wire device_clk_out;
wire device_data_out;

// Intellimouse capability register (controls device model behavior)
reg intellimouse_cap = 1'b0;

// Connect host outputs directly to bus (open-drain)
assign ps2_clk = (host_clk_from_dut === 1'b0) ? 1'b0 : 1'bz;
assign ps2_data = (host_data_from_dut === 1'b0) ? 1'b0 : 1'bz;

// Connect device outputs to bus (open-drain)
assign ps2_clk = (device_clk_out === 1'b0) ? 1'b0 : 1'bz;
assign ps2_data = (device_data_out === 1'b0) ? 1'b0 : 1'bz;

// Pullup resistors for open-drain PS/2 lines (simulate 10k pullups)
pullup(ps2_clk);
pullup(ps2_data);

// Mouse outputs
wire signed [15:0] mouse_x;
wire signed [15:0] mouse_y;
wire signed [15:0] mouse_z;
wire [7:0] mouse_buttons;

// Mouse device model instantiation
mouse_device #(
    .CLOCK_DIV(1100)  // 11MHz / 10kHz = 1100
) mouse_model (
    .clk(clk),
    .reset(reset),
    .ps2_clk_in(ps2_clk),
    .ps2_data_in(ps2_data),
    .ps2_clk_out(device_clk_out),
    .ps2_data_out(device_data_out),
    .intellimouse_capable(intellimouse_cap)
);

// Instantiate mouse module (DUT)
mouse #(
    .SIM(1)
) dut (
    .clk(clk),
    .reset(reset),
    .ps2_clk_in(ps2_clk),
    .ps2_data_in(ps2_data),
    .ps2_clk_out(host_clk_from_dut),
    .ps2_data_out(host_data_from_dut),
    .mouse_x(mouse_x),
    .mouse_y(mouse_y),
    .mouse_z(mouse_z),
    .mouse_buttons(mouse_buttons)
);

// Instantiate PS/2 protocol sniffer
ps2_sniffer #(
    .HOST_IS_TRISTATE(0),      // Host uses separate in/out
    .DEVICE_IS_TRISTATE(0)     // Device uses separate in/out
) sniffer (
    // Host side (non-tristate)
    .host_ps2_clk_in_i(ps2_clk),
    .host_ps2_data_in_i(ps2_data),
    .host_ps2_clk_out_i(host_clk_from_dut),
    .host_ps2_data_out_i(host_data_from_dut),

    // Device side (non-tristate)
    .device_ps2_clk_in_i(ps2_clk),
    .device_ps2_data_in_i(ps2_data),
    .device_ps2_clk_out_i(device_clk_out),
    .device_ps2_data_out_i(device_data_out)
);

// Test stimulus
initial begin
    automatic integer pass_count = 0;
    automatic integer fail_count = 0;
    $display("===== Mouse Testbench Start =====");

    // Reset
    reset = 1;
    #1000;
    reset = 0;
    #10000;

    // Wait for initialization to complete
    repeat(1000000) @(posedge clk);

    // Check that initialization actually completed
    if (dut.init_state != 5'd24) begin  // 5'd24 = INIT_DONE
        $display("FAIL: Mouse initialization not complete. init_state=%0d (expected 24)", dut.init_state);
        $finish(1);
    end
    $display("Mouse initialization verified: init_state=INIT_DONE");

    // Verify Intellimouse mode is disabled since intellimouse_cap=0
    if (mouse_model.device_id_reg == 8'h00 && mouse_model.intellimouse_mode == 1'b0) begin
        $display("Intellimouse mode verified: disabled (standard 3-byte packets)");
        pass_count = pass_count + 1;
    end else begin
        $display("ERROR: Expected intellimouse_mode=0, got %0d", dut.intellimouse_mode);
        fail_count = fail_count + 1;
    end

    $display("\n[%0t] Test 1: Small positive movement (X=+5, Y=+3)", $time);
    mouse_model.send_movement_packet(1'b0, 1'b0, 1'b0, 9'sd5, 9'sd3, 4'sd0);
    repeat(50000) @(posedge clk);
    if (mouse_x != 8'sd5 || mouse_y != 8'sd3) begin
        $display("ERROR: Expected x=5, y=3, got x=%0d, y=%0d", mouse_x, mouse_y);
        fail_count = fail_count + 1;
    end
    else begin
        $display("PASS: Correct relative movement");
        pass_count = pass_count + 1;
    end

    $display("\n[%0t] Test 2: Negative movement (X=-10, Y=-15)", $time);
    mouse_model.send_movement_packet(1'b0, 1'b0, 1'b0, -9'sd10, -9'sd15, 4'sd0);
    repeat(50000) @(posedge clk);
    // Accumulates: x = 5 + (-10) = -5, y = 3 + (-15) = -12 (8-bit signed)
    if (mouse_x != -8'sd5 || mouse_y != -8'sd12) begin
        $display("ERROR: Expected x=-5, y=-12 (accumulated), got x=%0d, y=%0d", mouse_x, mouse_y);
        fail_count = fail_count + 1;
    end
    else begin
        $display("PASS: Correct negative movement (accumulated)");
        pass_count = pass_count + 1;
    end

    $display("\n[%0t] Test 3: Left button press (X=+1, Y=+1)", $time);
    mouse_model.send_movement_packet(1'b1, 1'b0, 1'b0, 9'sd1, 9'sd1, 4'sd0);
    repeat(50000) @(posedge clk);
    // Accumulates: x = -5 + 1 = -4, y = -12 + 1 = -11
    if (mouse_buttons[0] != 1'b1) begin
        $display("ERROR: Expected left button pressed, got buttons=%b", mouse_buttons);
        fail_count = fail_count + 1;
    end
    else begin
        $display("PASS: Left button detected");
        pass_count = pass_count + 1;
    end

    $display("\n[%0t] Test 4: Right button press (X=+2, Y=-2)", $time);
    mouse_model.send_movement_packet(1'b0, 1'b1, 1'b0, 9'sd2, -9'sd2, 4'sd0);
    repeat(50000) @(posedge clk);
    // Accumulates: x = -4 + 2 = -2, y = -11 + (-2) = -13
    if (mouse_buttons[1] != 1'b1) begin
        $display("ERROR: Expected right button pressed, got buttons=%b", mouse_buttons);
        fail_count = fail_count + 1;
    end
    else begin
        $display("PASS: Right button detected");
        pass_count = pass_count + 1;
    end

    $display("\n[%0t] Test 5: Middle button press (X=-5, Y=+5)", $time);
    mouse_model.send_movement_packet(1'b0, 1'b0, 1'b1, -9'sd5, 9'sd5, 4'sd0);
    repeat(100000) @(posedge clk);
    // Accumulates: x = -2 + (-5) = -7, y = -13 + 5 = -8
    if (mouse_buttons[2] != 1'b1) begin
        $display("ERROR: Expected middle button pressed, got buttons=%b", mouse_buttons);
        fail_count = fail_count + 1;
    end
    else begin
        $display("PASS: Middle button detected");
        pass_count = pass_count + 1;
    end

    $display("\n[%0t] Test 6: No movement, no buttons", $time);
    mouse_model.send_movement_packet(1'b0, 1'b0, 1'b0, 9'sd0, 9'sd0, 4'sd0);
    repeat(100000) @(posedge clk);
    // Final accumulated: x = -7 + 0 = -7, y = -8 + 0 = -8, no buttons
    if (mouse_x != -8'sd7 || mouse_y != -8'sd8 || mouse_buttons != 8'h00) begin
        $display("ERROR: Expected x=-7, y=-8, no buttons, got x=%0d, y=%0d, buttons=%b",
                 mouse_x, mouse_y, mouse_buttons);
        fail_count = fail_count + 1;
    end
    else begin
        $display("PASS: Idle state correct");
        pass_count = pass_count + 1;
    end

    // ========================================================================
    // Intellimouse (scroll wheel) tests
    // ========================================================================

    $display("\n[%0t] Test 7: Enable Intellimouse capability and verify auto-detection", $time);

    // Enable Intellimouse capability in device model
    intellimouse_cap = 1'b1;
    $display("  Set intellimouse_cap = 1");

    // Give the signal time to propagate before resetting
    repeat(100) @(posedge clk);

    // Reset mouse to trigger re-initialization with Intellimouse detection
    reset = 1'b1;
    repeat(100) @(posedge clk);
    reset = 1'b0;
    $display("  Reset asserted and released");

    // Wait for initialization to complete (includes magic sequence now)
    repeat(2000000) @(posedge clk);  // Longer wait for full magic sequence

    // Check that initialization completed
    if (dut.init_state != 5'd24) begin  // 5'd24 = INIT_DONE
        $display("ERROR: Mouse re-initialization not complete. init_state=%0d (expected 24)", dut.init_state);
        fail_count = fail_count + 1;
    end else begin
        $display("  Mouse re-initialization verified: init_state=INIT_DONE");
    end

    // Verify DUT detected Intellimouse mode automatically
    if (dut.intellimouse_mode == 1'b1) begin
        $display("PASS: DUT auto-detected Intellimouse mode (4-byte packets)");
        pass_count = pass_count + 1;
    end else begin
        $display("ERROR: DUT didn't detect Intellimouse mode, intellimouse_mode=%0d", dut.intellimouse_mode);
        $display("  Device model: ID=0x%02h, mode=%0d", mouse_model.device_id_reg, mouse_model.intellimouse_mode);
        fail_count = fail_count + 1;
    end

    // Send movement with scroll wheel: X=+3, Y=+2, Z=+5
    $display("\n[%0t] Test 8: Scroll wheel positive (Z=+5)", $time);
    mouse_model.send_movement_packet(1'b0, 1'b0, 1'b0, 9'sd3, 9'sd2, 4'sd5);
    repeat(100000) @(posedge clk);
    // Accumulates: x = -7 + 3 = -4, y = -8 + 2 = -6, z = 0 + 5 = 5
    if (mouse_z != 16'sd5) begin
        $display("ERROR: Expected z=5, got z=%0d", mouse_z);
        fail_count = fail_count + 1;
    end
    else begin
        $display("PASS: Scroll wheel positive detected");
        pass_count = pass_count + 1;
    end

    $display("\n[%0t] Test 9: Scroll wheel negative (Z=-3)", $time);
    mouse_model.send_movement_packet(1'b0, 1'b0, 1'b0, 9'sd0, 9'sd0, -4'sd3);
    repeat(100000) @(posedge clk);
    // Accumulates: z = 5 + (-3) = 2
    if (mouse_z != 16'sd2) begin
        $display("ERROR: Expected z=2 (accumulated), got z=%0d", mouse_z);
        fail_count = fail_count + 1;
    end
    else begin
        $display("PASS: Scroll wheel negative (accumulated)");
        pass_count = pass_count + 1;
    end

    #1000;
    $display("\n===== Mouse Testbench Complete =====");
    if (fail_count == 0) begin
        $display("ALL TESTS PASSED (%0d)", pass_count);
        $finish(0);
    end else begin
        $display("SOME TESTS FAILED (%0d passed, %0d failed)", pass_count, fail_count);
        $finish(1);
    end
end

endmodule
