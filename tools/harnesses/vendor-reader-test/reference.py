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

# The same frames under the XML FormatoEMPAD recognises (RosettaSciIO's legacy pix_x/pix_y): 3 x 2, and 6 x 1 (a scan axis of size 1).
(root / "empad_kit.xml").write_text('<root><raw_file filename="empad.raw"/><pix_x>3</pix_x><pix_y>2</pix_y></root>')
(root / "empad_row.xml").write_text('<root><raw_file filename="empad.raw"/><pix_x>6</pix_x><pix_y>1</pix_y></root>')

# Both spellings, disagreeing: the app's precedence (scan_resolution_x/y: 3 x 2) wins; the kit's pix_x/pix_y (2 x 3) must not transpose it.
(root / "empad_both.xml").write_text('<root><raw_file filename="empad.raw"/><pix_x>2</pix_x><pix_y>3</pix_y>'
    '<scan_parameters mode="acquire"><scan_resolution_x>3</scan_resolution_x><scan_resolution_y>2</scan_resolution_y></scan_parameters></root>')

mib = root / "merlin.mib"
# A real Merlin header (the layout of FormatoKit's MIB fixtures): frame, offset, chips, width, height, pixel code, assembly, then
# ... timestamp, exposure in ns, a trailing field. FormatoMIB reads width and height from the header.
fields = ["MQ1", "000000", "00384", "1", "256", "256", "U16", "1x1", "12", " " * 40,
          "2026-07-14T00:00:00.000000Z", "1250000ns", "0", ""]
header = (",".join(fields).encode("ascii") + b"\0").ljust(384, b"\0")
with mib.open("wb") as f:
    for frame in range(2):
        f.write(header)
        values = [(frame * 1000 + i) % 65535 for i in range(256 * 256)]
        f.write(struct.pack(">%dH" % len(values), *values))
(root / "merlin.hdr").write_text("ScanX:\t2\nScanY:\t1\n")
(root / "ambiguous.raw").write_bytes(raw.read_bytes()[: 2 * 130 * 128 * 4])

# A MIB the former reader took and FormatoMIB refuses: a 512-byte header (the kit takes 384 or 768) with no width and height in it.
legacy_fields = ["MQ1", "1", "512", "1", "0", "0", "U16", "1x1", "0",
                 "2026-07-14 00:00:00", "0.001", "0", "0", "0", "0", "0", "0", "0", "12"]
legacy_header = (",".join(legacy_fields).encode("ascii") + b"\0").ljust(512, b"\0")
with (root / "legacy.mib").open("wb") as f:
    for frame in range(2):
        f.write(legacy_header)
        values = [(frame * 1000 + i) % 65535 for i in range(256 * 256)]
        f.write(struct.pack(">%dH" % len(values), *values))
(root / "legacy.hdr").write_text("ScanX:\t2\nScanY:\t1\n")
