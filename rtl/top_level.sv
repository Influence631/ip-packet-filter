`default_nettype none

//flat-port top: verilator/cocotb and fpga pins can't use interface ports, so the axi-lite interface lives here
module top_level #(
  parameter int BlacklistDepth = 32,
  parameter int PktFifoDepth = 16,
  parameter int AxilAddrW = $clog2(BlacklistDepth) + 3  // entry index + byte offset + table/VALID select
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
  input wire logic [AxilAddrW-1:0] s_axil_awaddr,
  input wire logic [2:0] s_axil_awprot,
  input wire logic s_axil_awvalid,
  output logic s_axil_awready,
  input wire logic [31:0] s_axil_wdata,
  input wire logic [3:0] s_axil_wstrb,
  input wire logic s_axil_wvalid,
  output logic s_axil_wready,
  output logic [1:0] s_axil_bresp,
  output logic s_axil_bvalid,
  input wire logic s_axil_bready,
  input wire logic [AxilAddrW-1:0] s_axil_araddr,
  input wire logic [2:0] s_axil_arprot,
  input wire logic s_axil_arvalid,
  output logic s_axil_arready,
  output logic [31:0] s_axil_rdata,
  output logic [1:0] s_axil_rresp,
  output logic s_axil_rvalid,
  input wire logic s_axil_rready,

  //        status: one pulse per packet as it leaves
  output logic pkt_valid_o,
  output logic pkt_drop_o
);
  taxi_axil_if #(
    .DATA_W(32),
    .ADDR_W(AxilAddrW)
  ) axil ();

  //master -> slave
  assign axil.awaddr = s_axil_awaddr;
  assign axil.awprot = s_axil_awprot;
  assign axil.awuser = '0;
  assign axil.awvalid = s_axil_awvalid;
  assign axil.wdata = s_axil_wdata;
  assign axil.wstrb = s_axil_wstrb;
  assign axil.wuser = '0;
  assign axil.wvalid = s_axil_wvalid;
  assign axil.bready = s_axil_bready;
  assign axil.araddr = s_axil_araddr;
  assign axil.arprot = s_axil_arprot;
  assign axil.aruser = '0;
  assign axil.arvalid = s_axil_arvalid;
  assign axil.rready = s_axil_rready;

  //slave -> master
  assign s_axil_awready = axil.awready;
  assign s_axil_wready = axil.wready;
  assign s_axil_bresp = axil.bresp;
  assign s_axil_bvalid = axil.bvalid;
  assign s_axil_arready = axil.arready;
  assign s_axil_rdata = axil.rdata;
  assign s_axil_rresp = axil.rresp;
  assign s_axil_rvalid = axil.rvalid;

  ip_filter #(
    .BlacklistDepth(BlacklistDepth),
    .PktFifoDepth(PktFifoDepth)
  ) ip_filter_u (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tlast(m_axis_tlast),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .s_axil_wr(axil),
    .s_axil_rd(axil),
    .pkt_valid_o(pkt_valid_o),
    .pkt_drop_o(pkt_drop_o)
  );
endmodule
