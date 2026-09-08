`default_nettype none

module axis_delayed_fifo #(
  parameter int FifoDepth = 16,
  parameter int DataWidth = 32,
  parameter int KeepWidth = DataWidth/8
) (
  input wire logic clk_i,
  input wire logic rst_ni,

  //        s-axis side
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
  input logic m_axis_tready
  );
  localparam int RdLatency = 2;
  localparam int FifoWidth = DataWidth + KeepWidth + 1; //storing the data + tkeep + tlast
  localparam int OBufDepth = RdLatency + 2;
  localparam int CntW = $clog2(OBufDepth) + 1; //counter width which has to fit the depth

  //bram sync fifo
  logic fifo_we, fifo_re;
  logic fifo_full, fifo_empty;
  
  //resource management
  logic [CntW-1:0] credits;
  logic [FifoWidth-1:0] rd_fifo_data;
  logic [RdLatency-1:0] rd_valid_q; //this will be m_tvalid
  logic insert, remove;
  
  //output bufer
  logic [CntW-1:0] obuf_fill;
  logic [$clog2(OBufDepth)-1:0] obuf_rd_ptr, obuf_wr_ptr;
  logic [FifoWidth-1:0] obuf_q [OBufDepth-1:0];
  logic obuf_empty;
  //      --writing into sync fifo--    //
  assign fifo_we = s_axis_tvalid && !fifo_full;
  assign s_axis_tready = !fifo_full && rst_ni;
  //    --reading data from sync fifo to bufer--     //
  assign fifo_re = (credits != '0) && (!fifo_empty);

  assign insert = (fifo_re);
  assign remove = (m_axis_tvalid && m_axis_tready); 
  assign obuf_empty = obuf_fill == '0;

  //reading from the output bufer
  assign m_axis_tvalid = !obuf_empty;
  
  always_ff @(posedge clk_i) begin 
    if(!rst_ni) begin 
      obuf_fill <= '0;
      credits <= CntW'(OBufDepth);
      rd_valid_q <= '0;
      obuf_rd_ptr <= '0;
      obuf_wr_ptr <= '0;
    end else begin 
      //conveyer for do_read (after do_read is set, data arrives from fifo 2 cycles later)
      rd_valid_q <= {rd_valid_q[RdLatency-2:0], fifo_re}; 
      
      credits <= credits - insert + remove;
      obuf_fill <= obuf_fill + rd_valid_q[RdLatency-1] - remove;
      //writing into the buffer
      if (rd_valid_q[RdLatency-1]) begin //the latency has passed, read the fifo output data into buffer
        obuf_q[obuf_wr_ptr] <= {rd_fifo_data};
        obuf_wr_ptr <= obuf_wr_ptr + 1'b1; 
      end 
      //reading from the buffer
      if (remove) begin 
        obuf_rd_ptr <= obuf_rd_ptr + 1'b1;
      end
    end
  end
  
  assign {m_axis_tdata, m_axis_tkeep, m_axis_tlast} = obuf_q[obuf_rd_ptr];
        
  sync_fifo #(
    .Depth(FifoDepth),
    .Width(FifoWidth)
  ) sfifo_u (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .we_i(fifo_we),
    .re_i(fifo_re),
    .data_i({s_axis_tdata, s_axis_tkeep, s_axis_tlast}),
    .data_o(rd_fifo_data),
    .full_o(fifo_full),
    .empty_o(fifo_empty)
  );


  //    ASSERTIONS    //

  
endmodule