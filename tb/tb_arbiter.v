`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// Test d'intégration : NDVI accelerator lit/écrit la SRAM via wb_arbiter.
// Scénario « end-to-end » :
//   1. Le master 0 (faux CPU) charge 4 pixels RED + 4 pixels NIR dans la SRAM.
//   2. Le master 0 programme les registres CSR du NDVI (addresses, npix…).
//   3. Le NDVI démarre, accède la SRAM via master 1 (arbiter) et écrit les
//      résultats.
//   4. Le master 0 relit le buffer de sortie et vérifie les valeurs NDVI.
// -----------------------------------------------------------------------------
module tb_arbiter;
    reg clk=0; reg rst=1;
    always #10 clk=~clk;

    // Master 0 (CPU)
    reg [31:0] m0_adr, m0_dat_i; wire [31:0] m0_dat_o;
    reg [3:0]  m0_sel; reg m0_we, m0_stb, m0_cyc; wire m0_ack;
    // Master 1 (NDVI DMA)
    wire [31:0] m1_adr, m1_dat_i_w; wire [31:0] m1_dat_o;
    wire [3:0]  m1_sel; wire m1_we, m1_stb, m1_cyc; wire m1_ack;
    // slave (partagé SRAM ou NDVI CSR selon adresse)
    wire [31:0] s_adr, s_dat_o_w, s_dat_i_w;
    wire [3:0]  s_sel; wire s_we, s_stb, s_cyc, s_ack;

    wb_arbiter u_arb (
        .clk_i(clk), .rst_i(rst),
        .m0_adr_i(m0_adr), .m0_dat_i(m0_dat_i), .m0_dat_o(m0_dat_o),
        .m0_sel_i(m0_sel), .m0_we_i(m0_we), .m0_stb_i(m0_stb),
        .m0_cyc_i(m0_cyc), .m0_ack_o(m0_ack),
        .m1_adr_i(m1_adr), .m1_dat_i(m1_dat_i_w), .m1_dat_o(m1_dat_o),
        .m1_sel_i(m1_sel), .m1_we_i(m1_we), .m1_stb_i(m1_stb),
        .m1_cyc_i(m1_cyc), .m1_ack_o(m1_ack),
        .s_adr_o(s_adr), .s_dat_o(s_dat_o_w), .s_dat_i(s_dat_i_w),
        .s_sel_o(s_sel), .s_we_o(s_we), .s_stb_o(s_stb),
        .s_cyc_o(s_cyc), .s_ack_i(s_ack)
    );

    // Mux slave : adr[15:12]==0xA → NDVI CSR, sinon SRAM
    wire  ndvi_sel  = (s_adr[15:12] == 4'hA);
    wire  sram_sel  = !ndvi_sel;
    wire [31:0] sram_dat_o, ndvi_dat_o;
    wire sram_ack, ndvi_ack;

    assign s_dat_i_w = ndvi_sel ? ndvi_dat_o : sram_dat_o;
    assign s_ack     = ndvi_sel ? ndvi_ack   : sram_ack;

    sram_wrap u_sram (
        .clk_i(clk), .rst_i(rst),
        .wb_adr_i(s_adr), .wb_dat_i(s_dat_o_w), .wb_dat_o(sram_dat_o),
        .wb_sel_i(s_sel), .wb_we_i(s_we), .wb_stb_i(s_stb & sram_sel),
        .wb_cyc_i(s_cyc & sram_sel), .wb_ack_o(sram_ack)
    );

    ndvi_accel u_ndvi (
        .clk_i(clk), .rst_i(rst),
        .wb_adr_i(s_adr), .wb_dat_i(s_dat_o_w), .wb_dat_o(ndvi_dat_o),
        .wb_sel_i(s_sel), .wb_we_i(s_we), .wb_stb_i(s_stb & ndvi_sel),
        .wb_cyc_i(s_cyc & ndvi_sel), .wb_ack_o(ndvi_ack),
        .dma_adr_o(m1_adr), .dma_dat_o(m1_dat_i_w), .dma_dat_i(m1_dat_o),
        .dma_we_o(m1_we),   .dma_stb_o(m1_stb),     .dma_cyc_o(m1_cyc),
        .dma_ack_i(m1_ack), .irq_o()
    );
    assign m1_sel = 4'hF;

    // Tâches WB
    task m0_wr(input [31:0] a, input [31:0] d);
        begin @(posedge clk);
            m0_adr=a; m0_dat_i=d; m0_sel=4'hF; m0_we=1; m0_stb=1; m0_cyc=1;
            wait(m0_ack); @(posedge clk);
            m0_stb=0; m0_cyc=0; m0_we=0; end
    endtask
    task m0_rd(input [31:0] a, output [31:0] d);
        begin @(posedge clk);
            m0_adr=a; m0_sel=4'hF; m0_we=0; m0_stb=1; m0_cyc=1;
            wait(m0_ack); d=m0_dat_o; @(posedge clk);
            m0_stb=0; m0_cyc=0; end
    endtask

    integer errors = 0, i;
    reg [31:0] r;
    reg [7:0]  red [0:3];
    reg [7:0]  nir [0:3];

    initial begin
        red[0]=10;  nir[0]=200;  // NDVI attendu ~ +115
        red[1]=120; nir[1]=130;  // NDVI ~ +5
        red[2]=200; nir[2]=10;   // NDVI ~ -115
        red[3]=50;  nir[3]=150;  // NDVI ~ +63
    end

    // Timeout global (sécurité) : le test ne doit jamais dépasser 500 µs.
    initial begin
        #500000;
        $display("FAIL tb_arbiter — TIMEOUT 500us (deadlock probable)");
        $finish;
    end

    initial begin
        $dumpfile("build/tb_arbiter.vcd"); $dumpvars(0,tb_arbiter);
        m0_adr=0; m0_dat_i=0; m0_sel=0; m0_we=0; m0_stb=0; m0_cyc=0;
        #100 rst=0;
        repeat (5) @(posedge clk);

        // 1) CPU écrit les 4 pixels RED à 0x1000_0000 (octet par octet via m0_wr 32b)
        //    On écrit 4 octets en 1 mot à chaque adresse mot-alignée (idx 0,1,2,3)
        //    -> ici simplification : 1 mot = 1 pixel (octet bas), reste = 0
        for (i = 0; i < 4; i = i + 1) begin
            m0_wr(32'h1000_0000 + (i << 2), {24'h0, red[i]});
            m0_wr(32'h1000_0100 + (i << 2), {24'h0, nir[i]});
        end

        // 2) Programmer les CSR NDVI (base 0x3000_A000)
        m0_wr(32'h3000_A008, 32'h1000_0000); // RED_ADDR
        m0_wr(32'h3000_A00C, 32'h1000_0100); // NIR_ADDR
        m0_wr(32'h3000_A010, 32'h1000_0200); // OUT_ADDR
        m0_wr(32'h3000_A014, 32'd4);          // NPIX
        m0_wr(32'h3000_A000, 32'h1);          // start

        // 3) Poller STATUS busy
        r = 32'h1;
        while (r[0] == 1'b1) begin
            m0_rd(32'h3000_A004, r);
        end

        // 4) Relire les résultats (les NDVI sont stockés comme mot 32b avec
        //    sign-extension du int8 ; on ne lit que les 8 bits bas).
        for (i = 0; i < 4; i = i + 1) begin
            m0_rd(32'h1000_0200 + (i << 2), r);
            $display("NDVI[%0d] = %0d (brut=0x%08x)", i, $signed(r[7:0]), r);
        end

        // vérifs
        m0_rd(32'h1000_0200 + 0, r);
        if ($signed(r[7:0]) < 100) begin $display("FAIL NDVI[0]"); errors=errors+1; end
        m0_rd(32'h1000_0200 + 8, r);
        if ($signed(r[7:0]) > -100) begin $display("FAIL NDVI[2]"); errors=errors+1; end

        if (errors == 0) $display("PASS tb_arbiter — NDVI DMA via arbiter OK");
        else             $display("FAIL tb_arbiter (%0d erreurs)", errors);
        $finish;
    end
endmodule
