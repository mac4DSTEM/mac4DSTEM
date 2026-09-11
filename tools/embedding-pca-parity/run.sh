#!/bin/zsh
# Decomposition parity for DiffractionEmbedding (PCA + k-means over box-binned
# diffraction patterns) against py4DSTEM and numpy. Sources come from
# tools/lib/sources.manifest (`embedding` group) -- never a hand list.
#
# This is the FIRST number on the app's AI side that can be checked against
# anything upstream. What it can and cannot check, and why, is in
# verify_py4dstem.py's header; the short version is that PCA and the
# eigensolver have upstream counterparts, while the featurisation and k-means
# do not, and a real cube cannot be used because py4DSTEM's PCA goes
# nondeterministic above 500 rows.
#
# It is also the first GATED harness to compile Core/ with
# -Xcc -DACCELERATE_NEW_LAPACK. The only other users of that flag
# (bragg-spacing-probe, training-dataset-campaign) are `diagnostic`, so nothing
# reported it if Package.swift and the harnesses ever drifted apart. Now
# something does.
#
# NEGATIVE CONTROLS -- all seven APPLIED AND RUN 2026-09-11, with the measured
# outcome recorded. Four must go red; three must stay green, and recording THAT
# is the point, because it is exactly where this harness is blind.
#   NC1  symmetricEigenTop `let column = d - 1 - c` -> `= c` (ascending order):
#        RED -- A, B, C, D, S2a and S2b all fail.
#   NC2  basis written column-major in the basis-fill loop:
#        RED -- B, C, D fail (|cos| collapses).
#   NC3  drop the mean subtraction in the projection:
#        RED -- D ALONE fails while A stays green. This is what proves D is
#        independent of A rather than a restatement of it.
#   NC4  basis component 1 <-> 2 at the fill loop:
#        RED -- B, C, D fail. (A first attempt that shadowed `eigenvectors`
#        with a `var` did not COMPILE, so it was never a control at all; it was
#        redone against the fill loop.)
#   NC5  covariance divisor n -> n-1:
#        GREEN, as predicted. Every published quantity is ddof-invariant, so
#        this harness cannot pin that deviation.
#   NC6  embed's log1p -> identity:
#        GREEN, as predicted. The featurisation is not pinned BY CONSTRUCTION:
#        both sides consume the matrix `embed` produced. That is the whole
#        limit of this harness and the reason the DEVIATION note exists.
#   NC7  guard F. The obvious mutation -- make two fixture amplitudes equal --
#        did NOT fire it: the gap went 0.115 -> 0.150, because the per-position
#        coefficients are independent, so equal amplitudes give equal EXPECTED
#        variance with ~15% sampling spread at 400 positions. Firing it needed
#        equal amplitudes AND seed 0xBEEF01, which gives gap 0.094: the harness
#        then exits 1 with "guard F: eigenvalues too close". Recorded because
#        the first attempt looked like a passing control and was not one.
#
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-embedding-pca-parity.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main at
# init, and the embedding's cube streaming touches it -- measured, not assumed:
# without this the harness dies at MetalEngine.swift:172 with exit 133.
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  name="$(basename "$source" .metal)"
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$name.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" embedding

xcrun swiftc -package-name mac4DSTEM -parse-as-library -o "$WORK/harness" \
  main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  -Xcc -DACCELERATE_NEW_LAPACK \
  -framework Accelerate -framework Metal
codesign -f -s - "$WORK/harness" 2>/dev/null

# stderr stays OPEN: a refusal's text is the diagnostic (the S1 lesson).
"$WORK/harness" "$WORK"

ln -sfn "$REPO/References/py4DSTEM-dev" "$WORK/../py4DSTEM-dev" 2>/dev/null || true
PYTHONPATH="$REPO/References/py4DSTEM-dev" \
  "$PYTHON_BIN" verify_py4dstem.py "$WORK"
