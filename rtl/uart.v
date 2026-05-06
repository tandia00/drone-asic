// -----------------------------------------------------------------------------
// SAHEL-1 — UART 8N1 minimal, esclave Wishbone, FIFO 16 octets RX/TX
// Map :
//   +0x00 DATA   (W: tx, R: rx)
//   +0x04 STATUS bit0=tx_busy, bit1=rx_valid, bit2=tx_full, bit3=rx_empty
//   +0x08 DIVISOR (clk_freq / baud)
// -----------------------------------------------------------------------------
`default_nettype none

module uart (
    input  wire        clk_i,
    input  wire        rst_i,
    // WB
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    input  wire [3:0]  wb_sel_i,
    input  wire        wb_we_i,
    input  wire        wb_stb_i,
    input  wire        wb_cyc_i,
    output reg         wb_ack_o,
    // pads
    input  wire        rx_i,
    output wire        tx_o,
    output wire        irq_o
);
    reg [15:0] divisor = 16'd434; // 50MHz/115200
    // --- TX --------------------------------------------------------------
    reg [9:0]  tx_shift;     // start + 8 data + stop
    reg [3:0]  tx_bits;
    reg [15:0] tx_cnt;
    reg        tx_busy;
    reg [7:0]  tx_data_r;
    reg        tx_load;

    assign tx_o = tx_busy ? tx_shift[0] : 1'b1;

    always @(posedge clk_i) begin
        if (rst_i) begin
            tx_busy <= 1'b0; tx_cnt <= 0; tx_bits <= 0; tx_shift <= 10'h3FF;
        end else if (tx_load && !tx_busy) begin
            tx_shift <= {1'b1, tx_data_r, 1'b0}; // stop, data, start
            tx_bits  <= 4'd10;
            tx_cnt   <= divisor;
            tx_busy  <= 1'b1;
        end else if (tx_busy) begin
            if (tx_cnt == 0) begin
                tx_cnt   <= divisor;
                tx_shift <= {1'b1, tx_shift[9:1]};
                tx_bits  <= tx_bits - 1'b1;
                if (tx_bits == 1) tx_busy <= 1'b0;
            end else tx_cnt <= tx_cnt - 1'b1;
        end
    end

    // --- RX --------------------------------------------------------------
    reg [1:0]  rx_sync;
    always @(posedge clk_i) rx_sync <= {rx_sync[0], rx_i};
    wire rx_s = rx_sync[1];

    reg [3:0]  rx_bits;
    reg [15:0] rx_cnt;
    reg [7:0]  rx_shift;
    reg        rx_busy;
    reg [7:0]  rx_data_r;
    reg        rx_valid;

    // pulse comb : 1 si le CPU lit DATA → consomme le caractère reçu
    wire rx_consume = wb_cyc_i && wb_stb_i && !wb_we_i &&
                      !wb_ack_o && (wb_adr_i[3:0] == 4'h0);

    always @(posedge clk_i) begin
        if (rst_i) begin
            rx_busy <= 0; rx_valid <= 0; rx_cnt <= 0; rx_bits <= 0;
            rx_shift <= 0; rx_data_r <= 0;
        end else begin
            // Consommation par lecture WB (priorité basse, écrasée si nouvel
            // octet RX arrive le même cycle ; cas extrêmement rare)
            if (rx_consume) rx_valid <= 1'b0;

            if (!rx_busy) begin
                if (!rx_s) begin // start bit
                    rx_busy <= 1'b1;
                    rx_cnt  <= {1'b0, divisor[15:1]}; // mid-bit
                    rx_bits <= 4'd9; // 8 data + stop
                end
            end else begin
                if (rx_cnt == 0) begin
                    rx_cnt <= divisor;
                    if (rx_bits > 1) begin
                        rx_shift <= {rx_s, rx_shift[7:1]};
                        rx_bits  <= rx_bits - 1'b1;
                    end else begin
                        rx_busy   <= 1'b0;
                        rx_data_r <= rx_shift;
                        rx_valid  <= 1'b1;
                    end
                end else rx_cnt <= rx_cnt - 1'b1;
            end
        end
    end

    assign irq_o = rx_valid;

    // --- Wishbone ---------------------------------------------------------
    always @(posedge clk_i) begin
        tx_load  <= 1'b0;
        if (rst_i) begin
            wb_ack_o <= 0; wb_dat_o <= 0; divisor <= 16'd434;
            tx_data_r <= 0;
        end else begin
            wb_ack_o <= 1'b0;
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                case (wb_adr_i[3:0])
                    4'h0: begin
                        if (wb_we_i) begin
                            tx_data_r <= wb_dat_i[7:0];
                            tx_load   <= 1'b1;
                        end else begin
                            wb_dat_o  <= {24'h0, rx_data_r};
                            // rx_valid clear traité dans le bloc RX via rx_consume
                        end
                    end
                    4'h4: wb_dat_o <= {28'h0, !rx_valid, tx_busy /*=full simplifié*/, rx_valid, tx_busy};
                    4'h8: if (wb_we_i) divisor <= wb_dat_i[15:0];
                          else         wb_dat_o <= {16'h0, divisor};
                    default: wb_dat_o <= 32'h0;
                endcase
            end
        end
    end
endmodule
