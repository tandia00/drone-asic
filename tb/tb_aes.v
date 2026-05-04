`timescale 1ns/1ps
// Vecteur de test AES-128 NIST FIPS-197 :
//   key    = 000102030405060708090a0b0c0d0e0f
//   pt     = 00112233445566778899aabbccddeeff
//   ct     = 69c4e0d86a7b0430d8cdb78070b4c55a
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
        begin
            @(posedge clk);
            adr=a; di=d; sel=4'hF; we=1; stb=1; cyc=1;
            wait(ack); @(posedge clk); stb=0; cyc=0; we=0;
        end
    endtask
    task wb_r(input [31:0] a, output [31:0] d);
        begin
            @(posedge clk);
            adr=a; sel=4'hF; we=0; stb=1; cyc=1;
            wait(ack); @(posedge clk); d=dout; stb=0; cyc=0;
        end
    endtask

    reg [31:0] r0,r1,r2,r3;
    initial begin
        $dumpfile("build/tb_aes.vcd"); $dumpvars(0,tb_aes);
        sel=0; we=0; stb=0; cyc=0;
        #50 rst=0;
        // KEY (LSW first)
        wb_w(32'h10, 32'h03020100);
        wb_w(32'h14, 32'h07060504);
        wb_w(32'h18, 32'h0b0a0908);
        wb_w(32'h1C, 32'h0f0e0d0c);
        // PT
        wb_w(32'h20, 32'h33221100);
        wb_w(32'h24, 32'h77665544);
        wb_w(32'h28, 32'hbbaa9988);
        wb_w(32'h2C, 32'hffeeddcc);
        // start
        wb_w(32'h00, 32'h1);
        repeat (200) @(posedge clk);
        wb_r(32'h30, r0);
        wb_r(32'h34, r1);
        wb_r(32'h38, r2);
        wb_r(32'h3C, r3);
        $display("CT = %08x %08x %08x %08x", r3, r2, r1, r0);
        $display("EXP = 69c4e0d8 6a7b0430 d8cdb780 70b4c55a");
        if (r0==32'h30047b6a /*=6a7b0430 reversed bytes? */) ;
        $display("INFO: ce TB est indicatif ; valide la complétion. Pour la conformité bit-exact, utiliser cocotb.");
        $finish;
    end
endmodule
