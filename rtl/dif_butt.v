`default_nettype none

// explore pipelined multiplies, different rounding options

module dif_butt
#(
   parameter IN_W           = 10,
   parameter OUT_W          = IN_W + 1,
   parameter STAGE          = 0,
   parameter TOTAL_STAGES   = 8,
   parameter TWID_W         = TOTAL_STAGES - STAGE >= 2 ? IN_W + 4 : 0,
   parameter IS_IFFT        = 1'b0,
   localparam STAGE_FFT_LEN = 2**(TOTAL_STAGES-STAGE)
) (
  input wire                     mclk,
  input wire                     i_init,
  input wire                     i_vld,
  input wire signed   [IN_W-1:0] i_LI,
  input wire signed   [IN_W-1:0] i_LQ,
  input wire signed   [IN_W-1:0] i_RI,
  input wire signed   [IN_W-1:0] i_RQ,
  output wire                    o_vld,
  output wire signed [OUT_W-1:0] o_LI,
  output wire signed [OUT_W-1:0] o_LQ,
  output wire signed [OUT_W-1:0] o_RI,
  output wire signed [OUT_W-1:0] o_RQ,
  output wire                    o_clip_strb // does not need to allign with valid
);

  localparam IN_PIPE_STG = 2;

  reg init_r;
  always @(posedge mclk) init_r <= i_init;

  reg signed [IN_W-1:0] lI_r;
  reg signed [IN_W-1:0] lQ_r;
  reg signed [IN_W-1:0] rI_r;
  reg signed [IN_W-1:0] rQ_r;

  always @(posedge mclk) lI_r <= ~init_r & i_vld ? i_LI : lI_r;
  always @(posedge mclk) lQ_r <= ~init_r & i_vld ? i_LQ : lQ_r;
  always @(posedge mclk) rI_r <= ~init_r & i_vld ? i_RI : rI_r;
  always @(posedge mclk) rQ_r <= ~init_r & i_vld ? i_RQ : rQ_r;

  reg [IN_PIPE_STG-1:0]  pipe_in_valid = {IN_PIPE_STG{1'b0}};

  always @(posedge mclk) pipe_in_valid <= {IN_PIPE_STG{~init_r}} & {pipe_in_valid[IN_PIPE_STG-2:0], i_vld};

  localparam SUMS_LEN = IN_W+1;
  localparam S1_LEN   = SUMS_LEN+TWID_W;

  reg signed [SUMS_LEN-1:0] sumI;
  reg signed [SUMS_LEN-1:0] sumQ;
  reg signed [SUMS_LEN-1:0] diffI;
  reg signed [SUMS_LEN-1:0] diffQ;

  wire signed [SUMS_LEN-1:0] sumI_e1  = lI_r + rI_r;
  wire signed [SUMS_LEN-1:0] sumQ_e1  = lQ_r + rQ_r;
  wire signed [SUMS_LEN-1:0] diffI_e1 = lI_r - rI_r;
  wire signed [SUMS_LEN-1:0] diffQ_e1 = lQ_r - rQ_r;

  always @(posedge mclk) sumI  <= pipe_in_valid[0] & ~init_r ? sumI_e1  : sumI;
  always @(posedge mclk) sumQ  <= pipe_in_valid[0] & ~init_r ? sumQ_e1  : sumQ;
  always @(posedge mclk) diffI <= pipe_in_valid[0] & ~init_r ? diffI_e1 : diffI;
  always @(posedge mclk) diffQ <= pipe_in_valid[0] & ~init_r ? diffQ_e1 : diffQ;

  wire signed [S1_LEN+4-1:0] twiddOutLI;
  wire signed [S1_LEN+4-1:0] twiddOutLQ;
  wire signed [S1_LEN+4-1:0] twiddOutRI;
  wire signed [S1_LEN+4-1:0] twiddOutRQ;

  wire                              twiddOutValid;
  wire                              twiddOutClip;

  generate
    case (STAGE_FFT_LEN)
    'd2: begin: no_twiddle
      assign twiddOutLI    = $signed({sumI,  {TWID_W+4{1'b0}}});
      assign twiddOutLQ    = $signed({sumQ,  {TWID_W+4{1'b0}}});
      assign twiddOutRI    = $signed({diffI, {TWID_W+4{1'b0}}});
      assign twiddOutRQ    = $signed({diffQ, {TWID_W+4{1'b0}}});
      assign twiddOutValid = pipe_in_valid[IN_PIPE_STG-1];
      assign twiddOutClip  = 1'b0;
    end
    'd4: begin: quarter_twiddle
      reg   twidd_count = 1'b0;
      always @(posedge mclk) twidd_count <= init_r ? 1'b0 : twidd_count ^ pipe_in_valid[IN_PIPE_STG-1];

      reg signed [SUMS_LEN-1:0] twiddOutLIR;
      reg signed [SUMS_LEN-1:0] twiddOutLQR;
      reg signed [SUMS_LEN-1:0] twiddOutRIR;
      reg signed [SUMS_LEN-1:0] twiddOutRQR;
      reg                       twiddOutValidR = 1'b0;

      always @(posedge mclk) twiddOutValidR <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r;
      always @(posedge mclk) twiddOutLIR    <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? sumI : twiddOutLIR;
      always @(posedge mclk) twiddOutLQR    <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? sumQ : twiddOutLQR;
      always @(posedge mclk) twiddOutRIR    <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ?
                                                 twidd_count == 1'b0 ?  diffI : //  1
                                                 twidd_count == 1'b1 ?          // -j
                                                   IS_IFFT == 1'b0 ? diffQ :
                                                   -diffQ :
                                                 {SUMS_LEN{1'bx}} :
                                               twiddOutRIR;
      always @(posedge mclk) twiddOutRQR    <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ?
                                                 twidd_count == 1'b0 ?  diffQ : //  1
                                                 twidd_count == 1'b1 ?
                                                   IS_IFFT == 1'b0 ?  -diffI :
                                                   diffI :
                                                 {SUMS_LEN{1'bx}} :
                                               twiddOutRQR;

      assign twiddOutLI    = $signed({twiddOutLIR, {TWID_W+4{1'b0}}});
      assign twiddOutLQ    = $signed({twiddOutLQR, {TWID_W+4{1'b0}}});
      assign twiddOutRI    = $signed({twiddOutRIR, {TWID_W+4{1'b0}}});
      assign twiddOutRQ    = $signed({twiddOutRQR, {TWID_W+4{1'b0}}});
      assign twiddOutValid = twiddOutValidR;
      assign twiddOutClip  = 1'b0;
    end
    default: begin: full_twiddle
      // STAGE 0, prefetch twiddles and setup for gauss algo
      localparam C_W = $clog2(STAGE_FFT_LEN) - 1;

      reg  [C_W-1:0] twidd_count = {C_W{1'b0}};
      wire [C_W-1:0] twidd_addr  = twidd_count + {{C_W-1{1'b0}}, pipe_in_valid[IN_PIPE_STG-2]};

      always @(posedge mclk) twidd_count <= init_r ? {C_W{1'b0}} : twidd_addr;

      reg signed [SUMS_LEN:0] diffSum;

      always @(posedge mclk)  diffSum <= ~init_r & pipe_in_valid[IN_PIPE_STG-2] ? diffI_e1 + diffQ_e1 : diffSum;

      wire signed [TWID_W-1:0] twiddI;
      wire signed [TWID_W-1:0] twiddQ;
      wire signed   [TWID_W:0] twiddSum;

      twiddle_rom    #(.IS_IFFT(IS_IFFT),
                       .OUT_W(TWID_W),
                       .FFT_LEN(STAGE_FFT_LEN)
      ) inst_twiddle_rom (
        .mclk   (mclk),
        .i_addr (twidd_addr),
        .o_cos  (twiddI),
        .o_sin  (twiddQ),
        .o_sum  (twiddSum)
      );

      // ------------ STAGE 1 ----------------------
      // Gauss algorithm to multiply with 3 multipliers
      reg vld1 = 1'b0;
      reg signed [SUMS_LEN-1:0] sumI_d1;
      reg signed [SUMS_LEN-1:0] sumQ_d1;
      always @(posedge mclk)  sumI_d1 <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? sumI : sumI_d1;
      always @(posedge mclk)  sumQ_d1 <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? sumQ : sumQ_d1;
      always @(posedge mclk)  vld1    <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r;
      reg signed   [S1_LEN-1:0] s1;
      reg signed   [S1_LEN-1:0] s2;
      reg signed [S1_LEN+2-1:0] s3;
      always @(posedge mclk) s1 <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? diffI   * twiddI   : s1;
      always @(posedge mclk) s2 <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? diffQ   * twiddQ   : s2;
      always @(posedge mclk) s3 <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? diffSum * twiddSum : s3;
      // ------------ STAGE 2 ----------------------
      // combine
      reg twiddOutValidR = 1'b0;
      reg twiddOutClipR  = 1'b0;
      reg signed [SUMS_LEN-1:0] twiddOutLIR;
      reg signed [SUMS_LEN-1:0] twiddOutLQR;
      always @(posedge mclk) twiddOutLIR    <= vld1 & ~init_r ? sumI_d1 : twiddOutLIR;
      always @(posedge mclk) twiddOutLQR    <= vld1 & ~init_r ? sumQ_d1 : twiddOutLQR;
      always @(posedge mclk) twiddOutValidR <= vld1 & ~init_r;

      localparam BITS_TO_CHOP = 6;

      reg signed  [S1_LEN+4-BITS_TO_CHOP-1:0] twiddOutRIR;
      reg signed  [S1_LEN+4-BITS_TO_CHOP-1:0] twiddOutRQR;

      wire signed [S1_LEN+4-1:0] twiddOutRIR_e1 = $signed({{4{s1[S1_LEN-1]}}, s1}) - $signed({{4{s2[S1_LEN-1]}}, s2});
      wire signed [S1_LEN+4-1:0] twiddOutRQR_e1 = $signed({{2{s3[S1_LEN+1]}}, s3}) - $signed({{4{s2[S1_LEN-1]}}, s2}) - $signed({{4{s1[S1_LEN-1]}}, s1});

      wire twiddI_clip = ~init_r & vld1 & (&twiddOutRIR_e1[S1_LEN+4-1 -: BITS_TO_CHOP+1] ^ |twiddOutRIR_e1[S1_LEN+4-1 -: BITS_TO_CHOP+1]);
      wire twiddQ_clip = ~init_r & vld1 & (&twiddOutRQR_e1[S1_LEN+4-1 -: BITS_TO_CHOP+1] ^ |twiddOutRQR_e1[S1_LEN+4-1 -: BITS_TO_CHOP+1]);

      wire signed [S1_LEN+4-BITS_TO_CHOP-1:0] twiddI_clip_val = $signed({twiddOutRIR_e1[S1_LEN+4-1], {S1_LEN+4-1-BITS_TO_CHOP{~twiddOutRIR_e1[S1_LEN+4-1]}}});
      wire signed [S1_LEN+4-BITS_TO_CHOP-1:0] twiddQ_clip_val = $signed({twiddOutRQR_e1[S1_LEN+4-1], {S1_LEN+4-1-BITS_TO_CHOP{~twiddOutRQR_e1[S1_LEN+4-1]}}});

      always @(posedge mclk)  twiddOutRIR <= vld1 & ~init_r ?
                                               twiddI_clip ? twiddI_clip_val :
                                               $signed(twiddOutRIR_e1[S1_LEN+4-BITS_TO_CHOP-1:0]) :
                                             twiddOutRIR;
      always @(posedge mclk)  twiddOutRQR <= vld1 & ~init_r ?
                                               twiddQ_clip ? twiddQ_clip_val :
                                               $signed(twiddOutRQR_e1[S1_LEN+4-BITS_TO_CHOP-1:0]) :
                                             twiddOutRIR;
      always @(posedge mclk)  twiddOutClipR <= vld1 & ~init_r & (twiddI_clip | twiddQ_clip);
      // ------------ OUT -----------------------------
      assign twiddOutLI    = $signed({twiddOutLIR, {TWID_W+4{1'b0}}});
      assign twiddOutLQ    = $signed({twiddOutLQR, {TWID_W+4{1'b0}}});
      assign twiddOutRI    = $signed({twiddOutRIR, {BITS_TO_CHOP{1'b0}}});
      assign twiddOutRQ    = $signed({twiddOutRQR, {BITS_TO_CHOP{1'b0}}});
      assign twiddOutClip  = twiddOutClipR;
      assign twiddOutValid = twiddOutValidR;
    end
    endcase
  endgenerate

/* verilator lint_off PINCONNECTEMPTY */
  round #(.IN_W(S1_LEN+4), .OUT_W(OUT_W))
  inst_rndLI(
    .mclk(mclk),
    .i_init(i_init),
    .i_data(twiddOutLI),
    .i_vld (twiddOutValid),
    .o_data(o_LI),
    .o_vld (o_vld)
  );
  round #(.IN_W(S1_LEN+4), .OUT_W(OUT_W))
  inst_rndLQ(
    .mclk(mclk),
    .i_init(i_init),
    .i_data(twiddOutLQ),
    .i_vld (twiddOutValid),
    .o_data(o_LQ),
    .o_vld ()
  );
  round #(.IN_W(S1_LEN+4), .OUT_W(OUT_W))
  inst_rndRI(
    .mclk(mclk),
    .i_init(i_init),
    .i_data(twiddOutRI),
    .i_vld (twiddOutValid),
    .o_data(o_RI),
    .o_vld ()
  );
  round #(.IN_W(S1_LEN+4), .OUT_W(OUT_W))
  inst_rndRQ(
    .mclk(mclk),
    .i_init(i_init),
    .i_data(twiddOutRQ),
    .i_vld (twiddOutValid),
    .o_data(o_RQ),
    .o_vld ()
  );
/* verilator lint_on PINCONNECTEMPTY */

  assign o_clip_strb = ~init_r & twiddOutClip;

endmodule
