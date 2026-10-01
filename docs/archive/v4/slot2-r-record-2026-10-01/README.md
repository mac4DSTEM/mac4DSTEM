Lane R (R2+R3, 2026-10-01) scratch scripts and logs, staged for docs/archive/v4/slot2-r-record-2026-10-01/. Paths: every script runs
from this directory with REPO (default /Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM), PYTHON (default
~/miniconda3/envs/py4dstem/bin/python; numpy 2.5 + py4DSTEM 0.14.19 from References/py4DSTEM-dev) and SP (the session scratchpad,
only in graphene.sh / finish.sh / mutate*.sh / harness.sh / build-dump.sh, which took the heavy lock there). Order: build-dump.sh
(dump/main.swift -> dump/dump against the app's ptychography sources) -> synth.py make -> run-e0.sh -> run-sweep.sh -> run-sens.sh
-> run-seeds-fixp.sh -> run-arbiter.sh; graphene.sh then gr-compare.sh (needs the SSD cube); mutate-all.sh + mutate2.sh (harness
mutations); dm64.py / dm64-wrongprobe.py are the refuter's float64 runs. Left out: *.npy, fixture JSONs (12 MB each) and run
outputs (json dumps); truth-*.json (38 MB) — regenerate with tools/singleslice-ptychography-test/truth.py.
