// SPDX-License-Identifier: Apache-2.0
// Functional QPI read/write subset for the APS6404L-3SQR-SN.
// Adapted from the Hasemi Stage 3 QPI model; chip-mode tracking is separate.
//
// Quartus/DE10-Nano note:
//   Keep the backing store as a synchronous-read memory so Quartus can map it
//   into Cyclone-V M10K blocks.  An asynchronous array read of 256 KiB causes
//   Quartus 18.1 to implement the storage as registers and exceeds the device
//   register budget.
//
// The QPI protocol state machine prefetches the next byte one system clock
// ahead.  The six QPI wait clocks before read data provide ample latency for
// the first synchronous RAM read; subsequent bytes are prefetched while the
// current byte's high nibble is being transferred.

`default_nettype none
module ctw_psram_qpi_model #(
    parameter integer MEM_BYTES = 262144,
    parameter integer ADDR_W = $clog2(MEM_BYTES),
    parameter integer STRICT_BACKING = 0
) (
    input  logic       clk,
    input  logic       rstn,
    input  logic       cs_n,
    input  logic       sck,
    input  logic [3:0] dq_from_master,
    input  logic [3:0] dq_master_oe,
    output logic [3:0] dq_to_master
);
    localparam logic [2:0] ST_CMD   = 3'd0;
    localparam logic [2:0] ST_ADDR  = 3'd1;
    localparam logic [2:0] ST_WAIT  = 3'd2;
    localparam logic [2:0] ST_READ  = 3'd3;
    localparam logic [2:0] ST_WRITE = 3'd4;

    // Synchronous read + registered write pattern intended to infer Cyclone-V
    // embedded RAM.  The memory contents intentionally have no reset.
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] mem [0:MEM_BYTES-1];
    logic [ADDR_W-1:0] ram_rd_addr_q;
    logic [7:0]        ram_rdata_q;

    logic [2:0] state_q;
    logic last_sck_q, last_cs_n_q;
    logic [3:0] count_q;
    logic [7:0] cmd_q;
    logic [23:0] addr_shift_q;
    logic [23:0] mem_addr_q;
    logic nibble_low_q;
    logic [7:0] write_byte_q;
    logic [7:0] read_byte_q;

    wire sck_rise = sck && !last_sck_q;
    wire cs_fall  = !cs_n && last_cs_n_q;
    wire [ADDR_W-1:0] ram_index = mem_addr_q[ADDR_W-1:0];
    wire [ADDR_W-1:0] ram_next_index = ram_index + {{(ADDR_W-1){1'b0}}, 1'b1};

    // A write occurs on the second data nibble of a QPI write byte.  Keeping
    // the memory access in this small clocked block avoids combinational reads
    // from the large array and gives Quartus a canonical RAM inference form.
    wire backed_addr = STRICT_BACKING == 0 || mem_addr_q[22:ADDR_W]==0;
    wire ram_write_now = backed_addr && (!cs_n) && sck_rise && (state_q == ST_WRITE) &&
                         (&dq_master_oe) && nibble_low_q;

    always_ff @(posedge clk) begin
        if (ram_write_now)
            mem[ram_index] <= {write_byte_q[7:4], dq_from_master};

        // One-clock synchronous read port.
        ram_rdata_q <= mem[ram_rd_addr_q];
    end

    always @* begin
        if (!cs_n && state_q == ST_READ)
            dq_to_master = !backed_addr ? 4'hf : (nibble_low_q ? read_byte_q[3:0] : read_byte_q[7:4]);
        else
            dq_to_master = 4'h0;
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            state_q       <= ST_CMD;
            last_sck_q    <= 1'b0;
            last_cs_n_q   <= 1'b1;
            count_q       <= 4'd0;
            cmd_q         <= 8'd0;
            addr_shift_q  <= 24'd0;
            mem_addr_q    <= 24'd0;
            nibble_low_q  <= 1'b0;
            write_byte_q  <= 8'd0;
            read_byte_q   <= 8'd0;
            ram_rd_addr_q <= {ADDR_W{1'b0}};
        end else begin
            last_sck_q  <= sck;
            last_cs_n_q <= cs_n;

            if (cs_n) begin
                state_q      <= ST_CMD;
                count_q      <= 4'd0;
                nibble_low_q <= 1'b0;
            end else if (cs_fall) begin
                state_q      <= ST_CMD;
                count_q      <= 4'd0;
                cmd_q        <= 8'd0;
                addr_shift_q <= 24'd0;
                nibble_low_q <= 1'b0;
            end else if (sck_rise) begin
                case (state_q)
                    ST_CMD: begin
                        if (&dq_master_oe) begin
                            if (count_q == 4'd0) begin
                                cmd_q[7:4] <= dq_from_master;
                                count_q <= 4'd1;
                            end else begin
                                cmd_q[3:0] <= dq_from_master;
                                count_q <= 4'd0;
                                state_q <= ST_ADDR;
                            end
                        end
                    end

                    ST_ADDR: begin
                        if (&dq_master_oe) begin
                            addr_shift_q <= {addr_shift_q[19:0], dq_from_master};
                            if (count_q == 4'd5) begin
                                mem_addr_q <= {addr_shift_q[19:0], dq_from_master};
                                count_q <= 4'd0;
                                if (cmd_q == 8'hEB) begin
                                    // Start the first synchronous RAM read as
                                    // soon as the QPI address is complete.
                                    ram_rd_addr_q <= {addr_shift_q[ADDR_W-5:0], dq_from_master};
                                    state_q <= ST_WAIT;
                                end else if (cmd_q == 8'h02) begin
                                    state_q <= ST_WRITE;
                                end else begin
                                    state_q <= ST_CMD;
                                end
                            end else begin
                                count_q <= count_q + 1'b1;
                            end
                        end
                    end

                    ST_WAIT: begin
                        // Six QPI wait clocks for 0xEB.  The synchronous RAM
                        // result is ready well before the first data nibble.
                        if (count_q == 4'd5) begin
                            count_q      <= 4'd0;
                            nibble_low_q <= 1'b0;
                            read_byte_q  <= ram_rdata_q;
                            state_q      <= ST_READ;
                        end else begin
                            count_q <= count_q + 1'b1;
                        end
                    end

                    ST_READ: begin
                        if (nibble_low_q) begin
                            // Low nibble of the current byte has just been
                            // consumed.  Move the already-prefetched next byte
                            // into the QPI output register.
                            nibble_low_q <= 1'b0;
                            mem_addr_q   <= mem_addr_q + 24'd1;
                            read_byte_q  <= ram_rdata_q;
                        end else begin
                            // High nibble is being consumed.  Prefetch the next
                            // byte; the intervening system clock before the low
                            // nibble completes provides the RAM read latency.
                            nibble_low_q  <= 1'b1;
                            ram_rd_addr_q <= ram_next_index;
                        end
                    end

                    ST_WRITE: begin
                        if (&dq_master_oe) begin
                            if (!nibble_low_q) begin
                                write_byte_q[7:4] <= dq_from_master;
                                nibble_low_q <= 1'b1;
                            end else begin
                                // The actual memory write is performed by the
                                // dedicated RAM inference block above.
                                write_byte_q[3:0] <= dq_from_master;
                                mem_addr_q <= mem_addr_q + 24'd1;
                                nibble_low_q <= 1'b0;
                            end
                        end
                    end

                    default: state_q <= ST_CMD;
                endcase
            end
        end
    end
endmodule
`default_nettype wire
