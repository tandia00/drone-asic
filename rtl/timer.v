// -----------------------------------------------------------------------------
// SAHEL-1 — Timer 32 bits + watchdog (sécurité vol)
// Map :
//   +0x00 COUNT (free-running)
//   +0x04 COMPARE  (IRQ si count == compare && CTRL.bit0)
//   +0x08 CTRL     bit0=irq_en, bit1=wdt_en
//   +0x0C WDT_RELOAD  (recharger pour kick le watchdog)
// -----------------------------------------------------------------------------
`default_nettype none

module timer (
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
    output reg         irq_o,
    output reg         wdt_reset_o
);
    reg [31:0] count, compare, wdt_cnt;
    reg [1:0]  ctrl;

    always @(posedge clk_i) begin
        if (rst_i) begin
            count <= 0; compare <= 32'hFFFF_FFFF; ctrl <= 0;
            wdt_cnt <= 32'h0010_0000; irq_o <= 0; wdt_reset_o <= 0;
        end else begin
            count <= count + 1'b1;
            irq_o <= ctrl[0] && (count == compare);
            if (ctrl[1]) begin
                if (wdt_cnt == 0) wdt_reset_o <= 1'b1;
                else              wdt_cnt <= wdt_cnt - 1'b1;
            end
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) wb_ack_o <= 0;
        else begin
            wb_ack_o <= 0;
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                case (wb_adr_i[3:0])
                    4'h0: wb_dat_o <= count;
                    4'h4: if (wb_we_i) compare <= wb_dat_i; else wb_dat_o <= compare;
                    4'h8: if (wb_we_i) ctrl <= wb_dat_i[1:0]; else wb_dat_o <= {30'h0, ctrl};
                    4'hC: if (wb_we_i) wdt_cnt <= wb_dat_i; else wb_dat_o <= wdt_cnt;
                    default: wb_dat_o <= 0;
                endcase
            end
        end
    end
endmodule
