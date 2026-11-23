/*
 * Hasemi stream-capable TinyQV memory controller.
 * SPDX-License-Identifier: Apache-2.0
 *
 * Derived from tinyqv_mem_ctrl. The TinyQV CPU core and qspi_controller are
 * unchanged. This wrapper adds one byte-stream write master for sensor/PIO
 * data. A stream transaction owns QSPI only at a transaction boundary.
 * While a stream burst is active, TinyQV naturally stalls on instruction/data
 * memory access; no CPU-core modification or generated clock is required.
 */

`default_nettype none
module hasemi_mem_ctrl_stream (
    input clk,
    input rstn,

    input [23:1] instr_addr,
    input        instr_fetch_restart,
    input        instr_fetch_stall,

    output reg     instr_fetch_started,
    output reg     instr_fetch_stopped,
    output  [15:0] instr_data,
    output         instr_ready,

    input [24:0] data_addr,
    input [1:0]  data_write_n,
    input [1:0]  data_read_n,
    input [31:0] data_to_write,
    input        data_continue,

    output         data_ready,
    output  [31:0] data_from_read,

    // PIO stream writer. Address must point to RAM A or RAM B, not Flash.
    input         stream_start,
    input  [24:0] stream_addr,
    input  [31:0] stream_length,
    input   [7:0] stream_data,
    input         stream_valid,
    input         stream_abort,
    output        stream_ready,
    output reg    stream_busy,
    output reg    stream_done,
    output reg    stream_error,

    input      [3:0] spi_data_in,
    output     [3:0] spi_data_out,
    output     [3:0] spi_data_oe,
    output           spi_clk_out,
    output           spi_flash_select,
    output           spi_ram_a_select,
    output           spi_ram_b_select,

    output        debug_stall_txn,
    output        debug_stop_txn
);
    reg start_instr;
    reg start_read;
    reg start_write;
    reg cpu_stop_txn;
    reg [1:0] data_txn_n;
    reg [1:0] data_txn_len;

    reg qspi_write_done;
    wire qspi_busy;
    reg instr_active;

    wire is_instr = instr_active || start_instr;
    wire [1:0] txn_len = is_instr ? 2'b01 : data_txn_len;
    // Address is only sampled by qspi_controller when a NEW transaction starts.
    // Use the already-registered CPU request flags to choose data vs fetch;
    // do not put the instr_active/start_instr control cone in front of all
    // 25 address bits. During a running transaction addr_in is not sampled.
    wire cpu_data_request = (data_read_n != 2'b11) || (data_write_n != 2'b11);
    wire [24:0] cpu_addr_in = cpu_data_request ? data_addr[24:0] : {1'b0, instr_addr, 1'b0};

    reg [31:0] qspi_data_buf;
    reg [1:0] qspi_data_byte_idx;
    wire qspi_data_req;
    wire qspi_data_req_early;
    wire qspi_data_ready;
    wire [7:0] qspi_data_out_byte;

    wire cpu_stall_txn = instr_active && instr_fetch_stall && !instr_ready && qspi_data_byte_idx == 2'b01;
    reg data_stall;

    // ------------------------------------------------------------------
    // Stream request state.
    // ------------------------------------------------------------------
    reg        stream_pending;
    reg [24:0] stream_addr_q;
    reg [31:0] stream_length_q;
    reg [31:0] stream_count_q;
    reg        stream_stop_pending;
    reg        stream_abort_pending;
    reg        start_stream;

    wire stream_request_valid = stream_valid;
    wire stream_addr_is_ram = stream_addr[24];
    wire stream_args_valid = stream_addr_is_ram && (stream_length != 32'd0);

    // Stream start is given priority only when QSPI is idle and no instruction
    // transaction remains active. If no sensor byte is available yet, CPU may
    // continue running until the capture FIFO produces the first byte.
    always @(*) begin
        start_stream = 1'b0;
        if (!qspi_busy && !instr_active && stream_pending && stream_request_valid)
            start_stream = 1'b1;
    end

    always @(*) begin
        start_instr = 0;
        start_read = 0;
        start_write = 0;
        cpu_stop_txn = 0;
        data_txn_n = data_write_n & data_read_n;
        data_txn_len = {data_txn_n[1], data_txn_n[1] | data_txn_n[0]};

        if (!stream_busy && !start_stream) begin
            if (qspi_busy || qspi_write_done) begin
                if (instr_active) begin
                    if (instr_fetch_restart && (!instr_fetch_started || cpu_stall_txn)) begin
                        cpu_stop_txn = 1;
                    end else if ((qspi_data_ready && qspi_data_byte_idx == 2'b01) || instr_fetch_stall) begin
                        if (data_txn_n != 2'b11)
                            cpu_stop_txn = 1;
                    end
                end else if ((qspi_data_ready || qspi_data_req) && qspi_data_byte_idx == data_txn_len && !data_continue) begin
                    cpu_stop_txn = 1;
                end
            end else begin
                // Pending stream with data ready wins at a clean boundary.
                if (!stream_pending || !stream_request_valid) begin
                    if (data_read_n != 2'b11)
                        start_read = 1;
                    else if (data_write_n != 2'b11)
                        start_write = 1;
                    else if (instr_fetch_restart)
                        start_instr = 1;
                end
            end
        end
    end

    // Stream bookkeeping.
    always @(posedge clk) begin
        if (!rstn) begin
            stream_pending      <= 1'b0;
            stream_busy         <= 1'b0;
            stream_done         <= 1'b0;
            stream_error        <= 1'b0;
            stream_addr_q       <= 25'd0;
            stream_length_q     <= 32'd0;
            stream_count_q      <= 32'd0;
            stream_stop_pending <= 1'b0;
            stream_abort_pending<= 1'b0;
        end else begin
            stream_done  <= 1'b0;
            stream_error <= 1'b0;

            if (stream_abort && stream_pending && !stream_busy) begin
                stream_pending <= 1'b0;
                stream_error   <= 1'b1;
            end

            if (stream_start && !stream_pending && !stream_busy) begin
                if (!stream_args_valid) begin
                    stream_error <= 1'b1;
                end else begin
                    stream_pending  <= 1'b1;
                    stream_addr_q   <= stream_addr;
                    stream_length_q <= stream_length;
                    stream_count_q  <= 32'd0;
                end
            end

            if (start_stream) begin
                stream_pending      <= 1'b0;
                stream_busy         <= 1'b1;
                stream_count_q      <= 32'd0;
                stream_stop_pending <= 1'b0;
                stream_abort_pending<= 1'b0;
            end

            if (stream_busy && stream_abort) begin
                stream_abort_pending <= 1'b1;
                stream_stop_pending  <= 1'b1;
            end

            // qspi_data_req is intentionally one core clock too late for a
            // standard ready/valid producer: qspi_controller samples data_in
            // on the same edge that the producer would advance.  Consume the
            // stream on data_req_early instead, so the next byte is stable
            // before the QSPI write-byte boundary.
            if (stream_busy && qspi_data_req_early && stream_valid) begin
                stream_count_q <= stream_count_q + 32'd1;
                if (stream_count_q + 32'd1 >= stream_length_q)
                    stream_stop_pending <= 1'b1;
            end

            // qspi_controller has returned to IDLE after the safe stop point.
            if (stream_busy && stream_stop_pending && !qspi_busy) begin
                stream_busy          <= 1'b0;
                stream_stop_pending  <= 1'b0;
                if (stream_abort_pending) begin
                    stream_abort_pending <= 1'b0;
                    stream_error         <= 1'b1;
                end else begin
                    stream_done          <= 1'b1;
                end
            end
        end
    end

    // Keep the original TinyQV instruction-active behavior outside stream
    // ownership. A stream begins only when instr_active is clear.
    always @(posedge clk) begin
        if (!rstn || cpu_stop_txn) begin
            instr_active <= 0;
        end else if (!stream_busy && !start_stream) begin
            instr_active <= qspi_busy ? instr_active : start_instr;
        end
    end

    // Stream owns QSPI until its byte count is complete. Empty capture FIFO
    // stalls the QSPI write without losing transaction context.
    wire stream_stall_txn = stream_busy && !stream_valid;
    wire stream_stop_txn  = stream_busy && stream_stop_pending;
    wire qspi_stall_txn   = stream_busy ? stream_stall_txn : (cpu_stall_txn || data_stall);
    wire qspi_stop_txn    = stream_busy ? stream_stop_txn : cpu_stop_txn;

    wire [24:0] qspi_addr_in = (stream_busy || start_stream) ? stream_addr_q : cpu_addr_in;
    wire [1:0] write_qspi_data_byte_idx = qspi_data_byte_idx + (qspi_data_req ? 2'b01 : 2'b00);
    wire [7:0] cpu_qspi_data_in = data_to_write[{write_qspi_data_byte_idx,3'b000} +:8];
    wire [7:0] qspi_write_data_in = (stream_busy || start_stream) ? stream_data : cpu_qspi_data_in;

    qspi_controller q_ctrl(
        clk,
        rstn,

        spi_data_in,
        spi_data_out,
        spi_data_oe,
        spi_clk_out,

        spi_flash_select,
        spi_ram_a_select,
        spi_ram_b_select,

        qspi_addr_in,
        qspi_write_data_in,
        (!stream_busy && !start_stream) && (start_read || start_instr),
        start_stream || ((!stream_busy) && start_write),
        qspi_stall_txn,
        qspi_stop_txn,

        qspi_data_out_byte,
        qspi_data_req,
        qspi_data_ready,
        qspi_busy,
        qspi_data_req_early
    );

    // Producer advances one clock BEFORE the legacy qspi data_req boundary.
    // This removes the deterministic one-byte lag observed by TEST 5.
    assign stream_ready = stream_busy && qspi_data_req_early && stream_valid;

    always @(posedge clk) begin
        if (!rstn) begin
            instr_fetch_started <= 1'b0;
            instr_fetch_stopped <= 1'b0;
        end else begin
            instr_fetch_started <= start_instr;
            instr_fetch_stopped <= cpu_stop_txn;
        end
    end

    // CPU byte index is frozen during stream ownership.
    always @(posedge clk) begin
        if (!rstn || start_instr || start_read || start_write) begin
            qspi_data_byte_idx <= 2'b00;
        end else if (!stream_busy && !start_stream) begin
            if (qspi_data_ready || qspi_data_req) begin
                qspi_data_byte_idx <= qspi_data_byte_idx + 2'b01;
                if (qspi_data_byte_idx == txn_len)
                    qspi_data_byte_idx <= 0;
            end
        end
    end

    always @(posedge clk) begin
        if (!stream_busy && qspi_data_ready)
            qspi_data_buf[{qspi_data_byte_idx,3'b000} +:8] <= qspi_data_out_byte;
    end

    assign instr_data = {qspi_data_out_byte, qspi_data_buf[7:0]};
    assign instr_ready = !stream_busy && instr_active && qspi_data_ready && qspi_data_byte_idx == 2'b01;

    always @(posedge clk) begin
        if (!rstn)
            qspi_write_done <= 1'b0;
        else
            qspi_write_done <= !stream_busy && qspi_data_req && qspi_data_byte_idx == data_txn_len;
    end

    always @(posedge clk) begin
        if (!rstn) begin
            data_stall <= 1'b0;
        end else if (!stream_busy) begin
            if (data_continue) begin
                if ((qspi_data_req && qspi_data_byte_idx + 2'b01 == data_txn_len) ||
                    (qspi_data_ready && qspi_data_byte_idx == data_txn_len))
                    data_stall <= 1;
                else if ((data_read_n != 2'b11 || data_write_n != 2'b11) && qspi_data_byte_idx == 2'b00 && !data_ready)
                    data_stall <= 0;
            end else begin
                data_stall <= 0;
            end
        end
    end

    assign data_ready = !stream_busy && !instr_active &&
                        ((qspi_data_ready && qspi_data_byte_idx == data_txn_len) || qspi_write_done);
    assign data_from_read = data_ready ? ({qspi_data_out_byte, qspi_data_buf[23:16],
        data_txn_len == 2'b01 ? qspi_data_out_byte : qspi_data_buf[15:8],
        data_txn_len == 2'b00 ? qspi_data_out_byte : qspi_data_buf[7:0]}) : qspi_data_buf;

    assign debug_stall_txn = qspi_stall_txn;
    assign debug_stop_txn  = qspi_stop_txn;
endmodule
`default_nettype wire
