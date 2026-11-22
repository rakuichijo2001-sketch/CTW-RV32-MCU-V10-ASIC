module ctw_jp1_harness(
    input wire clk,rst_drive_low,
    input wire [1:0] key,
    input wire [7:0] host_o,host_oe,
    input wire [2:0] sensor_data,
    input wire sensor_uart_in,
    output wire sensor_uart_out,
    output wire [7:0] bus_i,led,fpga_oe,mcu_oe
);
    tri [7:0] bus;
    pullup(bus[0]); pullup(bus[6]); pullup(bus[7]);
    genvar i;
    generate for(i=0;i<8;i=i+1) begin: pads
        assign bus[i]=host_oe[i] ? host_o[i] : 1'bz;
    end endgenerate
    wire ram_a_cs_n, ram_b_cs_n;
    tri [1:0] bidir;
    pulldown(bidir[0]); pulldown(bidir[1]);
    assign bus[6]=ram_a_cs_n;
    assign bus[7]=ram_b_cs_n;
    assign bus_i=bus;
    assign fpga_oe=dut.pad_oe;
    assign mcu_oe=dut.mcu_oe;
    ctw_de10_top dut(
        .CLOCK_50(clk),.KEY(key),.ESP_RST_N(!rst_drive_low),.SENSOR_D(sensor_data),
        .SENSOR_RX(sensor_uart_in),.SENSOR_TX(sensor_uart_out),
        .RAM_A_CS_N(ram_a_cs_n),.RAM_B_CS_N(ram_b_cs_n),
        .LED(led),.JP1_QSPI(bus[5:0]),.JP1_BIDIR(bidir));
endmodule
