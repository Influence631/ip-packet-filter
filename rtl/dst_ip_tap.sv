`default_nettype none
`include "assert.svh"

module dst_ip_tap #(
  parameter int LookupLat = 2  // dst_ip_o register + blacklist lookup register
) (
  input wire logic clk_i,
  input wire logic rst_ni,

  //        snooped s-axis beats (the tap never stalls the stream)
  input wire logic [31:0] s_axis_tdata,
  input wire logic [3:0] s_axis_tkeep,
  input wire logic s_axis_tlast,
  input wire logic s_axis_tvalid,
  input wire logic s_axis_tready,

  //        blacklist lookup
  output logic [31:0] dst_ip_o,
  input wire logic is_blacklisted_i,

  //        one decision per packet, in packet order
  output logic dec_valid_o,
  output logic dec_drop_o
);
  localparam int DstBeat = 4;  // IPv4 header row 4 = destination address (RFC 791 3.1)

  logic beat, at_dst, short_pkt;
  logic [2:0] beat_cnt_q;  // saturates at DstBeat+1 so long packets never re-capture
  logic [LookupLat-1:0] pend_q, force_drop_q;

  assign beat = s_axis_tvalid && s_axis_tready;
  assign at_dst = beat && beat_cnt_q == 3'(DstBeat);
  // tlast before the dst beat, or a partial dst beat: not a complete IPv4 header
  assign short_pkt = (beat && s_axis_tlast && beat_cnt_q < 3'(DstBeat))
                  || (at_dst && s_axis_tkeep != '1);

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      beat_cnt_q <= '0;
      pend_q <= '0;
      force_drop_q <= '0;
    end else begin
      if (beat) begin
        if (s_axis_tlast) beat_cnt_q <= '0;
        else if (beat_cnt_q <= 3'(DstBeat)) beat_cnt_q <= beat_cnt_q + 1'b1;
      end
      //short packets travel the same pipe as lookups so decisions stay in packet order
      pend_q <= {pend_q[LookupLat-2:0], at_dst || short_pkt};
      force_drop_q <= {force_drop_q[LookupLat-2:0], short_pkt};
    end
  end

  //byte 0 arrives in tdata[7:0], IP addresses are big-endian on the wire
  always_ff @(posedge clk_i) begin
    if (at_dst) dst_ip_o <= {s_axis_tdata[7:0], s_axis_tdata[15:8], s_axis_tdata[23:16], s_axis_tdata[31:24]};
  end

  assign dec_valid_o = pend_q[LookupLat-1];
  assign dec_drop_o = force_drop_q[LookupLat-1] || is_blacklisted_i;

  //    ASSERTIONS    //
  `ifndef SYNTHESIS
  `ASSERT_ARM
  `ASSERT(cnt_range, beat_cnt_q <= 3'(DstBeat + 1), "beat counter past saturation")
  `endif
endmodule
