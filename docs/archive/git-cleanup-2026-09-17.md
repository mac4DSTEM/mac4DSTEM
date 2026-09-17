# Git cleanup 2026-09-17 — back to a single `main`

**Rule going forward (owner directive 2026-09-17):** all work happens on `main`; commit directly to `main`; no feature or worktree branches, local or remote. Recorded as a hard rule in `CLAUDE.md`.

Constraints honoured: no push, no force-push, no rebase or rewrite of `main`, tags untouched (`v1.0.0 … v3.0.0`), no builds. Every deletion below was proven merged or superseded first; the evidence is the command quoted.

## Before

```
$ git branch -vv
  ai-analysis               a5bb9f3 [origin/ai-analysis] status-handoff: merge landed, point /pickup at v3.1 (Calibration foundation)
  ai/precipitates-embedding 9b9949b Correct the record: the refuter's website/index.html exists, in the sibling repo
* main                      77ace8b [origin/main: ahead 2] v3.1 R–Q rotation speed: parallelise the grid search and the null (bit-identical)
  ml/disk-detector          f057545 [origin/ml/disk-detector] C6 size session: --size on every entry point, fit_to crop-or-pad, native-frame labels, the overnight 256-px chain
  split/ci-parity-skip      c7ff7a6 CI: the learned-detector parity fixture is a Neural Engine claim, and the runner has none

$ git branch -r
  origin/HEAD -> origin/main
  origin/ai-analysis
  origin/main
  origin/ml/disk-detector

$ git stash list
stash@{0}: On split/ci-parity-skip: !!GitHub_Desktop<split/ci-parity-skip>
stash@{1}: On main: !!GitHub_Desktop<main>
stash@{2}: On ml/disk-detector: !!GitHub_Desktop<ml/disk-detector>
stash@{3}: On s13-q-calibration: !!GitHub_Desktop<s13-q-calibration>
stash@{4}: WIP on main: 15fd49b Update UserInterfaceState.xcuserstate

$ git tag
v1.0.0
v2.0.0
v2.5.0
v2.5.1
v3.0.0

$ git log --oneline -20 --all --graph
* 77ace8b v3.1 R–Q rotation speed: parallelise the grid search and the null (bit-identical)
* 03ca440 v3.1 Friedel speed: precompute the mask FFTs once, parallelise the full-scan loop
* d2f8719 v3.1 item 4: vacuum probe from a separate scan
* a74500f v3.1 item 3: wire the Friedel beamstop-tolerant origin into the app
* ee4f270 v3.1 item 3: port get_beamstop_mask, validated pixel-identical to scipy on the real Au_ref cube
* 6ef135b v3.1 item 3: port get_origin_friedel (beamstop-tolerant origin) + parity harness
* c334b31 v3.1 item 1 finish: D4 count row + step-3 measured on four cubes
* 0d99936 closeout: tighten the validity-mask records; move item-2 diagnostic to the pre-reg doc
* d77e76b status-handoff: item 2 (CoM centre) diagnostic entry point, needs owner data
* c4aae69 v3.1-origin-validity-mask: surface the trim's per-position kept mask (disclosure-only)
* 4fb4cd2 v3.1-preregistration: origin validity mask leads Calibration foundation (disclosure-only)
* a5bb9f3 status-handoff: merge landed, point /pickup at v3.1 (Calibration foundation)
*   ccbbca6 Merge PR #1: AI Analysis room — diffraction grouping and vector-matched phase mapping (unvalidated by design)
|\  
| * 1fc63ca status-handoff: point /pickup at the merge, fold in the py4DSTEM T1 finding
| * ad6d31c py4dstem-t1-comparison: py4DSTEM's own phase method mislabels T1 as Al on the same peaks
| * 190b5e2 t1-origin-experiment: the not-indexed T1 residual is per-peak noise, not origin (Gate D experiment run)
| * 0d3516b parked-item investigations: 4 deviation notes, parallax bin-schedule Gate D, T1 Friedel diagnosis
| * bc334ee real-data-acceptance-run: run truly last, exit 1 recorded honestly (YELLOW)
| * 433c542 braggvector-emd-writer-split: extract the pure data-model types (YELLOW, prepared and parked)
| * b752050 resultexport-split: extract the pure rendering helpers (YELLOW, prepared and parked)

$ git status --short (empty = clean)
```

## Branches

| Branch | ahead / behind `main` | Evidence | Action |
|---|---|---|---|
| `ai-analysis` (also `origin/ai-analysis`) | 0 / 11 | `git branch --merged main` lists it; `git cherry main ai-analysis` empty | deleted locally (`git branch -d`); **remote deletion owed to the owner** |
| `ai/precipitates-embedding` | 0 / 142 | same two checks | deleted locally (`git branch -d`) |
| `split/ci-parity-skip` | 1 / 110 | its one commit `c7ff7a6` is on `main` as `d2aae44` by patch-id (`git cherry main split/ci-parity-skip` → `-`); the added lines absent on `main` are the reworded comment and open-items prose, not the skip logic, as `docs/status.md` already recorded | deleted locally (`git branch -D`, merge proven by patch-id) |
| `ml/disk-detector` (also `origin/ml/disk-detector`) | 27 / 183 | 27 commits by patch-id (`git cherry`). Content audit — every added code line of every commit grepped against `main`'s tree: 22 commits re-landed or superseded by symbol; 5 unique by text (`65fb084 c5489ac 73f5eb5 0a38efc 0cc91de`), each targeting a design retired by a recorded decision (six-workspace AI room; real-space precipitate segmentation, `decisions/019`; `DiskLabelStore`, superseded by `Session/DiskCentreLabels.swift`; the Core AI runtime, replaced by `MLModel` on 2026-09-07); none applies (`git apply --check` conflicts on every substantive file) | **left for the owner** (the session's auto-mode classifier refused the delete): `git branch -D ml/disk-detector`, then the remote step below |

## Stashes

All five were GitHub Desktop auto-stashes or Xcode UI state. Stash commit SHAs are recorded so a dropped stash stays recoverable with `git stash apply <sha>` until git prunes unreachable objects (default two weeks after their date).

| Stash | Content | Evidence | Action |
|---|---|---|---|
| `stash@{0}` `4fee4ef` on `split/ci-parity-skip` | `OriginCalibration.swift` +8 (`FriedelSlots`) | the struct is on `main` at `OriginCalibration.swift:80` (commit `77ace8b`) | dropped |
| `stash@{1}` `4e01995` on `main` | `FriedelOrigin.swift` 65+/50− (`PreparedBeamstop`) | all 41 added code lines present verbatim in `main:FriedelOrigin.swift` (commit `03ca440`) | dropped |
| `stash@{2}` `64ac772` on `ml/disk-detector` | 107 files, all under the gitignored `scratchpad/` (Gate D harness logs from the 2026-09-09 review; three `.fixed`/`patched` Swift copies whose `main` counterparts are supersets or later rewrites) | `git stash show --name-only` → every path under `scratchpad/`; the review's record is `docs/archive/2026-09-09-review/` | **left for the owner** (the session's auto-mode classifier refused the drop): `git stash drop 'stash@{0}'` |
| `stash@{3}` `683d8ca` on `s13-q-calibration` (branch gone) | 2 965 files, all under `.build/` | `git stash show --name-only` → only `.build/` | dropped |
| `stash@{4}` `52d8748` on `main` | `UserInterfaceState.xcuserstate` | Xcode UI state, never wanted | dropped |

## GitHub side (owner)

GitHub already has `main` as the default branch; "automatically delete head branches" is off (read with `gh repo view`). Steps, in order:

1. Push `main` (GitHub Desktop → Push origin). `main` is ahead of `origin/main` by the commits listed under "After".
2. Delete `origin/ai-analysis`: GitHub → Code → Branches → trash icon next to `ai-analysis` (its PR #1 is merged). Or from a terminal with a token: `git push origin --delete ai-analysis`.
3. `git branch -D ml/disk-detector` locally, then delete `origin/ml/disk-detector` the same way (Branches → trash icon, or `git push origin --delete ml/disk-detector`). Its 27 commits carry no work `main` lacks (Branches table above); the audit's per-commit table is in the session log, its conclusions in that table.
4. Optional, so a future PR self-cleans: GitHub → Settings → General → Pull Requests → tick "Automatically delete head branches" (or `gh repo edit --delete-branch-on-merge`).
5. `git stash drop 'stash@{0}'` for the one remaining scratchpad stash, then `git fetch --prune` so the deleted remote branches disappear locally.

## After (local, verified)

```
$ git branch
* main
  ml/disk-detector
$ git branch -r
  origin/HEAD -> origin/main
  origin/ai-analysis
  origin/main
  origin/ml/disk-detector
$ git stash list
stash@{0}: On ml/disk-detector: !!GitHub_Desktop<ml/disk-detector>
$ git log --oneline origin/main..main   # unpushed, plus this record's commit
77ace8b v3.1 R–Q rotation speed: parallelise the grid search and the null (bit-identical)
03ca440 v3.1 Friedel speed: precompute the mask FFTs once, parallelise the full-scan loop
$ git tag
v1.0.0 v2.0.0 v2.5.0 v2.5.1 v3.0.0 
```

Left for the owner: local `ml/disk-detector`, `origin/ai-analysis`, `origin/ml/disk-detector`, one stash. After those, `git branch` shows only `main`, `git branch -r` only `origin/HEAD` and `origin/main`, and `git stash list` is empty.

