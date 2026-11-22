// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps
module tb_v10_watchdog;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,active=0,enable=0,kick=0;
    reg [15:0] timeout_ms=10;
    wire reboot,last_reset;
    wire [7:0] event_count;
    wire [15:0] elapsed_ms;
    // Unit-test scaled clock 10kHz: 10 cycles = 1ms
    ctw_sys_watchdog #(.CLK_HZ(10000),.HOLD_CYCLES(4)) dut(
        .clk(clk),.rst_n(rst_n),.active(active),.enable(enable),
        .timeout_ms(timeout_ms),.kick(kick),.reboot(reboot),
        .last_reset(last_reset),.event_count(event_count),.elapsed_ms(elapsed_ms)
    );
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        active=1;
        repeat(150) @(negedge clk);
        if (reboot || event_count!=0) $fatal(1,"watchdog triggered while disabled");
        enable=1;
        repeat(70) @(negedge clk);
        if (reboot) $fatal(1,"watchdog triggered before timeout");
        kick=1;
        @(negedge clk); kick=0;
        repeat(70) @(negedge clk);
        if (reboot) $fatal(1,"feed did not reload watchdog");
        wait(reboot);
        if (event_count!=1 || !last_reset) $fatal(1,"failed to latch WDT cause");
        enable=0; // CPU's configuration resets during reboot
        repeat(6) @(negedge clk);
        if(reboot || event_count!=1 || !last_reset)
            $fatal(1,"reboot did not terminate / history lost");
        active=0;
        rst_n=0;
        repeat(3) @(negedge clk);
        if(event_count!=0 || last_reset || reboot)
            $fatal(1,"external reset failed to clear history");
        $display("PASS V10 WATCHDOG: disable, feed, autonomous reset, retained cause, external reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"watchdog testbench timed out"); end
endmodule
