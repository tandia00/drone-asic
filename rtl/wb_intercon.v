// -----------------------------------------------------------------------------
// SAHEL-1 — Wishbone B4 classic interconnect (1 master, N slaves)
// Décodage par tranches de 4 KB sur addr[15:12].
// -----------------------------------------------------------------------------
`default_nettype none

module wb_intercon #(
    parameter NSLAVES = 12
) (
    input  wire                  clk_i,
    input  wire                  rst_i,

    // Master in
    input  wire        [31:0]    m_adr_i,
    input  wire        [31:0]    m_dat_i,
    output reg         [31:0]    m_dat_o,
    input  wire        [3:0]     m_sel_i,
    input  wire                  m_we_i,
    input  wire                  m_stb_i,
    input  wire                  m_cyc_i,
    output reg                   m_ack_o,

    // Slaves out (concat: NSLAVES * width)
    output wire [NSLAVES*32-1:0] s_adr_o,
    output wire [NSLAVES*32-1:0] s_dat_o,
    input  wire [NSLAVES*32-1:0] s_dat_i,
    output wire [NSLAVES*4-1:0]  s_sel_o,
    output wire [NSLAVES-1:0]    s_we_o,
    output wire [NSLAVES-1:0]    s_stb_o,
    output wire [NSLAVES-1:0]    s_cyc_o,
    input  wire [NSLAVES-1:0]    s_ack_i
);

    // Décodage : périphériques en 0x3000_X000 (X = index)
    // Mémoires :  0x0000_0000 = ROM (slave 0), 0x1000_0000 = SRAM (slave 1)
    // Périph idx commence à 2 → slave i = 0x3000_(i-2)000
    reg [NSLAVES-1:0] sel;
    integer k;
    always @(*) begin
        sel = {NSLAVES{1'b0}};
        if (m_adr_i[31:28] == 4'h0)      sel[0] = 1'b1; // ROM
        else if (m_adr_i[31:28] == 4'h1) sel[1] = 1'b1; // SRAM
        else if (m_adr_i[31:28] == 4'h3) begin
            for (k = 2; k < NSLAVES; k = k + 1)
                if (m_adr_i[15:12] == (k-2)) sel[k] = 1'b1;
        end
    end

    // Broadcast des signaux master vers les slaves, gate par sel
    genvar i;
    generate
        for (i = 0; i < NSLAVES; i = i + 1) begin : g_slv
            assign s_adr_o[i*32 +: 32] = m_adr_i;
            assign s_dat_o[i*32 +: 32] = m_dat_i;
            assign s_sel_o[i*4  +: 4]  = m_sel_i;
            assign s_we_o[i]           = m_we_i;
            assign s_stb_o[i]          = m_stb_i & sel[i];
            assign s_cyc_o[i]          = m_cyc_i & sel[i];
        end
    endgenerate

    // Mux retour vers master
    integer j;
    always @(*) begin
        m_dat_o = 32'h0;
        m_ack_o = 1'b0;
        for (j = 0; j < NSLAVES; j = j + 1) begin
            if (sel[j]) begin
                m_dat_o = s_dat_i[j*32 +: 32];
                m_ack_o = s_ack_i[j];
            end
        end
    end

endmodule
