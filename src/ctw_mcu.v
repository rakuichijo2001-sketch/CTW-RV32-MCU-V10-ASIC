// SPDX-License-Identifier: Apache-2.0
`default_nettype none
module ctw_mcu #(parameter integer UART_DIV = 174) (
    input wire clk, rst_n, ena,
    input wire [7:0] gpio_in,
    output reg [7:0] gpio_out,
    input wire [1:0] gpio_bidir_in,
    output reg [1:0] gpio_bidir_out, gpio_bidir_dir,
    input wire uart_rx,
    output wire uart_tx,
    input wire [2:0] delay_cfg,
    input wire [3:0] dq_in,
    output wire [3:0] dq_out, dq_oe,
    output wire sck, flash_cs_n, rama_cs_n, ramb_cs_n,
    output wire enabled,
    output wire [2:0] pinmux,
    output wire pwm0, pwm1,
    output wire i2c_scl_low, i2c_sda_low,
    output wire wdt_enable,
    output wire [15:0] wdt_timeout_ms,
    output wire wdt_kick,
    input wire [7:0] wdt_event_count,
    input wire wdt_last_reset,
    input wire [15:0] wdt_elapsed_ms
);
    // Asynchronous assertion for immediate bus release, synchronous release.
    wire ext_rst_n = rst_n && ena;
    (* async_reg = "true" *) reg [2:0] reset_pipe;
    always @(posedge clk or negedge ext_rst_n)
        if (!ext_rst_n) reset_pipe <= 0;
        else reset_pipe <= {reset_pipe[1:0],1'b1};
    wire run_n = reset_pipe[2];
    assign enabled = ext_rst_n && run_n;

    wire [27:0] addr;
    // A single high-page decode feeds all the local MMIO offsets.
    wire mmio_page = (addr[27:8] == 20'h80000);
    wire [1:0] wr_n, rd_n;
    wire [31:0] wdata;
    reg [31:0] rdata;
    wire rd = rd_n != 2'b11;
    wire wr = wr_n != 2'b11;
    wire data_sel = mmio_page && (addr[7:0] == 8'h0c);
    wire tx_busy, rx_valid;
    wire [7:0] rx_data;
    wire ready = (rd || wr) && !(wr && data_sel && tx_busy);
    wire tx_start = ready && wr && data_sel;
    wire rx_ack = ready && rd && data_sel;
    (* async_reg = "true" *) reg [7:0] gpio_meta, gpio_sync;
    (* async_reg = "true" *) reg [1:0] bidir_meta, bidir_sync;
    // V9 alternate-function registers. Reset keeps original V8 GPIO behavior.
    reg [2:0] pinmux_reg;
    assign pinmux = pinmux_reg;
    reg pwm_enable;
    reg [15:0] pwm_div;
    reg [7:0] pwm_duty0, pwm_duty1;
    reg [6:0] i2c_addr;
    reg [7:0] i2c_tx;
    reg [15:0] i2c_div;
    wire [7:0] i2c_rx;
    wire i2c_busy, i2c_done, i2c_nack, i2c_timeout;
    wire i2c_go = enabled && ready && wr && (mmio_page && addr[7:0]==8'h50) && wdata[0] && !i2c_busy;
    ctw_pwm pwm_i(
        .clk(clk), .rst_n(run_n), .enable(pwm_enable),
        .divider(pwm_div), .duty0(pwm_duty0), .duty1(pwm_duty1),
        .pwm0(pwm0), .pwm1(pwm1)
    );
    ctw_i2c_master i2c_i(
        .clk(clk), .rst_n(run_n), .enable(pinmux_reg[0]),
        .start(i2c_go), .operation(wdata[2:1]),
        .slave_addr(i2c_addr), .tx_byte(i2c_tx),
        .half_period(i2c_div),
        .scl_in(bidir_sync[1]), .sda_in(bidir_sync[0]),
        .scl_drive_low(i2c_scl_low), .sda_drive_low(i2c_sda_low),
        .rx_byte(i2c_rx), .busy(i2c_busy), .done(i2c_done),
        .nack(i2c_nack), .timeout(i2c_timeout)
    );
    // Independent system watchdog lives in ctw_mcu_pads, NOT in CPU reset domain.
    // Only CPU-controlled configuration and a write-one strobe live here.
    // 0x68: bit0 enable, bits[31:16] timeout in milliseconds (>= 10 ms).
    // 0x6c: write 0xA55A5AA5 to feed; any other value is ignored.
    // 0x70: bit0 last reset was WDT; bits[15:8] WDT event counter.
    // 0x74: elapsed time since feed (ms). Reset and PROGRAM disable WDT.
    reg [31:0] wdt_cfg;
    assign wdt_enable = wdt_cfg[0] && wdt_cfg[31:16] >= 16'd10;
    assign wdt_timeout_ms = wdt_cfg[31:16];
    assign wdt_kick = enabled && ready && wr && mmio_page && addr[7:0]==8'h6c &&
                      wdata==32'ha55a5aa5;
    reg [31:0] timer_cycles;
    // IRQ16: edge GPIO (ui[6:0], then input-mode uio[7:6]);
    // IRQ17: one-shot timer compare; IRQ18/19: UART level sources.
    reg [8:0] gpio_prev, gpio_rise_mask, gpio_fall_mask;
    wire [8:0] gpio_irq_value = {bidir_sync, gpio_sync[6:0]};
    wire [8:0] gpio_irq_inputs = {~gpio_bidir_dir, 7'h7f};
    wire gpio_event = |(((gpio_irq_value & ~gpio_prev & gpio_rise_mask) |
                         (~gpio_irq_value & gpio_prev & gpio_fall_mask)) & gpio_irq_inputs);
    reg [31:0] timer_compare;
    reg timer_armed;
    wire timer_event = timer_armed && (timer_cycles == timer_compare);
    wire [3:0] irq_req = {!tx_busy, rx_valid, timer_event, gpio_event};

    wire uart_txd;
    assign uart_tx = enabled ? uart_txd : 1'b1;

    always @(posedge clk) begin
        if (!run_n) begin
            gpio_meta <= 0;
            gpio_sync <= 0;
            gpio_out <= 0;
            bidir_meta <= 2'b00;
            bidir_sync <= 2'b00;
            gpio_bidir_out <= 2'b00;
            gpio_bidir_dir <= 2'b00;
            pinmux_reg <= 3'b000;
            pwm_enable <= 1'b0;
            pwm_div <= 16'd199;
            pwm_duty0 <= 8'd64;
            pwm_duty1 <= 8'd192;
            i2c_addr <= 7'h42;
            i2c_tx <= 8'h00;
            i2c_div <= 16'd249;
            timer_cycles <= 0;
            wdt_cfg <= 32'h0;
            gpio_prev <= 0;
            gpio_rise_mask <= 0;
            gpio_fall_mask <= 0;
            timer_compare <= 0;
            timer_armed <= 0;
        end else begin
            gpio_meta <= gpio_in;
            gpio_sync <= gpio_meta;
            bidir_meta <= gpio_bidir_in;
            bidir_sync <= bidir_meta;
            timer_cycles <= timer_cycles + 1'b1;
            gpio_prev <= gpio_irq_value;
            if (timer_event) timer_armed <= 0;
            if (ready && wr && mmio_page) begin
                case (addr[7:0])
                    8'h24: gpio_rise_mask <= wdata[8:0];
                    8'h28: gpio_fall_mask <= wdata[8:0];
                    8'h2c: timer_compare <= wdata;
                    8'h30: timer_armed <= wdata[0];
                    8'h34: pinmux_reg <= wdata[2:0];
                    8'h38: pwm_enable <= wdata[0];
                    8'h3c: pwm_div <= wdata[15:0];
                    8'h40: pwm_duty0 <= wdata[7:0];
                    8'h44: pwm_duty1 <= wdata[7:0];
                    8'h54: i2c_addr <= wdata[6:0];
                    8'h58: i2c_tx <= wdata[7:0];
                    8'h64: i2c_div <= wdata[15:0];
                    8'h68: wdt_cfg <= wdata;
                    default: ;
                endcase
            end
            if (wr && mmio_page && addr[7:0] == 8'h04)
                gpio_out <= wdata[7:0];
            // Additional bidirectional GPIO pads uio[7:6].
            // DIR: 0=input (high-Z), 1=output.
            if (wr && mmio_page && addr[7:0] == 8'h18)
                gpio_bidir_dir <= wdata[1:0];
            if (wr && mmio_page && addr[7:0] == 8'h1c)
                gpio_bidir_out <= wdata[1:0];
        end
    end

    always @* begin
        rdata = 32'b0;
        if (mmio_page) begin
            case (addr[7:0])
            8'h00: rdata = {24'd0,gpio_sync};
            8'h04: rdata = {24'd0,gpio_out};
            8'h08: rdata = timer_cycles;
            8'h0c: rdata = {24'd0,rx_data};
            8'h10: rdata = {30'd0,rx_valid,tx_busy};
            8'h14: rdata = 32'h43545731;
            8'h18: rdata = {30'd0,gpio_bidir_dir};
            8'h1c: rdata = {30'd0,gpio_bidir_out};
            8'h20: rdata = {30'd0,bidir_sync};
            8'h24: rdata = {23'd0,gpio_rise_mask};
            8'h28: rdata = {23'd0,gpio_fall_mask};
            8'h2c: rdata = timer_compare;
            8'h30: rdata = {31'd0,timer_armed};
            8'h34: rdata = {29'd0,pinmux_reg};
            8'h38: rdata = {31'd0,pwm_enable};
            8'h3c: rdata = {16'd0,pwm_div};
            8'h40: rdata = {24'd0,pwm_duty0};
            8'h44: rdata = {24'd0,pwm_duty1};
            8'h50: rdata = {31'd0,i2c_busy};
            8'h54: rdata = {25'd0,i2c_addr};
            8'h58: rdata = {24'd0,i2c_tx};
            8'h5c: rdata = {24'd0,i2c_rx};
            8'h60: rdata = {28'd0,i2c_timeout,i2c_nack,i2c_done,i2c_busy};
            8'h64: rdata = {16'd0,i2c_div};
            8'h68: rdata = wdt_cfg;
            8'h6c: rdata = 32'b0;
            8'h70: rdata = {16'b0,wdt_event_count,7'b0,wdt_last_reset};
            8'h74: rdata = {16'b0,wdt_elapsed_ms};
                default: rdata = 0;
            endcase
        end
    end

    ctw_uart #(.DIV(UART_DIV)) uart_i (
        .clk(clk), .rst_n(run_n), .rx(uart_rx), .tx_start(tx_start),
        .rx_ack(rx_ack), .tx_data(wdata[7:0]), .tx(uart_txd),
        .tx_busy(tx_busy), .rx_data(rx_data), .rx_valid(rx_valid)
    );

    hasemi_tinyqv_pio cpu_i (
        .clk(clk), .rstn(run_n), .data_addr(addr), .data_write_n(wr_n),
        .data_read_n(rd_n), .data_read_complete(), .data_out(wdata),
        .data_ready(ready), .data_in(rdata), .interrupt_req(irq_req),
        .stream_start(1'b0), .stream_addr(25'b0), .stream_length(32'b0),
        .stream_data(8'b0), .stream_valid(1'b0), .stream_abort(1'b0),
        .stream_ready(), .stream_busy(), .stream_done(), .stream_error(),
        .spi_data_in(run_n ? dq_in : {1'b0,delay_cfg}),
        .spi_data_out(dq_out), .spi_data_oe(dq_oe), .spi_clk_out(sck),
        .spi_flash_select(flash_cs_n), .spi_ram_a_select(rama_cs_n),
        .spi_ram_b_select(ramb_cs_n),
        .debug_instr_complete(), .debug_instr_ready(), .debug_instr_valid(),
        .debug_fetch_restart(), .debug_data_ready(), .debug_interrupt_pending(),
        .debug_branch(), .debug_early_branch(), .debug_ret(), .debug_reg_wen(),
        .debug_counter_0(), .debug_data_continue(), .debug_stall_txn(),
        .debug_stop_txn(), .debug_rd()
    );
endmodule
`default_nettype wire
