// SPDX-License-Identifier: Apache-2.0
// Mode tracking for the APS6404L 0x66, 0x99, 0x35 bring-up sequence.
// This is a functional subset, not an analog model.
module ctw_psram_mode_model #(
    parameter integer POR_CYCLES=7500  // 150 us at 50 MHz
)(
    input wire clk, rst_n, cs_n, sck,
    input wire [3:0] dq,
    output reg qpi
);
    reg old_cs, old_sck;
    reg [3:0] bits_seen;
    reg [7:0] shift;
    reg reset_en, reset_seen, init_done;
    localparam integer CW = $clog2(POR_CYCLES+1);
    localparam [CW-1:0] POR_LAST = POR_CYCLES[CW-1:0]-1'b1;
    reg [CW-1:0] elapsed;
    reg [1:0] reset_guard;
    always @(posedge clk) begin
        if (!rst_n) begin
            old_cs<=1; old_sck<=0; bits_seen<=0; shift<=0; reset_en<=0;
            reset_seen<=0; qpi<=0; init_done<=0; elapsed<=0; reset_guard<=0;
        end else begin
            if (!init_done) begin
                if (elapsed==POR_LAST) init_done<=1;
                else elapsed<=elapsed+1'b1;
            end
            if (reset_guard!=0) reset_guard<=reset_guard-1'b1;
            old_cs<=cs_n;
            old_sck<=sck;
            if (!init_done) begin
                old_cs<=1; old_sck<=0; bits_seen<=0;
                reset_en<=0;
            end else if (cs_n && !old_cs && bits_seen==8) begin
                if (shift!=8'h66) reset_en<=0;
                if (qpi) begin
                    if (shift==8'hf5) qpi<=0;
                end else begin
                    case (shift)
                        8'h66: reset_en<=1;
                        8'h99: if (reset_en) begin
                            reset_seen<=1; reset_guard<=3;
                        end
                        8'h35: if (reset_seen && reset_guard==0) qpi<=1;
                        default: ;
                    endcase
                end
            end else if (!cs_n && old_cs) begin bits_seen<=0; shift<=0; end
            else if (!cs_n && sck && !old_sck && bits_seen<8) begin
                bits_seen <= bits_seen + (qpi ? 4'd4 : 4'd1);
                shift <= qpi ? {shift[3:0],dq} : {shift[6:0],dq[0]};
            end
        end
    end
endmodule
