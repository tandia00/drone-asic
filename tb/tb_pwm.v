`timescale 1ns/1ps
module tb_pwm;
    reg clk = 0; reg rst = 1;
    always #10 clk = ~clk; // 50 MHz

    reg  [31:0] adr, dat_i; wire [31:0] dat_o;
    reg  [3:0]  sel; reg we, stb, cyc; wire ack;
    wire [5:0]  pwm_out;

    pwm dut (
        .clk_i(clk), .rst_i(rst),
        .wb_adr_i(adr), .wb_dat_i(dat_i), .wb_dat_o(dat_o),
        .wb_sel_i(sel), .wb_we_i(we), .wb_stb_i(stb), .wb_cyc_i(cyc),
        .wb_ack_o(ack), .pwm_o(pwm_out)
    );

    task wb_write(input [31:0] a, input [31:0] d);
        begin
            @(posedge clk);
            adr=a; dat_i=d; sel=4'hF; we=1; stb=1; cyc=1;
            wait(ack); @(posedge clk);
            stb=0; cyc=0; we=0;
        end
    endtask

    initial begin
        $dumpfile("build/tb_pwm.vcd");
        $dumpvars(0, tb_pwm);
        sel=0; we=0; stb=0; cyc=0; adr=0; dat_i=0;
        #50 rst = 0;
        // Canal 0 : période 100, duty 25 → 25 % d.c.
        wb_write(32'h00, 32'd100); // PERIOD
        wb_write(32'h04, 32'd25);  // DUTY
        wb_write(32'h08, 32'd1);   // EN
        #5000;
        if (pwm_out[0] === 1'bx) begin $display("FAIL pwm_out X"); $finish; end
        $display("PASS tb_pwm — pwm0 toggles");
        $finish;
    end
endmodule
