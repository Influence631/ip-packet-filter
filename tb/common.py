import os
import random
from pathlib import Path
from cocotb_tools.runner import get_runner

TB = Path(__file__).resolve().parent
ROOT = TB.parent
RTL = ROOT / "rtl"


def run(top, test_module, sources=None, parameters=None, testcase=None):
    """Build `top` out of rtl/ and run `test_module` against it."""
    # Run a subset with TESTCASE=<regex>; unset runs all of them.
    testcase = testcase or os.environ.get("TESTCASE")
    # Verilator seed must be non-zero. Override with SEED=<n> to reproduce a failure.
    seed = int(os.environ.get("SEED") or random.randrange(1, 2**31))
    print(f"[common] SEED={seed}")

    runner = get_runner("verilator")
    runner.build(
        sources=sources or [RTL / f"{top}.sv"],
        hdl_toplevel=top,
        parameters=parameters or {},
        build_args=[
            "--trace-fst",
            "--assert",
            # randomize undriven/uninitialized signals and RTL X assignments
            "--x-initial", "unique",
            "--x-assign", "unique",
        ],
        build_dir=ROOT / "sim_build" / top,
        always=True,
        waves=True,
    )
    runner.test(
        hdl_toplevel=top,
        test_module=test_module,
        test_filter=testcase,
        waves=True,
        plusargs=[f"+verilator+seed+{seed}", "+verilator+rand+reset+2"],
    )
