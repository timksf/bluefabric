"""Verify that invalid supplied maps are rejected during BSC elaboration."""

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = (
    "overlaps region", "base must be aligned", "positive power of two", "positive power of two",
    "outside the address space", "outside the address space", "outside the address space", "positive power of two",
)
for case, diagnostic in enumerate(EXPECTED):
    directory = ROOT / "build/addr-map-validation" / str(case)
    directory.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["bsc", "-u", "-verilog", "-g", "mkTestInvalidAddrMap", "-D", f"ADDR_MAP_INVALID_CASE={case}",
         "-bdir", str(directory), "-vdir", str(directory), "-p", "+:src/common:test/bsv", "test/bsv/TestAddrMapDecoder.bsv"],
        cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    (directory / "elaboration.log").write_text(result.stdout)
    normalized = " ".join(result.stdout.split())
    assert result.returncode != 0 and "Bluespec evaluation-time error" in normalized and diagnostic in normalized, result.stdout
print(f"Rejected all {len(EXPECTED)} invalid address maps during elaboration")
