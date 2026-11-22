// SPDX-License-Identifier: Apache-2.0
// CTW V9 small 7-bit I2C master. No push-pull HIGH: SDA/SCL are open drain.
// cmd: 00 write one byte, 01 read one byte, 10 write register pointer then
// repeated-START/read one byte. Each command ends with STOP. No FIFO.
`default_nettype none
module ctw_i2c_master (
    input wire clk, rst_n, enable,
    input wire start,
    input wire [1:0] operation,
    input wire [6:0] slave_addr,
    input wire [7:0] tx_byte,
    input wire [15:0] half_period,
    input wire scl_in, sda_in,
    output reg scl_drive_low, sda_drive_low,
    output reg [7:0] rx_byte,
    output reg busy, done, nack, timeout
);
    localparam [4:0] IDLE=0, START_A=1, START_B=2,
        TX_SETUP=3, TX_HIGH=4, TX_LOW=5,
        ACK_SETUP=6, ACK_HIGH=7, ACK_LOW=8,
        RESTART_A=9, RESTART_B=10, RESTART_C=11,
        RX_SETUP=12, RX_HIGH=13, RX_LOW=14,
        NACK_SETUP=15, NACK_HIGH=16, NACK_LOW=17,
        STOP_A=18, STOP_B=19, STOP_C=20;
    localparam [1:0] PH_ADDR_W=0, PH_DATA=1, PH_ADDR_R=2, PH_RECEIVE=3;
    reg [4:0] state;
    reg [1:0] phase, op_latch;
    reg [6:0] addr_latch;
    reg [7:0] tx_latch, tx_shift;
    reg [2:0] bit_index;
    reg [15:0] phase_count;
    reg [19:0] wait_count;
    wire need_scl_high = (state==START_A || state==START_B ||
                          state==TX_HIGH || state==ACK_HIGH ||
                          state==RESTART_B || state==RESTART_C ||
                          state==RX_HIGH || state==NACK_HIGH ||
                          state==STOP_B || state==STOP_C);
    wire wait_line = need_scl_high && !scl_in;
    wire tick = (phase_count >= half_period);

    // Output levels are derived from registered FSM state and data.
    always @* begin
        scl_drive_low=1'b0;
        sda_drive_low=1'b0;
        case(state)
            START_B, RESTART_C: sda_drive_low=1'b1;
            TX_SETUP, TX_LOW: begin
                scl_drive_low=1'b1;
                sda_drive_low=~tx_shift[bit_index];
            end
            TX_HIGH: sda_drive_low=~tx_shift[bit_index];
            ACK_SETUP, ACK_LOW, RX_SETUP, RX_LOW,
            NACK_SETUP, NACK_LOW: scl_drive_low=1'b1;
            ACK_HIGH, RX_HIGH, NACK_HIGH: begin end
            RESTART_A: scl_drive_low=1'b1;
            STOP_A: begin scl_drive_low=1'b1; sda_drive_low=1'b1; end
            STOP_B: sda_drive_low=1'b1;
            default: begin end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; phase<=0; op_latch<=0;
            addr_latch<=0; tx_latch<=0; tx_shift<=0; bit_index<=0;
            phase_count<=0; wait_count<=0; rx_byte<=0;
            busy<=0; done<=0; nack<=0; timeout<=0;
        end else if (!enable) begin
            state<=IDLE; phase_count<=0; wait_count<=0;
            busy<=0; done<=0; nack<=0; timeout<=0;
        end else if(state==IDLE) begin
            phase_count<=0; wait_count<=0;
            if(start) begin
                op_latch<=operation;
                addr_latch<=slave_addr;
                tx_latch<=tx_byte;
                tx_shift<={slave_addr, (operation==2'd1)};
                phase<=(operation==2'd1) ? PH_ADDR_R : PH_ADDR_W;
                bit_index<=3'd7;
                rx_byte<=0;
                done<=0; nack<=0; timeout<=0; busy<=1;
                state<=START_A;
            end
        end else if (wait_line) begin
            phase_count<=0; // no I2C progress while SCL is stretched
            if(wait_count==20'hfffff) begin
                state<=IDLE; busy<=0; done<=1; timeout<=1;
            end else wait_count<=wait_count+1'b1;
        end else begin
            wait_count<=0;
            if (!tick) phase_count<=phase_count+1'b1;
            else begin
                phase_count<=0;
                case(state)
                    START_A: begin
                        if(sda_in) state<=START_B;
                        else begin state<=IDLE; busy<=0; done<=1; timeout<=1; end
                    end
                    START_B: state<=TX_SETUP;
                    TX_SETUP: state<=TX_HIGH;
                    TX_HIGH: state<=TX_LOW;
                    TX_LOW: begin
                        if(bit_index==0) state<=ACK_SETUP;
                        else begin bit_index<=bit_index-1'b1; state<=TX_SETUP; end
                    end
                    ACK_SETUP: state<=ACK_HIGH;
                    ACK_HIGH: begin
                        if(sda_in) nack<=1;
                        state<=ACK_LOW;
                    end
                    ACK_LOW: begin
                        if(nack) state<=STOP_A;
                        else if(phase==PH_ADDR_R) begin
                            phase<=PH_RECEIVE; bit_index<=3'd7;
                            state<=RX_SETUP;
                        end else if(phase==PH_ADDR_W) begin
                            phase<=PH_DATA; bit_index<=3'd7;
                            tx_shift<=tx_latch; state<=TX_SETUP;
                        end else if(phase==PH_DATA && op_latch==2'd2) begin
                            state<=RESTART_A;
                        end else state<=STOP_A;
                    end
                    RESTART_A: state<=RESTART_B;
                    RESTART_B: state<=RESTART_C;
                    RESTART_C: begin
                        tx_shift<={addr_latch,1'b1}; phase<=PH_ADDR_R;
                        bit_index<=3'd7; state<=TX_SETUP;
                    end
                    RX_SETUP: state<=RX_HIGH;
                    RX_HIGH: begin
                        rx_byte[bit_index]<=sda_in;
                        state<=RX_LOW;
                    end
                    RX_LOW: begin
                        if(bit_index==0) state<=NACK_SETUP;
                        else begin bit_index<=bit_index-1'b1; state<=RX_SETUP; end
                    end
                    NACK_SETUP: state<=NACK_HIGH;
                    NACK_HIGH: state<=NACK_LOW;
                    NACK_LOW: state<=STOP_A;
                    STOP_A: state<=STOP_B;
                    STOP_B: state<=STOP_C;
                    STOP_C: begin state<=IDLE; busy<=0; done<=1; end
                    default: begin state<=IDLE; busy<=0; done<=1; timeout<=1; end
                endcase
            end
        end
    end
endmodule
`default_nettype wire
