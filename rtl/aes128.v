// -----------------------------------------------------------------------------
// SAHEL-1 — AES-128 ECB, encrypt only (suffisant pour authentifier télémétrie)
// Implémentation compacte : 1 round / cycle, 11 cycles par bloc.
// Clé étendue à la volée à chaque START.
// Esclave Wishbone — voir docs/memory_map.md.
//
// ⚠ STATUS v0.1 : skeleton fonctionnel, NON bit-exact vs FIPS-197.
// La logique de key_expand/round réutilise des appels combinatoires multiples
// dans la même affectation NBA, ce qui peut donner des résultats incorrects.
// AVANT TAPE-OUT : remplacer par tiny_aes_128 (OpenCores, vérifié bit-exact)
// ou par l'IP AES de SecWorks. Voir https://github.com/secworks/aes
// -----------------------------------------------------------------------------
`default_nettype none

module aes128 (
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
    output reg         irq_o
);
    reg [127:0] key_r, din_r, dout_r;
    reg [127:0] state_r, rkey_r;
    reg [3:0]   round;
    reg         busy, done, ctrl_start, ctrl_irq;

    // S-box (256 octets) — synthèse en LUT/ROM
    function [7:0] sbox;
        input [7:0] x;
        begin
            case (x)
                // Pour la lisibilité, on utilise une fonction de calcul GF(2^8)
                // remplacée à la synthèse par une ROM optimisée par Yosys.
                default: sbox = sbox_table(x);
            endcase
        end
    endfunction

    function [7:0] sbox_table;
        input [7:0] x;
        reg [7:0] s [0:255];
        integer i;
        begin
            // Table standard AES S-box
            s[0]=8'h63;  s[1]=8'h7c;  s[2]=8'h77;  s[3]=8'h7b;
            s[4]=8'hf2;  s[5]=8'h6b;  s[6]=8'h6f;  s[7]=8'hc5;
            s[8]=8'h30;  s[9]=8'h01;  s[10]=8'h67; s[11]=8'h2b;
            s[12]=8'hfe; s[13]=8'hd7; s[14]=8'hab; s[15]=8'h76;
            s[16]=8'hca; s[17]=8'h82; s[18]=8'hc9; s[19]=8'h7d;
            s[20]=8'hfa; s[21]=8'h59; s[22]=8'h47; s[23]=8'hf0;
            s[24]=8'had; s[25]=8'hd4; s[26]=8'ha2; s[27]=8'haf;
            s[28]=8'h9c; s[29]=8'ha4; s[30]=8'h72; s[31]=8'hc0;
            s[32]=8'hb7; s[33]=8'hfd; s[34]=8'h93; s[35]=8'h26;
            s[36]=8'h36; s[37]=8'h3f; s[38]=8'hf7; s[39]=8'hcc;
            s[40]=8'h34; s[41]=8'ha5; s[42]=8'he5; s[43]=8'hf1;
            s[44]=8'h71; s[45]=8'hd8; s[46]=8'h31; s[47]=8'h15;
            s[48]=8'h04; s[49]=8'hc7; s[50]=8'h23; s[51]=8'hc3;
            s[52]=8'h18; s[53]=8'h96; s[54]=8'h05; s[55]=8'h9a;
            s[56]=8'h07; s[57]=8'h12; s[58]=8'h80; s[59]=8'he2;
            s[60]=8'heb; s[61]=8'h27; s[62]=8'hb2; s[63]=8'h75;
            s[64]=8'h09; s[65]=8'h83; s[66]=8'h2c; s[67]=8'h1a;
            s[68]=8'h1b; s[69]=8'h6e; s[70]=8'h5a; s[71]=8'ha0;
            s[72]=8'h52; s[73]=8'h3b; s[74]=8'hd6; s[75]=8'hb3;
            s[76]=8'h29; s[77]=8'he3; s[78]=8'h2f; s[79]=8'h84;
            s[80]=8'h53; s[81]=8'hd1; s[82]=8'h00; s[83]=8'hed;
            s[84]=8'h20; s[85]=8'hfc; s[86]=8'hb1; s[87]=8'h5b;
            s[88]=8'h6a; s[89]=8'hcb; s[90]=8'hbe; s[91]=8'h39;
            s[92]=8'h4a; s[93]=8'h4c; s[94]=8'h58; s[95]=8'hcf;
            s[96]=8'hd0; s[97]=8'hef; s[98]=8'haa; s[99]=8'hfb;
            s[100]=8'h43;s[101]=8'h4d;s[102]=8'h33;s[103]=8'h85;
            s[104]=8'h45;s[105]=8'hf9;s[106]=8'h02;s[107]=8'h7f;
            s[108]=8'h50;s[109]=8'h3c;s[110]=8'h9f;s[111]=8'ha8;
            s[112]=8'h51;s[113]=8'ha3;s[114]=8'h40;s[115]=8'h8f;
            s[116]=8'h92;s[117]=8'h9d;s[118]=8'h38;s[119]=8'hf5;
            s[120]=8'hbc;s[121]=8'hb6;s[122]=8'hda;s[123]=8'h21;
            s[124]=8'h10;s[125]=8'hff;s[126]=8'hf3;s[127]=8'hd2;
            s[128]=8'hcd;s[129]=8'h0c;s[130]=8'h13;s[131]=8'hec;
            s[132]=8'h5f;s[133]=8'h97;s[134]=8'h44;s[135]=8'h17;
            s[136]=8'hc4;s[137]=8'ha7;s[138]=8'h7e;s[139]=8'h3d;
            s[140]=8'h64;s[141]=8'h5d;s[142]=8'h19;s[143]=8'h73;
            s[144]=8'h60;s[145]=8'h81;s[146]=8'h4f;s[147]=8'hdc;
            s[148]=8'h22;s[149]=8'h2a;s[150]=8'h90;s[151]=8'h88;
            s[152]=8'h46;s[153]=8'hee;s[154]=8'hb8;s[155]=8'h14;
            s[156]=8'hde;s[157]=8'h5e;s[158]=8'h0b;s[159]=8'hdb;
            s[160]=8'he0;s[161]=8'h32;s[162]=8'h3a;s[163]=8'h0a;
            s[164]=8'h49;s[165]=8'h06;s[166]=8'h24;s[167]=8'h5c;
            s[168]=8'hc2;s[169]=8'hd3;s[170]=8'hac;s[171]=8'h62;
            s[172]=8'h91;s[173]=8'h95;s[174]=8'he4;s[175]=8'h79;
            s[176]=8'he7;s[177]=8'hc8;s[178]=8'h37;s[179]=8'h6d;
            s[180]=8'h8d;s[181]=8'hd5;s[182]=8'h4e;s[183]=8'ha9;
            s[184]=8'h6c;s[185]=8'h56;s[186]=8'hf4;s[187]=8'hea;
            s[188]=8'h65;s[189]=8'h7a;s[190]=8'hae;s[191]=8'h08;
            s[192]=8'hba;s[193]=8'h78;s[194]=8'h25;s[195]=8'h2e;
            s[196]=8'h1c;s[197]=8'ha6;s[198]=8'hb4;s[199]=8'hc6;
            s[200]=8'he8;s[201]=8'hdd;s[202]=8'h74;s[203]=8'h1f;
            s[204]=8'h4b;s[205]=8'hbd;s[206]=8'h8b;s[207]=8'h8a;
            s[208]=8'h70;s[209]=8'h3e;s[210]=8'hb5;s[211]=8'h66;
            s[212]=8'h48;s[213]=8'h03;s[214]=8'hf6;s[215]=8'h0e;
            s[216]=8'h61;s[217]=8'h35;s[218]=8'h57;s[219]=8'hb9;
            s[220]=8'h86;s[221]=8'hc1;s[222]=8'h1d;s[223]=8'h9e;
            s[224]=8'he1;s[225]=8'hf8;s[226]=8'h98;s[227]=8'h11;
            s[228]=8'h69;s[229]=8'hd9;s[230]=8'h8e;s[231]=8'h94;
            s[232]=8'h9b;s[233]=8'h1e;s[234]=8'h87;s[235]=8'he9;
            s[236]=8'hce;s[237]=8'h55;s[238]=8'h28;s[239]=8'hdf;
            s[240]=8'h8c;s[241]=8'ha1;s[242]=8'h89;s[243]=8'h0d;
            s[244]=8'hbf;s[245]=8'he6;s[246]=8'h42;s[247]=8'h68;
            s[248]=8'h41;s[249]=8'h99;s[250]=8'h2d;s[251]=8'h0f;
            s[252]=8'hb0;s[253]=8'h54;s[254]=8'hbb;s[255]=8'h16;
            sbox_table = s[x];
        end
    endfunction

    // xtime
    function [7:0] xtime; input [7:0] b;
        xtime = (b << 1) ^ ((b[7]) ? 8'h1b : 8'h00);
    endfunction

    // Rcon
    function [7:0] rcon; input [3:0] r;
        case (r)
            4'd1: rcon=8'h01; 4'd2: rcon=8'h02; 4'd3: rcon=8'h04; 4'd4: rcon=8'h08;
            4'd5: rcon=8'h10; 4'd6: rcon=8'h20; 4'd7: rcon=8'h40; 4'd8: rcon=8'h80;
            4'd9: rcon=8'h1b; 4'd10:rcon=8'h36; default: rcon=8'h00;
        endcase
    endfunction

    // SubBytes (16 octets)
    function [127:0] sub_bytes; input [127:0] s; integer i; begin
        for (i = 0; i < 16; i = i + 1)
            sub_bytes[i*8 +: 8] = sbox_table(s[i*8 +: 8]);
    end endfunction

    // ShiftRows (col-major AES)
    function [127:0] shift_rows; input [127:0] s;
        // s = b0..b15, col-major : b[c*4+r]
        // ligne 0 : pas de shift ; ligne 1 : <<1 ; ligne 2 : <<2 ; ligne 3 : <<3
        begin
            // row 0
            shift_rows[ 0*8 +: 8] = s[ 0*8 +: 8];
            shift_rows[ 4*8 +: 8] = s[ 4*8 +: 8];
            shift_rows[ 8*8 +: 8] = s[ 8*8 +: 8];
            shift_rows[12*8 +: 8] = s[12*8 +: 8];
            // row 1
            shift_rows[ 1*8 +: 8] = s[ 5*8 +: 8];
            shift_rows[ 5*8 +: 8] = s[ 9*8 +: 8];
            shift_rows[ 9*8 +: 8] = s[13*8 +: 8];
            shift_rows[13*8 +: 8] = s[ 1*8 +: 8];
            // row 2
            shift_rows[ 2*8 +: 8] = s[10*8 +: 8];
            shift_rows[ 6*8 +: 8] = s[14*8 +: 8];
            shift_rows[10*8 +: 8] = s[ 2*8 +: 8];
            shift_rows[14*8 +: 8] = s[ 6*8 +: 8];
            // row 3
            shift_rows[ 3*8 +: 8] = s[15*8 +: 8];
            shift_rows[ 7*8 +: 8] = s[ 3*8 +: 8];
            shift_rows[11*8 +: 8] = s[ 7*8 +: 8];
            shift_rows[15*8 +: 8] = s[11*8 +: 8];
        end
    endfunction

    // MixColumns (1 colonne)
    function [31:0] mix_col; input [31:0] c;
        reg [7:0] a0,a1,a2,a3,b0,b1,b2,b3;
        begin
            a0=c[7:0]; a1=c[15:8]; a2=c[23:16]; a3=c[31:24];
            b0 = xtime(a0) ^ (xtime(a1) ^ a1) ^ a2 ^ a3;
            b1 = a0 ^ xtime(a1) ^ (xtime(a2) ^ a2) ^ a3;
            b2 = a0 ^ a1 ^ xtime(a2) ^ (xtime(a3) ^ a3);
            b3 = (xtime(a0) ^ a0) ^ a1 ^ a2 ^ xtime(a3);
            mix_col = {b3,b2,b1,b0};
        end
    endfunction

    function [127:0] mix_columns; input [127:0] s;
        begin
            mix_columns[ 31:  0] = mix_col(s[ 31:  0]);
            mix_columns[ 63: 32] = mix_col(s[ 63: 32]);
            mix_columns[ 95: 64] = mix_col(s[ 95: 64]);
            mix_columns[127: 96] = mix_col(s[127: 96]);
        end
    endfunction

    // Key schedule (un round à la fois)
    function [127:0] key_expand; input [127:0] k; input [3:0] r;
        reg [31:0] w0,w1,w2,w3,t;
        begin
            w0=k[31:0]; w1=k[63:32]; w2=k[95:64]; w3=k[127:96];
            t = {w3[23:0], w3[31:24]}; // RotWord
            t = {sbox_table(t[31:24]), sbox_table(t[23:16]),
                 sbox_table(t[15:8]),  sbox_table(t[7:0])};
            t = t ^ {24'h0, rcon(r)};
            w0 = w0 ^ t;
            w1 = w1 ^ w0;
            w2 = w2 ^ w1;
            w3 = w3 ^ w2;
            key_expand = {w3,w2,w1,w0};
        end
    endfunction

    // FSM
    always @(posedge clk_i) begin
        if (rst_i) begin
            busy <= 0; done <= 0; round <= 0; irq_o <= 0;
        end else begin
            irq_o <= 0;
            if (ctrl_start && !busy) begin
                state_r <= din_r ^ key_r;     // AddRoundKey initial
                rkey_r  <= key_r;
                round   <= 1;
                busy    <= 1; done <= 0;
            end else if (busy) begin
                rkey_r  <= key_expand(rkey_r, round[3:0]);
                if (round < 10) begin
                    state_r <= mix_columns(shift_rows(sub_bytes(state_r))) ^ key_expand(rkey_r, round[3:0]);
                    round   <= round + 1'b1;
                end else begin
                    // dernier round : pas de MixColumns
                    state_r <= shift_rows(sub_bytes(state_r)) ^ key_expand(rkey_r, round[3:0]);
                    busy    <= 0; done <= 1; dout_r <= shift_rows(sub_bytes(state_r)) ^ key_expand(rkey_r, round[3:0]);
                    if (ctrl_irq) irq_o <= 1'b1;
                end
            end
        end
    end

    // WB CSR
    always @(posedge clk_i) begin
        if (rst_i) begin
            wb_ack_o <= 0; ctrl_start <= 0; ctrl_irq <= 0;
            key_r <= 0; din_r <= 0;
        end else begin
            wb_ack_o   <= 0;
            ctrl_start <= 0;
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                case (wb_adr_i[7:0])
                    8'h00: if (wb_we_i) begin ctrl_start<=wb_dat_i[0]; ctrl_irq<=wb_dat_i[2]; end
                    8'h04: wb_dat_o <= {30'h0, done, busy};
                    8'h10: if (wb_we_i) key_r[ 31:  0] <= wb_dat_i; else wb_dat_o <= key_r[ 31:  0];
                    8'h14: if (wb_we_i) key_r[ 63: 32] <= wb_dat_i; else wb_dat_o <= key_r[ 63: 32];
                    8'h18: if (wb_we_i) key_r[ 95: 64] <= wb_dat_i; else wb_dat_o <= key_r[ 95: 64];
                    8'h1C: if (wb_we_i) key_r[127: 96] <= wb_dat_i; else wb_dat_o <= key_r[127: 96];
                    8'h20: if (wb_we_i) din_r[ 31:  0] <= wb_dat_i; else wb_dat_o <= din_r[ 31:  0];
                    8'h24: if (wb_we_i) din_r[ 63: 32] <= wb_dat_i; else wb_dat_o <= din_r[ 63: 32];
                    8'h28: if (wb_we_i) din_r[ 95: 64] <= wb_dat_i; else wb_dat_o <= din_r[ 95: 64];
                    8'h2C: if (wb_we_i) din_r[127: 96] <= wb_dat_i; else wb_dat_o <= din_r[127: 96];
                    8'h30: wb_dat_o <= dout_r[ 31:  0];
                    8'h34: wb_dat_o <= dout_r[ 63: 32];
                    8'h38: wb_dat_o <= dout_r[ 95: 64];
                    8'h3C: wb_dat_o <= dout_r[127: 96];
                    default: wb_dat_o <= 0;
                endcase
            end
        end
    end
endmodule
