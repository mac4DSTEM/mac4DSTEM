# Lane D probe: a DM4 on a disk that is force-ejected (Slot 4⅞, 2026-10-04)

What it shows, on macOS 27.0.1, with a 64 MB RAM disk (`hdiutil attach -nomount ram://131072`, HFS+ volume
`mac4dstemD`, a 32 MB synthetic int16 DM4) and `hdiutil detach -force`:

| reader | after the force-detach | after a same-name remount with the file copied back |
|---|---|---|
| HEAD (a841f9ae) | readPattern dies, exit status 138 (SIGBUS), for an untouched page AND for the page read before the yank | still dies (138): the old mapping stays dead |
| guarded (held descriptor + latch) | THREW "cube.dm4 is no longer reachable: its disk was disconnected. Reconnect it and reopen." (exit 0) | still THREW, also when no read ran while the disk was gone |

Candidate liveness checks (logs/remount.log): `statfs(path)` / `stat(path)` fail after the yank and PASS again after the
remount with the identical f_fsid / st_dev / st_ino, so they cannot see the replug; a descriptor opened before the yank fails
for good (`fstat` EBADF, `fstatfs` ENOTSUP, `pread` EIO) before and after the remount. The reader keeps such a descriptor and latches
the first failure.

Not measured: a real cable yank; the window between the media vanishing and the unmount completing (a read in flight can still crash).

Run: `build-probe.sh <DM4Reader.swift> <out>`, then `drive.sh <out> <scenario> <logdir>` with scenario one of
crash-last | crash-first | remount | remount-nocheck (HEAD reader) or guard-yank | guard-remount | guard-remount-nocheck (guarded reader).
`drive.sh` creates and detaches only its own RAM disks. `probe <bin> hash <file>` prints an FNV-1a hash of the pixels the reader serves
(logs/hash-*.txt: identical for HEAD and guarded).

## Re-run condition (the real probe is unit-blind)

`FinalPolishDTests` drives the reader through an injected check and cannot see the real one. The independent refuter swapped
`fstat` for `fcntl(F_GETFD)` in `DM4Reader.HeldDescriptor.answers`: all 11 unit tests (then) stayed green and the RAM-disk probe
still died with status 138 after the yank (`refuter/exp/E9-hfs-yank-m11.log`). So this folder's `drive.sh` is the only check of
that probe: re-run it after ANY change to `MappingLiveness` / `HeldDescriptor` in `DM4Reader.swift` (HEAD scenarios must die 138,
guarded scenarios must THROW and exit 0). Two things to know before re-running:

- exFAT volume names are at most 11 characters (`diskutil erasevolume ExFAT mac4dstemDref` is refused; the refuter used
  `M4DREF`). `refuter/refdrive.sh` takes the volume name from `VOLNAME` and the file system as its second argument.
- `hdiutil attach -nomount ram://...` prints macOS 27's deprecation warning ("Please use 'diskutil image attach ...'
  instead"); the replacement is `diskutil image attach --noMount ram://<sectors>`. The scripts here still use the old verb,
  which worked on 27.0.1 for every run recorded.

## Independent re-run (refuter, 2026-10-04, `refuter/`)

`refuter/refuter.md` is the verdict; `refuter/exp/E*.log` are the runs, one RAM disk each, detached by the script. Result: HEAD
(a841f9ae) dies with status 138 in all six HEAD runs; the guarded reader THROWS the owner's sentence and exits 0 in all six
guarded runs.

| file system | HEAD, `hdiutil detach -force` | guarded, `hdiutil detach -force` | guarded, force unmount then `diskutil mount` of the same device |
|---|---|---|---|
| HFS+ | 138 (E1) | threw, 0 (E2) | threw, 0 (E11; HEAD 138, E12) |
| APFS | 138 (E8) | threw, 0 (E7) | not run |
| exFAT (FSKit-served on 27.0.1, still `MNT_LOCAL`, so the file is mapped) | 138 (E3) | threw, 0 (E4) | threw, 0, same inode back, descriptor still dead (E5; HEAD 138, E6) |

`diskutil eject force` on HFS+ (E10) also threw and exited 0. A soft `diskutil unmount` is refused for HEAD and guarded alike (the
mapping already pins the volume). The logs name the scratchpad path of the probe binaries as `<scratchpad>`; nothing else is edited.
The refuter's own `diskutil list` before/after files are not archived.
`refuter/refuter.md` cites its session scratchpad as `$SP`; the runs it names are the `refuter/exp/` files here.
