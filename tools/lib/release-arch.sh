#!/bin/sh

# The one place the release architecture is spelled (2026-09-11).
#
# mac4DSTEM is Apple-Silicon-only by design, and two independent things in the
# tree enforce it: the three embedded HDF5 libraries are arm64-only Mach-Os,
# and Core/ML/LearnedDiskDetector.swift uses Float16, which does not exist on
# x86_64 macOS. An x86_64 slice therefore cannot be built, and if it could be
# it would launch and then fail every dataset open, because H5Reader dlopens
# libhdf5 from Contents/Frameworks at runtime rather than linking it.
#
# WHY THIS FILE EXISTS, measured 2026-09-11 and not inferred:
# `ARCHS = arm64` is set at PROJECT level in both configurations and does NOT
# reach the SwiftPM package targets DSTEMCore and DSTEMSession, which is where
# every Core/ and Session/ source is actually compiled (the app target lists
# them under membershipExceptions). With a destination that does not constrain
# the architecture the package targets build ARCHS_STANDARD — arm64 x86_64 —
# and the Float16 compile fails. Reproduce it:
#   1. `build -configuration Release -destination 'generic/platform=macOS'`, no
#      archive, no credentials: BUILD FAILED, and the failing command is
#      "SwiftCompile normal x86_64 (in target 'DSTEMCore' ... Package.swift)".
#   2. the same with ARCHS=arm64 on the xcodebuild COMMAND LINE: BUILD
#      SUCCEEDED, zero `-target x86_64` frontend invocations.
# So the pin has to travel on the command line. A project-level fix was tried
# — `EXCLUDED_ARCHS = x86_64` beside each of the two project-level `ARCHS`
# lines — and the build still failed on an x86_64 DSTEMCore compile; that edit
# was reverted and its log is not retained, so treat it as a lead to re-run
# rather than as a result, and reproduce it with that one-line edit if it
# matters. What IS retained and decisive is 1 against 2.
#
# The CONCRETE destination `platform=macOS` constrains the package targets on
# its own: Release, Float16 present, no pin, BUILD SUCCEEDED and an arm64-only
# product (measured 2026-09-11). That is why every local build and the old
# packaging gate were green while the archive could not compile at all — not
# laxness, structural blindness.
#
# WHAT THIS COST: v2.5.1 shipped, notarized, on 2026-09-04 as a UNIVERSAL
# binary — `lipo -archs` on its executable is `x86_64 arm64` — with arm64-only
# HDF5 beside it. The 2026-09-09 review predicted that exact artefact (register
# D064) and the fix it received pinned the app target only, which is why the
# next archive was the first to fail rather than the first to be correct.
#
# A pin alone is not enough to trust, because the tempting wrong fix — making
# Float16 compile on x86_64 — turns a red build into a silently universal one.
# So the assertion below measures the PRODUCT, not the setting.

# Passed to xcodebuild as one argument. Command-line scope is the only scope
# that reaches SwiftPM package targets; see experiment 2 above.
MAC4DSTEM_ARCH_PIN='ARCHS=arm64'

# The destination the Developer ID archive uses. Any gate that means to cover
# the release path must use THIS, not 'platform=macOS': the concrete-machine
# destination filters the architectures itself and is structurally unable to
# see the defect above, which is how a green `all` and a broken archive
# coexisted for three days.
MAC4DSTEM_RELEASE_DESTINATION='generic/platform=macOS'

# Fail unless $1 is a Mach-O containing arm64 and nothing else.
assert_mac4dstem_arm64_only() {
  binary="$1"
  archs="$(lipo -archs "$binary" 2>/dev/null || true)"
  if [ "$archs" != "arm64" ]; then
    echo "FAIL: $binary is '${archs:-unreadable}', not arm64 alone." >&2
    echo "      mac4DSTEM ships arm64 only; the embedded HDF5 libraries are" >&2
    echo "      arm64-only and an x86_64 slice fails every dataset open." >&2
    echo "      See tools/lib/release-arch.sh." >&2
    return 1
  fi
}

# Every Mach-O a user receives: the executable and the embedded libraries.
#
# The status is accumulated explicitly rather than left to the last command or
# to `set -e`. The first version of this function ended on the dylib loop, so a
# universal EXECUTABLE printed FAIL and returned 0 — caught on 2026-09-11 by
# running it against the v2.5.1 bundle, which really is universal, before
# trusting it. `set -e` would have masked that in the callers below and not in
# an `if`, which is the one place a future caller is most likely to put it.
#
# The accumulator is NOT called `status`: these scripts are zsh, where `status`
# is a special parameter aliased to `$?`, and assigning to it makes the function
# return 1 unconditionally. Caught the same way, by running the controls again.
# The three libraries are named rather than globbed. A glob that matches
# nothing leaves the loop with no failures, so the earlier version passed a
# bundle that had LOST every embedded library — which is a worse defect than
# the one this function exists to catch, and package-test would have caught it
# only because it happens to assert the three by name a few lines later.
#
# The list is a LITERAL, not a variable holding a space-separated string: this
# file is /bin/sh but every caller is zsh, and zsh does not word-split an
# unquoted scalar, so `for library in $VAR` would iterate once over the whole
# string and find no such file. Caught by the positive control, which is what
# positive controls are for. tools/package-test/run.sh keeps its own list for
# codesign and otool — a different assertion; a library that goes missing now
# fails both.
assert_mac4dstem_bundle_arm64_only() {
  app="$1"
  arch_failures=0
  assert_mac4dstem_arm64_only "$app/Contents/MacOS/mac4DSTEM" || arch_failures=1
  for library in libhdf5.dylib libsz.2.dylib libaec.0.dylib; do
    if [ ! -f "$app/Contents/Frameworks/$library" ]; then
      echo "FAIL: $app is missing embedded $library." >&2
      arch_failures=1
      continue
    fi
    assert_mac4dstem_arm64_only "$app/Contents/Frameworks/$library" || arch_failures=1
  done
  return "$arch_failures"
}
