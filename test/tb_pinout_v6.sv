`timescale 1ns/1ps
module tb_pinout_v6;
    reg clk=0, rst_n=0, ena=1;
    always #50 clk=~clk;
    wire [7:0] uio_out, uio_oe, uo_out;
    wire boot_ready, boot_failed, ram_timeout;
    ctw_mcu_pads #(.CLK_HZ(10000000), .POWERUP_US(10)) dut (
        .clk(clk),.rst_n(rst_n),.ena(ena),.ui_in(8'h80),.uio_in(8'hff),
        .uo_out(uo_out),.uio_out(uio_out),.uio_oe(uio_oe),
        .boot_ready(boot_ready),.boot_failed(boot_failed),
        .gpio_debug(),.ram_timeout(ram_timeout)
    );
    initial begin
        repeat (2) @(negedge clk);
        if (uo_out[7:5]!==3'b111 || uio_oe!==8'h00)
            $fatal(1,"reset must deselect both PSRAMs and release all uio");
        #100 rst_n=1;
        force dut.boot_ready=1'b1;
        force dut.cpu_active=1'b1;
        force dut.gpio_out=8'h00;
        force dut.cpu_acs=1'b1;
        force dut.cpu_bcs=1'b1;
        repeat (5) @(negedge clk);
        if (uo_out[0]!==0 || uo_out[7:5]!==3'b111 || uio_oe[7:6]!==0)
            $fatal(1,"GPIO0/UART/CS default mapping failed");
        force dut.gpio_out=8'h01;
        repeat (2) @(negedge clk);
        if (uo_out[0]!==1 || uo_out[7:5]!==3'b111)
            $fatal(1,"GPIO0 not mapped to uo_out[0]");
        force dut.cpu_acs=1'b0;
        repeat (2) @(negedge clk);
        if (uo_out[5]!==0 || uo_out[6]!==1 || uio_oe[7:6]!==0)
            $fatal(1,"PSRAM A not mapped to uo_out[5]");
        force dut.cpu_acs=1'b1;
        force dut.cpu_bcs=1'b0;
        repeat (2) @(negedge clk);
        if (uo_out[5]!==1 || uo_out[6]!==0 || uio_oe[7:6]!==0)
            $fatal(1,"PSRAM B not mapped to uo_out[6]");
        rst_n=0;
        repeat (2) @(negedge clk);
        if (uo_out[7:5]!==3'b111 || uio_oe!==0)
            $fatal(1,"async reset did not release uio and deselect RAM");
        $display("PASS V6 pin remap: GPIO0=u0, PSRAM A=u5, B=u6, UART=u7, uio7:6 high-Z");
        $finish;
    end
    initial begin #10000; $fatal(1,"timeout"); end
endmodule
