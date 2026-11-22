`timescale 1ns/1ps
// Separate pin-level fixture for pre-silicon verification, not synthesis.
// PAD_NS is *assumed* one-direction transport including board + mux + pads.
// A passing 30 + 30 ns sweep is not a measured delay bound for any shuttle.
module ctw_timed_memory_fixture #(parameter integer PAD_NS=30)(
    input wire power_n,
    input wire cpu_sck, cpu_fcs, cpu_acs, cpu_bcs,
    input wire [3:0] cpu_dq, cpu_dq_oe,
    output wire [3:0] from_mem, from_mem_oe,
    output wire flash_xip, qpi_a, qpi_b,
    output wire flash_qe
);
    reg mclk=0;
    always #2.5 mclk=~mclk;
    wire sck, fcs, acs, bcs;
    wire [3:0] dq, dq_oe;
    assign #(PAD_NS) sck=cpu_sck;
    assign #(PAD_NS) fcs=cpu_fcs;
    assign #(PAD_NS) acs=cpu_acs;
    assign #(PAD_NS) bcs=cpu_bcs;
    assign #(PAD_NS) dq=cpu_dq;
    assign #(PAD_NS) dq_oe=cpu_dq_oe;
    wire [3:0] f_q, f_oe, a_q, a_oe, b_q, b_oe;
    ctw_flash_model flash_i(
        .clk(mclk),.rst_n(power_n),.cs_n(fcs),.sck(sck),.dq_i(dq),
        .dq_o(f_q),.dq_oe(f_oe),.xip(flash_xip),.image_present(),.busy()
    );
    assign flash_qe=flash_i.qe;
    // The FPGA model produces its runtime quad-read nibble after rising SCK.
    // Re-time that nibble at the emulated memory pins to the physical falling
    // edge. The already-correct serial path goes through unchanged.
    reg [3:0] f_quad_hold;
    reg f_quad_valid;
    always @(negedge sck or posedge fcs or negedge power_n) begin
        if (!power_n || fcs) begin f_quad_hold<=0; f_quad_valid<=0; end
        else begin f_quad_hold<=f_q; f_quad_valid<=(&f_oe); end
    end
    wire [3:0] f_devs, f_enable;
    // Round 7 ns device delay/disable is a test assumption, not a corner spec.
    assign #(7) f_devs = (&f_oe) ? f_quad_hold : f_q;
    assign #(7) f_enable = !fcs && (&f_oe) ? {4{f_quad_valid}} : f_oe;
    ctw_psram_mode_model #(.POR_CYCLES(30000)) mode_a(
        .clk(mclk),.rst_n(power_n),.cs_n(acs),.sck(sck),.dq(dq),.qpi(qpi_a));
    ctw_psram_mode_model #(.POR_CYCLES(30000)) mode_b(
        .clk(mclk),.rst_n(power_n),.cs_n(bcs),.sck(sck),.dq(dq),.qpi(qpi_b));
    ctw_psram_reference #(.MEM_BYTES(4096)) ram_a(
        .clk(mclk),.rstn(power_n && qpi_a),.cs_n(acs),.sck(sck),
        .dq_from_master(dq),.dq_master_oe(dq_oe),.dq_to_master(a_q),.drive_oe(a_oe));
    ctw_psram_reference #(.MEM_BYTES(4096)) ram_b(
        .clk(mclk),.rstn(power_n && qpi_b),.cs_n(bcs),.sck(sck),
        .dq_from_master(dq),.dq_master_oe(dq_oe),.dq_to_master(b_q),.drive_oe(b_oe));
    assign #(PAD_NS) from_mem = f_enable!=0 ? f_devs : a_oe!=0 ? a_q : b_q;
    assign #(PAD_NS) from_mem_oe = f_enable | a_oe | b_oe;
    always @(negedge mclk) if (power_n) begin
        if ((!fcs && !acs) || (!fcs && !bcs) || (!acs && !bcs))
            $fatal(1,"external endpoint observed overlapping chip-selects");
        if ((dq_oe & (f_enable | a_oe | b_oe))!=0)
            $fatal(1,"controller and memory drive DQ concurrently at device pins");
        if (((f_enable!=0)&&(a_oe!=0||b_oe!=0)) || (a_oe!=0 && b_oe!=0))
            $fatal(1,"multiple external chips drive DQ");
    end
endmodule
