// SPDX-License-Identifier: Apache-2.0
// W25Q128JVSIM FPGA protocol subset, one backed 4 KiB sector.
// SCK is oversampled on clk. Both host SPI and internal TinyQV use this model.
module ctw_flash_model (
    input wire clk, rst_n, cs_n, sck,
    input wire [3:0] dq_i,
    output reg [3:0] dq_o, dq_oe,
    output reg xip, image_present,
    output wire busy
);
    localparam [3:0] IDLE=0, CMD=1, ADDR=2, PAGE=3, QADDR=4, QMODE=5,
                     QDUMMY=6, QREAD=7, SERIAL_OUT=8, SR2_IN=9, IGNORE=10;
    localparam [1:0] OP_NONE=0, OP_ERASE=1, OP_PAGE_RD=2, OP_PAGE_WR=3;

    (* ramstyle = "M10K, no_rw_check" *) reg [7:0] flash [0:4095];
    (* ramstyle = "M10K, no_rw_check" *) reg [7:0] page_buffer [0:255];
    reg [7:0] memory_q, staged_q;
    reg [11:0] raddr, op_addr;
    reg [11:0] page_start;
    reg [7:0] page_count, page_index;
    reg page_full;
    reg [3:0] state;
    reg [1:0] op;
    reg old_cs, old_sck;
    reg [4:0] count;
    reg [7:0] shift, cmd, out_byte;
    reg [23:0] address, qaddr;
    reg [7:0] mode_shift;
    reg [1:0] id_index;
    reg [2:0] bit_index;
    reg serial_out_started;
    reg low_nibble, wel, volatile_wel, qe, mode_valid, mode_next, erase_req, sr2_valid, sr2_next;
    wire rise = sck && !old_sck;
    wire fall = !sck && old_sck;
    wire select = !cs_n && old_cs;
    wire deselect = cs_n && !old_cs;
    wire [7:0] new_byte = {shift[6:0],dq_i[0]};
    wire [23:0] serial_addr = {address[22:0],dq_i[0]};
    wire [23:0] quad_addr = {address[19:0],dq_i};
    wire [7:0] new_mode = {mode_shift[3:0],dq_i};
    wire [7:0] status = {6'd0,wel,busy};
    wire [7:0] pp_limit = page_full ? 8'hff : page_count-1'b1;
    wire staged_write = rst_n && !cs_n && rise && state==PAGE && count==7 &&
                        wel && !busy && address[23:12]==0;
    assign busy = op != OP_NONE;

    integer i;
    initial for (i=0;i<4096;i=i+1) flash[i] = 8'hff;

    wire [11:0] ram_ra = op==OP_PAGE_RD || op==OP_PAGE_WR ? op_addr : raddr;
    always @(posedge clk) begin
        memory_q <= flash[ram_ra];
        staged_q <= page_buffer[page_index];
        if (staged_write) page_buffer[page_count] <= new_byte;
        if (rst_n && (op==OP_ERASE || op==OP_PAGE_WR))
            flash[op_addr] <= op==OP_ERASE ? 8'hff : (memory_q & staged_q);
    end

    always @* begin
        dq_o=0;
        dq_oe=0;
        if (rst_n && !cs_n) begin
            if (state==QREAD) begin
                dq_oe=4'hf;
                dq_o=low_nibble ? out_byte[3:0] : out_byte[7:4];
            end else if (state==SERIAL_OUT && serial_out_started) begin
                dq_oe=4'b0010;
                case (cmd)
                    8'h05: dq_o[1]=status[7-bit_index];
                    8'h35: dq_o[1]=bit_index==6 && qe;
                    8'h03: dq_o[1]=qaddr[23:12]==0 ? memory_q[7-bit_index] : 1'b1;
                    default: dq_o[1]=out_byte[7-bit_index];
                endcase
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            old_cs<=1; old_sck<=0; state<=IDLE; count<=0;
            shift<=0; cmd<=0; out_byte<=0; address<=0; qaddr<=0;
            mode_shift<=0; mode_valid<=0; mode_next<=0; xip<=0;
            bit_index<=0; serial_out_started<=0; low_nibble<=0; id_index<=0; wel<=0; volatile_wel<=0; qe<=0;
            erase_req<=0; sr2_valid<=0; sr2_next<=0;
            image_present<=0; op<=OP_NONE; op_addr<=0; raddr<=0;
            page_start<=0; page_count<=0; page_index<=0; page_full<=0;
        end else begin
            old_cs<=cs_n;
            old_sck<=sck;
            case (op)
                OP_ERASE: begin
                    op_addr<=op_addr+1'b1;
                    if (&op_addr) op<=OP_NONE;
                end
                OP_PAGE_RD: op<=OP_PAGE_WR;
                OP_PAGE_WR: begin
                    if (op_addr==0 && (memory_q & staged_q)!=8'hff) image_present<=1;
                    if (page_index==pp_limit) op<=OP_NONE;
                    else begin
                        page_index<=page_index+1'b1;
                        op_addr[7:0]<=op_addr[7:0]+1'b1;
                        op<=OP_PAGE_RD;
                    end
                end
                default: ;
            endcase
            if (deselect) begin
                state<=IDLE;
                if (!busy) begin
                    if (mode_valid) xip<=mode_next;
                    if (cmd==8'h06 && state==IGNORE && !xip) wel<=1;
                    if (cmd==8'h04 && state==IGNORE && !xip) wel<=0;
                    if (cmd==8'h50 && state==IGNORE && !xip) volatile_wel<=1;
                    if (sr2_valid && (wel || volatile_wel)) begin
                        qe<=sr2_next; wel<=0; volatile_wel<=0;
                    end
                    if (erase_req && wel) begin
                        op<=OP_ERASE; op_addr<=0; wel<=0; image_present<=0;
                    end
                    if (state==PAGE && wel && (page_count!=0 || page_full) && address[23:12]==0) begin
                        op<=OP_PAGE_RD; op_addr<=page_start; page_index<=0; wel<=0;
                    end
                end
            end else if (select) begin
                state<=xip && !busy ? QADDR : CMD;
                count<=0; shift<=0; cmd<=0; address<=0;
                mode_valid<=0; mode_shift<=0; erase_req<=0; sr2_valid<=0;
                page_count<=0; page_full<=0; bit_index<=0; id_index<=0; serial_out_started<=0;
            end else if (!cs_n && state==SERIAL_OUT && fall) begin
                // SPI flash launches DO on a falling edge. The first falling
                // edge after the command/address makes bit 7 available; every
                // later falling edge advances the bit. Keep DO stable through
                // the high phase even if the master samples after SCK rises.
                if (!serial_out_started) serial_out_started<=1;
                else begin
                    bit_index<=bit_index+1'b1;
                    if (bit_index==7) begin
                        if (cmd==8'h9f) begin
                            case (id_index)
                                0: begin id_index<=1; out_byte<=8'h70; end
                                1: begin id_index<=2; out_byte<=8'h18; end
                                default: begin id_index<=0; out_byte<=8'hef; end
                            endcase
                        end else if (cmd==8'h03) begin
                            qaddr<=qaddr+1'b1; raddr<=raddr+1'b1;
                        end
                    end
                end
            end else if (!cs_n && rise) begin
                case (state)
                    CMD: begin
                        shift<=new_byte;
                        if (count==7) begin
                            cmd<=new_byte; count<=0;
                            if (new_byte==8'h05) state<=SERIAL_OUT;
                            else if (busy) state<=IGNORE;
                            else begin
                                case (new_byte)
                                    8'h9f: begin out_byte<=8'hef; state<=SERIAL_OUT; end
                                    8'h35: state<=SERIAL_OUT;
                                    8'h03,8'h02,8'h20: state<=ADDR;
                                    8'h31: state<=SR2_IN;
                                    8'heb: state<=qe ? QADDR : IGNORE;
                                    default: state<=IGNORE;
                                endcase
                            end
                        end else count<=count+1'b1;
                    end
                    SR2_IN: begin
                        shift<=new_byte;
                        if (count==7) begin
                            sr2_next<=new_byte[1]; sr2_valid<=1; state<=IGNORE;
                        end else count<=count+1'b1;
                    end
                    ADDR: begin
                        address<=serial_addr;
                        if (count==23) begin
                            count<=0; qaddr<=serial_addr; raddr<=serial_addr[11:0];
                            if (cmd==8'h03) state<=SERIAL_OUT;
                            else if (cmd==8'h02) begin state<=PAGE; page_start<=serial_addr[11:0]; end
                            else begin state<=IGNORE; erase_req<=serial_addr[23:12]==0; end
                        end else count<=count+1'b1;
                    end
                    PAGE: begin
                        shift<=new_byte;
                        if (count==7) begin
                            count<=0; page_count<=page_count+1'b1;
                            if (&page_count) page_full<=1;
                        end else count<=count+1'b1;
                    end
                    QADDR: begin
                        address<=quad_addr;
                        if (count==5) begin
                            qaddr<=quad_addr; raddr<=quad_addr[11:0]; count<=0; state<=QMODE;
                        end else count<=count+1'b1;
                    end
                    QMODE: begin
                        mode_shift<=new_mode;
                        if (count==1) begin
                            mode_next<=new_mode[5:4]==2'b10;
                            mode_valid<=1; state<=QDUMMY; count<=0;
                        end else count<=count+1'b1;
                    end
                    QDUMMY: begin
                        if (count==3) begin
                            low_nibble<=0; state<=QREAD;
                            out_byte<=qaddr[23:12]==0 ? memory_q : 8'hff;
                        end else count<=count+1'b1;
                    end
                    QREAD: begin
                        low_nibble<=!low_nibble;
                        if (low_nibble) begin
                            qaddr<=qaddr+1'b1;
                            out_byte<=qaddr<24'h000fff ? memory_q : 8'hff;
                        end else raddr<=raddr+1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
