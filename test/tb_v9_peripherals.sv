// SPDX-License-Identifier: Apache-2.0
// Isolated PWM + I2C smoke bench. Run with `make test-v9-rtl` (Icarus).
`timescale 1ns/1ps
module tb_v9_peripherals;
    reg clk=0, rst_n=0;
    always #10 clk=~clk; // 50 MHz
    reg pwm_en=0;
    wire pwm0, pwm1;
    ctw_pwm dut_pwm(.clk(clk),.rst_n(rst_n),.enable(pwm_en),
        .divider(16'd3),.duty0(8'd64),.duty1(8'd192),
        .pwm0(pwm0),.pwm1(pwm1));
    reg i2c_en=0, i2c_start=0;
    reg [1:0] i2c_op=0;
    reg [6:0] i2c_addr=7'h42;
    reg [7:0] i2c_tx=8'h5a;
    reg slave_sda_low=0;
    wire scl_low, sda_low;
    tri1 scl_bus;
    tri1 sda_bus;
    assign scl_bus = scl_low ? 1'b0 : 1'bz;
    assign sda_bus = sda_low ? 1'b0 : 1'bz;
    assign sda_bus = slave_sda_low ? 1'b0 : 1'bz;
    wire [7:0] i2c_rx;
    wire busy, done, nack, timeout;
    ctw_i2c_master dut_i2c(.clk(clk),.rst_n(rst_n),.enable(i2c_en),
        .start(i2c_start),.operation(i2c_op),.slave_addr(i2c_addr),
        .tx_byte(i2c_tx),.half_period(16'd7),
        .scl_in(scl_bus),.sda_in(sda_bus),
        .scl_drive_low(scl_low),.sda_drive_low(sda_low),
        .rx_byte(i2c_rx),.busy(busy),.done(done),.nack(nack),.timeout(timeout));
    integer n, high0, high1;
    task kick;
        input [1:0] op;
        begin
            @(negedge clk); i2c_op=op; i2c_start=1;
            @(negedge clk); i2c_start=0;
        end
    endtask
    task wait_result;
        integer j;
        begin
            j=0;
            while (!done && j<5000) begin @(posedge clk); j=j+1; end
            if(!done || busy || timeout) $fatal(1,"I2C timeout/stuck: done=%b busy=%b timeout=%b",done,busy,timeout);
        end
    endtask
    task ack_byte;
        integer k;
        begin
            for(k=0;k<8;k=k+1) @(posedge scl_bus);
            @(negedge scl_bus); slave_sda_low=1;
            @(negedge scl_bus); slave_sda_low=0;
        end
    endtask
    initial begin
        repeat (6) @(negedge clk); rst_n=1; pwm_en=1;
        repeat (1024) @(negedge clk);
        high0=0; high1=0;
        for(n=0;n<1024;n=n+1) begin
            @(negedge clk);
            if(pwm0) high0=high0+1;
            if(pwm1) high1=high1+1;
        end
        if(high0!=256 || high1!=768)
            $fatal(1,"PWM duty wrong: %0d / %0d expected 256/768",high0,high1);
        $display("PWM PASS: 25%% and 75%%");
        // No slave: addresses must NACK and STOP, never push SDA high.
        i2c_en=1;
        kick(2'd0);
        wait_result();
        if (!nack || sda_low || scl_low) $fatal(1,"I2C NACK/STOP incorrect");
        $display("I2C NACK/STOP PASS");
        // New command must clear old NACK status; slave ACKs address+data.
        fork
            begin
                @(negedge sda_bus); // START
                ack_byte(); // address 0x42, write
                ack_byte(); // value 0x5A
            end
            begin
                kick(2'd0);
                wait_result();
                if(nack || timeout) $fatal(1,"I2C write ACK missing");
                $display("I2C WRITE ACK PASS");
            end
        join
        $display("PASS V9 PWM + basic I2C");
        $finish;
    end
endmodule
