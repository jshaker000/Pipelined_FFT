#!/usr/bin/env python3

import math
from fractions import Fraction

# Note that perhaps we should be using mpmath for higher precision rather than using the 'math' routines

def bank_round(n):
   nr = int(round(n*10))
   if (nr % 10 == 5):
       n = int(nr/10) if int(nr/10) % 2 == 0 else int(nr/10) + 1
   else:
       n = int(round(n))
   return n

max_bits    = 64
max_fft_len = 4096

file_v = open("twiddle_rom.v", "w")
file_v.write("`default_nettype none\n"                               +
             "// This file is manually generated.\n"                 +
             "// Do Not Modify by hand.\n"                           +
             "// This should(?) Synthsize to a ROM of the reduced width\n" +
             "// Take advantage of symetries to reduce amount of RAM needed\n" +
             "// Latency of 2 clks"                                  +
             "// For FFTS up to length %d\n"  % (max_fft_len)        +
             "module twiddle_rom #(\n"                               +
             "  parameter  IS_IFFT       = 1'b0,\n"                  +
             "  parameter  OUT_W         = %d,\n"    % (max_bits)    +
             "  parameter  FFT_LEN       = %d,\n"   % (max_fft_len)  +
             "  localparam ADDR_W        = $clog2(FFT_LEN)-1,\n"     +
             "  localparam MAX_FFT_LEN   = %d,\n" % (max_fft_len)    +
             "  localparam MASTER_OUT_W  = %d,\n" % (max_bits)       +
             "  localparam MASTER_ADDR_W = $clog2(MAX_FFT_LEN)-1\n"  +
             ") (\n" +
             "  input wire                      clk,\n"   +
             "  input wire         [ADDR_W-1:0] i_addr,\n" +
             "  output reg signed   [OUT_W-1:0] o_cos,\n"  +
             "  output reg signed   [OUT_W-1:0] o_sin,\n"   +
             "  output reg signed     [OUT_W:0] o_sum // sum of I and Q, useful for 3 multiply complex multipliers\n"   +
             ");\n\n")

file_v.write("  localparam [OUT_W-1:0] COS_N_4 = {OUT_W{1'b0}};\n" +
             "  localparam [OUT_W-1:0] SIN_N_4 = IS_IFFT == 0 ? {{2{1'b1}}, {OUT_W-2{1'b0}}} : {{2{1'b0}}, {OUT_W-2{1'b1}}};\n\n")

for str_base in ["cos_rom", "sin_rom"]:
    file_v.write("  localparam [MASTER_OUT_W*(MAX_FFT_LEN/4)-1:0] %s_MASTER = {\n" % (str_base.upper()))
    for j in range (int(max_fft_len/4) - 1, -1, -1):
        if (str_base=="cos_rom"):
            trig = bank_round((2**(max_bits-2))*math.cos(-1*math.pi*Fraction(2*j, max_fft_len)))
        else:
            trig = bank_round((2**(max_bits-2))*math.sin(-1*math.pi*Fraction(2*j, max_fft_len)))
        if trig < 0:
            max_bits_tmp = -1*max_bits
        else:
            max_bits_tmp = max_bits
        trig = abs(trig)
        file_v.write("    $unsigned(%d'sd%d)%s /* %s{e^(-j 2pi (%d/%d))} */\n" % (max_bits_tmp, trig,
                                                                    " " if j==0 else ",",
                                                                    "Re" if str_base=="cos_rom" else "Im", j, max_fft_len))
    file_v.write("  };\n\n")

for str_base in ["cos_rom", "sin_rom"]:
    file_v.write("  // select the needed signals from %s_MASTER into %s and apply convergent rounding to make the real, synthesized rom\n" %(str_base.upper(), str_base) +
                 "  reg signed [OUT_W-1:0] %s [0:(FFT_LEN/4)-1];\n" % (str_base) +
                 "  initial begin: init_%s\n" % (str_base)+
                 "    reg [$clog2((MAX_FFT_LEN/2)*MASTER_OUT_W)-2:0] strt_idx;\n" +
                 "    reg signed [MASTER_OUT_W-1:0] sel_val;\n" +
                 "    /* verilator lint_off UNUSED */\n" +
                 "    reg signed [MASTER_OUT_W-1:0] rnd_val;\n" +
                 "    /* verilator lint_off UNUSED */\n" +
                 "    reg signed        [OUT_W-1:0] trunc_val;\n" +
                 "    integer                       ii;\n"        +
                 "    for(ii = 0; ii < FFT_LEN/4; ii=ii+1) begin\n" +
                 "      strt_idx  = MASTER_OUT_W*({ii[ADDR_W-1:0], {MASTER_ADDR_W-ADDR_W{1'b0}}});\n" +
                 "      sel_val   = $signed(%s_MASTER[strt_idx +: MASTER_OUT_W])%s;\n" % (str_base.upper(),
                        "" if str_base == "cos_rom" else " * (IS_IFFT ? -'sd1 : 'd1)") +
                 "      rnd_val   = sel_val + {{OUT_W{1'b0}}, sel_val[MASTER_OUT_W-OUT_W], {MASTER_OUT_W-OUT_W-1{~sel_val[MASTER_OUT_W-OUT_W]}}};\n" +
                 "      trunc_val = $signed(rnd_val[MASTER_OUT_W - 1 -: OUT_W]);\n" +
                 "      %s[ii] = trunc_val;\n"  % (str_base) +
                 "    end\n" +
                 "  end\n\n")

file_v.write("  reg               addr_sign_d1;\n"                                        +
             "  reg  [ADDR_W-2:0] translated_addr;\n"                                     +
             "  wire addr_sign  = i_addr[ADDR_W-1];\n"                                    +
             "  wire is_n_4     = addr_sign & (translated_addr == 0);\n\n"                +
             "  always @(posedge clk) addr_sign_d1    <= addr_sign;\n"                   +
             "  always @(posedge clk) translated_addr <= addr_sign ? $unsigned(-i_addr[ADDR_W-2:0]) : i_addr[ADDR_W-2:0];\n\n" +
             "  wire signed [OUT_W-1:0] cos_e1 = is_n_4 ? $signed(COS_N_4) : addr_sign_d1 ? -cos_rom[translated_addr] : cos_rom[translated_addr];\n" +
             "  wire signed [OUT_W-1:0] sin_e1 = is_n_4 ? $signed(SIN_N_4) : sin_rom[translated_addr];\n\n" +
             "  always @(posedge clk) o_cos <= cos_e1;\n"
             "  always @(posedge clk) o_sin <= sin_e1;\n"
             "  always @(posedge clk) o_sum <= cos_e1 + sin_e1;\n\n")

file_v.write("endmodule\n")
