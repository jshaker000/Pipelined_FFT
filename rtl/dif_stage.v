`default_nettype none

// used to allign data
// First stage combines data from n and N/2, the next n and N/4, etc

module dif_stage
#(
  parameter IN_W         = 10,
  parameter OUT_W        = IN_W + 1,
  parameter STAGE        =  0,
  parameter TOTAL_STAGES =  8,
  parameter TWID_W       = TOTAL_STAGES - STAGE >= 2 ? IN_W + 4 : 0,
  parameter IS_IFFT      = 1'b0,
  localparam BUFF_DEPTH  = 2**(TOTAL_STAGES-STAGE-1)
) (
  input wire                     mclk,
  input wire                     i_init,
  input wire                     i_vld,
  input wire  signed  [IN_W-1:0] i_I,
  input wire  signed  [IN_W-1:0] i_Q,
  output wire                    o_vld,
  output wire signed [OUT_W-1:0] o_I,
  output wire signed [OUT_W-1:0] o_Q,
  output wire                    o_clip_strb
);

  wire           ibuff_full;
  wire           ibuff_empty;
  wire            ibuff_vld;
  wire [IN_W-1:0] inbuff_oI;
  wire [IN_W-1:0] inbuff_oQ;

  reg filling_ibuff;
  initial filling_ibuff = 1'b1;
  always @(posedge mclk) filling_ibuff <= i_init ? 1'b1 : ibuff_full ? 1'b0 : ibuff_empty ? 1'b1 : filling_ibuff;
  wire push_ibuff  = ~i_init & i_vld & ( filling_ibuff | ibuff_empty) & ~ibuff_full;
  wire pop_ibuff   = ~i_init & i_vld & (~filling_ibuff | ibuff_full)  & ~ibuff_empty;

  reg  [IN_W-1:0] iI_d1;
  reg  [IN_W-1:0] iQ_d1;

  always @(posedge mclk) iI_d1 <= pop_ibuff ? i_I : iI_d1;
  always @(posedge mclk) iQ_d1 <= pop_ibuff ? i_Q : iQ_d1;

/* verilator lint_off PINCONNECTEMPTY */
  fifo #(
    .DATA_WIDTH(IN_W*2),
    .FIFO_DEPTH(BUFF_DEPTH),
    .POP_VALID (1'b1)
  ) inst_in_buff(
    .i_clk  (mclk),
    .i_rst  (i_init),
    .i_data ({$unsigned(i_I), $unsigned(i_Q)}),
    .i_push (push_ibuff),
    .i_pop  (pop_ibuff),
    .o_data ({inbuff_oI, inbuff_oQ}),
    .o_valid(ibuff_vld),
    .o_word_count(),
    .o_empty     (ibuff_empty),
    .o_halffull  (),
    .o_full      (ibuff_full),
    .o_push_error(),
    .o_pop_error ()
  );
/* verilator lint_on PINCONNECTEMPTY */

  wire butt_vld;
  wire signed [OUT_W-1:0] butt_oLI;
  wire signed [OUT_W-1:0] butt_oLQ;
  wire signed [OUT_W-1:0] butt_oRI;
  wire signed [OUT_W-1:0] butt_oRQ;

  dif_butt #(
    .IN_W        (IN_W),
    .OUT_W       (OUT_W),
    .TWID_W      (TWID_W),
    .STAGE       (STAGE),
    .TOTAL_STAGES(TOTAL_STAGES)
  ) inst_dif_butt(
    .mclk  (mclk),
    .i_init(i_init),
    .i_vld (ibuff_vld),
    .i_LI  ($signed(inbuff_oI)),
    .i_LQ  ($signed(inbuff_oQ)),
    .i_RI  (iI_d1),
    .i_RQ  (iQ_d1),
    .o_vld (butt_vld),
    .o_LI  (butt_oLI),
    .o_LQ  (butt_oLQ),
    .o_RI  (butt_oRI),
    .o_RQ  (butt_oRQ),
    .o_clip_strb(o_clip_strb)
  );

  wire             obuff_empty;
  wire             obuff_full;
  wire [OUT_W-1:0] obuffI;
  wire [OUT_W-1:0] obuffQ;
  wire             obuff_vld;

  reg filling_obuff;
  initial filling_obuff = 1'b1;
  always @(posedge mclk) filling_obuff <= i_init ? 1'b1 : obuff_full ? 1'b0 : obuff_empty ? 1'b1 : filling_obuff;

  wire push_obuff  = ~i_init &  butt_vld & ( filling_obuff | obuff_empty) & ~obuff_full;
  wire pop_obuff   = ~i_init & ~butt_vld & (~filling_obuff | obuff_full)  & ~obuff_empty;

  reg             butt_vld_d1;
  reg [OUT_W-1:0] butt_oLI_d1;
  reg [OUT_W-1:0] butt_oLQ_d1;

  always @(posedge mclk) butt_vld_d1 <= push_obuff & butt_vld;
  always @(posedge mclk) butt_oLI_d1 <= push_obuff & butt_vld ? butt_oLI : butt_oLI_d1;
  always @(posedge mclk) butt_oLQ_d1 <= push_obuff & butt_vld ? butt_oLQ : butt_oLQ_d1;

/* verilator lint_off PINCONNECTEMPTY */
  fifo #(
    .DATA_WIDTH(OUT_W*2),
    .FIFO_DEPTH(BUFF_DEPTH),
    .POP_VALID (1'b1)
  ) inst_out_buff(
    .i_clk  (mclk),
    .i_rst  (i_init),
    .i_data ({$unsigned(butt_oRI), $unsigned(butt_oRQ)}),
    .i_push (push_obuff),
    .i_pop  (pop_obuff),
    .o_data ({obuffI, obuffQ}),
    .o_valid(obuff_vld),
    .o_word_count(),
    .o_empty     (obuff_empty),
    .o_halffull  (),
    .o_full      (obuff_full),
    .o_push_error(),
    .o_pop_error ()
  );
/* verilator lint_on PINCONNECTEMPTY */

  assign o_I   = butt_vld_d1 ? butt_oLI_d1 : $signed(obuffI);
  assign o_Q   = butt_vld_d1 ? butt_oLQ_d1 : $signed(obuffQ);
  assign o_vld = butt_vld_d1 | obuff_vld;

endmodule
