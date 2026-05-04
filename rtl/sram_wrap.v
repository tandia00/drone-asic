// -----------------------------------------------------------------------------
// SAHEL-1 — Wrapper SRAM 32 KB (8 K × 32 b). En simulation, modèle behavioral.
// En synthèse OpenLane, remplacé par macros sky130_sram_2kbyte_1rw1r_32x512_8.
// -----------------------------------------------------------------------------
`default_nettype none

module sram_wrap (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    input  wire [3:0]  wb_sel_i,
    input  wire        wb_we_i,
    input  wire        wb_stb_i,
    input  wire        wb_cyc_i,
    output reg         wb_ack_o
);
    // 32 KB = 8192 mots de 32 bits → addr[14:2]
    reg [31:0] mem [0:8191];
    wire [12:0] idx = wb_adr_i[14:2];

    always @(posedge clk_i) begin
        if (rst_i) wb_ack_o <= 0;
        else begin
            wb_ack_o <= 0;
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                if (wb_we_i) begin
                    if (wb_sel_i[0]) mem[idx][ 7: 0] <= wb_dat_i[ 7: 0];
                    if (wb_sel_i[1]) mem[idx][15: 8] <= wb_dat_i[15: 8];
                    if (wb_sel_i[2]) mem[idx][23:16] <= wb_dat_i[23:16];
                    if (wb_sel_i[3]) mem[idx][31:24] <= wb_dat_i[31:24];
                end else begin
                    wb_dat_o <= mem[idx];
                end
            end
        end
    end

`ifdef FIRMWARE_HEX
    initial $readmemh(`FIRMWARE_HEX, mem);
`endif
endmodule
