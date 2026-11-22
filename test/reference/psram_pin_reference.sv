`timescale 1ns/1ps
// Simulation-only QPI protocol reference constructed from APS6404L-3SQR
// Table 2 and Figures 15 and 16. Captures on SCK rising and drives the next
// output nibble tACLK after SCK falling. No dependency on FPGA model FSM.
module ctw_psram_reference #(
    parameter integer MEM_BYTES=4096, ADDR_W=$clog2(MEM_BYTES), STRICT_BACKING=1
)(
    input wire clk,rstn,cs_n,sck,
    input wire [3:0] dq_from_master,dq_master_oe,
    output wire [3:0] dq_to_master, drive_oe
);
    reg [7:0] mem[0:MEM_BYTES-1];
    // A sparse top-of-bank window makes the highest real addresses testable
    // without allocating a full 8 MiB in both simulated parts.
    reg [7:0] high_mem[0:31];
    localparam integer HIGH_BASE=8388576;
    function automatic [7:0] at_address(input integer at);
        if (at<MEM_BYTES) at_address=mem[at];
        else if (at>=HIGH_BASE && at<8388608) at_address=high_mem[at-HIGH_BASE];
        else at_address=8'hff;
    endfunction
    integer clocks=0;
    integer byte_addr;
    reg [7:0] opcode;
    reg [23:0] target;
    reg [3:0] write_high;
    reg [3:0] launched;
    assign #(5.5) dq_to_master=launched;
    reg valid;
    assign #(5.5) drive_oe=valid ? 4'hf : 4'h0;
    always @(posedge cs_n or negedge rstn or posedge sck) begin
        if (cs_n || !rstn) begin clocks=0; opcode=0; target=0; write_high=0; end
        else begin
            if (clocks<2) begin
                if (dq_master_oe!==4'hf) $fatal(1,"missing QPI opcode drive");
                opcode={opcode[3:0],dq_from_master};
            end else if ((opcode==8'heb || opcode==8'h02) && clocks<8) begin
                if (dq_master_oe!==4'hf) $fatal(1,"missing 24-bit address drive");
                target={target[19:0],dq_from_master};
            end else if (opcode==8'h02) begin
                if (dq_master_oe!==4'hf) $fatal(1,"missing QPI payload drive");
                byte_addr=int'(target)+((clocks-8)/2);
                if (clocks%2==0) write_high=dq_from_master;
                else if (byte_addr<MEM_BYTES) mem[byte_addr]={write_high,dq_from_master};
                else if (byte_addr>=HIGH_BASE && byte_addr<8388608)
                    high_mem[byte_addr-HIGH_BASE]={write_high,dq_from_master};
            end else if (opcode==8'heb && dq_master_oe!==4'h0) begin
                $fatal(1,"master did not release DQ for PSRAM dummy/read");
            end
            clocks=clocks+1;
        end
    end
    always @(negedge sck or posedge cs_n or negedge rstn) begin: launch
        integer at;
        if (!rstn || cs_n || opcode!=8'heb || clocks<14) begin launched=4'h0; valid=0; end
        else begin
            valid=1;
            at=int'(target)+((clocks-14)/2);
            if (clocks%2==0) launched=at_address(at)>>4;
            else launched=at_address(at);
        end
    end
endmodule
