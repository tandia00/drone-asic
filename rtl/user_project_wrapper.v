// -----------------------------------------------------------------------------
// Caravel User Project Wrapper — SAHEL-1
// Cf. https://github.com/efabless/caravel — interface fixée par eFabless.
// -----------------------------------------------------------------------------
`default_nettype none

module user_project_wrapper (
`ifdef USE_POWER_PINS
    inout wire vdda1, inout wire vdda2,
    inout wire vssa1, inout wire vssa2,
    inout wire vccd1, inout wire vccd2,
    inout wire vssd1, inout wire vssd2,
`endif
    input  wire        wb_clk_i,
    input  wire        wb_rst_i,

    // Caravel mgmt SoC <-> user project Wishbone (non utilisé ici)
    input  wire        wbs_stb_i,
    input  wire        wbs_cyc_i,
    input  wire        wbs_we_i,
    input  wire [3:0]  wbs_sel_i,
    input  wire [31:0] wbs_dat_i,
    input  wire [31:0] wbs_adr_i,
    output wire        wbs_ack_o,
    output wire [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  wire [127:0] la_data_in,
    output wire [127:0] la_data_out,
    input  wire [127:0] la_oenb,

    // IOs (38 broches)
    input  wire [37:0] io_in,
    output wire [37:0] io_out,
    output wire [37:0] io_oeb,

    // IRQ
    output wire [2:0]  user_irq
);
    // Pas de réponse au mgmt SoC en v0.1
    assign wbs_ack_o = 1'b0;
    assign wbs_dat_o = 32'h0;
    assign la_data_out = 128'h0;
    assign user_irq    = 3'h0;

    // Mapping pinout (cf. docs/pinout.md)
    wire        rst_n   = io_in[1];
    wire        u0_rx   = io_in[2];
    wire        u1_rx   = io_in[4];
    wire        spi0_miso = io_in[13];
    wire        spi1_miso = io_in[18];
    wire [11:0] gpio_in   = io_in[37:26];

    wire u0_tx, u1_tx;
    wire spi0_cs, spi0_sclk, spi0_mosi;
    wire spi1_cs, spi1_sclk, spi1_mosi;
    wire [5:0]  pwm;
    wire [11:0] gpio_out, gpio_oeb;

    agri_drone_soc u_soc (
        .clk_i(wb_clk_i),
        .rst_n_i(rst_n),
        .uart0_rx_i(u0_rx), .uart0_tx_o(u0_tx),
        .uart1_rx_i(u1_rx), .uart1_tx_o(u1_tx),
        .i2c0_scl_io(io_in[6]), .i2c0_sda_io(io_in[7]),
        .i2c1_scl_io(io_in[8]), .i2c1_sda_io(io_in[9]),
        .spi0_cs_o(spi0_cs), .spi0_sclk_o(spi0_sclk), .spi0_mosi_o(spi0_mosi),
        .spi0_miso_i(spi0_miso), .spi0_dio0_i(io_in[14]),
        .spi1_cs_o(spi1_cs), .spi1_sclk_o(spi1_sclk), .spi1_mosi_o(spi1_mosi),
        .spi1_miso_i(spi1_miso),
        .pwm_o(pwm),
        .gpio_in_i(gpio_in), .gpio_out_o(gpio_out), .gpio_oeb_o(gpio_oeb)
    );

    // io_out / io_oeb (oeb=0 → output)
    assign io_out[1:0]   = 2'b00;
    assign io_oeb[1:0]   = 2'b11;        // inputs
    assign io_out[3]     = u0_tx;
    assign io_oeb[3]     = 1'b0;
    assign io_out[2]     = 1'b0;
    assign io_oeb[2]     = 1'b1;
    assign io_out[5]     = u1_tx;
    assign io_oeb[5]     = 1'b0;
    assign io_oeb[4]     = 1'b1;
    assign io_oeb[7:6]   = 2'b11;        // I2C open-drain géré par module
    assign io_oeb[9:8]   = 2'b11;
    assign io_out[10]    = spi0_cs;   assign io_oeb[10] = 1'b0;
    assign io_out[11]    = spi0_sclk; assign io_oeb[11] = 1'b0;
    assign io_out[12]    = spi0_mosi; assign io_oeb[12] = 1'b0;
    assign io_oeb[13]    = 1'b1;
    assign io_oeb[14]    = 1'b1;
    assign io_out[15]    = spi1_cs;   assign io_oeb[15] = 1'b0;
    assign io_out[16]    = spi1_sclk; assign io_oeb[16] = 1'b0;
    assign io_out[17]    = spi1_mosi; assign io_oeb[17] = 1'b0;
    assign io_oeb[18]    = 1'b1;
    assign io_oeb[19]    = 1'b1;
    assign io_out[25:20] = pwm;
    assign io_oeb[25:20] = 6'b000000;
    assign io_out[37:26] = gpio_out;
    assign io_oeb[37:26] = gpio_oeb;

    // Tie-off non utilisés
    assign io_out[6]   = 1'b0;
    assign io_out[7]   = 1'b0;
    assign io_out[8]   = 1'b0;
    assign io_out[9]   = 1'b0;
    assign io_out[13]  = 1'b0;
    assign io_out[14]  = 1'b0;
    assign io_out[18]  = 1'b0;
    assign io_out[19]  = 1'b0;
    assign io_out[4]   = 1'b0;
    assign io_out[0]   = 1'b0;

endmodule
