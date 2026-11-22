// SPDX-License-Identifier: Apache-2.0
// Single Quartus top. Default models all three chips internally. Set
// MODEL_MEMORIES=0 for external ICs on the same JP1 pins (no second project).
module ctw_de10_top #(
    parameter integer MODEL_MEMORIES=1,
    parameter integer POWERUP_US=6000
)(
    input wire CLOCK_50,
    input wire [1:0] KEY,
    input wire ESP_RST_N,
    input wire [2:0] SENSOR_D,
    input wire SENSOR_RX,
    output wire SENSOR_TX,
    output wire PWM_TEST0, PWM_TEST1,
    output wire RAM_A_CS_N,
    output wire RAM_B_CS_N,
    output wire [7:0] LED,
    inout wire [5:0] JP1_QSPI,
    inout wire [1:0] JP1_BIDIR
);
    wire clk=CLOCK_50;
    reg [5:0] por_count=0;
    always @(posedge clk) if (!(&por_count)) por_count<=por_count+1'b1;
    wire power_n=&por_count;
    wire target_rst_n=power_n && KEY[0] && ESP_RST_N;
    wire program_mode=power_n && !target_rst_n;

    wire [7:0] mcu_o, mcu_oe, mcu_i, uo_out, gpio_debug;
    wire boot_ready, boot_failed, ram_timeout;
    wire [7:0] pad_o, pad_oe;

    ctw_mcu_pads #(.CLK_HZ(50000000),.UART_DIV(434),.POWERUP_US(POWERUP_US)) soc (
        .ui_in({SENSOR_RX,SENSOR_D,3'b0,!KEY[1]}), .uo_out(uo_out), .uio_in(mcu_i),
        .uio_out(mcu_o),.uio_oe(mcu_oe),.ena(1'b1),.clk(clk),.rst_n(target_rst_n),
        .boot_ready(boot_ready),.boot_failed(boot_failed),
        .gpio_debug(gpio_debug),.ram_timeout(ram_timeout)
    );

    // These three outputs now correspond to uo_out[7], [5], [6] on ASIC.
    // Keep the same DE10 physical JP1 wiring for the memory fixture.
    assign SENSOR_TX=uo_out[7];
    // Extra FPGA-only observations: ASIC stays on uo_out[3] and [4].
    assign PWM_TEST0=uo_out[3];
    assign PWM_TEST1=uo_out[4];
    assign RAM_A_CS_N=uo_out[5];
    assign RAM_B_CS_N=uo_out[6];
    // LEDs are a DE10-only debug mirror of the firmware's GPIO register.
    // They are not the final ASIC uo_out pin values.
    assign LED=!power_n ? 8'h00 : program_mode ? 8'h02 :
               ram_timeout ? 8'he8 : boot_failed ? 8'he0 : !boot_ready ? 8'h10 : gpio_debug;

    generate if (MODEL_MEMORIES != 0) begin: model_memories
        // Only the Flash slave drives DQ towards the ESP during programming.
        // The MCU master has exactly the same pad ownership in both builds.
        // Local model feedback keeps the runtime data path inside the FPGA.
        (* async_reg = "true" *) reg [5:0] host_meta, host_sync;
        always @(posedge clk) begin
            host_meta<=program_mode ? JP1_QSPI[5:0] : 6'b000001;
            host_sync<=host_meta;
        end

        wire fcs=program_mode ? host_sync[0] : !mcu_oe[0] || mcu_o[0];
        wire acs=RAM_A_CS_N;
        wire bcs=RAM_B_CS_N;
        wire sck=program_mode ? host_sync[3] : mcu_o[3] && mcu_oe[3];
        wire [3:0] dq=program_mode ? {host_sync[5:4],host_sync[2:1]} : {mcu_o[5:4],mcu_o[2:1]};
        wire [3:0] master_oe={mcu_oe[5:4],mcu_oe[2:1]};
        wire [3:0] from_memory, flash_o, flash_oe;
        wire [3:0] return_oe=program_mode && !host_sync[0] ? flash_oe : 4'h0;
        assign mcu_i={JP1_BIDIR,from_memory[3:2],1'b0,from_memory[1:0],1'b1};
        assign pad_o=program_mode ? {2'b11,flash_o[3:2],1'b0,flash_o[1:0],1'b1} : mcu_o;
        assign pad_oe=mcu_oe | {2'b00,return_oe[3:2],1'b0,return_oe[1:0],1'b0};

        ctw_memory_models memory (
            .clk(clk),.power_n(power_n),.sck(sck),.fcs(fcs),.acs(acs),.bcs(bcs),
            .master_dq(dq),.master_oe(master_oe),.flash_dq(flash_o),.flash_oe(flash_oe),
            .data_to_master(from_memory),.flash_xip(),.flash_image(),
            .flash_busy(),.qpi_a(),.qpi_b()
        );
    end else begin: external_memories
        assign pad_o=mcu_o;
        assign pad_oe=mcu_oe;
        assign mcu_i={JP1_BIDIR,JP1_QSPI};
    end endgenerate

    // Two physical JP1 pins exercise the same ASIC uio[6:7] bidirectional
    // output-enable paths; no external model or second Quartus project.
    assign JP1_BIDIR[0] = pad_oe[6] ? pad_o[6] : 1'bz;
    assign JP1_BIDIR[1] = pad_oe[7] ? pad_o[7] : 1'bz;

    genvar i;
    generate for (i=0;i<6;i=i+1) begin: pads
        assign JP1_QSPI[i]=pad_oe[i] ? pad_o[i] : 1'bz;
    end endgenerate
endmodule
