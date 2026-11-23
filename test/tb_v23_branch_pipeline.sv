`timescale 1ns/1ps
// V23 pipeline-control unit test. The comparator outcome is injected only to
// isolate the branch resolution boundary; real firmware execution is tested by
// the normal RTL and gate-level boot regressions.
module tb_v23_branch_pipeline;
    reg clk = 1'b0;
    reg rstn = 1'b0;
    always #10 clk = ~clk;

    wire [23:1] instr_addr;
    wire instr_fetch_restart, instr_fetch_stall;
    wire [27:0] data_addr;
    wire [1:0] data_write_n, data_read_n;
    wire data_read_complete;
    wire [31:0] data_out;
    wire data_continue;
    wire debug_instr_complete, debug_instr_valid;
    wire debug_interrupt_pending, debug_branch;
    wire debug_early_branch, debug_ret, debug_reg_wen, debug_counter_0;
    wire [3:0] debug_rd;

    tinyqv_cpu dut (
        .clk(clk), .rstn(rstn),
        .instr_addr(instr_addr),
        .instr_fetch_restart(instr_fetch_restart),
        .instr_fetch_stall(instr_fetch_stall),
        .instr_fetch_started(1'b0), .instr_fetch_stopped(1'b0),
        .instr_data_in(16'h0001), .instr_ready(1'b0),
        .interrupt_req(4'b0000),
        .data_addr(data_addr), .data_write_n(data_write_n),
        .data_read_n(data_read_n), .data_read_complete(data_read_complete),
        .data_out(data_out), .data_continue(data_continue),
        .data_ready(1'b0), .data_in(32'b0),
        .debug_instr_complete(debug_instr_complete),
        .debug_instr_valid(debug_instr_valid),
        .debug_interrupt_pending(debug_interrupt_pending),
        .debug_branch(debug_branch), .debug_early_branch(debug_early_branch),
        .debug_ret(debug_ret), .debug_reg_wen(debug_reg_wen),
        .debug_counter_0(debug_counter_0), .debug_rd(debug_rd)
    );

    reg [23:1] target_expected;

    task automatic reset_cpu;
        begin
            @(negedge clk); rstn = 1'b0;
            repeat (3) @(negedge clk);
            rstn = 1'b1;
        end
    endtask

    task automatic wait_last_phase;
        begin
            @(negedge clk);
            while (dut.counter_hi !== 3'd7) @(negedge clk);
        end
    endtask

    initial begin
        #200000;
        $fatal(1, "V23 branch pipeline unit timeout");
    end

    initial begin
        reset_cpu();
        wait_last_phase();
        // Emulate the last nibble of a taken conditional branch. Keep the
        // operands and branch type stable across its sampling edge.
        dut.instr_data_start = 21'h00220;
        dut.pc_offset = 2'b01;
        force dut.imm = 32'h00000040;  // +0x40 bytes
        force dut.is_branch = 1'b1;
        force dut.instr_valid = 1'b1;
        force dut.branch_from_core = 1'b1;
        target_expected = dut.pc[23:1] + dut.imm[23:1];
        if (dut.branch !== 1'b0)
            $fatal(1, "Conditional branch must not redirect combinationally");
        @(posedge clk); #1;
        if (dut.branch_taken_pipe !== 1'b1 ||
            dut.branch_target_pipe !== target_expected)
            $fatal(1, "Taken branch not captured in pipeline");
        if (dut.instr_valid_core !== 1'b0 || dut.branch !== 1'b1)
            $fatal(1, "Speculative fallthrough not squashed");
        release dut.imm;
        release dut.is_branch;
        release dut.instr_valid;
        release dut.branch_from_core;
        @(posedge clk); #1;
        if (dut.pc[23:1] !== target_expected)
            $fatal(1, "Registered branch target not committed");
        if (dut.branch_taken_pipe !== 1'b0)
            $fatal(1, "Branch pipeline did not clear after redirect");
        $display("PASS V23 taken-branch capture/flush/redirect");

        reset_cpu();
        wait_last_phase();
        force dut.is_branch = 1'b1;
        force dut.instr_valid = 1'b1;
        force dut.branch_from_core = 1'b0;
        @(posedge clk); #1;
        if (dut.branch_taken_pipe !== 1'b0 || dut.branch !== 1'b0)
            $fatal(1, "Untaken conditional branch redirected");
        release dut.is_branch;
        release dut.instr_valid;
        release dut.branch_from_core;
        $display("PASS V23 not-taken branch preserves fallthrough");

        reset_cpu();
        wait_last_phase();
        force dut.is_branch = 1'b0;
        force dut.instr_valid = 1'b1;
        force dut.branch_from_core = 1'b1;
        #1; // permit continuous assignments to settle after hierarchical force
        if (dut.branch !== 1'b1)
            $fatal(1, "Nonconditional redirect must retain original cycle (branch=%b raw=%b is_branch=%b valid=%b pipe=%b)",
                dut.branch, dut.branch_from_core, dut.is_branch, dut.instr_valid, dut.branch_taken_pipe);
        @(posedge clk); #1;
        if (dut.branch_taken_pipe !== 1'b0)
            $fatal(1, "Nonconditional redirect must not enter branch pipeline");
        release dut.is_branch;
        release dut.instr_valid;
        release dut.branch_from_core;
        $display("PASS V23 direct JAL/system redirect remains unpipelined");
        $finish;
    end
endmodule
