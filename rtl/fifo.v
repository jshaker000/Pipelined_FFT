// Author: Joseph Shaker
// fifo.v
// Fifo of width DATA_WIDTH and Depth FIFO_DEPTH
// Can operate in 2 modes
//
// 1) Pop / Valid: Make a pop request when the fifo isnt empty. It will then
//    raise valid and output the data
// 2) Valid / Taken: When the Fifo is non empty, it will output the first in
//    element and data valid. When pop is high, it indicates the output is taken,
//    and the fifo will show the next value (if there is another element).
//    This doesnt infer as bram, though
//  Currently PUSH + POP while full is okay, but while empty is not
//  Can empty the FIFO by asserting i_rst
`default_nettype none

module fifo #(
  parameter  DATA_WIDTH         = 32,
  parameter  FIFO_DEPTH         = 128,
  parameter  POP_VALID          = 1'b0, // !=0->Pop/Valid, 0->Valid/Taken
  localparam FIFO_POINTER_WIDTH = $clog2(FIFO_DEPTH),
  localparam WORD_COUNT_WIDTH   = $clog2(FIFO_DEPTH+1'b1),
  localparam FIFO_MAX_POINTER   = FIFO_DEPTH-1'b1
)(
  input wire                         i_clk,
  input wire                         i_rst,

  input wire                         i_push,
  input wire        [DATA_WIDTH-1:0] i_data,
  input wire                         i_pop,

  output wire                        o_valid,
  output wire       [DATA_WIDTH-1:0] o_data,

  output wire [WORD_COUNT_WIDTH-1:0] o_word_count,
  output wire                        o_halffull,
  output wire                        o_empty,
  output wire                        o_full,
  output wire                        o_push_error,
  output wire                        o_pop_error
);

  generate
  if (FIFO_DEPTH == 1) begin: flop_fifo
    reg [DATA_WIDTH-1:0] memory;
    reg                  full_r;
    initial              full_r = 1'b0;
    assign               o_full       = full_r;
    assign               o_halffull   = full_r;
    assign               o_empty      = ~full_r;
    assign               o_word_count = full_r;
    assign               o_push_error = i_push & ~i_pop & full_r;
    assign               o_pop_error  = i_pop  & ~full_r;
    always @(posedge i_clk) memory   <= i_push ? i_data : memory;
    always @(posedge i_clk) full_r   <= i_rst           ? 1'b0   :
                                        i_push != i_pop ? i_push :
                                        full_r;
    if (POP_VALID != 1'b0) begin: pop_valid
      wire                    valid_e1  = ~i_rst & i_pop;
      reg                     valid_r;
      reg    [DATA_WIDTH-1:0] data_r;
      initial                 valid_r = 1'b0;
      always @(posedge i_clk) valid_r <= valid_e1;
      always @(posedge i_clk) data_r  <= valid_e1 ? memory : data_r;
      assign                  o_valid  = valid_r;
      assign                  o_data   = data_r;
    end
    else begin: valid_taken
      assign o_valid = full_r;
      assign o_data  = memory;
    end
  end

  else begin: ram_fifo
    reg          [DATA_WIDTH-1:0] memory [0:FIFO_DEPTH-1];
    reg  [FIFO_POINTER_WIDTH-1:0] r_pointer;
    reg  [FIFO_POINTER_WIDTH-1:0] w_pointer;
    reg                           completely_full;

    wire almostfull;

    initial begin
      r_pointer = {FIFO_POINTER_WIDTH{1'b0}};
      w_pointer = {FIFO_POINTER_WIDTH{1'b0}};
      completely_full = 1'b0;
    end

    wire [FIFO_POINTER_WIDTH-1:0] r_pointer_incremented;
    wire [FIFO_POINTER_WIDTH-1:0] w_pointer_incremented;

    assign o_word_count  = w_pointer == r_pointer ?
                             completely_full ? FIFO_DEPTH[WORD_COUNT_WIDTH-1:0] :
                             {WORD_COUNT_WIDTH{1'b0}} :
                           w_pointer > r_pointer ? w_pointer - r_pointer :
                           FIFO_DEPTH[WORD_COUNT_WIDTH-1:0] - r_pointer + w_pointer;

    assign o_empty      = o_word_count == 0;
    assign o_halffull   = o_word_count >= FIFO_DEPTH[WORD_COUNT_WIDTH-1:0] >> 1;
    assign   almostfull = o_word_count == FIFO_DEPTH[WORD_COUNT_WIDTH-1:0] - 1'b1;
    assign o_full       = o_word_count == FIFO_DEPTH[WORD_COUNT_WIDTH-1:0];


    assign r_pointer_incremented = r_pointer == FIFO_MAX_POINTER[FIFO_POINTER_WIDTH-1:0] ? {FIFO_POINTER_WIDTH{1'b0}} :
                                   r_pointer + 1'b1;
    assign w_pointer_incremented = w_pointer == FIFO_MAX_POINTER[FIFO_POINTER_WIDTH-1:0] ? {FIFO_POINTER_WIDTH{1'b0}} :
                                   w_pointer + 1'b1;
    assign o_pop_error           = o_empty &  i_pop;
    assign o_push_error          = o_full  & ~i_pop  &  i_push;

    always @(posedge i_clk) completely_full   <= i_rst ? 1'b0 :
                                                almostfull      &  i_push & ~i_pop ? 1'b1 :
                                                completely_full & ~i_push &  i_pop ? 1'b0 :
                                                completely_full;

    always @(posedge i_clk) r_pointer         <= i_rst  ? {FIFO_POINTER_WIDTH{1'b0}} :
                                                i_pop & ~o_pop_error   ? r_pointer_incremented :
                                                r_pointer;
    always @(posedge i_clk) w_pointer         <= i_rst  ? {FIFO_POINTER_WIDTH{1'b0}} :
                                                i_push & ~o_push_error ? w_pointer_incremented :
                                                w_pointer;

    if (POP_VALID != 1'b0) begin: pop_valid // treat pop as a request, then fulfil it by updating data and raising valid
      wire                 valid_e1  = ~i_rst & ~o_pop_error & i_pop;
      reg                  valid_r;
      reg [DATA_WIDTH-1:0] data_r;
      initial valid_r = 1'b0;
      always @(posedge i_clk) valid_r <= valid_e1;
      always @(posedge i_clk) begin
        if (i_push)   memory[w_pointer] <= i_data;
        if (valid_e1) data_r            <= memory[r_pointer];
      end
      assign o_valid = valid_r;
      assign o_data  = data_r;
    end
    else begin: ready_taken // always output data and vaid if not empty; treat pop as a statement that the data has been taken
      always @(posedge i_clk) begin
        if (i_push) memory[w_pointer] <= i_data;
      end
      assign o_valid = ~i_rst & ~o_empty;
      assign o_data  = memory[r_pointer];
    end
  end // if fifo_depth > 1
  endgenerate

  `ifdef verilator
  always @(posedge i_clk) begin
      assert (i_rst ? 1'b1 : ~o_pop_error) else
      begin
        $display("FIFO pop error!");
        $fatal;
      end
      assert (i_rst ? 1'b1 : ~o_push_error) else
      begin
        $display("FIFO push error!");
        $fatal;
      end
  end
  `endif

endmodule
