import itertools
import logging
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ReadOnly
from cocotbext.axi import AxiLiteBus, AxiLiteMaster, AxiResp
from cocotbext.axi.axil_master import AxiLiteReadResp, AxiLiteWriteResp
from common import run, RTL, TB as TB_DIR

TAXI = RTL / "third_party/taxi/src/axi/rtl"
log = logging.getLogger("tb.test_blacklist")
log.setLevel(logging.INFO)

class TB:
    def __init__(self, dut):
        self.dut = dut
        cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
        # the master owns every s_axil_* signal; never drive them from the test
        self.axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"),
                                  dut.clk_i, dut.rst_ni, reset_active_level=False)

    def _ifs(self):
        # AxiLiteMaster.__init__ sets these to None first; narrow for the type checker
        wr, rd = self.axil.write_if, self.axil.read_if
        assert wr is not None and rd is not None
        return wr, rd

    def set_idle_generator(self, gen=None):
        if gen:
            wr, rd = self._ifs()
            wr.aw_channel.set_pause_generator(gen())
            wr.w_channel.set_pause_generator(gen())
            rd.ar_channel.set_pause_generator(gen())

    def set_backpressure_generator(self, gen=None):
        if gen:
            wr, rd = self._ifs()
            wr.b_channel.set_pause_generator(gen())
            rd.r_channel.set_pause_generator(gen())

    async def reset(self):
        self.dut.ip_addr_i.value = 0
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 0
        for _ in range(2):
            await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        for _ in range(2):
            await RisingEdge(self.dut.clk_i)

    async def lookup(self, ip):
        self.dut.ip_addr_i.value = ip
        await RisingEdge(self.dut.clk_i)   # lookup[] is registered
        await ReadOnly()                   # settled post-edge value
        hit = bool(self.dut.is_blacklisted_o.value)
        await FallingEdge(self.dut.clk_i)  # leave ReadOnly before anything drives again
        return hit

    # write()/read() are unannotated upstream; isinstance narrows the result for the type checker
    async def write_resp(self, addr, value):
        op = await self.axil.write(addr, value.to_bytes(4, "little"))
        assert isinstance(op, AxiLiteWriteResp)
        return op.resp

    async def read_resp(self, addr):
        op = await self.axil.read(addr, 4)
        assert isinstance(op, AxiLiteReadResp)
        return op.resp


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


# cocotb tests are named run_test_* so pytest doesn't try to collect them
@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_match(dut, idle_inserter=None, backpressure_inserter=None):
    tb = TB(dut)
    await tb.reset()
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    ip = 0xC0A80001
    await tb.axil.write_dword(4 * 3, ip)          # ENTRY[3]
    assert not await tb.lookup(ip)                # written but not enabled
    await tb.axil.write_dword(0x80, 1 << 3)       # VALID bit 3
    assert await tb.lookup(ip)
    assert await tb.axil.read_dword(4 * 3) == ip
    assert await tb.axil.read_dword(0x80) == 1 << 3
    await tb.axil.write_dword(0x80, 0)            # disable
    assert not await tb.lookup(ip)


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_slverr(dut, idle_inserter=None, backpressure_inserter=None):
    tb = TB(dut)
    await tb.reset()
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    # mapped addresses answer OKAY
    assert await tb.write_resp(0x04, 0x11111111) == AxiResp.OKAY
    assert await tb.write_resp(0x80, 0x5) == AxiResp.OKAY
    assert await tb.read_resp(0x04) == AxiResp.OKAY
    assert await tb.read_resp(0x80) == AxiResp.OKAY

    # bit 7 set but index != 0 is unmapped
    for addr in (0x84, 0xC0, 0xFC):
        assert await tb.write_resp(addr, 0xFFFFFFFF) == AxiResp.SLVERR
        assert await tb.read_resp(addr) == AxiResp.SLVERR

    # unmapped writes must not alias onto VALID or the table (0x84 -> idx 1)
    assert await tb.axil.read_dword(0x80) == 0x5
    assert await tb.axil.read_dword(0x04) == 0x11111111


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_strobe(dut, idle_inserter=None, backpressure_inserter=None):
    tb = TB(dut)
    await tb.reset()
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    base = 0x11223344
    for addr in (4 * 3, 0x80):                    # one table entry, then VALID
        for lane in range(4):
            await tb.axil.write_dword(addr, base)
            await tb.axil.write_byte(addr + lane, 0xAB)
            expected = (base & ~(0xFF << 8 * lane)) | (0xAB << 8 * lane)
            got = await tb.axil.read_dword(addr)
            assert got == expected, f"addr {addr:#x} lane {lane}: {got:#010x} != {expected:#010x}"


@cocotb.test()
async def run_test_reset(dut):
    tb = TB(dut)
    await tb.reset()

    # mem isn't reset, but every valid bit is, so nothing may match
    assert await tb.axil.read_dword(0x80) == 0
    for ip in (0x00000000, 0xFFFFFFFF, 0xC0A80001):
        assert not await tb.lookup(ip)

    # an enabled entry must be disabled again by reset
    ip = 0xC0A80001
    await tb.axil.write_dword(4 * 5, ip)
    await tb.axil.write_dword(0x80, 1 << 5)
    assert await tb.lookup(ip)
    await tb.reset()
    assert await tb.axil.read_dword(0x80) == 0
    assert not await tb.lookup(ip)


def test_blacklist():
    run(
        sources=[
            TB_DIR / "test_blacklist.sv",
            TAXI / "taxi_axil_if.sv",
            RTL / "blacklist.sv",
        ],
        top="test_blacklist", test_module="test_blacklist", parameters={},
    )
