// SPDX-License-Identifier: Apache-2.0
// FPGA-only memory fixture. The three chips persist across MCU reset.
module ctw_memory_models (
    input wire clk, power_n,
    input wire sck, fcs, acs, bcs,
    input wire [3:0] master_dq, master_oe,
    output wire [3:0] flash_dq, flash_oe, data_to_master,
    output wire flash_xip, flash_image, flash_busy, qpi_a, qpi_b
);
    wire [3:0] ram_a_dq, ram_b_dq;

    // Undriven bits are modeled as ones on read. DQ0 of the SPI flash
    // being undriven does not matter when we sample its DQ1 output.
    assign data_to_master = !fcs ? (flash_dq | ~flash_oe) :
                            !acs && qpi_a ? ram_a_dq :
                            !bcs && qpi_b ? ram_b_dq : 4'hf;
    ctw_flash_model flash_i(
        .clk(clk),.rst_n(power_n),.cs_n(fcs),.sck(sck),.dq_i(master_dq),
        .dq_o(flash_dq),.dq_oe(flash_oe),.xip(flash_xip),
        .image_present(flash_image),.busy(flash_busy)
    );
    ctw_psram_mode_model mode_a(
        .clk(clk),.rst_n(power_n),.cs_n(acs),.sck(sck),.dq(master_dq),.qpi(qpi_a)
    );
    ctw_psram_mode_model mode_b(
        .clk(clk),.rst_n(power_n),.cs_n(bcs),.sck(sck),.dq(master_dq),.qpi(qpi_b)
    );
    ctw_psram_qpi_model #(.MEM_BYTES(4096),.STRICT_BACKING(1)) ram_a(
        .clk(clk),.rstn(power_n && qpi_a),.cs_n(acs),.sck(sck),
        .dq_from_master(master_dq),.dq_master_oe(master_oe),.dq_to_master(ram_a_dq)
    );
    ctw_psram_qpi_model #(.MEM_BYTES(4096),.STRICT_BACKING(1)) ram_b(
        .clk(clk),.rstn(power_n && qpi_b),.cs_n(bcs),.sck(sck),
        .dq_from_master(master_dq),.dq_master_oe(master_oe),.dq_to_master(ram_b_dq)
    );
endmodule
