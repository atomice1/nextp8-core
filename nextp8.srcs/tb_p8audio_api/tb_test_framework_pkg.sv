`timescale 1ns/1ps

package tb_test_framework_pkg;
    int tf_total = 0;
    int tf_pass = 0;
    int tf_fail = 0;

    task automatic tf_init();
        tf_total = 0;
        tf_pass = 0;
        tf_fail = 0;
    endtask

    task automatic tf_start_suite(input string name);
        $display("=== Test Suite: %s ===", name);
    endtask

    task automatic tf_start_test(input string name);
        tf_total++;
        $display("Test %0d: %s", tf_total, name);
    endtask

    task automatic tf_end_test(input string name, input bit pass);
        if (pass) begin
            tf_pass++;
            $display("  PASS: %s", name);
        end else begin
            tf_fail++;
            $display("  FAIL: %s", name);
        end
    endtask

    task automatic tf_summary();
        $display("=== Summary ===");
        $display("Total: %0d", tf_total);
        $display("Pass:  %0d", tf_pass);
        $display("Fail:  %0d", tf_fail);
        if (tf_fail != 0) begin
            $display("OVERALL: FAIL");
        end else begin
            $display("OVERALL: PASS");
        end
    endtask
endpackage
