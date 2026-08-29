`default_nettype none
`include "assert.svh"

module skid_buffer
#(
  parameter int WIDTH = 8
) (
  input wire logic clk_i,
  input wire logic rst_ni,

  input wire logic us_valid_i,
  input wire logic [WIDTH-1:0] us_data_i,
  input wire logic ds_ready_i,

  output logic ds_valid_o,
  output logic [WIDTH-1:0] ds_data_o,
  output logic us_ready_o
);

  typedef enum logic [1:0] {
    StEmpty,
    StBusy,
    StFull
  } state_e;

  state_e state_d, state_q;

  logic [WIDTH-1:0] skid_buf_d,skid_buf_q;
  logic [WIDTH-1:0] main_buf_d,main_buf_q;

  logic insert, remove;
  assign insert = us_valid_i & us_ready_o;
  assign remove = ds_valid_o & ds_ready_i;

  //the skid buffer can take value when empty of busy, not when full.
  assign us_ready_o = state_q != StFull; 
  //can read out value only when non-empty
  assign ds_valid_o = state_q != StEmpty;

  always_comb begin
    main_buf_d = main_buf_q;
    skid_buf_d = skid_buf_q;
    state_d = state_q;

    unique case (state_q)
      StEmpty : begin 
        if(insert) begin 
          main_buf_d = us_data_i;
          state_d = StBusy;
        end
      end
      StBusy : begin 
        if (insert && remove) begin
           main_buf_d = us_data_i;
        end
        else if (insert) begin
          skid_buf_d = us_data_i;
          state_d = StFull;
        end
        else if (remove) begin
          state_d = StEmpty;
        end
      end
      StFull: begin
        if (remove) begin 
          main_buf_d = skid_buf_q;
          state_d = StBusy;
        end
      end
      default : ;
    endcase
  end

  always_ff @(posedge clk_i) begin 
    if(!rst_ni) begin
      skid_buf_q <= '0;
      main_buf_q <= '0;
      state_q <= StEmpty;
    end else begin
      state_q <= state_d;
      skid_buf_q <= skid_buf_d;
      main_buf_q <= main_buf_d;
    end
  end

  assign ds_data_o = main_buf_q;

  `ifndef SYNTHESIS

  `ASSERT_ARM
  
  `ASSERT(a_us_hold, (us_valid_i & !us_ready_o) |=> (us_valid_i & $stable(us_data_i)), "us_valid/us_data changed without acceptance");

  `ASSERT(a_ds_hold, (ds_valid_o & !ds_ready_i) |=> (ds_valid_o & $stable(ds_data_o)), "a beat has been dropped before reading");

  `ASSERT(a_valid_state, state_q inside {StEmpty, StBusy, StFull}, "invalid state");

  `ASSERT(a_ready_recover, (ds_ready_i) |=> (us_ready_o), "us_ready_o stuck low after ds ready last cycle was high");

  `ASSERT(a_no_output_bubble, insert |=> ds_valid_o, "Accepted beat, but ds_valid_o != 1 next cycle.");
  
  `endif
  
endmodule