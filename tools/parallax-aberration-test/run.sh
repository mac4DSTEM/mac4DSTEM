#!/bin/zsh
set -euo pipefail

# reference.py source-locks py4DSTEM's low-order and higher-order aberration
# fit and CTF correction in process/phase/parallax.py and process/phase/utils.py;
# the Swift harness runs Core/Analysis/ParallaxAberrationFitting.swift's
# ParallaxAberrationFitter (fitLowOrder/fitHigherOrder/gradientSamples) and
# ParallaxAberrationCorrector.correct against the emitted fixtures, plus
# rejection cases (incomplete alignment, singular geometry, invalid/cancelled
# correction). Run with no arguments: tools/parallax-aberration-test/run.sh.
# Listed in both the `scientific` and `campaign` arrays of tools/run-tests.sh,
# so it runs under `tools/run-tests.sh scientific` and `...campaign` (and `all`).
# Pass condition: "PASS: ..." per case, final "parallax-aberration-test: all passed".

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-parallax-aberration-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"

"$PYTHON_BIN" reference.py > "$WORK/expected.json"
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" parallax
xcrun swiftc -package-name mac4DSTEM -parse-as-library -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate
"$WORK/harness" "$WORK/expected.json"
