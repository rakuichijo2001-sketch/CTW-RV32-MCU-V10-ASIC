// SPDX-License-Identifier: Apache-2.0
`default_nettype none
// Autonomous boot for W25Q128JVSIM (SPI + Quad I/O) and two APS6404L-3SQR-SN.
// Never writes the NOR array. If needed, sets a volatile copy of Flash QE.
module ctw_qspi_boot #(
    parameter integer CLK_HZ = 20000000,
    parameter integer POWERUP_US = 6000
)(
    input wire clk, rst_n,
    input wire [3:0] dq_in,
    output reg [3:0] dq_out, dq_oe,
    output reg sck, flash_cs_n, rama_cs_n, ramb_cs_n,
    output wire ready, failed
);
    localparam [4:0] F_EXIT=0, F_BUSY=1, F_SR2=2, F_VWE=3, F_WRITE=4,
                     F_CHECK=5, F_ARM=6, A_EXIT=7, A_WREN=8, A_RESET=9,
                     A_QUAD=10, B_EXIT=11, B_WREN=12, B_RESET=13,
                     B_QUAD=14, DONE=15, FAIL=16;
    localparam [2:0] POWER=0, GAP=1, LOW_PHASE=2, HIGH_PHASE=3,
                     HOLD_PHASE=4, EVAL=5;
    // Divide up, so nominal boot SCK is at most 2.5 MHz.
    localparam integer HALF = (CLK_HZ+4999999)/5000000;
    localparam integer US_CYCLES = (CLK_HZ+999999)/1000000;
    localparam integer POWER_CYCLES = US_CYCLES*POWERUP_US;
    localparam integer TW = $clog2(POWER_CYCLES+2);
    localparam integer HALF_INT=HALF-1, GUARD_INT=US_CYCLES-1, POWER_INT=POWER_CYCLES-1;
    localparam [TW-1:0] HALF_LAST=HALF_INT[TW-1:0];
    localparam [TW-1:0] GUARD=GUARD_INT[TW-1:0];
    localparam [TW-1:0] POWER_LAST=POWER_INT[TW-1:0];

    reg [4:0] step, index;
    reg [2:0] phase;
    reg [TW-1:0] timer;
    reg [7:0] received, sr2;
    reg [16:0] busy_retries;

    reg active;
    wire [1:0] target = step<=F_ARM ? 2'd0 : step<=A_QUAD ? 2'd1 : 2'd2;
    assign ready = step==DONE;
    assign failed = step==FAIL;

    reg [7:0] command;
    reg [4:0] last_index;
    wire [7:0] new_sr2 = (sr2 | 8'h02) & 8'h7f; // do not write SUS (RO)
    wire serial_read = step==F_BUSY || step==F_SR2 || step==F_CHECK;
    wire [2:0] tx_bit = 3'd7-index[2:0];
    always @* begin
        command=0;
        last_index=7;
        case(step)
            F_BUSY: begin command=8'h05; last_index=15; end
            F_SR2,F_CHECK: begin command=8'h35; last_index=15; end
            F_VWE: command=8'h50;
            F_WRITE: begin command=8'h31; last_index=15; end
            F_ARM: begin command=8'heb; last_index=21; end
            A_EXIT,B_EXIT: last_index=1;
            A_WREN,B_WREN: command=8'h66;
            A_RESET,B_RESET: command=8'h99;
            A_QUAD,B_QUAD: command=8'h35;
            default: ;
        endcase
        // All zero while waiting after power-up (AP Memory initialization).
        dq_out=4'h0;
        dq_oe=phase==POWER ? 4'hf : 4'h0;
        if (active) begin
            if (step==F_EXIT) begin
                dq_out=4'hf; dq_oe=4'hf; // 8 clocks with M4 high exit continuous read
            end else if (step==A_EXIT || step==B_EXIT) begin
                dq_out=index==0 ? 4'hf : 4'h5; dq_oe=4'hf;
            end
            else if (step==F_ARM && index>=8) begin
                if (index==14) dq_out=4'ha; // six 24-bit address nibbles, mode A0
                dq_oe=index<16 ? 4'hf : 4'h0; // four dummy clocks and two read nibbles
            end else if (target==0) begin
                dq_out={3'b110,index<8 ? command[tx_bit] : new_sr2[tx_bit]};
                dq_oe=serial_read && index>=8 ? 4'b1100 : 4'b1101;
            end else begin
                dq_out={3'b000,command[tx_bit]};
                dq_oe=4'b0001;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step<=F_EXIT; index<=0; received<=0; sr2<=0;
            phase<=POWER; timer<=0; busy_retries<=0;
            active<=0; sck<=0; flash_cs_n<=1; rama_cs_n<=1; ramb_cs_n<=1;
        end else if (!ready && !failed) begin
            case (phase)
                POWER: if (timer==POWER_LAST) begin phase<=GAP; timer<=GUARD; end
                       else timer<=timer+1'b1;
                GAP: if (timer==0) begin
                         index<=0; received<=0; phase<=LOW_PHASE; timer<=HALF_LAST;
                         active<=1; flash_cs_n<=target!=0;
                         rama_cs_n<=target!=1; ramb_cs_n<=target!=2;
                     end else timer<=timer-1'b1;
                LOW_PHASE: if (timer==0) begin
                    if (serial_read && index>=8) received<={received[6:0],dq_in[1]};
                    if (step==F_ARM && index>=20) received<={received[3:0],dq_in};
                    phase<=HIGH_PHASE; timer<=HALF_LAST; sck<=1;
                end else timer<=timer-1'b1;
                HIGH_PHASE: if (timer==0) begin
                    if (index==last_index) phase<=HOLD_PHASE;
                    else begin index<=index+1'b1; phase<=LOW_PHASE; end
                    timer<=HALF_LAST; sck<=0;
                end else timer<=timer-1'b1;
                HOLD_PHASE: if (timer==0) begin
                                phase<=EVAL; active<=0;
                                flash_cs_n<=1; rama_cs_n<=1; ramb_cs_n<=1;
                            end
                            else timer<=timer-1'b1;
                EVAL: begin
                    phase<=GAP; timer<=GUARD;
                    case (step)
                        F_BUSY: begin
                            if (!received[0]) step<=F_SR2;
                            else if (&busy_retries) step<=FAIL;
                            else busy_retries<=busy_retries+1'b1;
                        end
                        F_SR2: begin sr2<=received; step<=received[1] ? F_ARM : F_VWE; end
                        F_CHECK: step<=received[1] ? F_ARM : FAIL;
                        // FF is not a legal first byte of an RV32EC instruction.
                        // This is a blank/no-response guard, not an integrity check.
                        F_ARM: step<=received==8'hff ? FAIL : A_EXIT;
                        default: step<=step+1'b1;
                    endcase
                end
                default: phase<=POWER;
            endcase
        end
    end
endmodule
`default_nettype wire
