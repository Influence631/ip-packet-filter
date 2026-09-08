`default_nettype none

module ip_filter_top #(

) (
  input wire logic clk_i,
  input wire logic rst_ni,
  output logic a
);

  always_ff @(posedge clk_i) begin 
    if (!rst_ni) a <= '0;
    else a <= 1'b1;
  end
endmodule