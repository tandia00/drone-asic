// -----------------------------------------------------------------------------
// SAHEL-1 — Top SoC
// Cœur PicoRV32 + interconnect Wishbone + ROM + SRAM + périphériques drone.
// PicoRV32 est inclus en submodule git : ext/picorv32/picorv32.v
// -----------------------------------------------------------------------------
`default_nettype none

module agri_drone_soc (
    input  wire        clk_i,
    input  wire        rst_n_i,
    // UART
    input  wire        uart0_rx_i,
    output wire        uart0_tx_o,
    input  wire        uart1_rx_i,
    output wire        uart1_tx_o,
    // I²C
    inout  wire        i2c0_scl_io,
    inout  wire        i2c0_sda_io,
    inout  wire        i2c1_scl_io,
    inout  wire        i2c1_sda_io,
    // SPI0 (LoRa)
    output wire        spi0_cs_o,
    output wire        spi0_sclk_o,
    output wire        spi0_mosi_o,
    input  wire        spi0_miso_i,
    input  wire        spi0_dio0_i,
    // SPI1 (caméra)
    output wire        spi1_cs_o,
    output wire        spi1_sclk_o,
    output wire        spi1_mosi_o,
    input  wire        spi1_miso_i,
    // PWM
    output wire [5:0]  pwm_o,
    // GPIO
    input  wire [11:0] gpio_in_i,
    output wire [11:0] gpio_out_o,
    output wire [11:0] gpio_oeb_o
);
    wire rst = ~rst_n_i;

    // -------------------------------------------------------------------------
    // PicoRV32 master Wishbone
    // -------------------------------------------------------------------------
    wire        cpu_valid, cpu_ready;
    wire [31:0] cpu_addr, cpu_wdata, cpu_rdata;
    wire [3:0]  cpu_wstrb;

    picorv32_wb #(
        .PROGADDR_RESET(32'h0000_0000),
        .COMPRESSED_ISA(1)
    ) u_cpu (
        .wb_clk_i (clk_i),
        .wb_rst_i (rst),
        .wbm_adr_o(cpu_addr),
        .wbm_dat_o(cpu_wdata),
        .wbm_dat_i(cpu_rdata),
        .wbm_we_o (cpu_we),
        .wbm_sel_o(cpu_wstrb),
        .wbm_stb_o(cpu_valid),
        .wbm_ack_i(cpu_ready),
        .wbm_cyc_o(cpu_cyc),
        .irq      (32'h0)
    );
    wire cpu_we, cpu_cyc;

    // -------------------------------------------------------------------------
    // NDVI accelerator DMA master (bas priorité)
    // -------------------------------------------------------------------------
    wire [31:0] ndvi_dma_adr, ndvi_dma_dat_o, ndvi_dma_dat_i;
    wire        ndvi_dma_we,  ndvi_dma_stb,   ndvi_dma_cyc, ndvi_dma_ack;
    wire        ndvi_irq;
    wire [3:0]  ndvi_dma_sel = 4'hF;

    // -------------------------------------------------------------------------
    // Arbiter 2→1 : CPU (prio haute) + NDVI DMA (prio basse) → Wishbone master
    // -------------------------------------------------------------------------
    wire [31:0] arb_adr, arb_dat_o, arb_dat_i;
    wire [3:0]  arb_sel;
    wire        arb_we, arb_stb, arb_cyc, arb_ack;

    wb_arbiter u_arb (
        .clk_i(clk_i), .rst_i(rst),
        .m0_adr_i(cpu_addr), .m0_dat_i(cpu_wdata), .m0_dat_o(cpu_rdata),
        .m0_sel_i(cpu_wstrb), .m0_we_i(cpu_we), .m0_stb_i(cpu_valid),
        .m0_cyc_i(cpu_cyc),  .m0_ack_o(cpu_ready),
        .m1_adr_i(ndvi_dma_adr), .m1_dat_i(ndvi_dma_dat_o), .m1_dat_o(ndvi_dma_dat_i),
        .m1_sel_i(ndvi_dma_sel),  .m1_we_i(ndvi_dma_we), .m1_stb_i(ndvi_dma_stb),
        .m1_cyc_i(ndvi_dma_cyc), .m1_ack_o(ndvi_dma_ack),
        .s_adr_o(arb_adr), .s_dat_o(arb_dat_o), .s_dat_i(arb_dat_i),
        .s_sel_o(arb_sel), .s_we_o(arb_we), .s_stb_o(arb_stb),
        .s_cyc_o(arb_cyc), .s_ack_i(arb_ack)
    );

    // -------------------------------------------------------------------------
    // Interconnect (13 slaves : + NDVI CSR)
    // -------------------------------------------------------------------------
    localparam N = 13;
    wire [N*32-1:0] s_adr, s_dat_o, s_dat_i;
    wire [N*4-1:0]  s_sel;
    wire [N-1:0]    s_we, s_stb, s_cyc, s_ack;

    wb_intercon #(.NSLAVES(N)) u_xbar (
        .clk_i(clk_i), .rst_i(rst),
        .m_adr_i(arb_adr), .m_dat_i(arb_dat_o), .m_dat_o(arb_dat_i),
        .m_sel_i(arb_sel), .m_we_i(arb_we), .m_stb_i(arb_stb),
        .m_cyc_i(arb_cyc), .m_ack_o(arb_ack),
        .s_adr_o(s_adr), .s_dat_o(s_dat_o), .s_dat_i(s_dat_i),
        .s_sel_o(s_sel), .s_we_o(s_we), .s_stb_o(s_stb), .s_cyc_o(s_cyc),
        .s_ack_i(s_ack)
    );

    // helper macro pour brancher un slave
    `define WBSLV(IDX) \
        .wb_adr_i (s_adr [IDX*32 +: 32]), \
        .wb_dat_i (s_dat_o[IDX*32 +: 32]), \
        .wb_dat_o (s_dat_i[IDX*32 +: 32]), \
        .wb_sel_i (s_sel [IDX*4  +: 4 ]), \
        .wb_we_i  (s_we  [IDX]),          \
        .wb_stb_i (s_stb [IDX]),          \
        .wb_cyc_i (s_cyc [IDX]),          \
        .wb_ack_o (s_ack [IDX])

    // 0 : ROM (boot) — petite ROM hex 4KB simulation, en synthèse remplacée
    sram_wrap u_rom (.clk_i(clk_i), .rst_i(rst), `WBSLV(0));
    // 1 : SRAM
    sram_wrap u_sram (.clk_i(clk_i), .rst_i(rst), `WBSLV(1));

    // 2 : UART0 (GPS)
    uart u_uart0 (.clk_i(clk_i), .rst_i(rst), .rx_i(uart0_rx_i), .tx_o(uart0_tx_o), .irq_o(),
                  `WBSLV(2));
    // 3 : UART1 (debug)
    uart u_uart1 (.clk_i(clk_i), .rst_i(rst), .rx_i(uart1_rx_i), .tx_o(uart1_tx_o), .irq_o(),
                  `WBSLV(3));
    // 4 : I2C0
    i2c_master u_i2c0 (.clk_i(clk_i), .rst_i(rst),
                       .scl_io(i2c0_scl_io), .sda_io(i2c0_sda_io), `WBSLV(4));
    // 5 : I2C1
    i2c_master u_i2c1 (.clk_i(clk_i), .rst_i(rst),
                       .scl_io(i2c1_scl_io), .sda_io(i2c1_sda_io), `WBSLV(5));
    // 6 : SPI0 (LoRa)
    spi_master u_spi0 (.clk_i(clk_i), .rst_i(rst),
                       .sclk_o(spi0_sclk_o), .mosi_o(spi0_mosi_o), .miso_i(spi0_miso_i),
                       .cs_no(spi0_cs_o), `WBSLV(6));
    // 7 : SPI1 (caméra)
    spi_master u_spi1 (.clk_i(clk_i), .rst_i(rst),
                       .sclk_o(spi1_sclk_o), .mosi_o(spi1_mosi_o), .miso_i(spi1_miso_i),
                       .cs_no(spi1_cs_o), `WBSLV(7));
    // 8 : PWM
    pwm u_pwm (.clk_i(clk_i), .rst_i(rst), .pwm_o(pwm_o), `WBSLV(8));
    // 9 : GPIO (12 broches dans ce SoC)
    gpio #(.W(12)) u_gpio (.clk_i(clk_i), .rst_i(rst),
                 .gpio_in_i(gpio_in_i), .gpio_out_o(gpio_out_o), .gpio_oeb_o(gpio_oeb_o),
                 `WBSLV(9));
    // 10 : TIMER + WDT
    timer u_timer (.clk_i(clk_i), .rst_i(rst), .irq_o(), .wdt_reset_o(), `WBSLV(10));
    // 11 : AES-128
    aes128 u_aes (.clk_i(clk_i), .rst_i(rst), .irq_o(), `WBSLV(11));

    // 12 : NDVI accelerator (CSR) + DMA master via u_arb
    ndvi_accel u_ndvi (
        .clk_i(clk_i), .rst_i(rst),
        // CSR (slave)
        `WBSLV(12),
        // DMA master → arbiter m1
        .dma_adr_o(ndvi_dma_adr),
        .dma_dat_o(ndvi_dma_dat_o),
        .dma_dat_i(ndvi_dma_dat_i),
        .dma_we_o (ndvi_dma_we),
        .dma_stb_o(ndvi_dma_stb),
        .dma_cyc_o(ndvi_dma_cyc),
        .dma_ack_i(ndvi_dma_ack),
        .irq_o    (ndvi_irq)
    );

endmodule
