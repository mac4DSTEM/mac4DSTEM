# Performance baseline

This is a non-gating trend measurement for two known CPU hot paths: exact-shape
2-D FFTs and the first full-batch single-slice ptychography engine. It compiles
optimized production sources, warms the FFT path, and emits machine-readable
JSON with checksums. Wall-clock thresholds are deliberately absent because
laptop power/thermal state and hardware differ.

Run it before and after a performance slice on the same machine and power mode:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  tools/performance-baseline/run.sh
```
