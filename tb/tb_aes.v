`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// Vecteur NIST FIPS-197 Appendix C.1 (AES-128) :
//   key = 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f
//   pt  = 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff
//   ct  = 69 c4 e0 d8 6a 7b 04 30 d8 cd b7 80 70 b4 c5 5a
// Le firmware stocke la clé/plaintext LSW-first. L'octet 0x00 est sur les
// bits [7:0] de KEY[0], l'octet 0x0f sur les bits [31:24] de KEY[3].
// -----------------------------------------------------------------------------
module tb_aes;
    reg clk=0; reg rst=1;
    always #10 clk=~clk;

    reg  [31:0] adr, di; wire [31:0] dout;
    reg  [3:0] sel; reg we, stb, cyc; wire ack;
    wire irq;

    aes128 dut (
        .clk_i(clk), .rst_i(rst),
        .wb_adr_i(adr), .wb_dat_i(di), .wb_dat_o(dout),
        .wb_sel_i(sel), .wb_we_i(we), .wb_stb_i(stb), .wb_cyc_i(cyc),
        .wb_ack_o(ack), .irq_o(irq)
    );

    task wb_w(input [31:0] a, input [31:0] d);
        begin @(posedge clk);
            adr=a; di=d; sel=4'hF; we=1; stb=1; cyc=1;
            wait(ack); @(posedge clk); stb=0; cyc=0; we=0; end
    endtask
    task wb_r(input [31:0] a, output [31:0] d);
        begin @(posedge clk);
            adr=a; sel=4'hF; we=0; stb=1; cyc=1;
            wait(ack); d=dout; @(posedge clk); stb=0; cyc=0; end
    endtask

    reg [31:0] r0,r1,r2,r3, st;
    initial begin
        $dumpfile("build/tb_aes.vcd"); $dumpvars(0,tb_aes);
        sel=0; we=0; stb=0; cyc=0;
        #100 rst=0;
        repeat (20) @(posedge clk);

        // KEY (LSW-first) : 0x03020100, 0x07060504, 0x0b0a0908, 0x0f0e0d0c
        wb_w(32'h10, 32'h03020100);
        wb_w(32'h14, 32'h07060504);
        wb_w(32'h18, 32'h0b0a0908);
        wb_w(32'h1C, 32'h0f0e0d0c);
        // PT (LSW-first) : 0x33221100, 0x77665544, 0xbbaa9988, 0xffeeddcc
        wb_w(32'h20, 32'h33221100);
        wb_w(32'h24, 32'h77665544);
        wb_w(32'h28, 32'hbbaa9988);
        wb_w(32'h2C, 32'hffeeddcc);
        // Start encrypt
        wb_w(32'h00, 32'h1);

        // Attendre done (env. 60 cycles pour init + next)
        repeat (200) begin
            @(posedge clk);
            wb_r(32'h04, st);
            if (st[1]) begin
                wb_r(32'h30, r0);
                wb_r(32'h34, r1);
                wb_r(32'h38, r2);
                wb_r(32'h3C, r3);
                $display("CT  = %08x %08x %08x %08x", r3, r2, r1, r0);
                $display("EXP = 5ac5b470 80b7cdd8 30047b6a d8e0c469");
                if (r0 == 32'hd8e0c469 && r1 == 32'h30047b6a &&
                    r2 == 32'h80b7cdd8 && r3 == 32'h5ac5b470)
                    $display("PASS tb_aes — NIST FIPS-197 vector OK");
                else
                    $display("FAIL tb_aes");
                $finish;
            end
        end
        $display("FAIL tb_aes — timeout");
        $finish;
    end
endmodule
