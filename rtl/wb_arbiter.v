// -----------------------------------------------------------------------------
// SAHEL-1 — Wishbone arbiter 2→1 à priorité fixe (m0 > m1).
// m0 = CPU (priorité haute pour garder la réactivité temps-réel du drone).
// m1 = DMA NDVI (charge bulk, peut attendre).
//
// Lorsque m0 n'a pas de cycle actif (m0_cyc=0) ET m1 demande, m1 est accordé.
// Durant un burst m0, m1 est mis en attente (ack=0, dat=0).
// -----------------------------------------------------------------------------
`default_nettype none

module wb_arbiter (
    input  wire        clk_i,
    input  wire        rst_i,

    // Master 0 (CPU, haute priorité)
    input  wire [31:0] m0_adr_i, input  wire [31:0] m0_dat_i,
    output wire [31:0] m0_dat_o, input  wire [3:0]  m0_sel_i,
    input  wire        m0_we_i,  input  wire        m0_stb_i,
    input  wire        m0_cyc_i, output wire        m0_ack_o,

    // Master 1 (NDVI DMA, basse priorité)
    input  wire [31:0] m1_adr_i, input  wire [31:0] m1_dat_i,
    output wire [31:0] m1_dat_o, input  wire [3:0]  m1_sel_i,
    input  wire        m1_we_i,  input  wire        m1_stb_i,
    input  wire        m1_cyc_i, output wire        m1_ack_o,

    // Slave sortie
    output wire [31:0] s_adr_o,  output wire [31:0] s_dat_o,
    input  wire [31:0] s_dat_i,  output wire [3:0]  s_sel_o,
    output wire        s_we_o,   output wire        s_stb_o,
    output wire        s_cyc_o,  input  wire        s_ack_i
);
    // Arbitration transaction-locked : une fois un maître granté, il garde
    // le bus jusqu'à ce que son 'cyc' retombe. Cela évite de couper une
    // transaction WB au milieu (ce qui provoquerait un deadlock côté slave
    // qui n'ack pas, ou côté master qui n'a jamais son ack).
    // Priorité à m0 (CPU) quand les deux demandent simultanément au repos.
    reg  grant;   // 0 = m0, 1 = m1
    always @(posedge clk_i) begin
        if (rst_i) grant <= 1'b0;
        else begin
            case (grant)
                1'b0: if (!m0_cyc_i && m1_cyc_i) grant <= 1'b1; // libre et m1 demande
                1'b1: if (!m1_cyc_i)            grant <= 1'b0;  // m1 a fini
            endcase
        end
    end
    wire sel_m0 = (grant == 1'b0);
    wire sel_m1 = (grant == 1'b1);

    assign s_adr_o = sel_m0 ? m0_adr_i : (sel_m1 ? m1_adr_i : 32'h0);
    assign s_dat_o = sel_m0 ? m0_dat_i : (sel_m1 ? m1_dat_i : 32'h0);
    assign s_sel_o = sel_m0 ? m0_sel_i : (sel_m1 ? m1_sel_i : 4'h0);
    assign s_we_o  = sel_m0 ? m0_we_i  : (sel_m1 ? m1_we_i  : 1'b0);
    assign s_stb_o = sel_m0 ? m0_stb_i : (sel_m1 ? m1_stb_i : 1'b0);
    assign s_cyc_o = sel_m0 ? m0_cyc_i : (sel_m1 ? m1_cyc_i : 1'b0);

    // Retours vers les masters
    assign m0_dat_o = s_dat_i;
    assign m0_ack_o = sel_m0 ? s_ack_i : 1'b0;
    assign m1_dat_o = s_dat_i;
    assign m1_ack_o = sel_m1 ? s_ack_i : 1'b0;
endmodule
