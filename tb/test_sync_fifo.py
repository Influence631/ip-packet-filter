import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles
from common import run
import logging 
import random
from cocotb.types import LogicArray
from collections import deque

FIFO_DEPTH = 32
FIFO_WIDTH = 32
NUM_BEATS = 1000

log = logging.getLogger("tb.test_fifo")
log.setLevel(logging.INFO)

class StreamSource:
    def __init__(self, clk, *, wr_en, data, full, width):
        self.clk = clk
        self.wr_en = wr_en
        self.full = full
        self.data = data
        self.width = width

    async def run(self, n_beats, stall_chance=0.0) :
        sent = 0
        while (sent < n_beats):
            we = 0 if (random.random() < stall_chance) else 1
            self.wr_en.value = we
            self.data.value = random.randint(0, 2**self.width - 1)
            await RisingEdge(self.clk)
            if (self.full.value == 0 and self.wr_en.value == 1) : #last cycle was not full and we was set
                sent += 1
        self.wr_en.value = 0

class StreamSink:
    def __init__(self, clk, *, rd_en, data, empty):
        self.clk = clk
        self.rd_en = rd_en
        self.empty = empty
        self.data = data

    async def run(self, stall_chance=0.0) :
        while (1):
            self.rd_en.value = 0 if (random.random() < stall_chance) else 1
            await RisingEdge(self.clk)

            
class FIFO_TB:
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
        self.src.wr_en.value = 0
        self.src.data.value = 0
        self.sink.rd_en.value = 0
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
    async def create(cls, dut, sink_stall_rate=0.0, width=FIFO_WIDTH, depth=FIFO_DEPTH):
        src = StreamSource(
            dut.clk_i, wr_en=dut.we_i, data=dut.data_i, 
            full=dut.full_o, width=width
        )
        sink = StreamSink(dut.clk_i, rd_en=dut.re_i, data=dut.data_o, empty=dut.empty_o)

        tb = FIFO_TB(dut, src=src, sink=sink, depth=depth)
        cocotb.start_soon(Clock(tb.dut.clk_i, 10, "ns").start(start_high=False))

        await tb.reset()
        cocotb.start_soon(tb.sink.run(sink_stall_rate))
        cocotb.start_soon(tb.mon_us())
        cocotb.start_soon(tb.mon_ds())
        return tb

    async def mon_us(self):
        while 1 :
            if ((self.src.wr_en.value == 1) & (self.src.full.value == 0)) :
                self.accepted += 1
                self.model.append(self.src.data.value)

            assert 0 <= self.accepted - self.beats <= self.depth, (
                f"the model has {len(self.model)} elements," 
                f"where max {self.depth} allowed"
            )
            await RisingEdge(self.dut.clk_i)
                        

    async def mon_ds(self):
        while 1 :
            if ((self.sink.rd_en.value == 1) & (self.sink.empty.value == 0)) :
                assert self.model, f"trying to ready from an empty buffer"
                exp = self.model.popleft()
                got = self.sink.data.value
                self.beats += 1
                assert got == exp, f"got {hex(got)}, exp {hex(exp)}"
            await RisingEdge(self.dut.clk_i)
                        

@cocotb.test(timeout_time=200, timeout_unit="us")
async def full_throughput(dut) :
    tb = await FIFO_TB.create(dut)
    await tb.src.run(n_beats=NUM_BEATS, stall_chance=0.0)
    await tb.wait_quiet(expected=NUM_BEATS)

    assert tb.accepted == tb.beats, f"accepted {tb.accepted} != beats {tb.beats}"


@cocotb.test(timeout_time=200, timeout_unit="us")
async def back_pressure(dut) :
    tb = await FIFO_TB.create(dut, sink_stall_rate=0.9)
    await tb.src.run(n_beats=NUM_BEATS, stall_chance=0.5)
    await tb.wait_quiet(expected=NUM_BEATS)

    assert tb.accepted == tb.beats, f"accepted {tb.accepted} != beats {tb.beats}"
         
def test_sync_fifo():
    run(top="sync_fifo", test_module="test_sync_fifo", parameters={"WIDTH" : FIFO_WIDTH, "DEPTH" : FIFO_DEPTH})
