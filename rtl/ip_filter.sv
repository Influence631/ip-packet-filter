`default_nettype none
`include "assert.svh"

module ip_filter #(
  parameter int BlacklistDepth = 32,
  parameter int PktFifoDepth = 16
) (
  input wire logic clk_i,
  input wire logic rst_ni,

  //        s-axis: raw ipv4 packets
  input wire logic [31:0] s_axis_tdata,
  input wire logic [3:0] s_axis_tkeep,
  input wire logic s_axis_tlast,
  input wire logic s_axis_tvalid,
  output logic s_axis_tready,

  //        m-axis: packets that passed the blacklist
  output logic [31:0] m_axis_tdata,
  output logic [3:0] m_axis_tkeep,
  output logic m_axis_tlast,
  output logic m_axis_tvalid,
  input wire logic m_axis_tready,

  //        axi-lite blacklist config
  taxi_axil_if.wr_slv s_axil_wr,
  taxi_axil_if.rd_slv s_axil_rd,

  //        status: one pulse per packet as it leaves
  output logic pkt_valid_o,
  output logic pkt_drop_o
);
  //every pending decision has >= 1 beat in the packet fifo, so its capacity bounds the decision fifo
  localparam int DecDepth = PktFifoDepth + 4;  // bram depth + axis_delayed_fifo output buffer

  logic [31:0] dst_ip;
  logic is_blacklisted;

  logic dec_valid, dec_drop;
  logic dec_head, dec_pop, dec_empty, dec_full;

  //packet fifo -> gate
  logic [31:0] pf_tdata;
  logic [3:0] pf_tkeep;
  logic pf_tlast, pf_tvalid, pf_tready;

  axis_delayed_fifo #(
    .FifoDepth(PktFifoDepth),
    .DataWidth(32)
  ) pkt_fifo_u (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .m_axis_tdata(pf_tdata),
    .m_axis_tkeep(pf_tkeep),
    .m_axis_tlast(pf_tlast),
    .m_axis_tvalid(pf_tvalid),
    .m_axis_tready(pf_tready)
  );

  //watches the same handshake the packet fifo accepts on
  dst_ip_tap #(
    .LookupLat(2)
  ) tap_u (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .dst_ip_o(dst_ip),
    .is_blacklisted_i(is_blacklisted),
    .dec_valid_o(dec_valid),
    .dec_drop_o(dec_drop)
  );

  blacklist #(
    .DEPTH(BlacklistDepth)
  ) blacklist_u (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .ip_addr_i(dst_ip),
    .s_axi_wr(s_axil_wr),
    .s_axi_rd(s_axil_rd),
    .is_blacklisted_o(is_blacklisted)
  );

  reg_fifo #(
    .Depth(DecDepth),
    .Width(1)
  ) dec_fifo_u (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .push_i(dec_valid),
    .data_i(dec_drop),
    .pop_i(dec_pop),
    .data_o(dec_head),
    .empty_o(dec_empty),
    .full_o(dec_full)
  );

  drop_gate #(
    .DataWidth(32)
  ) gate_u (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .s_axis_tdata(pf_tdata),
    .s_axis_tkeep(pf_tkeep),
    .s_axis_tlast(pf_tlast),
    .s_axis_tvalid(pf_tvalid),
    .s_axis_tready(pf_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tlast(m_axis_tlast),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .dec_empty_i(dec_empty),
    .dec_drop_i(dec_head),
    .dec_pop_o(dec_pop),
    .pkt_valid_o(pkt_valid_o),
    .pkt_drop_o(pkt_drop_o)
  );

  //    ASSERTIONS    //
  `ifndef SYNTHESIS
  `ASSERT_ARM
  `ASSERT(dec_fifo_bound, !(dec_valid && dec_full),
      "decision fifo full: packet fifo capacity no longer bounds pending decisions")
  `endif
endmodule
