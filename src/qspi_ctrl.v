/*
 * HASEMI adaptation of Michael Bell TinyQV QSPI controller.
 * SPDX-License-Identifier: Apache-2.0
 *
 * Runtime target: W25Q128JVSIM continuous read and two APS6404L-3SQR-SN
 * (QPI read 0xEB, six dummy clocks; QPI write 0x02). The shared
 * ctw_qspi_boot block initializes these devices before releasing the core.
 */

module qspi_controller (
    input clk,
    input rstn,

    input      [3:0] spi_data_in,
    output reg [3:0] spi_data_out,
    output reg [3:0] spi_data_oe,
    output reg       spi_clk_out,

    output reg       spi_flash_select,
    output reg       spi_ram_a_select,
    output reg       spi_ram_b_select,

    // Address map:
    // 0x0000000 - 0x0FFFFFF: Flash
    // 0x1000000 - 0x17FFFFF: RAM A
    // 0x1800000 - 0x1FFFFFF: RAM B
    input [24:0] addr_in,
    input  [7:0] data_in,
    input        start_read,
    input        start_write,
    input        stall_txn,
    input        stop_txn,

    output [7:0] data_out,
    output reg   data_req,
    output reg   data_ready,
    output       busy,

    // Hasemi stream extension:
    // Assert one core clock before data_req, while the current write byte is
    // still being shifted. A ready/valid stream can consume its current byte
    // on this pulse so the NEXT byte is stable before qspi_controller samples
    // data_in at the following write-byte boundary.
    output       data_req_early
);

    localparam ADDR_BITS = 24;
    localparam DATA_WIDTH_BITS = 8;

    localparam FSM_IDLE = 0;
    localparam FSM_CMD  = 1;
    localparam FSM_ADDR = 2;
    localparam FSM_DUMMY1 = 3;
    localparam FSM_DUMMY2 = 4;
    localparam FSM_DATA = 5;
    localparam FSM_STALLED = 6;
    localparam FSM_STALL_RECOVER = 7;

    localparam [7:0] PSRAM_QPI_READ_CMD  = 8'hEB;
    localparam [7:0] PSRAM_QPI_WRITE_CMD = 8'h02;
    localparam [2:0] PSRAM_QPI_READ_WAIT_CLOCKS = 3'd6;

    reg [2:0] fsm_state;
    reg       is_writing;
    reg [ADDR_BITS-1:0]       addr;
    reg [DATA_WIDTH_BITS-1:0] data;
    reg [2:0] nibbles_remaining;
    reg [2:0] delay_cycles_cfg;
    reg [7:0] spi_in_buffer;

    assign data_out = data;
    assign busy = fsm_state != FSM_IDLE;

    // For a QPI write, nibbles_remaining==1 with spi_clk_out high is the
    // half-cycle immediately before the existing data_req pulse. This is the
    // correct point for a ready/valid producer to advance to its next byte.
    //
    // Do NOT replace data_req itself: the original TinyQV CPU write path uses
    // data_req semantics unchanged. Only the Hasemi stream writer consumes
    // data_req_early.
    assign data_req_early =
        is_writing &&
        (fsm_state == FSM_DATA) &&
        spi_clk_out &&
        (nibbles_remaining == 3'd1);

    reg stop_txn_reg;
    wire stop_txn_now = stop_txn_reg || (stop_txn && (!is_writing || spi_clk_out));
    always @(posedge clk) begin
        if (!rstn)
            stop_txn_reg <= 0;
        else
            stop_txn_reg <= stop_txn && !stop_txn_now;
    end

    reg [2:0] read_cycles_count;

    reg last_ram_a_sel;
    reg last_ram_b_sel;
    wire ram_a_block = (last_ram_a_sel == 0) && addr_in[24:23] == 2'b10;
    wire ram_b_block = (last_ram_b_sel == 0) && addr_in[24:23] == 2'b11;

    // TinyQV input sampling compensation. Drive spi_data_in[2:0] to a stable
    // configuration while rstn is low. Start with 0 for FPGA bring-up.
    always @(posedge clk) begin
        if (!rstn)
            delay_cycles_cfg <= spi_data_in[2:0];
    end

    always @(posedge clk) begin
        if (!rstn || stop_txn_now) begin
            fsm_state <= FSM_IDLE;
            is_writing <= 0;
            nibbles_remaining <= 0;
            data_ready <= 0;
            spi_clk_out <= 0;
            spi_data_oe <= 4'b0000;
            spi_flash_select <= 1;
            spi_ram_a_select <= 1;
            spi_ram_b_select <= 1;
            data_req <= 0;
            read_cycles_count <= 0;
        end else begin
            data_ready <= 0;
            data_req <= 0;

            if (fsm_state == FSM_IDLE) begin
                if ((start_read || start_write) && !ram_a_block && !ram_b_block) begin
                    // Flash has no command phase: it is assumed to be in
                    // continuous read mode. RAM always starts with a QPI command.
                    fsm_state <= addr_in[24] ? FSM_CMD : FSM_ADDR;
                    is_writing <= !start_read && addr_in[24];
                    nibbles_remaining <= addr_in[24] ? 3'd1 : 3'd5;
                    spi_data_oe <= 4'b1111;
                    spi_clk_out <= 0;
                    spi_flash_select <= addr_in[24];
                    spi_ram_a_select <= addr_in[24:23] != 2'b10;
                    spi_ram_b_select <= addr_in[24:23] != 2'b11;
                end
            end else begin
                if (read_cycles_count == 0)
                    read_cycles_count <= 3'b001;
                else
                    read_cycles_count <= read_cycles_count - 3'b001;

                if (fsm_state == FSM_STALLED) begin
                    spi_clk_out <= 0;
                    if (!stall_txn && read_cycles_count < 3'b010) begin
                        data_ready <= !is_writing;
                        if (is_writing) begin
                            fsm_state <= FSM_DATA;
                            read_cycles_count <= 3'b000;
                        end else begin
                            fsm_state <= (delay_cycles_cfg[2:1] == 2'b00) ? FSM_DATA : FSM_STALL_RECOVER;
                            read_cycles_count <= {1'b0, delay_cycles_cfg[2], delay_cycles_cfg[0]};
                        end
                    end
                end else begin
                    spi_clk_out <= !spi_clk_out;
                    if (((fsm_state == FSM_DATA && !is_writing) || fsm_state == FSM_STALL_RECOVER) ?
                        (read_cycles_count == 0) : spi_clk_out) begin

                        if (nibbles_remaining == 0 ||
                            (fsm_state == FSM_STALL_RECOVER && delay_cycles_cfg[2])) begin

                            if (fsm_state == FSM_DATA || fsm_state == FSM_STALL_RECOVER) begin
                                data_ready <= !is_writing && !stall_txn;
                                nibbles_remaining <= 3'd1;
                                if (stall_txn) begin
                                    fsm_state <= FSM_STALLED;
                                    read_cycles_count <= delay_cycles_cfg | 3'b001;
                                end else begin
                                    fsm_state <= FSM_DATA;
                                end
                            end else begin
                                fsm_state <= fsm_state + 1'b1;

                                if (fsm_state == FSM_CMD) begin
                                    nibbles_remaining <= 3'd5; // 24-bit address
                                end
                                else if (fsm_state == FSM_ADDR) begin
                                    if (is_writing) begin
                                        // APS6404L QPI write 0x02 has no wait clocks.
                                        fsm_state <= FSM_DATA;
                                        nibbles_remaining <= 3'd1;
                                    end else if (spi_flash_select) begin
                                        // RAM selected. ESP-PSRAM64H 0xEB QPI Fast Read:
                                        // command + 24-bit address + six wait clocks + data.
                                        fsm_state <= FSM_DUMMY2;
                                        spi_data_oe <= 4'b0000;
                                        nibbles_remaining <= PSRAM_QPI_READ_WAIT_CLOCKS - 1'b1;
                                    end else begin
                                        // Flash selected. Continue the upstream W25Q128JV
                                        // continuous-read sequence with A0 mode byte.
                                        nibbles_remaining <= 3'd1;
                                    end
                                end
                                else if (fsm_state == FSM_DUMMY1) begin
                                    spi_data_oe <= 4'b0000;
                                    nibbles_remaining <= 3'd3; // four flash dummy clocks
                                end
                                else if (fsm_state == FSM_DUMMY2) begin
                                    nibbles_remaining <= 3'd1;
                                    read_cycles_count <= delay_cycles_cfg;
                                end
                            end
                        end else begin
                            if (fsm_state == FSM_STALL_RECOVER)
                                fsm_state <= FSM_DATA;
                            nibbles_remaining <= nibbles_remaining - 1'b1;
                        end
                    end else begin
                        data_req <= is_writing && (fsm_state == FSM_DATA) && nibbles_remaining == 0;
                    end
                end
            end
        end
    end

    always @(posedge clk) begin
        if (fsm_state == FSM_IDLE && (start_read || start_write)) begin
            // Each PSRAM has a separate chip-select; A23 selects the bank in
            // the SoC map and is not a physical address bit of either 8 MiB IC.
            addr <= {addr_in[24] ? 1'b0 : addr_in[23], addr_in[22:0]};
        end else if (fsm_state == FSM_ADDR && spi_clk_out) begin
            addr <= {addr[ADDR_BITS-5:0], 4'b0000};
        end
    end

    always @(posedge clk) begin
        if (is_writing) begin
            if (fsm_state == FSM_STALLED) begin
                data <= data_in;
            end else if (spi_clk_out) begin
                if (nibbles_remaining == 0) begin
                    data <= data_in;
                end else if (fsm_state == FSM_DATA) begin
                    data <= {data[DATA_WIDTH_BITS-5:0], spi_data_in};
                end
            end
        end else if (read_cycles_count == 0 && fsm_state == FSM_DATA) begin
            data <= {data[DATA_WIDTH_BITS-5:0], spi_data_in};
        end else if (read_cycles_count == 3'b010 && fsm_state == FSM_STALL_RECOVER) begin
            data <= {data[DATA_WIDTH_BITS-5:0], spi_in_buffer[7:4]};
        end else if (read_cycles_count == 0 && fsm_state == FSM_STALL_RECOVER) begin
            data <= {data[DATA_WIDTH_BITS-5:0], spi_in_buffer[3:0]};
        end else if (read_cycles_count[2:1] != 2'b00 && read_cycles_count[0] == 1'b0 && fsm_state == FSM_STALLED) begin
            spi_in_buffer <= {spi_in_buffer[3:0], spi_data_in};
        end
    end

    always @(*) begin
        case (fsm_state)
            FSM_CMD: begin
                if (is_writing) begin
                    if (nibbles_remaining[0])
                        spi_data_out = PSRAM_QPI_WRITE_CMD[7:4];
                    else
                        spi_data_out = PSRAM_QPI_WRITE_CMD[3:0];
                end else begin
                    if (nibbles_remaining[0])
                        spi_data_out = PSRAM_QPI_READ_CMD[7:4];
                    else
                        spi_data_out = PSRAM_QPI_READ_CMD[3:0];
                end
            end
            FSM_ADDR:
                spi_data_out = addr[ADDR_BITS-1:ADDR_BITS-4];
            FSM_DUMMY1:
                spi_data_out = 4'b1010; // W25Q128JV mode byte A0
            FSM_DATA:
                spi_data_out = data[DATA_WIDTH_BITS-1:DATA_WIDTH_BITS-4];
            default:
                spi_data_out = 4'b1010;
        endcase
    end

    // Allow two core clocks before reselecting the same RAM, preserving TinyQV upstream behavior.
    always @(posedge clk) begin
        if (!rstn) begin
            last_ram_a_sel <= 1;
            last_ram_b_sel <= 1;
        end else begin
            last_ram_a_sel <= spi_ram_a_select;
            last_ram_b_sel <= spi_ram_b_select;
        end
    end

endmodule
