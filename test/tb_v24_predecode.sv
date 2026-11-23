`timescale 1ns/1ps
// V24: phase lookahead and conditional-branch target precomputation.
// Focused control test; full firmware tests still run separately.
module tb_v24_predecode;
    reg clk = 1'b0, rstn = 1'b0;
    always #10 clk = ~clk;
    tinyqv_cpu dut(
        .clk(clk), .rstn(rstn),
        .instr_fetch_started(1'b0), .instr_fetch_stopped(1'b0),
        .instr_data_in(16'h0001), .instr_ready(1'b0),
        .interrupt_req(4'b0), .data_ready(1'b0), .data_in(32'b0)
    );
    reg [23:1] expected_target;
    integer i;
    initial begin
        #200000; $fatal(1, "V24 control-unit timeout");
    end
    initial begin
        repeat (3) @(negedge clk);
        rstn = 1'b1;
        for (i = 0; i < 20; i = i + 1) begin
            @(negedge clk); #1;
            if (dut.i_core.last_count !== (dut.counter_hi == 3'd7))
                $fatal(1, "predecoded last_count skew at phase %d", dut.counter_hi);
        end
        $display("PASS V24 registered phase-7 lookahead");
        @(negedge clk);
        while (dut.counter_hi != 3'd5) @(negedge clk);
        dut.instr_data_start = 21'h00220;
        dut.pc_offset = 2'b01;
        force dut.imm = 32'h00000060;
        force dut.instr_valid = 1'b1;
        force dut.is_branch = 1'b1;
        force dut.branch = 1'b0;
        #1;
        expected_target = dut.pc[23:1] + dut.imm[23:1];
        @(negedge clk);
        if (dut.counter_hi !== 3'd6)
            $fatal(1, "Unexpected phase before address precomputation");
        @(posedge clk); #1;
        if (dut.early_branch_target_q !== expected_target)
            $fatal(1, "Early branch target wrong: got %h exp %h",
                dut.early_branch_target_q,expected_target);
        @(negedge clk);
        if (dut.counter_hi !== 3'd7) $fatal(1, "Branch phase changed");
        force dut.branch = 1'b1;
        @(posedge clk); #1;
        if (dut.pc[23:1] !== expected_target)
            $fatal(1, "Phase-7 redirect wrong: got %h exp %h",
                dut.pc[23:1],expected_target);
        release dut.branch;
        release dut.imm;
        release dut.instr_valid;
        release dut.is_branch;
        $display("PASS V24 lookahead branch target and zero-latency redirect");
        $finish;
    end
endmodule
