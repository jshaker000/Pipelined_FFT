// Right now setting OUT_W to less that INT_W + STAGES leads to incorrect
// rounding issues. But with full width, it does work :)
// Should implement clipping detection

`default_nettype none
module fft #(
  parameter  IN_W    =  12,
  parameter  FFT_LEN =  256,
  localparam STAGES  =  $clog2(FFT_LEN),
  localparam INT_W   =  IN_W + STAGES,
  parameter  OUT_W   =  INT_W
) (
  input wire                     mclk,
  input wire                     i_init,
  input wire                     i_vld,
  input wire signed   [IN_W-1:0] i_I,
  input wire signed   [IN_W-1:0] i_Q,
  output wire                    o_vld,
  output wire                    o_new_fft,
  output wire signed [OUT_W-1:0] o_I,
  output wire signed [OUT_W-1:0] o_Q,
  output wire                    o_clip_strb
);

  reg [3:0] por = 4'b0000;
  always @(posedge mclk) por <= por > 0 ? por - 1 : 0;

  wire init = i_init | por > 0;

  wire         [STAGES:0] fft_ivld;
  wire signed [INT_W-1:0] fft_iI [STAGES:0];
  wire signed [INT_W-1:0] fft_iQ [STAGES:0];

  assign fft_ivld[0] = i_vld;
  assign fft_iI[0]   = {{INT_W-IN_W{i_I[IN_W-1]}}, i_I};
  assign fft_iQ[0]   = {{INT_W-IN_W{i_Q[IN_W-1]}}, i_Q};

  wire [STAGES-1:0] clip_strb;

  genvar i;
  generate
    for(i=0; i < STAGES; i=i+1) begin: fft_stage
      localparam iw = IN_W + i       <= OUT_W ? IN_W +  i      : OUT_W;
      localparam ow = IN_W + (i + 1) <= OUT_W ? IN_W + (i + 1) : OUT_W;
      localparam tw = i >= STAGES-2 ? 0 : iw + 4;
      dif_stage #(
        .IN_W        (iw),
        .OUT_W       (ow),
        .TWID_W      (tw),
        .STAGE       (i),
        .TOTAL_STAGES(STAGES),
        .IS_IFFT     (1'b0)
      ) inst_dif_stage (
        .mclk  (mclk),
        .i_init(init),
        .i_vld (fft_ivld[i]),
        .i_I   (fft_iI[i][iw-1:0]),
        .i_Q   (fft_iQ[i][iw-1:0]),
        .o_vld (fft_ivld[i+1]),
        .o_I   (fft_iI[i+1][ow-1:0]),
        .o_Q   (fft_iQ[i+1][ow-1:0]),
        .o_clip_strb(clip_strb[i])
      );
      `ifdef verilator
        always @(posedge mclk) begin
          assert(init ? 1'b1 : ~clip_strb[i]) else begin
            $display("FFT: DIF BUTT STG %d clipped!\n", i);
            $fatal;
          end
        end
      `endif
    end
  endgenerate

  wire signed [OUT_W-1:0] bit_dereverse_iI;
  wire signed [OUT_W-1:0] bit_dereverse_iQ;
  wire                    bit_dereverse_iVld;

/* verilator lint_off PINCONNECTEMPTY */
  round #(.IN_W(INT_W), .OUT_W(OUT_W))
  inst_rndoI(
    .mclk(mclk),
    .i_init(init),
    .i_data(fft_iI[STAGES]),
    .i_vld (fft_ivld[STAGES]),
    .o_data(bit_dereverse_iI),
    .o_vld (bit_dereverse_iVld)
  );
  round #(.IN_W(INT_W), .OUT_W(OUT_W))
  inst_rndoQ(
    .mclk(mclk),
    .i_init(init),
    .i_data(fft_iQ[STAGES]),
    .i_vld (fft_ivld[STAGES]),
    .o_data(bit_dereverse_iQ),
    .o_vld ()
  );
/* verilator lint_on PINCONNECTEMPTY */

  wire [OUT_W-1:0] bit_dereverse_oI;
  wire [OUT_W-1:0] bit_dereverse_oQ;
  wire             bit_dereverse_oVld;

  bit_dereverse #(
    .DATA_W(2*OUT_W),
    .DEPTH (FFT_LEN)
  ) inst_bit_dereverse (
    .mclk  (mclk),
    .i_init(init),
    .i_vld (bit_dereverse_iVld),
    .i_data({$unsigned(bit_dereverse_iI), $unsigned(bit_dereverse_iQ)}),
    .o_vld (bit_dereverse_oVld),
    .o_new_fft(o_new_fft),
    .o_data({bit_dereverse_oI, bit_dereverse_oQ})
  );

  assign o_vld = bit_dereverse_oVld;
  assign   o_I = $signed(bit_dereverse_oI);
  assign   o_Q = $signed(bit_dereverse_oQ);
  assign o_clip_strb = ~init & |clip_strb;

  `ifdef verilator
    function integer get_inw;
      // verilator public
      get_inw = IN_W;
    endfunction
    function integer get_outw;
      // verilator public
      get_outw = OUT_W;
    endfunction
    function integer get_fft_len;
      // verilator public
      get_fft_len = FFT_LEN;
    endfunction
  `endif

endmodule
