---
name: track-b
description: Record or prepare a mac4DSTEM Track B visual-acceptance pass. Use whenever the user reports driving the app — "I drove it", "here are screenshots", "F1.3b passed", "the configurator looks wrong" — or when a session changed what the app draws and rows need writing. Turns findings into checklist updates and open-items entries.
---

# Track B — the human visual pass

Track B is a person driving the app against
`docs/visual-acceptance-checklist.md`. You never run it; you prepare it and
record it. It has beaten the full automated suite repeatedly — which is why
its bookkeeping deserves the same precision as a fixture.

## Asking the owner to launch it — say WHICH build

**Never tell the owner to run `open -a mac4DSTEM`.** It launches whatever is
installed in `/Applications` — the signed release — not the build under test, and
the two silently differ by every commit since the last DMG. Cost the first time
it happened (2026-08-19): a probe was run against the wrong binary and had to be
repeated.

Ask for a **Run from Xcode** (⌘R) instead, or name the built product explicitly:

```sh
open "$(xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2}')/mac4DSTEM.app"
```

And do not hand the owner an unsigned build to launch — `tools/run-tests.sh unit`
is the only place `CODE_SIGNING_ALLOWED=NO` belongs (repo hard rule).

## Recording a pass (the user reports what they saw)

1. Update each driven row: PASSED / FAILED / PARTLY, with the date and the
   dataset. Score what was *looked at*, not what was present — F1.3b was
   once scored PASSED because the dialog appeared, while both preview
   images were blank. Quote the observed detail that justifies the score.
2. Every finding goes to `docs/open-items.md` with date, dataset, and what
   was driven. Findings must not live only in the chat log.
3. NEVER change app code to make a row pass. A blocked row is a finding,
   not a bug to fix inline (standing rule, inherited from the retired QC
   playthrough).

## Preparing a pass (a session changed what the app draws)

1. Write specific rows: the check, the expected result, the known trap
   behind it — the existing §F1 rows are the template.
2. Verify each row against what the build actually does before queuing it.
   The withdrawn F1.1 row asked the owner to watch a phase that cannot run
   by design; a row that can't pass on any dataset spends the scarcest
   resource this project has — the owner's attention.
3. State plainly that the change is unverified on screen until the pass
   comes back, and list which rows block that claim.
