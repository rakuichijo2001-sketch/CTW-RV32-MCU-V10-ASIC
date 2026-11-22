// SPDX-License-Identifier: Apache-2.0
// V10: independent (of CPU reset domain) watchdog, checked with a derived
// millisecond timebase. Requires a *running* clk; not a brownout detector.
// External rst_n/ena clear its history. A WDT expiry resets the entire
// boot + CPU subsystem for HOLD_CYCLES; I/O pad gating is in ctw_mcu_pads.
`default_nettype none
module ctw_sys_watchdog #(
    parameter integer CLK_HZ=20000000,
    parameter integer HOLD_CYCLES=16,
    parameter integer TICK_CYCLES=(CLK_HZ+999)/1000,
    parameter integer TICK_WIDTH=$clog2(TICK_CYCLES+1),
    parameter integer HOLD_WIDTH=$clog2(HOLD_CYCLES+1)
)(
    input wire clk, rst_n, active, enable, kick,
    input wire [15:0] timeout_ms,
    output reg reboot,
    output reg last_reset,
    output reg [7:0] event_count,
    output reg [15:0] elapsed_ms
);
    reg [TICK_WIDTH-1:0] tick_count;
    reg [HOLD_WIDTH-1:0] hold_count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_count<=0; hold_count<=0; elapsed_ms<=0;
            reboot<=0; last_reset<=0; event_count<=0;
        end else if (reboot) begin
            tick_count<=0; elapsed_ms<=0;
            if (hold_count==HOLD_CYCLES-1) begin
                reboot<=0;
                hold_count<=0;
            end else hold_count<=hold_count+1'b1;
        end else if (!active || !enable || timeout_ms<16'd10 || kick) begin
            tick_count<=0; elapsed_ms<=0;
        end else if (tick_count == TICK_CYCLES-1) begin
            tick_count<=0;
            if (elapsed_ms+16'd1 >= timeout_ms) begin
                reboot<=1;
                last_reset<=1;
                if (event_count!=8'hff) event_count<=event_count+1'b1;
                elapsed_ms<=0;
            end else elapsed_ms<=elapsed_ms+1'b1;
        end else tick_count<=tick_count+1'b1;
    end
endmodule
`default_nettype wire
