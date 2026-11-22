// SPDX-License-Identifier: Apache-2.0
`default_nettype none
module ctw_uart #(parameter integer DIV = 174) (
    input wire clk, rst_n, rx, tx_start, rx_ack,
    input wire [7:0] tx_data,
    output wire tx, tx_busy,
    output reg [7:0] rx_data,
    output reg rx_valid
);
    localparam integer W = $clog2(DIV);
    localparam integer HALF_DIV = DIV/2;
    localparam [W-1:0] BIT_RELOAD  = DIV[W-1:0]-1'b1;
    localparam [W-1:0] HALF_RELOAD = HALF_DIV[W-1:0]-1'b1;
    reg [W-1:0] tx_count, rx_count;
    reg [3:0] tx_bits, rx_phase;
    reg [9:0] tx_shift;
    reg [7:0] rx_shift;
    (* async_reg = "true" *) reg rx_meta, rx_sync;

    assign tx_busy = tx_bits != 0;
    assign tx = tx_shift[0];

    always @(posedge clk) begin
        if (!rst_n) begin
            tx_shift <= 10'h3ff;
            tx_bits <= 0;
            tx_count <= 0;
            rx_meta <= 1;
            rx_sync <= 1;
            rx_phase <= 0;
            rx_count <= 0;
            rx_shift <= 0;
            rx_valid <= 0;
            rx_data <= 0;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
            if (!tx_busy) begin
                if (tx_start) begin
                    tx_shift <= {1'b1, tx_data, 1'b0};
                    tx_count <= BIT_RELOAD;
                    tx_bits <= 10;
                end
            end else if (tx_count == 0) begin
                tx_count <= BIT_RELOAD;
                tx_shift <= {1'b1,tx_shift[9:1]};
                tx_bits <= tx_bits - 1'b1;
            end else tx_count <= tx_count - 1'b1;

            if (rx_ack) rx_valid <= 0;
            if (rx_phase == 0) begin
                if (!rx_sync) begin
                    rx_count <= HALF_RELOAD;
                    rx_phase <= 1;
                end
            end else if (rx_count != 0) rx_count <= rx_count - 1'b1;
            else begin
                rx_count <= BIT_RELOAD;
                if (rx_phase == 1) rx_phase <= rx_sync ? 4'd0 : 4'd2;
                else if (rx_phase <= 9) begin
                    rx_shift <= {rx_sync, rx_shift[7:1]};
                    rx_phase <= rx_phase + 1'b1;
                end else begin
                    rx_phase <= 0;
                    if (rx_sync && (!rx_valid || rx_ack)) begin
                        rx_valid <= 1;
                        rx_data <= rx_shift;
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
