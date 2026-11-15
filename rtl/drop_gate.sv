`default_nettype none
`include "assert.svh"

module drop_gate #(
  parameter int DataWidth = 32,
  parameter int KeepWidth = DataWidth/8
) (
  input wire logic clk_i,
  input wire logic rst_ni,

  //        s-axis side (packet fifo)
  input wire logic [DataWidth-1:0] s_axis_tdata,
  input wire logic [KeepWidth-1:0] s_axis_tkeep,
  input wire logic s_axis_tlast,
  input wire logic s_axis_tvalid,
  output logic s_axis_tready,

  //        m-axis side
  output logic [DataWidth-1:0] m_axis_tdata,
  output logic [KeepWidth-1:0] m_axis_tkeep,
  output logic m_axis_tlast,
  output logic m_axis_tvalid,
  input wire logic m_axis_tready,

  //        decision fifo head (first-word fall-through)
  input wire logic dec_empty_i,
  input wire logic dec_drop_i,
  output logic dec_pop_o,

  //        status: one pulse per packet when its first beat leaves the fifo
  output logic pkt_valid_o,
  output logic pkt_drop_o
);
  logic in_pkt_q, drop_q;
  logic can_go, cur_drop, s_beat;

  //first beat uses the decision fifo head directly, later beats the latched copy
  assign cur_drop = in_pkt_q ? drop_q : dec_drop_i;
  assign can_go = in_pkt_q || !dec_empty_i;

  assign m_axis_tdata = s_axis_tdata;
  assign m_axis_tkeep = s_axis_tkeep;
  assign m_axis_tlast = s_axis_tlast;
  assign m_axis_tvalid = s_axis_tvalid && can_go && !cur_drop;
  //dropped beats are consumed without waiting for downstream
  assign s_axis_tready = can_go && (cur_drop || m_axis_tready);

  assign s_beat = s_axis_tvalid && s_axis_tready;
  assign dec_pop_o = s_beat && !in_pkt_q;
  assign pkt_valid_o = dec_pop_o;
  assign pkt_drop_o = cur_drop;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      in_pkt_q <= 1'b0;
      drop_q <= 1'b0;
    end else if (s_beat) begin
      if (s_axis_tlast) in_pkt_q <= 1'b0;
      else if (!in_pkt_q) begin
        in_pkt_q <= 1'b1;
        drop_q <= dec_drop_i;
      end
    end
  end

  //    ASSERTIONS    //
  `ifndef SYNTHESIS
  `ASSERT_ARM
  `ASSERT(pop_has_dec, !(dec_pop_o && dec_empty_i), "popped an empty decision fifo")
  `ASSERT(ds_hold_values, (m_axis_tvalid && !m_axis_tready) |=>
      $stable(m_axis_tvalid) && $stable(m_axis_tdata) && $stable(m_axis_tkeep) && $stable(m_axis_tlast),
      "m_axis changed without m_tready")
  `endif
endmodule
