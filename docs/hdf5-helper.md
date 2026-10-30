# libhdf5 in a helper process

Status: accepted 2026-10-29 (the owner's decision); this page is the design. Slice 1 lands with it.

## Why

libhdf5 is C code that trusts the file it reads. A crafted or damaged `.h5` can make it crash (the app dies with it)
or hang (the window stops answering, and quitting waits on a call that never returns). Size caps in the readers
cannot reach inside libhdf5. The one fix is to run libhdf5 in another process. If that process crashes, the app gets
an error sentence. If it hangs, it is ended.

## Decisions

### An XPC service, not a helper tool

The app embeds `HDF5Helper.xpc` in `Contents/XPCServices`. launchd starts it on the first message and restarts it on
the next message after it dies.

| | XPC service (chosen) | Helper tool (`Process` + pipes) |
|---|---|---|
| Lifetime | launchd's; ends with the app | the app's child; the app must reap it |
| Transport | `NSXPCConnection`, typed protocol, Codable values | our own framing on pipes |
| A crash | the connection is interrupted; pending calls fail | EOF on the pipe |
| Sandbox | its own sandbox and entitlements | inherits the app's (`com.apple.security.inherit`) |
| Instances | one per app, shared by every window | one per file is possible |
| Kill on hang | its own watchdog, plus `kill` from the app | `kill` of a child pid |

Every window shares one helper. A file that hangs it therefore costs every open HDF5 file its handle. That is accepted:
- the client opens again on the next call;
- a hang is rare;
- separate processes per file would need the helper tool, which would mean writing our own transport and handling the sandbox inheritance ourselves.

### Messages

The protocol is `HDF5HelperXPC` (in `Core/Data/HDF5HelperProtocol.swift`):

- `open(url, seconds) -> handle | sentence`
- `describePrimaryDataset(handle, seconds) -> JSON | sentence`. This is the datacube `H5Reader` would choose, plus its shape, dtype, chunks and stored rank.
- `close(handle)`
- Later slices add `metadata(handle)` (calibration, voltage, probe candidates) and `readSlab(handle, view, region, seconds)`.

Every reply carries either a value or the reader's own error sentence. Structured values cross as JSON of small Codable
structs, so the helper and the app can never disagree on a type's layout. A handle that the helper does not hold, for
example after a restart, is refused with "Open the file again."

### Frames: shared memory, not messages

Frames can be large. A 4D tile is commonly tens of MB, and XPC copies every message. For slab reads:
1. The app creates an unlinked temporary file in its container, sizes it, and maps it.
2. It passes the helper its `FileHandle` once per open; the helper maps the same file.
3. A slab read writes float32 values into the shared region. The reply carries only the byte count and a generation number.

This keeps one copy, the one libhdf5 makes anyway. `IOSurface` is the alternative if a mapped file shows up in a
profile. Chunked messages are rejected: they would copy each frame twice and add round trips.

### Timeouts and hangs

Each call carries the seconds the helper allows it. The helper runs it under a watchdog that calls `_exit(70)` when
time runs out, because a libhdf5 call cannot be cancelled. The client waits two seconds longer than that. It then
answers `timedOut` itself, sends `SIGKILL` to the helper, and drops the connection. The next call reaches a fresh
process.

Measured in slice 1:
- the watchdog ends a hung helper in 1.0 s at a 1 s limit;
- launchd then starts the helper again no sooner than 10 s after its previous launch, so the first call after a crash may wait that long.

The proposed limits are 30 s for opening and metadata. For reads, the limit grows with the requested size.

This also covers the quit wait. Quitting no longer has to wait for libhdf5: the helper ends with the app.

### Sandbox and entitlements

The helper is sandboxed with no extra entitlements (`HDF5Helper/HDF5Helper.entitlements`). It reads only the files the
app passes to it:
- **Plan:** the file is passed as a `URL` over the connection, and the sandbox extension the app holds goes with the security-scoped URL.
- **Fallback:** if a signed build shows that the extension does not go with the URL, the app passes an open `FileHandle` and the helper opens `/dev/fd/<n>`.

Unit tests run unsigned, so no sandbox applies there. Checking this needs a signed build, which only the owner can make
(below).

### FormatoKit inside the helper

The helper runs the same code the app runs in process: `H5Reader` (DSTEMCore) over FormatoKit's `HDF5Reader` and
`HDF5SlabReader`, under `HDF5Serial`.
- The in-process tests and the helper therefore share one implementation, `HDF5HelperService`.
- The same fixture must give byte-identical results either way (readers are tested exact).
- The protocol and client start in the app (DSTEMCore). The plan moves them to FormatoKit once macTEM adopts them, so both apps share one client. The app copy is then deleted.

The helper links DSTEMCore whole, about 26 MB. Xcode also copies FormatoKit's three libhdf5 frameworks into the
helper's own `Contents/Frameworks`. A later slice slims both: a helper-only target with `H5Reader` and FormatoKit,
and one copy of the frameworks.

### Off by default

The user default `HDF5ReadsInHelper` turns the helper on. It is off until the slices below are done and the owner has
driven a real dataset with it on. Then it becomes the default, and the in-process path stays as the fallback for one
release.

## Slices

1. **The helper target, plus open, describe and close over XPC.** The watchdog, a client that turns a crash or a hang into an error, and the flag. Tests: the in-process protocol over an anonymous listener; the embedded helper crashing; the embedded helper hanging. Nothing in the app calls it yet.
2. **The open path.** With the flag on, `makeReader` opens and describes HDF5 files through the helper, so a file that crashes libhdf5 on open is refused with a sentence. Pixels are still read in process.
3. **Slab reads over shared memory.** `FourDDataSource` gets a helper-backed reader. Tests check byte-identical patterns, rows and tiles against `H5Reader` on the `Fixtures/H5Reader` files, plus a crafted file that crashes or hangs on read.
4. **Metadata and writers.** Calibration, probe candidates and attributes go through the helper. The session sidecar and export writers follow, or stay in process with a stated reason.
5. **Default on, then shared.** After the owner's drive: the flag defaults on; the protocol and client move to FormatoKit for macTEM; the helper target slims.

## What the owner must do

- **Slice 2: a signed build.** Run a signed Develop build with `defaults write com.mac4dstem.mac4DSTEM HDF5ReadsInHelper -bool YES` and open one real `.h5`. This settles whether the sandbox extension goes with the URL.
- **Release packaging.** The release script signs the nested `XPCServices/HDF5Helper.xpc` with the same identity as the app. Check that the helper's own copies of the libhdf5 frameworks pass the release checks; until slice 5, the checks look at `Contents/Frameworks` only.
