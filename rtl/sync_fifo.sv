`default_nettype none
`include "assert.svh"

module sync_fifo #(
  parameter integer DEPTH = 32,
  parameter integer WIDTH = 8
) (
  input wire logic clk_i,
  input wire logic rst_ni,
  input wire logic we_i,
  input wire logic re_i,
  input wire logic [WIDTH - 1:0] data_i,
  output logic [WIDTH - 1:0] data_o,
  output logic full_o,
  output logic empty_o
);
  localparam addr_w = $clog2(DEPTH);
  
  logic [addr_w:0] fill;
  (*ram_style = "block", rw_addr_collision = "no"*)
  logic [WIDTH-1:0] fifo [DEPTH];

  logic [WIDTH-1:0] rd_data_q;
  logic do_read_q;

  logic [addr_w-1:0] r_ptr;
  logic [addr_w-1:0] w_ptr;
  
  logic do_write, do_read;
  assign do_write = we_i && !full_o;
  assign do_read = re_i && !empty_o;

  //bram
  always_ff @(posedge clk_i) begin
    if (do_write) fifo[w_ptr] <= data_i;
    if (do_read) rd_data_q <= fifo[r_ptr]; //read into bram latch
    if (do_read_q) data_o <= rd_data_q; //read latch into bram reg
  end

  always_ff @(posedge clk_i) begin 
    if (!rst_ni) begin 
      r_ptr <= '0;
      w_ptr <= '0;
      fill <= '0;
      full_o <= '0;
      empty_o <= 1'b1;
    end else begin
      if (do_write) w_ptr <= w_ptr + 1'b1;
      if (do_read) r_ptr <= r_ptr + 1'b1;
      
      do_read_q <= do_read;
      
      fill <= fill + do_write - do_read;
      full_o <= (fill == (addr_w+1)'(DEPTH - 1) && do_write && !do_read) || (full_o && !do_read);
      empty_o <= (fill == (addr_w+1)'(1) && (do_read && !do_write)) || (empty_o && !do_write);  
    end
  end

  //ASSERTIONS//
  `ifndef SYNTHESIS

  `ASSERT_ARM
  `ASSERT_INIT(DEPTH >= 2 && DEPTH == 2**addr_w, "Depth has to be power of 2, >= 2.")
  `ASSERT(sanity_check, !(full_o && empty_o), "full && empty")
  `ASSERT(no_overflow, (we_i & full_o) |=> $stable(w_ptr), "wrote while full")
  `ASSERT(no_underflow, (re_i & empty_o) |=> $stable(r_ptr), "read while empty")
  `ASSERT(full_check, full_o == (fill == (addr_w+1)'(DEPTH)), "full_o != (fill == depth)")
  `ASSERT(empty_check, empty_o == (fill == 0), "empty where fill != 0")
  `ASSERT(depth_check, fill <= (addr_w+1)'(DEPTH), "fill >= DEPTH")
  `endif
  
endmodule