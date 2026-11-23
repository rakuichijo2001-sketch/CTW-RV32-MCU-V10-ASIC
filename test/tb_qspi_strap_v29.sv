// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps
module tb_qspi_strap_v29;
    reg clk=0, rst_n=0, ena=1;
    reg [7:0] ui_in=8'h02; // GPIO1=1: short-pad QSPI phase
    wire [7:0] uo_out, uio_out, uio_oe;
    wire boot_ready, boot_failed, ram_timeout;
    always #50 clk=~clk;

    ctw_mcu_pads #(
        .CLK_HZ(10000000), .POWERUP_US(10),
        .QSPI_READ_DELAY_CFG(3'b010), .QSPI_READ_STRAP_EN(1)
    ) dut (
        .ui_in(ui_in), .uio_in(8'hff),
        .uo_out(uo_out), .uio_out(uio_out), .uio_oe(uio_oe),
        .clk(clk), .rst_n(rst_n), .ena(ena),
        .boot_ready(boot_ready), .boot_failed(boot_failed),
        .gpio_debug(), .ram_timeout(ram_timeout)
    );

    initial begin
        repeat (3) @(negedge clk);
        rst_n=1;
        repeat (5) @(negedge clk);
        if (dut.qspi_read_delay_selected !== 3'b001)
            $fatal(1,"Short-pad strap was not captured after external reset");
        // Normal runtime GPIO changes cannot alter the latched QSPI phase.
        ui_in[1]=0;
        repeat (4) @(negedge clk);
        if (dut.qspi_read_delay_selected !== 3'b001)
            $fatal(1,"Runtime GPIO1 unexpectedly changed QSPI phase");
        force dut.wdt_reboot = 1'b1;
        repeat (4) @(negedge clk);
        if (dut.qspi_read_delay_selected !== 3'b001)
            $fatal(1,"Watchdog reboot re-sampled runtime GPIO1");
        release dut.wdt_reboot;
        // External reset is the only event that permits re-strapping.
        rst_n=0;
        repeat (3) @(negedge clk);
        rst_n=1;
        repeat (5) @(negedge clk);
        if (dut.qspi_read_delay_selected !== 3'b010)
            $fatal(1,"External reset failed to capture 30ns pad phase");
        ui_in[6:4]=3'b111;
        repeat (3) @(negedge clk);
        if (dut.qspi_read_delay_selected !== 3'b010)
            $fatal(1,"Live sensor data changed QSPI phase");
        $display("PASS V29 QSPI strap: latched external reset, unchanged by sensor/runtime GPIO/watchdog");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1,"QSPI strap test timeout");
    end
endmodule
