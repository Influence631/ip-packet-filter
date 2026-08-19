import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, FallingEdge
from common import run
import logging
import random
from collections import deque

NUM_ITER = 1000
BUFFER_WIDTH = 8

log = logging.getLogger("tb.test_skid_buffer")
log.setLevel(logging.INFO)

class StreamSource:
    def __init__(self, clk, *, valid, data, ready):
        self.clk = clk
        self.valid = valid
        self.ready = ready
        self.data = data

class StreamSink:
    def __init__(self, clk, *, valid, data, ready):
        self.clk = clk
        self.valid = valid
        self.ready = ready
        self.data = data

class SkidTB:
    def __init__(self, dut, src, sink):
        self.dut = dut
        self.src = src
        self.sink = sink

    """
    I want class method create_tb function which would do the shared setup
    between methods, e.g create the sink + src + reset + start running the clock + the monitors
    """

    """
    I need to add 2 monitors:
    1. for US (view the len of the deque is less than 2 -> skid + main regs)
    2. for DS (check that no read of empty deque happened)
    """
    

@cocotb.test()
async def full_thoughput(dut):
    """
    I need to send beats every cycle and count that the amount accepted == amount offered.
    The us_ready_o and us_valid_i must be high throughout.
    """

@cocotb.test()
async def backpressure(dut):
    src = StreamSource(dut, dut.valid_i, dut.data_i, dut.ready_o)
    sink = StreamSink(dut, dut.valid_o, dut.data_o, dut.ready_i)

    skid = SkidTB(dut, src, sink)

def test_skid_buffer():
    run(top="skid_buffer", test_module="test_skid_buffer", parameters={"WIDTH": BUFFER_WIDTH})