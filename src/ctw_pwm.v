// SPDX-License-Identifier: Apache-2.0
// Two 8-bit edge-aligned PWM channels with common programmable prescaler.
`default_nettype none
module ctw_pwm(
    input wire clk, rst_n, enable,
    input wire [15:0] divider,
    input wire [7:0] duty0, duty1,
    output wire pwm0, pwm1
);
    reg [15:0] prescale;
    reg [7:0] phase;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin prescale<=0; phase<=0; end
        else if(!enable) begin prescale<=0; phase<=0; end
        else if(prescale>=divider) begin
            prescale<=0;
            phase<=phase+1'b1;
        end else prescale<=prescale+1'b1;
    end
    assign pwm0=enable && (phase<duty0);
    assign pwm1=enable && (phase<duty1);
endmodule
`default_nettype wire
