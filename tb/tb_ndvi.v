`timescale 1ns/1ps
// Vérifie le calcul NDVI sur quelques pixels représentatifs.
//   Attendu :
//     R=10,  NIR=200 → (200-10)/(200+10) = 0.905 → ×127 ≈ +115
//     R=120, NIR=130 → (130-120)/(250)   = 0.040 → ×127 ≈ +5
//     R=200, NIR=10  → -(190/210)         = -0.905→ ×127 ≈ -115
module tb_ndvi;
    reg clk = 0; reg rst = 1;
    always #10 clk = ~clk;

    // CSR
    reg  [31:0] cs_adr, cs_di; wire [31:0] cs_do;
    reg  [3:0] cs_sel; reg cs_we, cs_stb, cs_cyc; wire cs_ack;

    // DMA (modèle mémoire)
    wire [31:0] dma_adr, dma_dat_o; reg [31:0] dma_dat_i;
    wire dma_we, dma_stb, dma_cyc; reg dma_ack;
    wire irq;

    ndvi_accel dut (
        .clk_i(clk), .rst_i(rst),
        .wb_adr_i(cs_adr), .wb_dat_i(cs_di), .wb_dat_o(cs_do),
        .wb_sel_i(cs_sel), .wb_we_i(cs_we), .wb_stb_i(cs_stb), .wb_cyc_i(cs_cyc),
        .wb_ack_o(cs_ack),
        .dma_adr_o(dma_adr), .dma_dat_o(dma_dat_o), .dma_dat_i(dma_dat_i),
        .dma_we_o(dma_we), .dma_stb_o(dma_stb), .dma_cyc_o(dma_cyc),
        .dma_ack_i(dma_ack),
        .irq_o(irq)
    );

    // Mémoire simulée 1 KB — word addressable (32b/mot)
    reg [31:0] mem [0:255];
    integer pix_red [0:2];
    integer pix_nir [0:2];
    reg [7:0] out_mem [0:2];

    initial begin
        pix_red[0]=10;  pix_nir[0]=200;
        pix_red[1]=120; pix_nir[1]=130;
        pix_red[2]=200; pix_nir[2]=10;
    end

    // Servir la DMA (word-addressable : addr[9:2] = index)
    always @(posedge clk) begin
        dma_ack <= 0;
        if (dma_stb && dma_cyc && !dma_ack) begin
            if (dma_we) begin
                // OUT_BASE=0x200 → out_mem idx = (addr - 0x200) >> 2
                out_mem[(dma_adr - 32'h200) >> 2] <= dma_dat_o[7:0];
            end else begin
                dma_dat_i <= mem[dma_adr[9:2]];
            end
            dma_ack <= 1'b1;
        end
    end

    task wb_w(input [31:0] a, input [31:0] d);
        begin
            @(posedge clk);
            cs_adr=a; cs_di=d; cs_sel=4'hF; cs_we=1; cs_stb=1; cs_cyc=1;
            wait(cs_ack); @(posedge clk);
            cs_stb=0; cs_cyc=0; cs_we=0;
        end
    endtask

    integer i;
    initial begin
        $dumpfile("build/tb_ndvi.vcd");
        $dumpvars(0, tb_ndvi);
        cs_sel=0; cs_we=0; cs_stb=0; cs_cyc=0;
        // initialiser mem : RED en 0x000, NIR en 0x100, OUT en 0x200
        // mem est word-indexed (1 pixel par mot 32b)
        for (i=0; i<3; i=i+1) begin
            mem[i]          = pix_red[i];           // idx 0,1,2  (addr 0x000,4,8)
            mem[8'h40 + i]  = pix_nir[i];           // idx 64,65,66 (addr 0x100,104,108)
        end
        #50 rst = 0;
        wb_w(32'h08, 32'h0000_0000); // RED_ADDR
        wb_w(32'h0C, 32'h0000_0100); // NIR_ADDR
        wb_w(32'h10, 32'h0000_0200); // OUT_ADDR
        wb_w(32'h14, 32'd3);          // NPIX
        wb_w(32'h00, 32'h1);          // start
        // attendre done
        wait(irq === 1'b1 || dut.st_done);
        repeat (10) @(posedge clk);
        $display("NDVI(10,200)  = %0d  (attendu ~+115)", $signed(out_mem[0]));
        $display("NDVI(120,130) = %0d  (attendu ~+5)",   $signed(out_mem[1]));
        $display("NDVI(200,10)  = %0d  (attendu ~-115)", $signed(out_mem[2]));
        if ($signed(out_mem[0]) > 100 && $signed(out_mem[2]) < -100)
            $display("PASS tb_ndvi");
        else
            $display("FAIL tb_ndvi");
        $finish;
    end
endmodule
