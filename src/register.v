/* Register file for TinyQV.

    RV32E architectural register file: x0 hard-wired zero, x1..x15 writable.
    Previous TinyQV revision hard-wired x3/gp and x4/tp to special constants,
    violating RV32E general-register semantics. This revision makes both
    ordinary registers while retaining the existing nibble-serial datapath.
    4-bit access and the registers are always rotated by 4 bits every clock.
 */

module tinyqv_registers #(parameter NUM_REGS=16, parameter REG_ADDR_BITS=4) (
    input clk,
    input rstn,
    input wr_en,
    input [2:0] counter,
    input [REG_ADDR_BITS-1:0] rs1,
    input [REG_ADDR_BITS-1:0] rs2,
    input [REG_ADDR_BITS-1:0] rd,
    output [3:0] data_rs1,
    output [3:0] data_rs2,
    input [3:0] data_rd,
    output [23:1] return_addr
);

    reg [31:0] registers [1:NUM_REGS-1];
    wire [3:0] reg_access [0:2**REG_ADDR_BITS-1];

    genvar i;
    generate
        for (i = 0; i < 2**REG_ADDR_BITS; i = i + 1) begin : gen_reg_bank
            if (i == 0 || i >= NUM_REGS) begin : gen_reg_zero
                assign reg_access[i] = 0;
            end else begin : gen_reg_normal
                always @(posedge clk) begin
                    if (wr_en && rd == i)
                        registers[i][3:0] <= data_rd;
                    else
                        registers[i][3:0] <= registers[i][7:4];
                end

                wire [31:4] reg_buf;
                `ifdef SIM
                buf #1 i_regbuf[31:4] (reg_buf, {registers[i][3:0], registers[i][31:8]});
                `elsif ICE40
                assign reg_buf = {registers[i][3:0], registers[i][31:8]};
                `elsif SCL_sky130_fd_sc_hd
                sky130_fd_sc_hd__dlygate4sd3_1 i_regbuf[31:4] ( .X(reg_buf), .A({registers[i][3:0], registers[i][31:8]}) );
                `else
                assign reg_buf = {registers[i][3:0], registers[i][31:8]};
                `endif
                always @(posedge clk) registers[i][31:4] <= reg_buf;

                assign reg_access[i] = registers[i][7:4];
            end
        end
    endgenerate

    assign data_rs1 = reg_access[rs1];
    assign data_rs2 = reg_access[rs2];
    assign return_addr = registers[1][31:9];

    // The serial register file has no architectural reset requirement.
    // Reset/interrupt handling and the first use of registers are handled by
    // the CPU/startup sequence; the unused reset/counter ports are retained
    // for source/interface compatibility with the known-good V10 design.
    wire _unused = &{rstn, counter, 1'b0};

endmodule
