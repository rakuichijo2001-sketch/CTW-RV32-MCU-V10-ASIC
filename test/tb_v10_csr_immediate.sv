`timescale 1ns/1ps
// Run with: make test-v10-csr-rtl
// Module-level CSR immediate test. Does NOT replace system-level ISA/PSRAM tests.
module tb_v10_csr_immediate;
  reg clk = 1'b0;
  always #5 clk = ~clk;
  reg rstn = 1'b0;
  reg [2:0] counter = 0;
  reg [3:0] alu_op = 4'b0101; // CSR*I funct3=101
  reg [4:0] csr_zimm = 5'd0;
  wire [3:0] data_out;
  wire [27:0] addr_out;
  wire address_ready, instr_complete, branch;
  wire [23:1] return_addr;
  wire interrupt_pending, debug_reg_wen;
  wire [3:0] debug_rd;
  integer i;

  tinyqv_core dut (
    .clk(clk), .rstn(rstn), .imm(4'b0000), .imm_lo(12'h341),
    .csr_zimm(csr_zimm),
    .is_load(1'b0), .is_alu_imm(1'b0), .is_auipc(1'b0),
    .is_store(1'b0), .is_alu_reg(1'b0), .is_lui(1'b0),
    .is_branch(1'b0), .is_jalr(1'b0), .is_jal(1'b0),
    .is_system(1'b1), .is_interrupt(1'b0), .is_stall(1'b0),
    .alu_op(alu_op), .mem_op(3'b000),
    .rs1(4'd0), .rs2(4'd0), .rd(4'd0),
    .counter(counter), .pc(4'b0), .next_pc(4'b0),
    .data_in(4'b0), .load_data_ready(1'b0),
    .data_out(data_out), .addr_out(addr_out),
    .address_ready(address_ready), .instr_complete(instr_complete),
    .branch(branch), .return_addr(return_addr),
    .interrupt_req(4'b0), .interrupt_pending(interrupt_pending),
    .debug_reg_wen(debug_reg_wen), .debug_rd(debug_rd)
  );

  task csr_cycle(input [3:0] operation, input [4:0] immediate,
                 input [23:0] expected, input integer id);
    integer j;
    begin
      for (j=0;j<8;j=j+1) begin
        @(negedge clk);
        alu_op=operation;
        csr_zimm=immediate;
        counter=j[2:0];
        @(posedge clk);
        #1;
      end
      if (dut.mepc !== expected) begin
        $display("CSR TEST FAIL ID=%0d mepc=%06h expected=%06h",id,dut.mepc,expected);
        $fatal(1);
      end
    end
  endtask

  initial begin
    for (i=0;i<8;i=i+1) begin
      @(negedge clk);
      counter=i[2:0];
      @(posedge clk); #1;
    end
    rstn=1'b1;
    csr_cycle(4'b0101,5'd16,24'd16,225); // CSRRWI 16
    csr_cycle(4'b0101,5'd30,24'd30,226); // CSRRWI 30
    csr_cycle(4'b0111,5'd16,24'd14,227); // CSRRCI 16
    csr_cycle(4'b0110,5'd16,24'd30,228); // CSRRSI 16
    csr_cycle(4'b0110,5'd0,24'd30,229); // CSRRSI 0 (no-op)
    csr_cycle(4'b0111,5'd0,24'd30,230); // CSRRCI 0 (no-op)
    $display("PASS: CSR immediate test IDs 225..230");
    $finish;
  end
endmodule
