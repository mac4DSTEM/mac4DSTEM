# Scope clean-up audit — candidates, 2026-09-25

Owner, 2026-09-25: the app should be "as clean and light weight as possible, simple, robust,
pure macOS and user friendly". This is a read-only inventory (Sonnet Explore agent, `mac4DSTEM/`
and the Xcode project's membership only; `tools/`, tests and docs excluded). **Every row is a
candidate, not a finding.** The caller evidence below is the agent's grep and has not been
re-checked. Verify each before removing it: a build, the unit gate, and for anything in `Core/`
the trigger test in CLAUDE.md. Nothing has been removed. It will be worked through with the
owner in a later session.

| # | Candidate | Where | Lines | Evidence (agent) | Risk | Owner call? |
|---|---|---|---|---|---|---|
| 1 | Unreachable "legacy assembly" branch in `displayedProduct` | `App/AppState.swift:666-721` | 56 | `resultImage`/`resultRGBA` are computed only from `resultPresentation.product`, which the line-668 early return already covers | Low; confirm with a build + coverage | No |
| 2 | Built-in crystal library (Al 4.0495 Å, Au, Ni, Cu, Fe, Si, WS₂) kept as a replay/test resolver | `Core/Crystal/CrystalModel.swift:327-373`, `Crystal.swift:254-260,330-347`; plumbing `AppState.swift:783-787`, `ReplayPlan.swift:524-536`, `ACOMSession.swift:178-184` | ~72 + plumbing | No UI offers it since S5; pre-S5 recipes and tests (`au_fcc`, `ws2_2h`, …) resolve through it | High: breaks replay of pre-S5 recipes and named tests | Yes |
| 3 | `completenessAwareCrossPhaseRanking`, always false, no UI | `Core/Crystal/PhaseVectorMatching.swift:182`, `:826-841` | ~20 | Only tests set it; a parked candidate waiting on a Gate D (`open-items.md`) | Medium: removing forecloses a science decision | Yes |
| 4 | `ResultExport.legacyDomain` for pre-provenance saved products | `Support/ResultExport.swift:900-914` (called `:849,875`) | 15 | Reached only when loading a pre-`display_domain` sidecar | High if old sessions exist on disk (silent fallback) | Yes |
| 5 | Duplicated tiled full-scan orchestration, classical vs learned | `Core/ML/LearnedDiskDetection.swift:167-271` vs `Core/Analysis/TiledDiskDetection.swift` | ~125 | Documented as deliberate (module boundary) | Design choice, not an oversight | Yes |
| 6 | Bundled `disk-detector-heatmap-256.json` that nothing loads | `Models/DiskDetector/` (whole-folder resource, `project.pbxproj:53,206`) | 4 KB | Code names only the `.mlpackage` | Low; ships in every build | No |
| 7–10 | Oversized mixed files (reorganise, not delete) | `BraggVectorEMDWriter.swift` 2606, `ResultExport.swift` 1601, `AppState.swift` 1602, `MapSettings` 1348, `ImagePanes` 1259, `PaneOverlays` 1057, `WorkspaceInspector` 1022 | — | 7–8 are already parked in `open-items.md` (Gate B support owed) | Reorganisation risk; wire format for 7 | 7–8 yes |

**Excluded on purpose:**
- The five separate `median` implementations. Keeping them apart is an owner decision (ADR 015),
  and merging them would be a science change.
- `@AppStorage("ui2.inspectorTab")` (`WorkspaceInspector.swift:50`) and `PhaseSettings.swift`'s
  name. These are renames only, in the Frozen Shell (ADR 035).
- The py4DSTEM-v0.12 compatibility paths in `H5Reader`/`DM4Reader`. These are real file-format
  interop.

**Gate D territory:** rows 2 and 3 sit in `Core/Crystal/`. Deleting row 2 changes what an old
recipe resolves to. Deleting row 3 decides a parked science question by removal.

**Not in this audit, still worth a look in the detailed session:** user-facing surface (menus,
settings and inspector rows that no longer earn their place), the `Package.swift` and target
layout, and the bundled dylibs (`libhdf5`, `libsz`, `libaec`; see the no-rebuild-path item in
`open-items.md`).
