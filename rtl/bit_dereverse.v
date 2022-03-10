// dereverse the bits. ping pong between which ram to read / write from

`default_nettype none
module bit_dereverse #(
  parameter  DATA_W =   20,
  parameter  DEPTH  =  128,
  localparam C_W    = $clog2(DEPTH)
) (
  input  wire                clk,
  input  wire                i_init,
  input  wire                i_vld,
  input  wire   [DATA_W-1:0] i_data,
  output reg                 o_vld,
  output reg                 o_new_fft,
  output reg    [DATA_W-1:0] o_data
);

  reg [DATA_W-1:0] ramA [0:DEPTH-1];
  reg [DATA_W-1:0] ramB [0:DEPTH-1];


  reg filled_any_ram_this_run;
  reg store_in_b;

  reg    [C_W-1:0] pointer;
  reg    [C_W-1:0] pointerA;
  reg    [C_W-1:0] pointerB;

  initial begin
    pointer  = {C_W{1'b0}};
    pointerA = {C_W{1'b0}};
    pointerB = {C_W{1'b0}};
    filled_any_ram_this_run = 1'b0;
    store_in_b              = 1'b0;
  end

  wire   [C_W-1:0] pointer_next = i_init ? {C_W{1'b0}} : i_vld ? pointer + {{C_W-1{1'b0}}, 1'b1} : pointer;
  wire                switch_rw = ~i_init & i_vld & (pointer == {C_W{1'b1}});

  always @(posedge clk) filled_any_ram_this_run <= i_init ? 1'b0 : switch_rw | filled_any_ram_this_run;
  always @(posedge clk) store_in_b              <= i_init ? 1'b0 : switch_rw ^ store_in_b;
  always @(posedge clk) pointer                 <= pointer_next;

  always @(posedge clk) begin: assign_ptrs_a_b
    integer i;
    for(i=0; i < C_W; i=i+1) begin
      pointerA[i] <= i_init ? 1'b0 : ~store_in_b ? pointer_next[C_W-i-1] : pointer_next[i];
      pointerB[i] <= i_init ? 1'b0 :  store_in_b ? pointer_next[C_W-i-1] : pointer_next[i];
    end
  end

  wire write_a = i_vld & ~store_in_b & ~i_init;
  wire write_b = i_vld &  store_in_b & ~i_init;

  wire read_a  = store_in_b  & i_vld & filled_any_ram_this_run;
  wire read_b  = ~store_in_b & i_vld & filled_any_ram_this_run;

  reg [DATA_W-1:0] rA;
  reg [DATA_W-1:0] rB;

  always @(posedge clk) begin
    if      (write_a) ramA[pointerA] <= i_data;
    else if (read_a)  rA             <= ramA[pointerA];
  end

  always @(posedge clk) begin
    if      (write_b) ramB[pointerB] <= i_data;
    else if (read_b)  rB             <= ramB[pointerB];
  end

  reg read_a_d1;
  reg read_b_d1;
  reg vld_e1;
  reg new_fft_e1;

  always @(posedge clk) read_a_d1  <= ~i_init & read_a;
  always @(posedge clk) read_b_d1  <= ~i_init & read_b;
  always @(posedge clk) vld_e1     <= i_vld & ~i_init & filled_any_ram_this_run;
  always @(posedge clk) new_fft_e1 <= i_vld & ~i_init & filled_any_ram_this_run & pointer == {C_W{1'b0}};

  always @(posedge clk) o_data     <= read_a_d1 & ~i_init ? rA : read_b_d1 & ~i_init ? rB : o_data;
  always @(posedge clk) o_vld      <= ~i_init & vld_e1;
  always @(posedge clk) o_new_fft  <= ~i_init & new_fft_e1;

endmodule
