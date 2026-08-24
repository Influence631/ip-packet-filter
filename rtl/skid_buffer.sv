`default_nettype none

module skid_buffer
#(
  parameter int WIDTH = 8
) (
  input logic clk_i,
  input logic rst_ni,

  input logic us_valid_i,
  input logic [WIDTH-1:0] us_data_i,
  input logic ds_ready_i,

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


  bit assert_en;
  initial assert_en = 1'b0;
  always_ff @(posedge clk_i) if (!rst_ni) assert_en <= 1'b1;
  //once us_valid_i is set, it must not go low untill a transmission happens
  a_us_hold : assert property (@(posedge clk_i) disable iff (!rst_ni  || !assert_en)
      (us_valid_i & !us_ready_o) |=> (us_valid_i & $stable(us_data_i))
  ) else $error("us_valid/us_data changed without acceptance");

  a_ds_hold : assert property (@(posedge clk_i) disable iff (!rst_ni  || !assert_en)
    (ds_valid_o & !ds_ready_i) |=> (ds_valid_o & $stable(ds_data_o))
  ) else $error("a beat has been dropped before reading");

  a_valid_state : assert property (@(posedge clk_i) disable iff (!rst_ni  || !assert_en)
    state_q inside {StEmpty, StBusy, StFull}
  ) else $error("invalid state");

  a_ready_recover : assert property (@(posedge clk_i) disable iff (!rst_ni  || !assert_en)
    (ds_ready_i) |=> (us_ready_o)
  ) else $error("us_ready_o stuck low after ds ready last cycle was high");

  a_no_output_bubble : assert property (@(posedge clk_i) disable iff (!rst_ni || !assert_en)
    insert |=> ds_valid_o
  ) else $error("Accepted beat, but ds_valid_o != 1 next cycle.");
  
endmodule