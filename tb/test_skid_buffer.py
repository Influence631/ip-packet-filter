import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, ReadOnly
from common import run
import logging
import random
from collections import deque

NUM_BEATS = 100
SRC_STALL_RATE = 0.3
SINK_STALL_RATE = 0.6 
BUFFER_WIDTH = 8

log = logging.getLogger("tb.test_skid_buffer")
log.setLevel(logging.INFO)

class StreamSource:
    def __init__(self, clk, *, valid, data, ready, width):
        self.clk = clk
        self.valid = valid
        self.ready = ready
        self.data = data
        self.width = width
        self.drain = False

    async def send(self, beat) :
        self.valid.value = 1
        self.data.value = beat

        #hold the valid high and data steady untill a transmission happens
        while 1 :
            await RisingEdge(self.clk)
            if (self.ready.value == 1) : 
                return
            

    async def run(self, n_beats, stall_chance=0.0) :
        #add drain logic so that after n_beats sent, the sink reads anything left in the buffer.
        for _ in range(n_beats):
            if (random.random() <= stall_chance) : #stall
                self.valid.value = 0
            else :
                beat = random.randint(0, 2**self.width - 1)
                await self.send(beat)
                self.sent += 1

            await RisingEdge(self.clk)

class StreamSink:
    def __init__(self, clk, *, valid, data, ready):
        self.clk = clk
        self.valid = valid
        self.ready = ready
        self.data = data

    async def run(self, stall_chance=0.0) :
        while (1):
            if (random.random() <= stall_chance) : # stall
                self.ready.value = 0 
            else :
                self.ready.value = 1
            await RisingEdge(self.clk)

            
class SkidTB:
    def __init__(self, dut, src, sink, depth):
        self.dut = dut
        self.src = src
        self.sink = sink
        self.accepted = 0
        self.beats = 0
        self.depth = depth
        self.model = deque()

    async def reset(self):
        self.dut.rst_ni.value = 0
        self.src.valid.value = 0
        self.src.data.value = 0
        self.sink.ready.value = 1
        self.model.clear()
        await ClockCycles(self.dut.clk_i, 2)
        self.dut.rst_ni.value = 1
        
    @classmethod
    async def create(cls, dut, src_stall_rate=0.0, sink_stall_rate=0.0, width=BUFFER_WIDTH):
        src = StreamSource(dut.clk_i, valid=dut.us_valid_i, data=dut.us_data_i, ready=dut.us_ready_o, width=width)
        sink = StreamSink(dut.clk_i, valid=dut.ds_valid_o, data=dut.ds_data_o, ready=dut.ds_ready_i)

        tb = SkidTB(dut, src=src, sink=sink, depth=2)
        cocotb.start_soon(Clock(tb.dut.clk_i, 10, "ns").start())

        await tb.reset()
        cocotb.start_soon(tb.sink.run())
        cocotb.start_soon(tb.mon_us())
        #cocotb.start_soon(tb.mon_ds())
        return tb

    async def mon_us(self):
        while 1 :
            await RisingEdge(self.dut.clk_i)
            if (self.src.valid.value & self.src.ready.value) :
                self.accepted += 1
                self.model.append(self.src.data.value)

            assert 0 <= self.accepted - self.beats <= self.depth, (
                f"the model has {len(self.model)} elements," 
                f"where max {self.depth} allowed"
            )
            assert self.src.sent == self.accepted, f"model and tb disagree, src sent {self.src.sent}, tb accepted {self.accepted}"

    async def mon_ds(self):
        #assert self.beats == self.accepted
        while 1 :
            await RisingEdge()
            if (self.sink.ready.value & self.sink.valid.value) :
                assert self.model, f"trying to ready from an empty buffer"
                exp = self.model.popleft()
                got = self.sink.data.value
                assert got == exp, f"got {hex(got)}, exp {hex(exp)}"
            #this needs draining before so probably doesnt belong here
            assert self.accepted == self.beats, f"gap written/read"  

@cocotb.test()
async def full_thoughput(dut):
    tb = await SkidTB.create(dut, src_stall_rate=0.0, sink_stall_rate=0.0)
    await tb.src.run(n_beats=NUM_BEATS, stall_chance=0.0) #full throughput
    #assert tb.accepted == tb.beats
    assert tb.src.sent == NUM_BEATS, f"expected sent {NUM_BEATS} beats, sent {tb.src.sent.value} beats."

"""
@cocotb.test()
async def backpressure(dut):
    tb = SkidTB.create(dut)
    await tb.src.run(stall_chance=SRC_STALL_RATE) #50% stall

    # await tb.sink.drain() #add drain logic and verify that the last cycles transmission works correctly
"""
def test_skid_buffer():
    run(top="skid_buffer", test_module="test_skid_buffer", parameters={"WIDTH": BUFFER_WIDTH})