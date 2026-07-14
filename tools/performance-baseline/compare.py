#!/usr/bin/env python3
"""Compare two schema-v2 mac4DSTEM baseline reports without gating CI."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def load(path: Path) -> dict[str, Any]:
    report = json.loads(path.read_text())
    if report.get("schema") != 2 or not isinstance(report.get("benchmarks"), dict):
        raise SystemExit(f"{path}: expected a schema-v2 performance report")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare same-machine mac4DSTEM performance reports"
    )
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    args = parser.parse_args()
    before = load(args.before)
    after = load(args.after)

    warnings: list[str] = []
    for key in ("machine", "os", "metal_device"):
        if before.get(key) != after.get(key):
            warnings.append(f"{key} differs; wall-clock ratios may not be comparable")

    comparisons: dict[str, Any] = {}
    common = sorted(set(before["benchmarks"]) & set(after["benchmarks"]))
    for name in common:
        old = float(before["benchmarks"][name]["median_ms"])
        new = float(after["benchmarks"][name]["median_ms"])
        comparisons[name] = {
            "before_median_ms": old,
            "after_median_ms": new,
            "after_over_before": new / old if old else None,
            "speedup": old / new if new else None,
            "percent_change": (new / old - 1) * 100 if old else None,
            "checksum_before": before["benchmarks"][name].get("checksum"),
            "checksum_after": after["benchmarks"][name].get("checksum"),
        }

    print(
        json.dumps(
            {
                "schema": 1,
                "before": str(args.before),
                "after": str(args.after),
                "warnings": warnings,
                "benchmarks": comparisons,
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
