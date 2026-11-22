`timescale 1ns/1ps
module tb_ram_guard;
parameter integer CLK_NS=100;
localparam integer CLK_HZ=1000000000/CLK_NS;
reg clk=0, rst_n=0, ena=1;
always #(CLK_NS/2) clk=~clk;
wire [7:0] out_data, oe, gp;
wire boot_ready, boot_failed;
ctw_mcu_pads #(.CLK_HZ(CLK_HZ),.POWERUP_US(10)) dut(
 .clk(clk), .rst_n(rst_n), .ena(ena), .ui_in(8'b0), .uio_in(8'b0),
 .uo_out(gp), .uio_out(out_data), .uio_oe(oe), .boot_ready(boot_ready), .boot_failed(boot_failed)
);
time started;
task check_bank(input integer bank);
 begin
    rst_n=0; repeat (5) @(negedge clk);
    // Inject a stalled, selected bus in the pad mux, independent of whether
    // software can normally enter that state at the CPU/LSU.
    force dut.boot_ready=1'b1;
    if (bank==0) begin
        force dut.b_acs=1'b0;
        force dut.b_bcs=1'b1;
        force dut.cpu_acs=1'b0;
        force dut.cpu_bcs=1'b1;
    end else begin
        force dut.b_acs=1'b1;
        force dut.b_bcs=1'b0;
        force dut.cpu_acs=1'b1;
        force dut.cpu_bcs=1'b0;
    end
    @(negedge clk);rst_n=1;
    wait((bank==0 && !gp[5]) || (bank==1 && !gp[6]));
    started=$time;
    wait(dut.ram_timeout);
    #1;
    if ($time-started>6100 || $time-started<5800)
        $fatal(1,"guard ran at %0d ns, clock %0d ns", $time-started,CLK_NS);
    if (out_data!==8'hc1 || oe!==8'h09 || gp[7:5]!==3'b111 || dut.cpu_active)
        $fatal(1,"guard did not park CS/clock/DQ and reset CPU");
    #12000;
    if (gp[7:5]!==3'b111) $fatal(1,"guard was not sticky");
    rst_n=0;
    #1;
    if (gp[7:5]!==3'b111 || oe!==8'h00) $fatal(1,"reset did not release the QSPI bus");
    release dut.b_acs; release dut.b_bcs; release dut.cpu_acs; release dut.cpu_bcs; release dut.boot_ready;
    $display("PASS bank %0d watchdog at %0d MHz: deselect safely and latch failure until reset",bank,CLK_HZ/1000000);
 end
endtask
initial begin check_bank(0);check_bank(1);$finish; end
initial begin #100000;$fatal(1,"timeout");end
endmodule
