// -----------------------------------------------------------------------------
// SAHEL-1 — GPIO 16 broches, esclave Wishbone
// Map : +0x00 DIR (1=out), +0x04 OUT, +0x08 IN
// -----------------------------------------------------------------------------
`default_nettype none

module gpio #(parameter W = 16) (
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
    input  wire [W-1:0] gpio_in_i,
    output wire [W-1:0] gpio_out_o,
    output wire [W-1:0] gpio_oeb_o   // 0 = output enabled
);
    reg [W-1:0] dir_r, out_r;
    assign gpio_out_o = out_r;
    assign gpio_oeb_o = ~dir_r;

    always @(posedge clk_i) begin
        if (rst_i) begin
            dir_r <= 0; out_r <= 0; wb_ack_o <= 0; wb_dat_o <= 0;
        end else begin
            wb_ack_o <= 0;
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                case (wb_adr_i[3:0])
                    4'h0: if (wb_we_i) dir_r <= wb_dat_i[W-1:0];
                          else         wb_dat_o <= {{(32-W){1'b0}}, dir_r};
                    4'h4: if (wb_we_i) out_r <= wb_dat_i[W-1:0];
                          else         wb_dat_o <= {{(32-W){1'b0}}, out_r};
                    4'h8: wb_dat_o <= {{(32-W){1'b0}}, gpio_in_i};
                    default: wb_dat_o <= 0;
                endcase
            end
        end
    end
endmodule
