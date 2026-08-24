import cocotb
from cocotb.clock import Clock
from cocotb.types import LogicArray
from cocotb.triggers import RisingEdge, ClockCycles, FallingEdge
from common import run
import logging
import random
from collections import deque

NUM_BEATS = 2000
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
    def __init__(self, clk, *, valid, data, ready):
        self.clk = clk
        self.valid = valid
        self.ready = ready
        self.data = data
        self.drain = False

    async def run(self, stall_chance=0.0) :
        while (1):
            if ((random.random() < stall_chance) & (not self.drain)) : # stall
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
        self.model: deque[LogicArray] = deque()

    async def reset(self):
        self.dut.rst_ni.value = 0
        self.src.valid.value = 0
        self.src.data.value = 0
        self.sink.ready.value = 1
        self.model.clear()
        await ClockCycles(self.dut.clk_i, 2)
        await FallingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)

    async def drain(self, expected, timeout=20) :
        self.sink.drain = True
        for _ in range(timeout):
            await RisingEdge(self.dut.clk_i)
            if (self.beats == expected and not self.model) :
                self.sink.drain = False
                return
        raise AssertionError(f"stuck : {list(self.model)}")

    @classmethod
    async def create(cls, dut, sink_stall_rate=0.0, width=BUFFER_WIDTH):
        src = StreamSource(
            dut.clk_i, valid=dut.us_valid_i, data=dut.us_data_i, 
            ready=dut.us_ready_o, width=width
        )
        sink = StreamSink(dut.clk_i, valid=dut.ds_valid_o, data=dut.ds_data_o, ready=dut.ds_ready_i)

        tb = SkidTB(dut, src=src, sink=sink, depth=2)
        cocotb.start_soon(Clock(tb.dut.clk_i, 10, "ns").start(start_high=False))

        await tb.reset()
        cocotb.start_soon(tb.sink.run(sink_stall_rate))
        cocotb.start_soon(tb.mon_us())
        cocotb.start_soon(tb.mon_ds())
        return tb

    async def mon_us(self):
        while 1 :
            await RisingEdge(self.dut.clk_i)
            if ((self.src.valid.value == 1) & (self.src.ready.value == 1)) :
                self.accepted += 1
                self.model.append(self.src.data.value)

            assert 0 <= self.accepted - self.beats <= self.depth, (
                f"the model has {len(self.model)} elements," 
                f"where max {self.depth} allowed"
            )
            

    async def mon_ds(self):
        while 1 :
            await RisingEdge(self.dut.clk_i)
            if ((self.sink.ready.value == 1) & (self.sink.valid.value == 1)) :
                assert self.model, f"trying to ready from an empty buffer"
                exp = self.model.popleft()
                got = self.sink.data.value
                assert got == exp, f"got {hex(got)}, exp {hex(exp)}"
                #log.info("element : %d", exp)
                self.beats += 1
            

@cocotb.test()
async def full_throughput(dut):
    tb = await SkidTB.create(dut, sink_stall_rate=0.0)
    await tb.src.run(n_beats=NUM_BEATS, stall_chance=0.0)
    await tb.drain(expected=NUM_BEATS)

    assert NUM_BEATS == tb.accepted == tb.beats, (
        f"sent {NUM_BEATS} beats, accepted {tb.accepted} beats, output {tb.beats} beats"
    )


@cocotb.test()
async def backpressure(dut):
    tb = await SkidTB.create(dut, sink_stall_rate=0.5)
    await tb.src.run(n_beats=NUM_BEATS, stall_chance=0.3)
    await tb.drain(expected=NUM_BEATS)
    
    assert NUM_BEATS == tb.accepted == tb.beats, (
        f"sent {NUM_BEATS} beats, accepted {tb.accepted} beats, output {tb.beats} beats"
    )

def test_skid_buffer():
    run(top="skid_buffer", test_module="test_skid_buffer", parameters={"WIDTH": BUFFER_WIDTH})