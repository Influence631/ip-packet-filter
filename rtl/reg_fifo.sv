`default_nettype none
`include "assert.svh"

module reg_fifo #(
  parameter int Depth = 4,
  parameter int Width = 1
) (
  input wire logic clk_i,
  input wire logic rst_ni,

  input wire logic push_i,
  input wire logic [Width-1:0] data_i,

  input wire logic pop_i,
  output logic [Width-1:0] data_o,  // oldest entry, valid while !empty_o
  output logic empty_o,
  output logic full_o
);
  localparam int PtrW = $clog2(Depth);

  logic [Width-1:0] mem_q [Depth];
  logic [PtrW-1:0] rd_ptr_q, wr_ptr_q;
  logic [PtrW:0] cnt_q;
  logic do_push, do_pop;

  assign empty_o = cnt_q == '0;
  assign full_o = cnt_q == (PtrW+1)'(Depth);
  assign do_push = push_i && !full_o;
  assign do_pop = pop_i && !empty_o;
  assign data_o = mem_q[rd_ptr_q];

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      rd_ptr_q <= '0;
      wr_ptr_q <= '0;
      cnt_q <= '0;
    end else begin
      //pointers wrap at Depth, so Depth doesn't have to be a power of 2
      if (do_push) wr_ptr_q <= (wr_ptr_q == PtrW'(Depth-1)) ? '0 : wr_ptr_q + 1'b1;
      if (do_pop) rd_ptr_q <= (rd_ptr_q == PtrW'(Depth-1)) ? '0 : rd_ptr_q + 1'b1;
      cnt_q <= cnt_q + do_push - do_pop;
    end
  end

  always_ff @(posedge clk_i) begin
    if (do_push) mem_q[wr_ptr_q] <= data_i;
  end

  //    ASSERTIONS    //
  `ifndef SYNTHESIS
  `ASSERT_ARM
  `ASSERT_INIT(Depth >= 2, "Depth has to be >= 2.")
  `ASSERT(no_overflow, !(push_i && full_o), "push while full")
  `ASSERT(no_underflow, !(pop_i && empty_o), "pop while empty")
  `endif
endmodule
