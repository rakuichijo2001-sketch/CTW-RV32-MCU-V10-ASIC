// SPDX-License-Identifier: Apache-2.0
`default_nettype none
// Shared between the FPGA and the Tiny Tapeout wrapper. Raw reset overrides
// output enables without a clock. A synchronized release starts the boot FSM.
module ctw_mcu_pads #(
    parameter integer CLK_HZ=20000000,
    parameter integer UART_DIV=174,
    parameter integer POWERUP_US=6000,
    parameter [2:0] QSPI_READ_DELAY_CFG=3'b000
)(
    input wire [7:0] ui_in, uio_in,
    output wire [7:0] uo_out, uio_out, uio_oe,
    input wire ena, clk, rst_n,
    output wire boot_ready, boot_failed,
    output wire [7:0] gpio_debug,
    output reg ram_timeout
);
    wire ext_rst_n = rst_n && ena;
    (* async_reg = "true" *) reg [2:0] reset_sync;
    always @(posedge clk or negedge ext_rst_n)
        if (!ext_rst_n) reset_sync <= 0;
        else reset_sync <= {reset_sync[1:0],1'b1};
    // Watchdog is not reset by its own reset request, so it can report the
    // reset reason after a CPU/boot restart. External rst_n/ena clears history.
    wire wdt_en, wdt_kick, wdt_reboot, wdt_cause;
    wire [15:0] wdt_limit_ms, wdt_elapsed_ms;
    wire [7:0] wdt_events;
    wire boot_rst_n = reset_sync[2] && !wdt_reboot;
    ctw_sys_watchdog #(.CLK_HZ(CLK_HZ)) sys_wdt (
        .clk(clk), .rst_n(ext_rst_n),
        .active(boot_ready && cpu_active && !ram_timeout),
        .enable(wdt_en), .timeout_ms(wdt_limit_ms), .kick(wdt_kick),
        .reboot(wdt_reboot), .last_reset(wdt_cause),
        .event_count(wdt_events), .elapsed_ms(wdt_elapsed_ms)
    );

    wire [7:0] gpio_out;
    wire [1:0] bidir_out, bidir_dir;
    wire [2:0] pinmux;
    wire pwm0, pwm1, i2c_scl_low, i2c_sda_low;
    assign gpio_debug = gpio_out;
    wire [3:0] dq_in = {uio_in[5:4],uio_in[2:1]};
    wire [3:0] b_dq, b_oe, cpu_dq, cpu_oe;
    wire b_sck, b_fcs, b_acs, b_bcs;
    wire cpu_sck, cpu_fcs, cpu_acs, cpu_bcs, cpu_active, uart_tx;
    // APS6404L-3SQR-SN standard grade tCEM max is 8 us. Leave 2 us
    // margin at the configured core clock. On timeout, park the pads
    // and stop the CPU until reset rather than continue a truncated read.
    localparam integer RAM_CS_BUDGET = 6 * (CLK_HZ / 1000000);
    localparam integer RAM_TIMER_W = $clog2(RAM_CS_BUDGET+1);
    localparam integer RAM_LAST_INT = RAM_CS_BUDGET-1;
    localparam [RAM_TIMER_W-1:0] RAM_LAST = RAM_LAST_INT[RAM_TIMER_W-1:0];
    reg [RAM_TIMER_W-1:0] ram_ticks;
    wire take_cpu = boot_rst_n && boot_ready && cpu_active && !ram_timeout;
    wire bus_active = ext_rst_n && boot_rst_n;
    wire [3:0] dq_out = take_cpu ? cpu_dq : b_dq;
    wire [3:0] dq_oe  = take_cpu ? cpu_oe : boot_ready || boot_failed ? 4'h0 : b_oe;
    wire sck = take_cpu ? cpu_sck : b_sck;
    wire fcs = take_cpu ? cpu_fcs : b_fcs;
    wire acs = take_cpu ? cpu_acs : b_acs;
    wire bcs = take_cpu ? cpu_bcs : b_bcs;
    wire ram_selected = !acs || !bcs;
    always @(posedge clk or negedge boot_rst_n) begin
        if (!boot_rst_n) begin
            ram_ticks <= 0;
            ram_timeout <= 0;
        end else if (!ram_timeout) begin
            if (!ram_selected) ram_ticks <= 0;
            else if (ram_ticks==RAM_LAST) ram_timeout <= 1;
            else ram_ticks <= ram_ticks+1'b1;
        end
    end

    // In RESET/PROGRAM only the two RAM chip selects are driven (high).
    // When TT ena is low, its design owns no pins.
    // V7: uio[7:6] are true software-programmable bidirectional pads.
    // When held in reset, during boot, when deselected or on RAM fault,
    // their output enables MUST remain 0, regardless of saved DIR bits.
    wire [1:0] pad_bidir_out = take_cpu ? (pinmux[0] ? 2'b00 : bidir_out) : 2'b00;
    wire [1:0] pad_bidir_oe = take_cpu ? (pinmux[0] ?
                                {i2c_scl_low,i2c_sda_low} : bidir_dir) : 2'b00;
    assign uio_out = bus_active && !ram_timeout ?
                     {pad_bidir_out,dq_out[3:2],sck,dq_out[1:0],fcs} : 8'h01;
    assign uio_oe = !ena ? 8'h00 : !bus_active ? 8'h00 :
                    ram_timeout ? 8'h09 :
                    {pad_bidir_oe,dq_oe[3:2],1'b1,dq_oe[1:0],1'b1};

    // Physical uo pads have no per-pin OE. Hold both PSRAM CS# HIGH
    // throughout reset, programming, ena=0 and watchdog fault.
    wire pad_acs = bus_active && !ram_timeout ? acs : 1'b1;
    wire pad_bcs = bus_active && !ram_timeout ? bcs : 1'b1;
    // Outputs 3/4 share pad with PWM alternate functions; reset -> GPIO.
    wire pwm_pad0 = pinmux[1] ? pwm0 : gpio_out[3];
    wire pwm_pad1 = pinmux[2] ? pwm1 : gpio_out[4];
    assign uo_out = {take_cpu ? uart_tx : 1'b1, pad_bcs, pad_acs,
                     take_cpu ? pwm_pad1 : 1'b0,
                     take_cpu ? pwm_pad0 : 1'b0,
                     take_cpu ? gpio_out[2:0] : 3'b000};

    ctw_qspi_boot #(.CLK_HZ(CLK_HZ),.POWERUP_US(POWERUP_US)) boot_i (
        .clk(clk),.rst_n(boot_rst_n),.dq_in(dq_in),.dq_out(b_dq),.dq_oe(b_oe),
        .sck(b_sck),.flash_cs_n(b_fcs),.rama_cs_n(b_acs),.ramb_cs_n(b_bcs),
        .ready(boot_ready),.failed(boot_failed)
    );
    // V28 QSPI sampling strap. For boards with short external Flash delays,
    // hold ui[6:4]=111 throughout CPU reset/boot to select sample phase 001.
    // All other patterns use the default 010 required by the 30ns-pad
    // timed Flash fixture. The QSPI controller samples this only while
    // its reset is asserted; after boot, ui[6:4] remain normal GPIOs.
    // This is a real hardware-selectable interface, NOT a test-only define.
    wire [2:0] qspi_read_delay_selected =
        (&ui_in[6:4]) ? 3'b001 : QSPI_READ_DELAY_CFG;
    ctw_mcu #(.UART_DIV(UART_DIV)) mcu_i (
        .clk(clk), .rst_n(boot_rst_n && boot_ready && !ram_timeout), .ena(ena),
        .gpio_in(ui_in), .gpio_out(gpio_out),
        .gpio_bidir_in(uio_in[7:6]),
        .gpio_bidir_out(bidir_out), .gpio_bidir_dir(bidir_dir),
        .pinmux(pinmux), .pwm0(pwm0), .pwm1(pwm1),
        .i2c_scl_low(i2c_scl_low), .i2c_sda_low(i2c_sda_low),
        .wdt_enable(wdt_en), .wdt_timeout_ms(wdt_limit_ms),
        .wdt_kick(wdt_kick), .wdt_event_count(wdt_events),
        .wdt_last_reset(wdt_cause), .wdt_elapsed_ms(wdt_elapsed_ms),
        .uart_rx(ui_in[7]),
        .uart_tx(uart_tx), .delay_cfg(qspi_read_delay_selected), .dq_in(dq_in),
        .dq_out(cpu_dq), .dq_oe(cpu_oe), .sck(cpu_sck), .flash_cs_n(cpu_fcs),
        .rama_cs_n(cpu_acs), .ramb_cs_n(cpu_bcs), .enabled(cpu_active)
    );
endmodule
`default_nettype wire
