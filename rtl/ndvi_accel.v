// -----------------------------------------------------------------------------
// SAHEL-1 — Accélérateur NDVI
//   NDVI = (NIR - RED) / (NIR + RED)   ∈ [-1, +1] → encodé int8 [-127, +127]
//
// Approche matérielle : pour éviter un divider full IEEE, on utilise une
// division entière 16/16 → 8 bits par soustraction successive (16 cycles/pixel).
// Largement suffisant pour 640x480 @ 30 fps : 9.2 Mpix/s ≪ 50 MHz / 16 = 3.1 Mpix/s
// par canal d'accélérateur. (En pratique pipeliné en 1 pix/cycle si besoin
// d'instancier un divider plus rapide ; ici on privilégie la surface.)
//
// Esclave Wishbone : registres voir docs/memory_map.md.
// Accès mémoire : maître Wishbone séparé (dma_*) pour lire R/NIR et écrire NDVI.
// -----------------------------------------------------------------------------
`default_nettype none

module ndvi_accel (
    input  wire        clk_i,
    input  wire        rst_i,

    // Slave WB (CSR)
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    input  wire [3:0]  wb_sel_i,
    input  wire        wb_we_i,
    input  wire        wb_stb_i,
    input  wire        wb_cyc_i,
    output reg         wb_ack_o,

    // Master WB (DMA) – simplifié : lit/écrit 32 bits par cycle d'accès
    output reg  [31:0] dma_adr_o,
    output reg  [31:0] dma_dat_o,
    input  wire [31:0] dma_dat_i,
    output reg         dma_we_o,
    output reg         dma_stb_o,
    output reg         dma_cyc_o,
    input  wire        dma_ack_i,

    output reg         irq_o
);
    // CSR
    reg        ctrl_start, ctrl_irq_en;
    reg        st_busy, st_done;
    reg [31:0] red_addr, nir_addr, out_addr;
    reg [31:0] npix;
    reg signed [7:0] threshold;
    reg [31:0] healthy_ct;

    // FSM
    localparam S_IDLE=0, S_RD_R=1, S_RD_R_W=2, S_RD_N=3, S_RD_N_W=4,
               S_DIV=5, S_PACK=6, S_WR=7, S_WR_W=8, S_NEXT=9, S_FIN=10;
    reg [3:0]  state;
    reg [31:0] idx;
    reg [7:0]  red_v, nir_v;
    reg signed [7:0] ndvi_v;

    // Diviseur séquentiel 16/16 → 8b signé
    reg [15:0] num_abs, den;
    reg [7:0]  quot;
    reg [4:0]  div_bit;
    reg        sign_neg;
    reg [16:0] rem;

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE; st_busy <= 0; st_done <= 0; irq_o <= 0;
            healthy_ct <= 0; idx <= 0;
            dma_stb_o <= 0; dma_cyc_o <= 0; dma_we_o <= 0;
        end else begin
            irq_o <= 0;
            case (state)
                S_IDLE: begin
                    if (ctrl_start) begin
                        st_busy <= 1; st_done <= 0; idx <= 0; healthy_ct <= 0;
                        state <= S_RD_R;
                    end
                end
                S_RD_R: begin
                    dma_adr_o <= red_addr + idx;
                    dma_we_o  <= 0;
                    dma_stb_o <= 1; dma_cyc_o <= 1;
                    state <= S_RD_R_W;
                end
                S_RD_R_W: if (dma_ack_i) begin
                    red_v <= dma_dat_i[7:0];
                    dma_stb_o <= 0; dma_cyc_o <= 0;
                    state <= S_RD_N;
                end
                S_RD_N: begin
                    dma_adr_o <= nir_addr + idx;
                    dma_stb_o <= 1; dma_cyc_o <= 1;
                    state <= S_RD_N_W;
                end
                S_RD_N_W: if (dma_ack_i) begin
                    // Lire la valeur NIR DIRECTEMENT depuis le bus (red_v déjà
                    // disponible depuis le cycle précédent)
                    nir_v <= dma_dat_i[7:0];
                    dma_stb_o <= 0; dma_cyc_o <= 0;
                    // setup division avec valeurs immédiates
                    if (dma_dat_i[7:0] >= red_v) begin
                        num_abs  <= {8'h0, (dma_dat_i[7:0] - red_v)} << 7;
                        sign_neg <= 1'b0;
                    end else begin
                        num_abs  <= {8'h0, (red_v - dma_dat_i[7:0])} << 7;
                        sign_neg <= 1'b1;
                    end
                    den     <= {8'h0, (dma_dat_i[7:0] + red_v)};
                    rem     <= 17'h0;
                    quot    <= 8'h0;
                    div_bit <= 5'd15;
                    state   <= S_DIV;
                end
                S_DIV: begin
                    // restoring division 1 bit/cycle : 16 cycles → 8 bits utiles
                    rem = {rem[15:0], num_abs[15]};
                    num_abs <= num_abs << 1;
                    if (rem >= {1'b0, den}) begin
                        rem  = rem - {1'b0, den};
                        quot <= {quot[6:0], 1'b1};
                    end else begin
                        quot <= {quot[6:0], 1'b0};
                    end
                    if (div_bit == 0) state <= S_PACK;
                    else              div_bit <= div_bit - 1'b1;
                end
                S_PACK: begin
                    // quot est désormais finalisé (NBA du dernier S_DIV propagée)
                    ndvi_v <= sign_neg ? -$signed({1'b0, quot[6:0]})
                                       :  $signed({1'b0, quot[6:0]});
                    state  <= S_WR;
                end
                S_WR: begin
                    dma_adr_o <= out_addr + idx;
                    dma_dat_o <= {{24{ndvi_v[7]}}, ndvi_v};
                    dma_we_o  <= 1;
                    dma_stb_o <= 1; dma_cyc_o <= 1;
                    state <= S_WR_W;
                end
                S_WR_W: if (dma_ack_i) begin
                    dma_stb_o <= 0; dma_cyc_o <= 0; dma_we_o <= 0;
                    if ($signed(ndvi_v) > $signed(threshold)) healthy_ct <= healthy_ct + 1'b1;
                    state <= S_NEXT;
                end
                S_NEXT: begin
                    idx <= idx + 1'b1;
                    if (idx + 1 == npix) state <= S_FIN;
                    else                 state <= S_RD_R;
                end
                S_FIN: begin
                    st_busy <= 0; st_done <= 1;
                    if (ctrl_irq_en) irq_o <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // CSR access
    always @(posedge clk_i) begin
        if (rst_i) begin
            wb_ack_o <= 0; ctrl_start <= 0; ctrl_irq_en <= 0;
            red_addr <= 0; nir_addr <= 0; out_addr <= 0; npix <= 0;
            threshold <= 8'sd25; // ~ NDVI 0.2 (échelle ×127)
        end else begin
            wb_ack_o   <= 0;
            ctrl_start <= 0; // pulse
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                case (wb_adr_i[7:0])
                    8'h00: if (wb_we_i) begin
                              ctrl_start  <= wb_dat_i[0];
                              ctrl_irq_en <= wb_dat_i[1];
                          end
                    8'h04: wb_dat_o <= {30'h0, st_done, st_busy};
                    8'h08: if (wb_we_i) red_addr <= wb_dat_i; else wb_dat_o <= red_addr;
                    8'h0C: if (wb_we_i) nir_addr <= wb_dat_i; else wb_dat_o <= nir_addr;
                    8'h10: if (wb_we_i) out_addr <= wb_dat_i; else wb_dat_o <= out_addr;
                    8'h14: if (wb_we_i) npix     <= wb_dat_i; else wb_dat_o <= npix;
                    8'h18: if (wb_we_i) threshold<= wb_dat_i[7:0]; else wb_dat_o <= {{24{threshold[7]}}, threshold};
                    8'h1C: wb_dat_o <= healthy_ct;
                    default: wb_dat_o <= 0;
                endcase
            end
        end
    end
endmodule
