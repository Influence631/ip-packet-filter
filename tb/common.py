from pathlib import Path
from cocotb_tools.runner import get_runner

TB = Path(__file__).resolve().parent
ROOT = TB.parent
RTL = ROOT / "rtl"


def run(top, test_module, sources=None, parameters=None):
    """Build `top` out of rtl/ and run `test_module` against it."""
    runner = get_runner("verilator")
    runner.build(
        sources=sources or [RTL / f"{top}.sv"],
        hdl_toplevel=top,
        parameters=parameters or {},
        build_args=["--trace-fst", "--assert"],
        build_dir=ROOT / "sim_build" / top,
        always=True,
        waves=True,
    )
    runner.test(hdl_toplevel=top, test_module=test_module, waves=True)
