// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps
module tb_gpio_bidir_v7;
    reg clk=0, rst_n=0, ena=1;
    always #50 clk=~clk;
    reg [1:0] stimulus=0;
    wire [7:0] uio_in={stimulus,6'b000001};
    wire [7:0] uio_out, uio_oe, uo_out;
    wire boot_ready, boot_failed, ram_timeout;
    ctw_mcu_pads #(.CLK_HZ(10000000), .POWERUP_US(10)) dut (
        .clk(clk),.rst_n(rst_n),.ena(ena),.ui_in(8'h80),.uio_in(uio_in),
        .uo_out(uo_out),.uio_out(uio_out),.uio_oe(uio_oe),
        .boot_ready(boot_ready),.boot_failed(boot_failed),
        .gpio_debug(),.ram_timeout(ram_timeout)
    );
    integer i;
    initial begin
        repeat (2) @(negedge clk);
        if (uio_oe!==8'h00 || uo_out[6:5]!==2'b11)
            $fatal(1,"reset must high-Z uio[7:6] and deselect RAM");
        rst_n=1;
        force dut.boot_ready=1'b1;
        force dut.cpu_active=1'b1;
        force dut.bidir_out=2'b00;
        force dut.bidir_dir=2'b00;
        force dut.cpu_acs=1'b1;
        force dut.cpu_bcs=1'b1;
        repeat (5) @(negedge clk);
        if (uio_oe[7:6]!==2'b00)
            $fatal(1,"default state must remain high-Z");
        for (i=0;i<4;i=i+1) begin
            stimulus=i;
            repeat (4) @(negedge clk);
            if (dut.mcu_i.bidir_sync!==stimulus)
                $fatal(1,"GPIO bidir sampled input wrong pattern=%0d read=%b",i,dut.mcu_i.bidir_sync);
        end
        // Firmware controls these registers with MMIO DIR and OUT. Force
        // their values at the pad boundary to verify all four output codes.
        for (i=0;i<4;i=i+1) begin
            case (i)
                0: force dut.bidir_out=2'b00;
                1: force dut.bidir_out=2'b01;
                2: force dut.bidir_out=2'b10;
                3: force dut.bidir_out=2'b11;
            endcase
            force dut.bidir_dir=2'b11;
            @(negedge clk);
            if (uio_oe[7:6]!==2'b11 || uio_out[7:6]!==i[1:0])
                $fatal(1,"GPIO bidir output failed pattern=%0d oe=%b out=%b",i,uio_oe[7:6],uio_out[7:6]);
        end
        force dut.bidir_dir=2'b00;
        @(negedge clk);
        if (uio_oe[7:6]!==2'b00)
            $fatal(1,"software did not release bidir outputs");
        force dut.bidir_dir=2'b11;
        #1 rst_n=0;
        #1;
        if (uio_oe!==8'h00 || uo_out[6:5]!==2'b11)
            $fatal(1,"raw reset did not release GPIO and select lines");
        #2 rst_n=1;
        repeat (4) @(negedge clk);
        ena=0;
        #1;
        if (uio_oe!==8'h00) $fatal(1,"ena=0 must release bidir");
        $display("PASS V7 GPIO bidir: 4 input patterns, 4 outputs, software high-Z, reset/ena high-Z");
        $finish;
    end
    initial begin #20000; $fatal(1,"timeout"); end
endmodule
