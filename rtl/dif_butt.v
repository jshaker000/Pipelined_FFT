`default_nettype none

// explore pipelined multiplies, different rounding options

module dif_butt
#(
   parameter IN_W   = 10,
   parameter OUT_W  = 10,
   parameter TWID_W = IN_W + 4,
   parameter STAGE  =  0,
   parameter TOTAL_STAGES   = 8,
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

  reg signed [IN_W+1-1:0] sumI;
  reg signed [IN_W+1-1:0] sumQ;
  reg signed [IN_W+1-1:0] diffI;
  reg signed [IN_W+1-1:0] diffQ;

  always @(posedge mclk) sumI  <= pipe_in_valid[0] & ~init_r ? lI_r + rI_r : sumI;
  always @(posedge mclk) sumQ  <= pipe_in_valid[0] & ~init_r ? lQ_r + rQ_r : sumQ;
  always @(posedge mclk) diffI <= pipe_in_valid[0] & ~init_r ? lI_r - rI_r : diffI;
  always @(posedge mclk) diffQ <= pipe_in_valid[0] & ~init_r ? lQ_r - rQ_r : diffQ;

  wire signed [IN_W+1+4+TWID_W-1:0] twiddOutLI;
  wire signed [IN_W+1+4+TWID_W-1:0] twiddOutLQ;
  wire signed [IN_W+1+4+TWID_W-1:0] twiddOutRI;
  wire signed [IN_W+1+4+TWID_W-1:0] twiddOutRQ;

  wire                              twiddOutValid;
  wire                              twiddOutClip;

/* verilator lint_off WIDTH */
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
      always @(posedge mclk) twidd_count <= init_r        ? 1'b0 :
                                            twidd_count ^ pipe_in_valid[IN_PIPE_STG-1];
      reg signed [IN_W+1-1:0] twiddOutLIR;
      reg signed [IN_W+1-1:0] twiddOutLQR;
      reg signed [IN_W+1-1:0] twiddOutRIR;
      reg signed [IN_W+1-1:0] twiddOutRQR;
      reg                     twiddOutValidR = 1'b0;

      always @(posedge mclk) twiddOutValidR <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r;
      always @(posedge mclk) twiddOutLIR    <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? sumI : twiddOutLIR;
      always @(posedge mclk) twiddOutLQR    <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? sumQ : twiddOutLQR;
      always @(posedge mclk) twiddOutRIR    <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ?
                                                 twidd_count == 1'b0 ?  diffI : //  1
                                                 twidd_count == 1'b1 ?          // -j
                                                   IS_IFFT == 1'b0 ? diffQ :
                                                   -diffQ :
                                                 'bx :
                                               twiddOutRIR;
      always @(posedge mclk) twiddOutRQR    <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ?
                                                 twidd_count == 1'b0 ?  diffQ : //  1
                                                 twidd_count == 1'b1 ?
                                                   IS_IFFT == 1'b0 ? -diffI :
                                                   diffI :
                                                 'bx :
                                               twiddOutRQR;
      assign twiddOutLI    = $signed({twiddOutLIR, {TWID_W+4{1'b0}}});
      assign twiddOutLQ    = $signed({twiddOutLQR, {TWID_W+4{1'b0}}});
      assign twiddOutRI    = $signed({twiddOutRIR, {TWID_W+4{1'b0}}});
      assign twiddOutRQ    = $signed({twiddOutRQR, {TWID_W+4{1'b0}}});
      assign twiddOutValid = twiddOutValidR;
      assign twiddOutClip  = 1'b0;
    end
    default: begin: full_twiddle
      localparam C_W = $clog2(STAGE_FFT_LEN) - 1;
      reg  [C_W-1:0] twidd_count = {C_W{1'b0}};
      wire [C_W-1:0] twidd_addr  = twidd_count + {{C_W{1'b0}}, pipe_in_valid[IN_PIPE_STG-2]};
      always @(posedge mclk) twidd_count <= init_r                       ? {C_W{1'b0}} :
                                            twidd_addr;

      wire signed [TWID_W-1:0] twiddI;
      wire signed [TWID_W-1:0] twiddQ;

      twiddle_rom    #(.IS_IFFT(IS_IFFT),
                       .OUT_W(TWID_W),
                       .FFT_LEN(STAGE_FFT_LEN)
      ) inst_twiddle_rom (
        .mclk   (mclk),
        .i_addr (twidd_addr),
        .o_cos  (twiddI),
        .o_sin  (twiddQ)
      );

      // ------------ STAGE 1 ----------------------
      // Gauss algorithm to multiply with 3 multipliers
      reg vld1 = 1'b0;
      reg signed [IN_W+1-1:0] sumI_d1;
      reg signed [IN_W+1-1:0] sumQ_d1;
      always @(posedge mclk)  sumI_d1 <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? sumI : sumI_d1;
      always @(posedge mclk)  sumQ_d1 <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? sumQ : sumQ_d1;
      always @(posedge mclk)  vld1    <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r;
      reg signed   [IN_W+1+TWID_W-1:0] s1;
      reg signed   [IN_W+1+TWID_W-1:0] s2;
      reg signed [IN_W+1+2+TWID_W-1:0] s3;
      always @(posedge mclk) s1 <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? diffI * twiddI : s1;
      always @(posedge mclk) s2 <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? diffQ * twiddQ : s2;
      always @(posedge mclk) s3 <= pipe_in_valid[IN_PIPE_STG-1] & ~init_r ? (diffI + diffQ) * (twiddI + twiddQ) : s3;
      // ------------ STAGE 2 ----------------------
      // combine
      reg twiddOutValidR = 1'b0;
      reg twiddOutClipR  = 1'b0;
      reg signed [IN_W+1-1:0] twiddOutLIR;
      reg signed [IN_W+1-1:0] twiddOutLQR;
      always @(posedge mclk)  twiddOutLIR    <= vld1 & ~init_r ? sumI_d1 : twiddOutLIR;
      always @(posedge mclk)  twiddOutLQR    <= vld1 & ~init_r ? sumQ_d1 : twiddOutLQR;
      always @(posedge mclk)  twiddOutValidR <= vld1 & ~init_r;
      localparam BITS_TO_CHOP = 6;
      reg signed  [IN_W+1+4+TWID_W-1:0] twiddOutRIR;
      reg signed  [IN_W+1+4+TWID_W-1:0] twiddOutRQR;
      wire signed [IN_W+1+4+TWID_W-1:0] r_real = s1 - s2;
      wire signed [IN_W+1+4+TWID_W-1:0] r_imag = s3 - s1 - s2;
      wire re_clip = ~init_r & vld1 & (&r_real[IN_W+1+4+TWID_W-1 -: BITS_TO_CHOP+1] ^ |r_real[IN_W+1+4+TWID_W-1 -: BITS_TO_CHOP+1]);
      wire im_clip = ~init_r & vld1 & (&r_imag[IN_W+1+4+TWID_W-1 -: BITS_TO_CHOP+1] ^ |r_imag[IN_W+1+4+TWID_W-1 -: BITS_TO_CHOP+1]);
      always @(posedge mclk)  twiddOutRIR <= vld1 & ~init_r ?
                                               re_clip ? $signed({{BITS_TO_CHOP+1{r_real[IN_W+1+4+TWID_W-1]}}, {IN_W+1+4+TWID_W-1-BITS_TO_CHOP{~r_real[IN_W+1+4+TWID_W-1]}}}) :
                                               r_real * (2**BITS_TO_CHOP) :
                                             twiddOutRIR;
      always @(posedge mclk)  twiddOutRQR <= vld1 & ~init_r ?
                                               im_clip ? $signed({{BITS_TO_CHOP+1{r_imag[IN_W+1+4+TWID_W-1]}}, {IN_W+1+4+TWID_W-1-BITS_TO_CHOP{~r_imag[IN_W+1+4+TWID_W-1]}}}) :
                                               r_imag * (2**BITS_TO_CHOP) :
                                             twiddOutRIR;
      always @(posedge mclk)  twiddOutClipR <= vld1 & ~init_r & (re_clip | im_clip);
      // ------------ OUT -----------------------------
      assign twiddOutLI    = {twiddOutLIR, {TWID_W+4{1'b0}}};
      assign twiddOutLQ    = {twiddOutLQR, {TWID_W+4{1'b0}}};
      assign twiddOutRI    = {twiddOutRIR};
      assign twiddOutRQ    = {twiddOutRQR};
      assign twiddOutClip  = twiddOutClipR;
      assign twiddOutValid = twiddOutValidR;
    end
    endcase
  endgenerate
/* verilator lint_on WIDTH */
/* verilator lint_off PINCONNECTEMPTY */
  round #(.IN_W(IN_W+1+4+TWID_W), .OUT_W(OUT_W))
  inst_rndLI(
    .mclk(mclk),
    .i_init(i_init),
    .i_data(twiddOutLI),
    .i_vld (twiddOutValid),
    .o_data(o_LI),
    .o_vld (o_vld)
  );
  round #(.IN_W(IN_W+1+4+TWID_W), .OUT_W(OUT_W))
  inst_rndLQ(
    .mclk(mclk),
    .i_init(i_init),
    .i_data(twiddOutLQ),
    .i_vld (twiddOutValid),
    .o_data(o_LQ),
    .o_vld ()
  );
  round #(.IN_W(IN_W+1+4+TWID_W), .OUT_W(OUT_W))
  inst_rndRI(
    .mclk(mclk),
    .i_init(i_init),
    .i_data(twiddOutRI),
    .i_vld (twiddOutValid),
    .o_data(o_RI),
    .o_vld ()
  );
  round #(.IN_W(IN_W+1+4+TWID_W), .OUT_W(OUT_W))
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
