# 020 — `-DACCELERATE_NEW_LAPACK` via `unsafeFlags` accepted

Dates: 2026-09-11

Status: live

## Decision

`.unsafeFlags(["-Xcc", "-DACCELERATE_NEW_LAPACK"])` is accepted in
`Package.swift`. `DiffractionEmbedding` needs `__LAPACK_int`, which only
exists behind Apple's new Accelerate LAPACK interface — verified empirically,
since `dsyevd_` alone compiles without the macro but `__LAPACK_int` is a hard
error. Two harnesses that compile `Core/**` themselves with a bare `swiftc`
(`tools/bragg-spacing-probe`, `tools/training-dataset-campaign`) needed the
flag added to their own `swiftc` lines in the same commit, since no gate
would otherwise report the break.

## Why

The alternatives were rejected on cost: Apple's deprecated legacy interface
keeps publishability but adopts a deprecated API and needs its own proof the
eigenvalues are unchanged; a C shim target is unverified and needs a spike.
The accepted cost is that SwiftPM will refuse to resolve `DSTEMCore` as a
versioned remote dependency while the flag is present — nothing consumes it
that way today.

## Governs

`Package.swift`'s `unsafeFlags`, `mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift`,
`tools/bragg-spacing-probe/run.sh`, `tools/training-dataset-campaign/run.sh`.

## Sources

- 2026-09-11 "`.unsafeFlags([\"-Xcc\", \"-DACCELERATE_NEW_LAPACK\"])` is accepted in `Package.swift`", log line 934
