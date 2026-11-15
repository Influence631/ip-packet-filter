import ipaddress
import itertools
import logging
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge
from cocotbext.axi import (AxiLiteBus, AxiLiteMaster, AxiStreamBus, AxiStreamFrame,
                           AxiStreamSink, AxiStreamSource)
from scapy.layers.inet import IP, UDP

from common import run, RTL

TAXI = RTL / "third_party/taxi/src/axi/rtl"
log = logging.getLogger("tb.test_top_level")
log.setLevel(logging.INFO)

VALID_ADDR = 0x80
IPV4_MIN_LEN = 20  # IHL >= 5 words (RFC 791)


def ip_int(ip):
    return int(ipaddress.IPv4Address(ip))


def ipv4(dst, payload_len):
    payload = bytes(random.randrange(256) for _ in range(payload_len))
    return bytes(IP(src="192.0.2.1", dst=dst) / UDP(sport=1234, dport=5678) / payload)


def dropped(pkt, blocked):
    """Reference model: too short for a full header, or dst on the blacklist."""
    return len(pkt) < IPV4_MIN_LEN or int.from_bytes(pkt[16:20], "big") in blocked


class TB:
    def __init__(self, dut):
        self.dut = dut
        cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
        self.axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"),
                                  dut.clk_i, dut.rst_ni, reset_active_level=False)
        self.source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"),
                                      dut.clk_i, dut.rst_ni, reset_active_level=False)
        self.sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"),
                                  dut.clk_i, dut.rst_ni, reset_active_level=False)
        self.status = []  # pkt_drop_o of every pkt_valid_o pulse, in order
        cocotb.start_soon(self._status_monitor())

    def set_idle_generator(self, gen=None):
        if gen:
            self.source.set_pause_generator(gen())

    def set_backpressure_generator(self, gen=None):
        if gen:
            self.sink.set_pause_generator(gen())

    async def reset(self):
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 0
        for _ in range(2):
            await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        for _ in range(2):
            await RisingEdge(self.dut.clk_i)
        self.status.clear()

    async def _status_monitor(self):
        # one settled sample per cycle
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            if self.dut.pkt_valid_o.value:
                self.status.append(bool(self.dut.pkt_drop_o.value))

    async def block(self, ips):
        mask = 0
        for i, ip in enumerate(ips):
            await self.axil.write_dword(4 * i, ip_int(ip))
            mask |= 1 << i
        await self.axil.write_dword(VALID_ADDR, mask)
        return {ip_int(ip) for ip in ips}

    async def check(self, pkts, blocked, stall_cycles=0):
        """Send pkts back-to-back, expect only the survivors on m_axis, in order."""
        expected = [p for p in pkts if not dropped(p, blocked)]
        if stall_cycles:
            self.sink.pause = True
        for p in pkts:
            await self.source.send(AxiStreamFrame(p))
        if stall_cycles:
            await ClockCycles(self.dut.clk_i, stall_cycles)
            self.sink.pause = False

        for i, exp in enumerate(expected):
            frame = await self.sink.recv()
            assert isinstance(frame, AxiStreamFrame)
            got = bytes(frame.tdata)
            assert got == exp, f"packet {i}: got {got.hex()} expected {exp.hex()}"

        await self.source.wait()
        await ClockCycles(self.dut.clk_i, 50)  # anything extra would have shown up by now
        assert self.sink.empty(), f"{self.sink.count()} unexpected packets on m_axis"
        assert self.status == [dropped(p, blocked) for p in pkts], "status pulses don't match"


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


# cocotb tests are named run_test_* so pytest doesn't try to collect them
@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_filter(dut, idle_inserter=None, backpressure_inserter=None):
    """Random mix of blacklisted and clean packets, back-to-back."""
    tb = TB(dut)
    await tb.reset()
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    blocked_ips = ["10.0.0.1", "192.168.1.77"]
    blocked = await tb.block(blocked_ips)
    # near misses (one bit / one byte off) must pass
    dsts = blocked_ips + ["10.0.0.2", "192.168.1.76", "1.0.0.10", "8.8.8.8"]
    pkts = [ipv4(random.choice(dsts), random.randrange(0, 40)) for _ in range(40)]
    await tb.check(pkts, blocked)


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_short(dut, idle_inserter=None, backpressure_inserter=None):
    """Every length below a full header is dropped; a bare 20-byte header passes."""
    tb = TB(dut)
    await tb.reset()
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    pkts = []
    for n in range(1, IPV4_MIN_LEN):
        pkts.append(bytes(random.randrange(256) for _ in range(n)))
        pkts.append(bytes(IP(src="192.0.2.1", dst="10.0.0.2")))
    await tb.check(pkts, blocked=set())


@cocotb.test()
async def run_test_stall(dut):
    """Output stalled while one-beat packets pile up behind a forwarded one."""
    tb = TB(dut)
    await tb.reset()
    blocked = await tb.block(["10.0.0.1"])

    pkts = [bytes(IP(src="192.0.2.1", dst="10.0.0.2"))]   # 5 beats, forwarded, stuck at the gate
    pkts += [bytes([i]) for i in range(30)]               # 1-beat packets fill the packet fifo
    pkts += [ipv4("10.0.0.1", 8), ipv4("10.0.0.3", 8)]
    await tb.check(pkts, blocked, stall_cycles=300)


@cocotb.test()
async def run_test_reconfig(dut):
    """Blacklist changes apply to packets sent after the write completes."""
    tb = TB(dut)
    await tb.reset()
    pkt = ipv4("172.16.0.5", 12)

    blocked = await tb.block(["172.16.0.5"])
    await tb.check([pkt], blocked)

    await tb.axil.write_dword(VALID_ADDR, 0)
    tb.status.clear()
    await tb.check([pkt], blocked=set())


def test_top_level():
    run(
        sources=[
            TAXI / "taxi_axil_if.sv",
            RTL / "sync_fifo.sv",
            RTL / "axis_delayed_fifo.sv",
            RTL / "reg_fifo.sv",
            RTL / "dst_ip_tap.sv",
            RTL / "blacklist.sv",
            RTL / "drop_gate.sv",
            RTL / "ip_filter.sv",
            RTL / "top_level.sv",
        ],
        top="top_level", test_module="test_top_level", parameters={},
    )
