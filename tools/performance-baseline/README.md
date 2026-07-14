# Performance baseline

This is a non-gating trend measurement for production CPU and Metal workloads:
exact-shape FFTs, disk detection, selected-area diffraction/tile staging,
single-slice ptychography, and ACOM plan/CPU/Metal matching. It compiles
optimized production sources, warms each path, and emits machine-readable JSON
with checksums. Wall-clock thresholds are deliberately absent because laptop
power/thermal state and hardware differ.

Run it before and after a performance slice on the same machine and power mode:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  tools/performance-baseline/run.sh
```
