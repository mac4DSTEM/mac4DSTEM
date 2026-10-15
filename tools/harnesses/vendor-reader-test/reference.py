#!/usr/bin/env python3
import pathlib
import struct
import sys

root = pathlib.Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)

raw = root / "empad.raw"
with raw.open("wb") as f:
    for frame in range(6):
        values = [float(frame * 100_000 + i) for i in range(128 * 128)]
        values += [-float(frame + 1)] * (2 * 128)
        f.write(struct.pack("<%df" % len(values), *values))
(root / "empad.xml").write_text(
    '<root><raw_file filename="empad.raw"/><type>scan</type>'
    '<scan_parameters mode="acquire"><scan_resolution_x>3</scan_resolution_x>'
    '<scan_resolution_y>2</scan_resolution_y></scan_parameters></root>'
)

mib = root / "merlin.mib"
fields = ["MQ1", "1", "384", "1", "0", "0", "U16", "1x1", "0",
          "2026-07-14 00:00:00", "0.001", "0", "0", "0", "0", "0", "0", "0", "12"]
header = (",".join(fields).encode("ascii") + b"\0").ljust(384, b"\0")
with mib.open("wb") as f:
    for frame in range(2):
        f.write(header)
        values = [(frame * 1000 + i) % 65535 for i in range(256 * 256)]
        f.write(struct.pack(">%dH" % len(values), *values))
(root / "merlin.hdr").write_text("ScanX:\t2\nScanY:\t1\n")
(root / "ambiguous.raw").write_bytes(raw.read_bytes()[: 2 * 130 * 128 * 4])
