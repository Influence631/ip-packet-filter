`default_nettype none
`include "assert.svh"

module sync_fifo #(
  parameter integer DEPTH = 32,
  parameter integer WIDTH = 8
) (
  input logic clk_i,
  input logic rst_ni,
  input logic we_i,
  input logic re_i,
  input logic [WIDTH - 1:0] data_i,
  output logic [WIDTH - 1:0] data_o,
  output logic full_o,
  output logic empty_o
);
  localparam addr_w = $clog2(DEPTH);
  
  logic [WIDTH-1:0] fifo [DEPTH];
  //the pointers have an extra bit to diffentiate between full and empty
  logic [addr_w:0] r_ptr;
  logic [addr_w:0] w_ptr;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin 
      r_ptr <= '0;
      w_ptr <= '0;
    end else begin 
      if (we_i && !full_o) begin 
        fifo[w_ptr[addr_w-1:0]] <= data_i;
        w_ptr <= w_ptr + 1'b1;
      end
      
      if (re_i && !empty_o) begin 
        r_ptr <= r_ptr + 1'b1;
      end
    end
  end
  assign data_o = fifo[r_ptr[addr_w-1:0]];

  assign full_o = r_ptr == {~w_ptr[addr_w], w_ptr[addr_w-1:0]};
  assign empty_o = r_ptr == w_ptr;

  //ASSERTIONS//
  `ASSERT_ARM
  `ASSERT_INIT(DEPTH >= 2 && DEPTH == 2**addr_w, "Depth has to be power of 2, >= 2.")
  `ASSERT(sanity_check, !(full_o && empty_o), "full && empty")
  `ASSERT(no_overflow, (we_i & full_o) |=> $stable(w_ptr), "wrote while full")
  `ASSERT(no_underflow, (re_i & empty_o) |=> $stable(r_ptr), "read while full")
  
endmodule