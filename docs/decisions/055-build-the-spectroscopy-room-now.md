# 055 — Build the Spectroscopy room now, against the accepted mock and a simulated 4D-STEM + EDX dataset

Dates: 2026-10-05

Status: **accepted** (owner, 2026-10-05). It amends the CLAUDE.md rule "Drive before more surface" for this room, and
builds on ADR 052–054.

## Decision

1. **The structure is accepted.** Mock v3 (`docs/archive/v5/spectroscopy-mock-2026-10-05/`, screens 1–4) is the
   room's structure. Owner: "we will make changes on the go, we will start with the build now."
   - Narrow windows: below about 760 pt of content, the results table stacks under the map, and the spectrum header's
     toggles fold into one "Show" menu.
   - "Map shows" (net counts / at%) sits in the map pane's header, as Velox does.
   - The frozen-shell files (ADR 035) may change for the seventh room against this picture.
2. **"Unverified on screen" does not block this room** (owner: "it doesn't touch the Replace clicks nor Train Model …
   this can be done later as well"). Those two rows stay open and are still owed. The rule in CLAUDE.md is changed here,
   not worked around, as "Rules serve the app" requires.
3. **A simulated 4D-STEM + EDX dataset** unlocks the development plan before the owner's joint GMS run exists.
   - It follows the measured and published file structure (`docs/archive/v5/4d-edx-file-structure-2026-10-05.md`).
   - It is built on the existing demo cube's recipes (`tools/demo-dataset/`), with a known per-phase composition as
     truth.
   - It is written both as a GMS-style multi-object `.dm4` and as a HyperSpy-style `.hspy` pair. The two public real
     pairs (figshare 10.48420/21610977, Zenodo 8000141; CC BY 4.0) serve as checks later.
   - The owner's real Velox files (`References/EDX/`) are the real-data test set for the spectrum-image-only path.
4. **No more questions this round** (owner). The session decides, records the decision, and the owner overrules on
   sight.

## Consequences

- Work package 2 is pre-registered in `docs/archive/v5/wp2-room-and-simulator-preregistration-2026-10-05.md`.
- Every guess in the simulated file's layout is listed, and the first real GMS joint file corrects it. A failed
  reproduction gate on the real file opens a new item (ADR 050).
