`ifndef ASSERT_SVH
`define ASSERT_SVH


`define ASSERT_ARM \
  bit assert_en; \
  initial assert_en = 1'b0; \
  always_ff @(posedge clk_i) if (!rst_ni) assert_en <= 1'b1;

`define ASSERT(__name, __prop, __msg) \
  __name : assert property (@(posedge clk_i) disable iff (!rst_ni || !assert_en) \
    __prop \
  ) else $error(__msg);

`define ASSERT_IM(__name, __prop, __msg) \
 __name : assert (__prop) \
 else $error(__msg);

`define ASSERT_INIT(__prop, __msg) \
 initial assert (__prop) \
 else $error(__msg);
`endif