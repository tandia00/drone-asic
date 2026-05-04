// -----------------------------------------------------------------------------
// SAHEL-1 — SPI master, modes 0/1/2/3, 8 bits, esclave Wishbone
// Map : +0x00 DATA, +0x04 CTRL (bit0=start, bit1=cs, bit[3:2]=mode),
//       +0x08 STATUS (bit0=busy, bit1=done), +0x0C DIVISOR
// -----------------------------------------------------------------------------
`default_nettype none

module spi_master (
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
    output reg         sclk_o,
    output reg         mosi_o,
    input  wire        miso_i,
    output reg         cs_no
);
    reg [7:0]  shift;
    reg [3:0]  bits;
    reg [15:0] div;
    reg [15:0] cnt;
    reg        busy, done;
    reg        cpol, cpha;
    reg [15:0] divisor = 16'd25; // 50MHz/25 ≈ 2 MHz
    reg        start;

    always @(posedge clk_i) begin
        start <= 1'b0;
        if (rst_i) begin
            busy <= 0; done <= 0; sclk_o <= 0; mosi_o <= 0; cs_no <= 1;
            cnt <= 0; bits <= 0; cpol <= 0; cpha <= 0;
        end else begin
            if (start && !busy) begin
                busy   <= 1'b1; done <= 1'b0;
                bits   <= 4'd8; cnt <= divisor;
                sclk_o <= cpol;
            end else if (busy) begin
                if (cnt == 0) begin
                    cnt   <= divisor;
                    sclk_o <= ~sclk_o;
                    // sample / shift sur les fronts selon CPHA
                    if (sclk_o == cpol) begin
                        // front actif : sample MISO
                        shift <= {shift[6:0], miso_i};
                    end else begin
                        // front inactif : shift suivant
                        if (bits == 0) begin busy <= 1'b0; done <= 1'b1; end
                        else bits <= bits - 1'b1;
                        mosi_o <= shift[7];
                    end
                end else cnt <= cnt - 1'b1;
            end
        end
    end

    // WB
    always @(posedge clk_i) begin
        if (rst_i) begin
            wb_ack_o <= 0;
        end else begin
            wb_ack_o <= 0;
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                case (wb_adr_i[3:0])
                    4'h0: if (wb_we_i) shift <= wb_dat_i[7:0];
                          else         wb_dat_o <= {24'h0, shift};
                    4'h4: if (wb_we_i) begin
                              if (wb_dat_i[0]) start <= 1'b1;
                              cs_no <= ~wb_dat_i[1];
                              cpol  <= wb_dat_i[2];
                              cpha  <= wb_dat_i[3];
                          end
                    4'h8: wb_dat_o <= {30'h0, done, busy};
                    4'hC: if (wb_we_i) divisor <= wb_dat_i[15:0];
                          else         wb_dat_o <= {16'h0, divisor};
                    default: wb_dat_o <= 32'h0;
                endcase
            end
        end
    end
endmodule
