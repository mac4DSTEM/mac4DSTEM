#!/bin/zsh
#
# volume-mmap-probe — S9b's evidence, re-runnable.
#
# `Data(contentsOf:options:.mappedIfSafe)` is a REQUEST. Foundation maps only
# when the mount is `MNT_LOCAL && !MNT_REMOVABLE`; otherwise it silently reads
# the whole file into anonymous memory. `Core/Data/DM4Reader.swift:64` is the
# app's only exposed call site, so a .dm4 on an external disk, a mounted disk
# image (INCLUDING one stored on the internal SSD) or a network share is read
# whole into RAM — the mechanism behind the 8 GB death entry in
# docs/open-items.md.
#
#   run.sh <file>...     probe those files
#   run.sh --mounts      just print the predicate for every mount
#
# Reports phys_footprint (what jetsam kills on), NOT resident_size — this data
# compresses, so resident_size understates the danger by ~5x.
#
# Does not gate: it measures the host, not the app. Any fix to DM4Reader needs
# a fixture built on the free trick this probe demonstrates — a disk image
# created on the INTERNAL disk carries MNT_REMOVABLE, so it reproduces the
# declining case with no external hardware.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir

if [[ "${1:-}" == "--mounts" ]]; then
  printf '%-32s %-8s %-10s %-11s %s\n' MOUNT FS MNT_LOCAL MNT_REMOVE PREDICTED
  cc -x c -o "$TMPDIR/mflags" - <<'C'
#include <sys/param.h>
#include <sys/mount.h>
#include <string.h>
#include <stdio.h>
int main(void){struct statfs*m;int n=getmntinfo(&m,MNT_NOWAIT);
 for(int i=0;i<n;i++){const char*p=m[i].f_mntonname;
  int loc=(m[i].f_flags&MNT_LOCAL)!=0, rem=(m[i].f_flags&MNT_REMOVABLE)!=0;
  if(strncmp(p,"/Volumes",8)&&strcmp(p,"/")&&strcmp(p,"/System/Volumes/Data"))continue;
  printf("%-32s %-8s %-10d %-11d %s\n",p,m[i].f_fstypename,loc,rem,
    (loc&&!rem)?"MAPPED":"DECLINED");}
 return 0;}
C
  "$TMPDIR/mflags"; rm -f "$TMPDIR/mflags"
  exit 0
fi

(( $# > 0 )) || { echo "Usage: run.sh <file>... | --mounts" >&2; exit 64; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -O -o "$WORK/probe" "$HERE/probe.swift"
for f in "$@"; do "$WORK/probe" "$f"; echo; done
