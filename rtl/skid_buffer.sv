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
          main_buf_d = skid_buf_q; // skid_buffer -> main_buffer on unload
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

  //once us_valid_i is set, it must not go low untill a transmission happens
  assert property (@(posedge clk_i) disable iff (!rst_ni)
      (us_valid_i & !us_ready_o) |-> $stable(us_data_i)
  ) else $error("data has changed while valid was set, without ready");
endmodule