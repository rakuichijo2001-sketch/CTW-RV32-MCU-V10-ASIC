// SPDX-License-Identifier: Apache-2.0
`default_nettype none
module tt_um_ctw_rv32_mcu #(parameter integer UART_DIV=87, CLK_HZ=10000000) (
    input wire [7:0] ui_in, uio_in,
    output wire [7:0] uo_out, uio_out, uio_oe,
    input wire ena, clk, rst_n
);
    ctw_mcu_pads #(.UART_DIV(UART_DIV),.CLK_HZ(CLK_HZ), .QSPI_READ_DELAY_CFG(3'b001)) soc (
        .ui_in(ui_in),.uio_in(uio_in),.uo_out(uo_out),.uio_out(uio_out),.uio_oe(uio_oe),
        .ena(ena),.clk(clk),.rst_n(rst_n),.boot_ready(),.boot_failed(),.gpio_debug(),.ram_timeout()
    );
endmodule
`default_nettype wire
