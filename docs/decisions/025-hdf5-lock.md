# 025 — HDF5 serialised by a lock, not an actor

Dates: 2026-09-15

Status: live

## Decision

HDF5 access is serialised by a lock around each logical operation (an open,
a tile read, a sidecar write), recursive so nested entries do not deadlock,
never held across an `await`. The one path that nests a reader inside a
writer — tile-streaming export — releases it before each read.

## Why

The originally recorded fix ("one actor owning the library handle") would
have turned 145 synchronous call sites of the writer's statics — most in
harnesses and tests — into awaits, for no more safety than HDF5's own
thread-safe build already provides (a global mutex around every API call).
`tools/hdf5-race-probe` is the acceptance test: SIGBUS on the first attempt
before the fix, three clean completions of three after.

## Governs

`HDF5Serial`, `tools/hdf5-race-probe`.

## Sources

- 2026-09-15 (late night) "HDF5 is serialised by a lock around operations, not by an actor", log line 1408

Evidence: `tools/hdf5-race-probe` (verified present).
