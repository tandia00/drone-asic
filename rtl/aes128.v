// -----------------------------------------------------------------------------
// SAHEL-1 — AES-128 Wishbone wrapper autour de secworks/aes_core
// Référence : https://github.com/secworks/aes  (vérifié FIPS-197 bit-exact)
//
// Fichiers requis (inclus via Makefile/OpenLane config) :
//   ext/secworks-aes/src/rtl/aes_core.v
//   ext/secworks-aes/src/rtl/aes_encipher_block.v
//   ext/secworks-aes/src/rtl/aes_decipher_block.v
//   ext/secworks-aes/src/rtl/aes_key_mem.v
//   ext/secworks-aes/src/rtl/aes_sbox.v
//   ext/secworks-aes/src/rtl/aes_inv_sbox.v
//
// Séquence d'utilisation :
//   1. Écrire la clé (4 mots) dans KEY[0..3].
//   2. Écrire le plaintext dans DIN[0..3].
//   3. CTRL.bit0 = 1 → démarre l'initialisation (key schedule).
//   4. Quand STATUS.bit0 = 0 (ready), CTRL.bit1 = 1 → lance le chiffrement.
//   5. Quand STATUS.bit1 = 1 (valid), lire DOUT[0..3].
//
// Pour simplifier le firmware, CTRL.bit0 enchaîne automatiquement INIT puis
// NEXT (chiffrement d'un bloc). STATUS.bit1 indique quand DOUT est prêt.
// -----------------------------------------------------------------------------
`default_nettype none

module aes128 (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    input  wire [3:0]  wb_sel_i,
    input  wire        wb_we_i,
    input  wire        wb_stb_i,
    input  wire        wb_cyc_i,
    output reg         wb_ack_o,
    output reg         irq_o
);
    // Registres utilisateur
    reg [127:0] key_r, din_r, dout_r;
    reg         encdec_r;     // 1=encrypt, 0=decrypt
    reg         ctrl_irq;
    reg         busy, done;
    reg         start_pulse;  // 1-cycle pulse from CSR write → FSM

    // Interface aes_core
    reg         core_init, core_next;
    wire        core_ready, core_result_valid;
    wire [127:0] core_result;
    // secworks/aes_core prend les 128 bits HAUTS de 'key' quand keylen=0 (AES-128).
    // Donc on place key_r en MSB. De plus, les TB NIST stockent la clé en big-endian :
    // byte0=0x00 doit se retrouver sur key[255:248]. On inverse donc l'ordre des octets.
    function [127:0] byte_reverse128; input [127:0] x; integer i;
        begin for (i = 0; i < 16; i = i + 1)
                byte_reverse128[i*8 +: 8] = x[(15-i)*8 +: 8]; end
    endfunction
    wire [127:0] key_be   = byte_reverse128(key_r);
    wire [127:0] din_be   = byte_reverse128(din_r);
    wire [255:0] core_key_256 = {key_be, 128'h0};
    wire         core_keylen  = 1'b0;              // 0 = 128 bits

    aes_core u_core (
        .clk         (clk_i),
        .reset_n     (~rst_i),
        .encdec      (encdec_r),
        .init        (core_init),
        .next        (core_next),
        .ready       (core_ready),
        .key         (core_key_256),
        .keylen      (core_keylen),
        .block       (din_be),
        .result      (core_result),
        .result_valid(core_result_valid)
    );

    // FSM séquenceur INIT → NEXT → capture DOUT
    // Important : ready est HAUT avant que init soit vu. On attend donc
    //   (1) ready BAS (init a été pris), puis (2) ready HAUT (init fini).
    localparam S_IDLE=0, S_INIT=1, S_INIT_BUSY=2, S_INIT_DONE=3,
               S_NEXT=4, S_NEXT_BUSY=5, S_CAPTURE=6, S_DONE=7;
    reg [2:0] state;

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE; busy <= 0; done <= 0; irq_o <= 0;
            core_init <= 0; core_next <= 0;
        end else begin
            irq_o     <= 1'b0;
            core_init <= 1'b0;
            core_next <= 1'b0;
            case (state)
                S_IDLE: if (start_pulse) begin
                    busy  <= 1'b1;
                    done  <= 1'b0;
                    state <= S_INIT;
                end
                S_INIT: begin
                    core_init <= 1'b1;
                    state     <= S_INIT_BUSY;
                end
                S_INIT_BUSY:  if (!core_ready) state <= S_INIT_DONE;
                S_INIT_DONE:  if ( core_ready) state <= S_NEXT;
                S_NEXT: begin
                    core_next <= 1'b1;
                    state     <= S_NEXT_BUSY;
                end
                S_NEXT_BUSY:  if (!core_ready) state <= S_CAPTURE;
                S_CAPTURE:    if ( core_ready && core_result_valid) begin
                    dout_r <= byte_reverse128(core_result);
                    state  <= S_DONE;
                end
                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    if (ctrl_irq) irq_o <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // Wishbone CSR
    always @(posedge clk_i) begin
        if (rst_i) begin
            wb_ack_o <= 0; ctrl_irq <= 0; encdec_r <= 1'b1;
            key_r <= 0; din_r <= 0; start_pulse <= 1'b0;
        end else begin
            wb_ack_o    <= 0;
            start_pulse <= 1'b0;   // auto-clear (pulse 1 cycle)
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                case (wb_adr_i[7:0])
                    8'h00: if (wb_we_i) begin
                              start_pulse <= wb_dat_i[0];
                              encdec_r    <= wb_dat_i[1] ? 1'b0 : 1'b1; // bit1=1 → decrypt
                              ctrl_irq    <= wb_dat_i[2];
                          end
                    8'h04: wb_dat_o <= {30'h0, done, busy};
                    8'h10: if (wb_we_i) key_r[ 31:  0] <= wb_dat_i; else wb_dat_o <= key_r[ 31:  0];
                    8'h14: if (wb_we_i) key_r[ 63: 32] <= wb_dat_i; else wb_dat_o <= key_r[ 63: 32];
                    8'h18: if (wb_we_i) key_r[ 95: 64] <= wb_dat_i; else wb_dat_o <= key_r[ 95: 64];
                    8'h1C: if (wb_we_i) key_r[127: 96] <= wb_dat_i; else wb_dat_o <= key_r[127: 96];
                    8'h20: if (wb_we_i) din_r[ 31:  0] <= wb_dat_i; else wb_dat_o <= din_r[ 31:  0];
                    8'h24: if (wb_we_i) din_r[ 63: 32] <= wb_dat_i; else wb_dat_o <= din_r[ 63: 32];
                    8'h28: if (wb_we_i) din_r[ 95: 64] <= wb_dat_i; else wb_dat_o <= din_r[ 95: 64];
                    8'h2C: if (wb_we_i) din_r[127: 96] <= wb_dat_i; else wb_dat_o <= din_r[127: 96];
                    8'h30: wb_dat_o <= dout_r[ 31:  0];
                    8'h34: wb_dat_o <= dout_r[ 63: 32];
                    8'h38: wb_dat_o <= dout_r[ 95: 64];
                    8'h3C: wb_dat_o <= dout_r[127: 96];
                    default: wb_dat_o <= 0;
                endcase
            end
        end
    end
endmodule
