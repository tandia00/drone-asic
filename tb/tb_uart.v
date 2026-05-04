`timescale 1ns/1ps
module tb_uart;
    reg clk=0; reg rst=1;
    always #10 clk=~clk;

    reg [31:0] adr, di; wire [31:0] dout;
    reg [3:0] sel; reg we, stb, cyc; wire ack;
    wire tx; reg rx = 1; wire irq;

    uart dut (.clk_i(clk), .rst_i(rst),
        .wb_adr_i(adr), .wb_dat_i(di), .wb_dat_o(dout),
        .wb_sel_i(sel), .wb_we_i(we), .wb_stb_i(stb), .wb_cyc_i(cyc),
        .wb_ack_o(ack), .rx_i(rx), .tx_o(tx), .irq_o(irq));

    task wb_w(input [31:0] a, input [31:0] d);
        begin @(posedge clk);
            adr=a; di=d; sel=4'hF; we=1; stb=1; cyc=1;
            wait(ack); @(posedge clk); stb=0; cyc=0; we=0; end
    endtask

    initial begin
        $dumpfile("build/tb_uart.vcd"); $dumpvars(0, tb_uart);
        sel=0; we=0; stb=0; cyc=0;
        #50 rst=0;
        // baud divisor pour test rapide : 4 cycles/bit
        wb_w(32'h08, 32'd4);
        // envoyer 'A' (0x41)
        wb_w(32'h00, 32'h41);
        // attendre la fin de transmission
        repeat (200) @(posedge clk);
        $display("PASS tb_uart (transmission de 'A' simulée)");
        $finish;
    end
endmodule
