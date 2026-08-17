import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, FallingEdge
from common import run
import logging
import random

NUM_ITER = 1000
BUFFER_WIDTH = 8

log = logging.getLogger("tb.test_skid_buffer")
log.setLevel(logging.INFO)

@cocotb.test()
async def passthrough(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())

    dut.rst_ni.value = 0
    dut.us_valid_i.value = 0
    dut.us_data_i.value = 0
    dut.ds_ready_i.value = 0
    await ClockCycles(dut.clk_i, 2)
    dut.rst_ni.value = 1
    await RisingEdge(dut.clk_i)
    await full_throughput(dut)

async def full_throughput(dut) :
    dut.ds_ready_i.value = 1
    dut.us_valid_i.value = 1

    for _ in range(NUM_ITER):
        val = random.randint(0, 2**BUFFER_WIDTH - 1)
        dut.us_data_i.value = val
        await RisingEdge(dut.clk_i)
        await FallingEdge(dut.clk_i)
        ds_val = dut.ds_data_o.value.to_unsigned()

        assert val == ds_val, f"FULL THROUGHPUT FAILED. exp {hex(val)}, got {hex(ds_val)}"

async def back_pressure() :
    for _ in range (NUM_ITER) :

def test_skid_buffer():
    run("skid_buffer", test_module="test_skid_buffer", parameters={"WIDTH": BUFFER_WIDTH})
