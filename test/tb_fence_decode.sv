`timescale 1ns/1ps
// Decode liveness regression for a representative base FENCE instruction.
// Run with: make test-v10-fence
module tb_fence_decode;
    reg [31:0] instr;
    wire [31:0] imm;
    wire ld, ai, au, st, ar, lui, br, jr, j, ret, sys;
    wire [2:1] ilen;
    wire [3:0] op, rs1, rs2, rd;
    wire [2:0] memop, amo;
    wire meminc;
    tinyqv_decoder dut (
       .instr(instr), .imm(imm), .is_load(ld), .is_alu_imm(ai),
       .is_auipc(au), .is_store(st), .is_alu_reg(ar), .is_lui(lui),
       .is_branch(br), .is_jalr(jr), .is_jal(j), .is_ret(ret),
       .is_system(sys), .instr_len(ilen), .alu_op(op), .mem_op(memop),
       .rs1(rs1), .rs2(rs2), .rd(rd),
       .additional_mem_ops(amo), .mem_op_increment_reg(meminc)
    );
    initial begin
        instr=32'h0ff0000f; #1;
        if (!(ai && rd==0 && rs1==0 && imm==0 && op==0))
            $fatal(1, "FENCE did not decode as architecturally inert operation");
        instr=32'h00000013; #1;
        if (!(ai && rd==0 && rs1==0 && imm==0 && op==0))
            $fatal(1, "ADDI x0,x0,0 broken");
        instr=32'h0000100f; #1;
        if (ai) $fatal(1, "FENCE.I accidentally treated as implemented FENCE");
        $display("PASS: FENCE decode safety and baseline ADDI");
        $finish;
    end
endmodule
