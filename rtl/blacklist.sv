`default_nettype none

module blacklist #(
  parameter unsigned DEPTH = 32
) (
  input wire logic clk_i,
  input wire logic rst_ni,
  input wire logic[31:0] ip_addr_i,

  taxi_axil_if.wr_slv s_axi_wr,
  taxi_axil_if.rd_slv s_axi_rd,
  output logic is_blacklisted_o
);
  localparam IDX_W = $clog2(DEPTH);
  localparam BYTE_OFF = $clog2(s_axi_wr.STRB_W);
  localparam SEL_BIT = IDX_W + BYTE_OFF;
  localparam IP_ADDR_W = 32;


  //word index for writing
  logic [IDX_W-1:0] wr_idx; 
  assign wr_idx = s_axi_wr.awaddr[2 +: IDX_W];

  //word index for reading
  logic [IDX_W-1:0] rd_idx; 
  assign rd_idx = s_axi_rd.araddr[2 +: IDX_W];

  logic [IP_ADDR_W -1:0] mem [DEPTH];
  logic [DEPTH-1:0] valid;
  logic [DEPTH-1:0] lookup;

  always_ff @(posedge clk_i) begin 
    if (!rst_ni) begin 
      // for (int i = 0; i < DEPTH; i++) begin
      //   mem[DEPTH][DATA_WIDTH] <= '0;
      // end
    end else begin 

        for (int i = 0; i < DEPTH; i++) begin
          lookup[i] <= mem[i][s_axi_wr.DATA_W-1:0] == ip_addr_i && valid[i];
        end

    end
  end
  
  assign is_blacklisted_o = |lookup;

  logic wr_accept, rd_accept;
  logic tbl_wr_en, tbl_rd_en;
  logic unmapped_wr, unmapped_rd;
  logic valid_wr_en, valid_rd_en;

  //write slv
  logic s_axil_awready_q, s_axil_wready_q;
  logic s_axil_awready_d, s_axil_wready_d;
  
  logic [1:0] s_axil_bresp_q, s_axil_bresp_d;
  logic s_axil_bvalid_q, s_axil_bvalid_d;

  assign s_axi_wr.awready = s_axil_awready_q;
  assign s_axi_wr.wready = s_axil_wready_q;
  assign s_axi_wr.bresp = s_axil_bresp_q;
  assign s_axi_wr.bvalid = s_axil_bvalid_q;
  assign s_axi_wr.buser = '0;

  //read slv
  logic s_axil_arready_q, s_axil_rvalid_q;
  logic s_axil_arready_d, s_axil_rvalid_d;
  logic [1:0] s_axil_rresp_d,s_axil_rresp_q;
  logic [s_axi_rd.DATA_W-1:0] s_axil_rdata_d, s_axil_rdata_q;

  assign s_axi_rd.arready = s_axil_arready_q;
  assign s_axi_rd.rdata = s_axil_rdata_q;
  assign s_axi_rd.rvalid = s_axil_rvalid_q;
  assign s_axi_rd.rresp = s_axil_rresp_q;
  assign s_axi_rd.ruser = '0;


  assign wr_accept = s_axi_wr.awvalid && s_axi_wr.wvalid
                     && !s_axil_wready_q && !s_axil_awready_q
                     && (!s_axil_bvalid_q || s_axi_wr.bready);

  //handshake + dont accept duplicated + old resp has been read
  assign rd_accept = s_axi_rd.arvalid && !s_axil_arready_q
                      && (!s_axil_rvalid_q || s_axi_rd.rready);

  //write side signals
  always_comb begin
    //defaults
    s_axil_bresp_d = s_axil_bresp_q;
    //handshake
    s_axil_awready_d = wr_accept;
    s_axil_wready_d = wr_accept;
    
    //register map write gating
    valid_wr_en = wr_accept && wr_idx == '0 && s_axi_wr.awaddr[SEL_BIT];
    tbl_wr_en = wr_accept && !s_axi_wr.awaddr[SEL_BIT];
    unmapped_wr = (wr_accept && !valid_wr_en && !tbl_wr_en);

                          //hold or clear               + set
    s_axil_bvalid_d = (s_axil_bvalid_q && !s_axi_wr.bready) || wr_accept;
    //an unmapped read returns slverror 
    if (wr_accept) s_axil_bresp_d =  unmapped_wr ? 2'b10 : 2'b00;
  end

  //read side channels
  always_comb begin 
    //AR :
    s_axil_arready_d = rd_accept;

    //R :
    s_axil_rresp_d = s_axil_rresp_q;
    s_axil_rdata_d = s_axil_rdata_q;
    //i need to drive the rdata + rvalid + rresp 
    //hold the valid untill its read, set it if rd accepted 
    s_axil_rvalid_d = (s_axil_rvalid_q && !s_axi_rd.rready) || rd_accept;

    //register map read gating
    valid_rd_en = rd_accept && rd_idx == '0 && s_axi_rd.araddr[SEL_BIT];
    tbl_rd_en = rd_accept && !s_axi_rd.araddr[SEL_BIT];
    unmapped_rd = (rd_accept && !valid_rd_en && !tbl_rd_en);

    if (rd_accept) s_axil_rresp_d = unmapped_rd ? 2'b10 : 2'b00;

    if (valid_rd_en || tbl_rd_en) begin 
      s_axil_rdata_d = valid_rd_en ? valid : mem[rd_idx];
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin 
      //write
      s_axil_awready_q <= 1'b0;
      s_axil_wready_q <= 1'b0;
      s_axil_bvalid_q <= 1'b0;
      s_axil_bresp_q <= 2'b00;
      valid <= '0;

      //read
      s_axil_arready_q <= 1'b0;
      s_axil_rvalid_q <= 1'b0;
      s_axil_rresp_q <= 2'b00;
      s_axil_rdata_q <= '0;

    end else begin
      //write
      s_axil_awready_q <= s_axil_awready_d;
      s_axil_wready_q <= s_axil_wready_d;
      s_axil_bresp_q <= s_axil_bresp_d;
      s_axil_bvalid_q <= s_axil_bvalid_d;

      for (int i = 0; i < s_axi_wr.STRB_W; i++) begin 
        if (s_axi_wr.wstrb[i]) begin 
          //1. table write
          if (tbl_wr_en) begin 
            mem[wr_idx][i*8 +: 8] <= s_axi_wr.wdata[i*8 +: 8];
          end else if (valid_wr_en) begin 
            valid[i*8 +: 8] <= s_axi_wr.wdata[i*8 +: 8];
          end
        end
      end

      //read

      s_axil_rresp_q <= s_axil_rresp_d;
      s_axil_rvalid_q <= s_axil_rvalid_d;
      s_axil_rdata_q <= s_axil_rdata_d;
      s_axil_arready_q <= s_axil_arready_d;

    end
  end
endmodule