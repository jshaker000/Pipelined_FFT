`default_nettype none
module round #(
  parameter IN_W  = 10,
  parameter OUT_W = 10
) (
  input wire                    mclk,
  input wire                    i_init,
  input wire                    i_vld,
  input wire signed  [IN_W-1:0] i_data,
  output reg                    o_vld,
  output reg signed [OUT_W-1:0] o_data
);

  initial o_vld = 1'b0;

  generate
    if  (IN_W > OUT_W) begin: round
      /* verilator lint_off UNUSED */
      wire signed [IN_W-1:0]  w_convergent = i_data[IN_W-1:0] +
                                                { {(OUT_W){1'b0}},
                                                  i_data[IN_W-OUT_W],
                                                  {(IN_W-OUT_W-1){~i_data[(IN_W-OUT_W)]}} };
      /* verilator lint_off UNUSED */
      always @(posedge mclk) o_vld  <= i_vld & ~i_init;
      always @(posedge mclk) o_data <= i_vld & ~i_init ? $signed(w_convergent[IN_W-1 -: OUT_W]) : o_data;
    end
    else begin: copy
      always @(posedge mclk) o_vld  <= i_vld & ~i_init;
      always @(posedge mclk) o_data <= $signed({i_data, {OUT_W-IN_W{1'b0}}});
    end
  endgenerate

endmodule
