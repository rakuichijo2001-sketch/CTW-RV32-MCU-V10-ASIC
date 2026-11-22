`timescale 1ns/1ps
// Unit test for TinyQV's nibble-serial GPR file. No full system/Flash needed.
module tb_v10_gp_tp_gpr;
  reg clk = 0;
  always #5 clk = ~clk;
  reg rstn = 0;
  reg wr_en = 0;
  reg [2:0] counter = 0;
  reg [3:0] rs1 = 0, rs2 = 0, rd = 0;
  reg [3:0] data_rd = 0;
  wire [3:0] data_rs1, data_rs2;
  wire [23:1] return_addr;
  tinyqv_registers #(.NUM_REGS(16), .REG_ADDR_BITS(4)) dut (
    .clk(clk), .rstn(rstn), .wr_en(wr_en), .counter(counter),
    .rs1(rs1), .rs2(rs2), .rd(rd), .data_rs1(data_rs1),
    .data_rs2(data_rs2), .data_rd(data_rd), .return_addr(return_addr)
  );

  task automatic write_then_read(input [3:0] index, input [31:0] value);
    integer k;
    reg [3:0] expected_nibble;
    begin
      for (k=0; k<8; k=k+1) begin
        @(negedge clk);
        wr_en = 1;
        rd = index;
        counter = k;
        data_rd = (value >> (4*k)) & 4'hf;
        @(posedge clk);
        #1;
      end
      wr_en = 0;
      rs1 = index;
      rs2 = index;
      for (k=0; k<8; k=k+1) begin
        expected_nibble = index == 0 ? 4'h0 : (value >> (4*k)) & 4'hf;
        #1;
        if (data_rs1 !== expected_nibble || data_rs2 !== expected_nibble) begin
          $display("FAIL reg x%0d, nibble %0d: got %h/%h expected %h", index, k, data_rs1, data_rs2, expected_nibble);
          $fatal(1, "GPR READ/WRITE FAILURE");
        end
        @(posedge clk);
        #1;
      end
    end
  endtask

  integer i;
  initial begin
    repeat (3) @(posedge clk);
    #1 rstn = 1;
    // Write 32-bit patterns in the 8 nibble slots used by TinyQV.
    write_then_read(4'd3,32'h1234_5678);
    write_then_read(4'd4,32'h8765_4321);
    write_then_read(4'd5,32'ha5f0_0a55);
    // x0 remains zero even when a store is attempted.
    write_then_read(4'd0,32'hffff_ffff);
    // Re-test write-after-write with opposite data and cross-read ports.
    write_then_read(4'd3,32'hfedc_ba98);
    write_then_read(4'd4,32'h1234_9876);
    rs1 = 4'd3;
    rs2 = 4'd4;
    for (i=0; i<8; i=i+1) begin
      #1;
      if (data_rs1 !== ((32'hfedc_ba98 >> (4*i)) & 4'hf) ||
          data_rs2 !== ((32'h1234_9876 >> (4*i)) & 4'hf)) begin
        $display("FAIL independent x3/x4, slot %0d: got %h/%h", i, data_rs1, data_rs2);
        $fatal(1, "TWO-PORT GPR FAILURE");
      end
      @(posedge clk);
      #1;
    end
    $display("PASS: x0 zero; x3/gp and x4/tp writable; other GPRs and read ports intact");
    $finish;
  end
endmodule
