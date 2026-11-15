`default_nettype none

module test_blacklist #(
  parameter unsigned DEPTH = 32,
  parameter unsigned ADDR_W = 8,
  parameter unsigned DATA_W = 32
  
) (
  input wire logic clk_i,
  input wire logic rst_ni,
  input wire logic[31:0] ip_addr_i,
  output logic is_blacklisted_o,
    // AW
  input logic [ADDR_W-1:0]    s_axil_awaddr,
  input logic [2:0]           s_axil_awprot,
  input logic                 s_axil_awvalid,
  output logic                 s_axil_awready,
  // W
  input logic [DATA_W-1:0]    s_axil_wdata,
  input logic [DATA_W/8-1:0]    s_axil_wstrb,
  input logic                 s_axil_wvalid,
  output logic                 s_axil_wready,
  // B
  output logic [1:0]           s_axil_bresp,

  output logic                 s_axil_bvalid,
  input logic                 s_axil_bready,
  // AR
  input logic [ADDR_W-1:0]    s_axil_araddr,
  input logic [2:0]           s_axil_arprot,
  input logic                 s_axil_arvalid,
  output logic                 s_axil_arready,
  // R
  output logic [DATA_W-1:0]    s_axil_rdata,
  output logic [1:0]           s_axil_rresp,
  output logic                 s_axil_rvalid,
  input logic                 s_axil_rready
);

  taxi_axil_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) axil ();

  blacklist #(.DEPTH(DEPTH)) blacklist_dut (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    .ip_addr_i (ip_addr_i),
    .s_axi_wr (axil),
    .s_axi_rd (axil),
    .is_blacklisted_o (is_blacklisted_o)
  );

  //inputs
  assign axil.awaddr = s_axil_awaddr;
  assign axil.awprot = s_axil_awprot;
  assign axil.awvalid = s_axil_awvalid;
  assign axil.wdata = s_axil_wdata;
  assign axil.wstrb = s_axil_wstrb;
  assign axil.wvalid = s_axil_wvalid;
  assign axil.bready = s_axil_bready;


  assign axil.araddr = s_axil_araddr;
  assign axil.arvalid = s_axil_arvalid;
  assign axil.arprot = s_axil_arprot;

  assign axil.rready = s_axil_rready;
  //outputs
  assign s_axil_awready = axil.awready;
  assign s_axil_wready = axil.wready;

  assign s_axil_bvalid = axil.bvalid;
  assign s_axil_arready = axil.arready;
  assign s_axil_rdata = axil.rdata;
  assign s_axil_rresp = axil.rresp;
  assign s_axil_rvalid = axil.rvalid;

  assign s_axil_bresp = axil.bresp;
endmodule