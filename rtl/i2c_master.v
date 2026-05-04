// -----------------------------------------------------------------------------
// SAHEL-1 — I²C master simple (mode standard 100 kHz / fast 400 kHz)
// Esclave Wishbone. Implémente START/STOP/byte transfer + ACK.
// Map :
//   +0x00 DATA
//   +0x04 CMD   bit0=start, bit1=stop, bit2=read, bit3=write, bit4=ack
//   +0x08 STATUS bit0=busy, bit1=ack_recv, bit2=done
//   +0x0C DIVISOR
// -----------------------------------------------------------------------------
`default_nettype none

module i2c_master (
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
    inout  wire        scl_io,
    inout  wire        sda_io
);
    // Open-drain : on tire à 0 ou on relâche (Z avec pull-up externe)
    reg scl_oe, sda_oe;
    assign scl_io = scl_oe ? 1'b0 : 1'bz;
    assign sda_io = sda_oe ? 1'b0 : 1'bz;
    wire scl_in = scl_io;
    wire sda_in = sda_io;

    reg [15:0] divisor = 16'd125; // 50MHz / (4*125) = 100 kHz
    reg [15:0] cnt;
    reg [3:0]  state;
    reg [3:0]  bit_cnt;
    reg [7:0]  data_r;
    reg        ack_recv;
    reg        busy, done;
    reg        cmd_start, cmd_stop, cmd_read, cmd_write, cmd_ack;
    reg        cmd_valid;

    localparam S_IDLE=0, S_START=1, S_BIT=2, S_ACK=3, S_STOP=4, S_DONE=5;

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE; busy <= 0; done <= 0;
            scl_oe <= 0; sda_oe <= 0; cnt <= 0; bit_cnt <= 0;
            cmd_valid <= 0;
        end else begin
            if (cnt != 0) cnt <= cnt - 1'b1;
            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (cmd_valid) begin
                        busy <= 1'b1; cmd_valid <= 0; cnt <= divisor;
                        if (cmd_start) state <= S_START;
                        else if (cmd_write || cmd_read) begin
                            bit_cnt <= 4'd8; state <= S_BIT;
                        end else if (cmd_stop) state <= S_STOP;
                    end
                end
                S_START: if (cnt == 0) begin
                    sda_oe <= 1'b1; // SDA bas, SCL haut → start
                    scl_oe <= 1'b0;
                    cnt <= divisor;
                    if (cmd_write || cmd_read) begin
                        bit_cnt <= 4'd8; state <= S_BIT;
                    end else state <= S_DONE;
                end
                S_BIT: if (cnt == 0) begin
                    cnt <= divisor;
                    // alterne SCL bas / haut
                    if (!scl_oe) begin
                        scl_oe <= 1'b1; // SCL bas
                        if (cmd_write) sda_oe <= ~data_r[7];
                        else           sda_oe <= 1'b0; // release for read
                    end else begin
                        scl_oe <= 1'b0; // SCL haut
                        if (cmd_read)  data_r <= {data_r[6:0], sda_in};
                        else           data_r <= {data_r[6:0], 1'b0};
                        bit_cnt <= bit_cnt - 1'b1;
                        if (bit_cnt == 1) state <= S_ACK;
                    end
                end
                S_ACK: if (cnt == 0) begin
                    cnt <= divisor;
                    if (!scl_oe) begin
                        scl_oe <= 1'b1;
                        sda_oe <= cmd_read ? cmd_ack : 1'b0; // send/release
                    end else begin
                        scl_oe <= 1'b0;
                        if (!cmd_read) ack_recv <= ~sda_in;
                        if (cmd_stop) state <= S_STOP;
                        else          state <= S_DONE;
                    end
                end
                S_STOP: if (cnt == 0) begin
                    sda_oe <= 1'b0; scl_oe <= 1'b0;
                    state <= S_DONE;
                end
                S_DONE: begin
                    busy <= 0; done <= 1'b1; state <= S_IDLE;
                end
            endcase
        end
    end

    // WB
    always @(posedge clk_i) begin
        if (rst_i) begin wb_ack_o <= 0; end
        else begin
            wb_ack_o <= 0;
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                case (wb_adr_i[3:0])
                    4'h0: if (wb_we_i) data_r <= wb_dat_i[7:0];
                          else         wb_dat_o <= {24'h0, data_r};
                    4'h4: if (wb_we_i) begin
                              cmd_start <= wb_dat_i[0]; cmd_stop  <= wb_dat_i[1];
                              cmd_read  <= wb_dat_i[2]; cmd_write <= wb_dat_i[3];
                              cmd_ack   <= wb_dat_i[4]; cmd_valid <= 1'b1;
                          end
                    4'h8: wb_dat_o <= {29'h0, done, ack_recv, busy};
                    4'hC: if (wb_we_i) divisor <= wb_dat_i[15:0];
                          else         wb_dat_o <= {16'h0, divisor};
                    default: wb_dat_o <= 0;
                endcase
            end
        end
    end
endmodule
