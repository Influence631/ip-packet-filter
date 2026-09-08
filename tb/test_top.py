import logging
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge

from common import run

log = logging.getLogger("tb.test_top")
log.setLevel(logging.INFO)

		
@cocotb.test()
async def passthrough(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start(start_high=False))

    dut.rst_ni.value = 0
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)

    
    # stimulus + checking goes here


def test_top():
    run(top="ip_filter_top", test_module="test_top", parameters={}) #e.g{WIDTH : 8}
