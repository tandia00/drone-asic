// -----------------------------------------------------------------------------
// SAHEL-1 — PWM controller, 6 canaux 16 bits, esclave Wishbone
// Map (offset par canal = i*0x10) :
//   +0 PERIOD, +4 DUTY, +8 CFG (bit0=en, bit1=invert)
// -----------------------------------------------------------------------------
`default_nettype none

module pwm #(
    parameter NCH = 6
) (
    input  wire             clk_i,
    input  wire             rst_i,
    // Wishbone slave
    input  wire [31:0]      wb_adr_i,
    input  wire [31:0]      wb_dat_i,
    output reg  [31:0]      wb_dat_o,
    input  wire [3:0]       wb_sel_i,
    input  wire             wb_we_i,
    input  wire             wb_stb_i,
    input  wire             wb_cyc_i,
    output reg              wb_ack_o,
    // PWM outputs
    output wire [NCH-1:0]   pwm_o
);
    reg [15:0] period [0:NCH-1];
    reg [15:0] duty   [0:NCH-1];
    reg [1:0]  cfg    [0:NCH-1];     // bit0=en, bit1=invert
    reg [15:0] cnt    [0:NCH-1];
    reg        out    [0:NCH-1];

    integer i;
    initial for (i = 0; i < NCH; i = i + 1) begin
        period[i] = 16'd1000; duty[i] = 16'd0;
        cfg[i]    = 2'b00;    cnt[i]  = 16'd0; out[i] = 1'b0;
    end

    // PWM core
    always @(posedge clk_i) begin
        if (rst_i) begin
            for (i = 0; i < NCH; i = i + 1) begin
                cnt[i] <= 16'd0; out[i] <= 1'b0;
            end
        end else begin
            for (i = 0; i < NCH; i = i + 1) begin
                if (cfg[i][0]) begin
                    cnt[i] <= (cnt[i] >= period[i] - 1) ? 16'd0 : cnt[i] + 16'd1;
                    out[i] <= (cnt[i] < duty[i]);
                end else begin
                    cnt[i] <= 16'd0; out[i] <= 1'b0;
                end
            end
        end
    end

    genvar g;
    generate
        for (g = 0; g < NCH; g = g + 1) begin : g_out
            assign pwm_o[g] = out[g] ^ cfg[g][1];
        end
    endgenerate

    // Wishbone access
    wire [3:0] ch  = wb_adr_i[7:4];
    wire [3:0] reg_ = wb_adr_i[3:0];

    always @(posedge clk_i) begin
        if (rst_i) begin
            wb_ack_o <= 1'b0;
            wb_dat_o <= 32'h0;
        end else begin
            wb_ack_o <= 1'b0;
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                if (ch < NCH) begin
                    if (wb_we_i) begin
                        case (reg_)
                            4'h0: period[ch] <= wb_dat_i[15:0];
                            4'h4: duty[ch]   <= wb_dat_i[15:0];
                            4'h8: cfg[ch]    <= wb_dat_i[1:0];
                            default: ;
                        endcase
                    end else begin
                        case (reg_)
                            4'h0: wb_dat_o <= {16'h0, period[ch]};
                            4'h4: wb_dat_o <= {16'h0, duty[ch]};
                            4'h8: wb_dat_o <= {30'h0, cfg[ch]};
                            default: wb_dat_o <= 32'h0;
                        endcase
                    end
                end
            end
        end
    end
endmodule
