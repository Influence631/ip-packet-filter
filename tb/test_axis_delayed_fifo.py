import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles
from common import run
import logging 
import random
from cocotb.types import LogicArray
from collections import deque

FIFO_DEPTH = 8
DATA_WIDTH = 8
BUFFER_DEPTH = 4 
NUM_BEATS = 1000

log = logging.getLogger("tb.delayed_fifo")
log.setLevel(logging.INFO)

class StreamSource:
    def __init__(self, clk, *, valid, data, ready, width):
        self.clk = clk
        self.valid = valid
        self.ready = ready
        self.data = data
        self.width = width

    async def send(self, beat) :
        self.valid.value = 1
        self.data.value = beat
        #hold the valid high and data steady untill a transmission happens
        while 1 :
            await RisingEdge(self.clk)
            if (self.ready.value == 1) : 
                return

    async def run(self, n_beats, stall_chance=0.0) :
        for _ in range(n_beats):
            while (random.random() < stall_chance) : #stall
                self.valid.value = 0
                await RisingEdge(self.clk)
            beat = random.randint(0, 2**self.width - 1)
            await self.send(beat)
        self.valid.value = 0

class StreamSink:
    def __init__(self, clk, *, data, ready, valid):
        self.clk = clk
        self.ready = ready
        self.data = data
        self.valid = valid

    async def run(self, stall_chance=0.0) :
        while (1):
            self.ready.value = 0 if (random.random() < stall_chance) else 1
            await RisingEdge(self.clk)

            
class AXI_FIFO_TB:
    def __init__(self, dut, src, sink, depth):
        self.dut = dut
        self.src = src
        self.sink = sink
        self.accepted = 0
        self.beats = 0
        self.depth = depth
        self.model: deque[LogicArray] = deque()

    async def reset(self):
        self.dut.rst_ni.value = 0
        self.src.valid.value = 0
        self.src.ready.value = 0
        self.src.data.value = 0
        self.sink.ready.value = 0
        self.accepted = 0
        self.beats = 0
        self.model.clear()
        await ClockCycles(self.dut.clk_i, 2)
        await FallingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)

    async def wait_quiet(self, expected) :
        while not (self.beats == expected and not self.model) :
            await RisingEdge(self.dut.clk_i)
        
    @classmethod
    async def create(cls, dut, sink_stall_rate=0.0, width=DATA_WIDTH, depth=FIFO_DEPTH):
        src = StreamSource(
            dut.clk_i, valid=dut.s_axis_tvalid, data=dut.s_axis_tdata, 
            ready=dut.s_axis_tready, width=width
        )
        sink = StreamSink(dut.clk_i, ready=dut.m_axis_tready, valid=dut.m_axis_tvalid, data=dut.m_axis_tdata)

        tb = AXI_FIFO_TB(dut, src=src, sink=sink, depth=depth)
        cocotb.start_soon(Clock(tb.dut.clk_i, 10, "ns").start(start_high=False))

        await tb.reset()
        cocotb.start_soon(tb.sink.run(sink_stall_rate))
        cocotb.start_soon(tb.mon_us())
        cocotb.start_soon(tb.mon_ds())
        return tb

    async def mon_us(self):
        while 1 :
            if ((self.src.valid.value == 1) and (self.src.ready.value == 1)) :
                self.accepted += 1
                self.model.append(self.src.data.value)

            assert 0 <= self.accepted - self.beats <= self.depth + BUFFER_DEPTH, (
                f"the model has {len(self.model)} elements," 
                f"where max {self.depth} allowed + buffer depth"
            )
            await RisingEdge(self.dut.clk_i)
                        

    async def mon_ds(self):
        while 1 :
            if (self.sink.valid.value == 1 and self.sink.ready.value == 1) :
                self.beats += 1
                exp = self.model.popleft()
                actual = self.sink.data.value
                assert actual == exp, f"actual {hex(actual)}, exp {hex(exp)}" 
            await RisingEdge(self.dut.clk_i)
            
                                        

@cocotb.test(timeout_time=200, timeout_unit="us")
async def s_axis_tready_throughput(dut) :
    tb = await AXI_FIFO_TB.create(dut)
    await tb.src.run(n_beats=NUM_BEATS, stall_chance=0.0)
    await tb.wait_quiet(expected=NUM_BEATS)
    
    assert tb.accepted == tb.beats, f"accepted {tb.accepted} != beats {tb.beats}"

@cocotb.test(timeout_time=1000, timeout_unit="us")
async def back_pressure(dut) :
    tb = await AXI_FIFO_TB.create(dut, sink_stall_rate=0.6)
    await tb.src.run(n_beats=NUM_BEATS, stall_chance=0.5)
    await tb.wait_quiet(expected=NUM_BEATS)

    assert tb.accepted == tb.beats, f"accepted {tb.accepted} != beats {tb.beats}"
      
def test_axis_delayed_fifo():
    run(
        top="axis_delayed_fifo", test_module="test_axis_delayed_fifo", 
        parameters={"FifoDepth" : FIFO_DEPTH, "DataWidth" : DATA_WIDTH}
    ) 