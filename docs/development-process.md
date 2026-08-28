# Development process & conventions

How we work on mac4DSTEM so the project stays clean and ships. Referenced
from `CLAUDE.md`. This is guidance for running sessions — adjust the model
tiers to your preference; the *disciplines* are the part that must hold.

## 1. Keeping docs current (there is no auto-update — this is the discipline)

Files do not update themselves. Treat doc maintenance as part of "done":

- **When a QC task lands:** tick its box in the Status checklist of
  `docs/open-items.md` and note the run folder. Not optional.
- **When the folder structure changes:** update the README structure block
  and the placement table in `CLAUDE.md`.
- **When a doc is superseded or dated:** move it to `docs/archive/` (with
  `git mv`) and repoint links.
- **One fact, one home.** A status/number lives in exactly one file; every
  other doc links to it. (Status lives in the prompts file; CLAUDE.md points
  to it, never restates it.)
- **Closed items leave `docs/open-items.md` immediately** — move the
  narrative to `docs/archive/`, keep one struck line with the date if the
  context matters. Every *live* item opens with one bold sentence so a
  session can triage by skimming. The file is loaded by every session; its
  length is a tax on all of them. *(Adopted 2026-08-18.)*
- **Tag call sites with their item:** when code is touched because of, or
  deferred to, an open item, leave `// OPEN-ITEM #nn` (or the session id,
  e.g. `// v2 S18`) at the site. Grep-able both ways: from the doc to the
  code and back. Adopt going forward; do not sweep retroactively.
  *(Adopted 2026-08-18.)*
- **Harness source lists come from one manifest.** New `tools/` runners
  include `tools/lib/sources.manifest` (created in v2 S2) instead of
  hand-listing app sources; existing runners migrate when next touched.
  Reason: adding one `Core/Data` file silently broke 5 of 8 runners on
  2026-08-17 because the same list was spelled three ways.
  *(Adopted 2026-08-18; the manifest exists as of 2026-08-19, S2.)*
  **It has fixed nothing yet** — only `tools/two-spec-analysis-test` sources it,
  so the eight hand-listing runners are exactly as exposed as before. The policy
  is what closes this, one migration at a time; until then do not cite the
  manifest as coverage.
  The manifest also carries `MAC4DSTEM_ISOLATION_FLAGS` (the app's actor
  isolation), which makes an isolation defect **visible** in a harness build but
  does not gate it — `swiftc` exits 0 on the warning.

## 2. Model & subagent tiers (cheap to scout, high-end to judge)

Match the tool to the job. Do not burn a top model on a file search, and do
not trust a cheap model to sign off on science.

| Job | Subagent / tool | Model |
|-----|-----------------|-------|
| Locate code, "where is X", read-only search, mechanical passes | **Explore** subagent | **Haiku** (cheapest/fastest) |
| Design a change / weigh approaches before coding | **Plan** subagent | **Opus** |
| Implement | main session | **Sonnet** (default) |
| Review a working diff before commit | `/code-review` | **Opus** |
| Adversarial parity review of `Core/` / science changes | direct subagent, prompted to *refute* | **Opus** (Fable 5 for the highest-stakes case) |
| Review a whole branch / final pre-release pass | `/code-review ultra` (ultrareview — cloud multi-agent, billed, you trigger it) | — |
| Security pass before a release | `/security-review` | high-end |
| Tidy the diff (reuse, simplify) | `/simplify` | Sonnet |

Rule of thumb: **Haiku scouts, Sonnet builds, Opus designs & judges; Fable 5 /
ultrareview only for the highest-stakes science change or the final
pre-release pass.** Never let the model that *wrote* a science-affecting
change be the only one that *approves* it.

**Project skills (`.claude/skills/`, added 2026-08-18).** Five slash
commands encode this file's disciplines as invocable actions: `/pickup`
(start the next v2 session), `/diagnose` (Gate D protocol),
`/adversarial-review` (Gate B mechanics), `/track-b` (prepare or record a
visual pass), `/closeout` (end-of-session checklist). Each points at the
docs rather than restating them — the docs stay the single source of truth;
the skills are the triggers. They also auto-suggest on matching phrasing
("I drove the app…", "why does the app…"), which is the point: the
discipline fires even when nobody remembers to ask for it.

**Target review by stakes, not blanket** — evaluation-only work (the QC
tasks: test target + docs, no `mac4DSTEM/` change) needs no premium review;
`/code-review` on Sonnet or a self-check is enough. Reserve Opus review for
real app/`Core/` changes.

- **Science-affecting or `Core/` changes get an adversarial review**: have a
  high-end model *try to refute* that the port still matches py4DSTEM (with a
  parity fixture in `tools/`) before trusting it. A green build is not proof
  of parity.
- A doc cannot force which model an agent runs — set the session model / agent
  definitions accordingly.

**Symmetric test constants are a mutation blind spot (S8, 2026-08-25).** A
suite in which every guard was observed failing under a discriminating
mutation can still be *collectively* blind: S8's display-wiring tests pinned
exactly 90°, where sin·cos = 0, so a wrong angle SIGN and a dropped transpose
each left the entire 15-mutation-verified suite green — three reviewer
mutations survived it that way. Geometry/rotation tests therefore pin
sign-discriminating constants (37.2°, not 90°/0°/45°) and carry an in-test
guard proving the wrong variant actually differs on the fixture; the
adversarial reviewer checks for this class explicitly.

**Structured build feedback (added 2026-08-18).** One MCP server is
registered at user scope in `~/.claude.json`: **XcodeBuildMCP** (pinned
`2.7.0`, npx via Homebrew node, **verified working** — MCP handshake + tools
list, macOS workflow confirmed served). Apple's **`xcrun mcpbridge` was
tried and deregistered the same day**: it answered `initialize` as
`xcode-tools 25245.3` but exposed zero tools to a hand-rolled client *and*
to the real Claude Code client after a restart, with Xcode running. If
headless preview rendering is wanted later, probe XcodeBuildMCP's
`xcode-ide` workflow before re-trying the raw bridge. The server carries
`DEVELOPER_DIR=/Applications/Xcode-beta.app` in its env, so it does not
depend on the system `xcode-select` pointer. **Workflows are selected
per-repo in the checked-in `.xcodebuildmcp/config.yaml`** — `macos`,
`project-discovery`, `utilities`; the server's default is simulator-only,
which is dead weight for a macOS app, and every extra workflow adds tools
that compete for an agent's attention.

When their tools are visible in a session, **prefer them over parsing raw
`xcodebuild` text**: `build_macos` / `build_run_macos` / `test_macos` instead
of Bash `xcodebuild` (typed file/line/severity diagnostics — also the
cheapest way to surface the actor-isolation warning class that only the app
build can see), and mcpbridge's documentation search over WebSearch for Apple
APIs. Without a stated preference an agent drifts back to Bash; this
paragraph is that preference. Known limits and measured facts, recorded so
they are not re-learned: **no visual judgement** (Track B unchanged); the
MCP layer builds into **its own workspace**, so the *first* build is full —
measured 56 s here 2026-08-18 — and later ones are incremental (~3 s), not a
per-build penalty; that first full build is also what surfaced the standing
isolation warnings recorded in `docs/open-items.md` (*Code hygiene*), which
warm incremental builds structurally cannot re-emit; and the `tools/`
harnesses keep their own runners — their output is already structured, the
MCP layer is for the app target and the unit suite.

## 3. Where new work slots into the structure

- **UI-friendliness** → run the Track B visual pass
  (`docs/visual-acceptance-checklist.md`) after a UI change and file friction in
  `docs/open-items.md`. *(Superseded 2026-08-17: this used to point at
  `tools/ui-qc-playthrough/run.sh` as the acceptance test — see §6.)*
- **Feasibility of a big idea (e.g. "is MLX worth it?")** → a *spike* first:
  a Plan subagent + a short `docs/` note weighing cost/benefit. Decide before
  building.
- **A new analysis (including ML/MLX)** → new module under `Core/Analysis`
  (or `Core/Compute` for an engine), validated against a py4DSTEM reference
  with a parity fixture in `tools/`. It must close a `docs/v1-scope.md` gap or
  be explicitly marked post-v1.

## 4. Delivering a clean, finished application

The delivery base already exists — this is about finishing, not building
infrastructure:

- **In place:** hardened + sandboxed Release config, self-contained HDF5,
  `tools/package-test` clean-Release audit, `docs/releasing.md` +
  `docs/distribution.md`.
- **"Finished" =** close the `docs/open-items.md` items + remaining
  `docs/v1-scope.md` gaps → then the release-owner actions (Developer ID
  signing, notarization/stapling, clean-account launch + save/reopen on the
  minimum supported macOS).

## 5. MLX / AI pipelines — feasibility snapshot

For when you take this on:

- **Status:** not in the current app. Prior art exists in
  `References/MigrationSource/Core/Compute/MLXEngine.swift`.
- **Reference to validate against exists:** py4DSTEM's ML disk detection
  `References/py4DSTEM-dev/py4DSTEM/braggvectors/diskdetection_aiml.py`
  (FCU-Net), plus the `FCU-Net_vs_Correlation_*` tutorial.
- **So it's feasible and well-grounded, but a real new workstream:** add the
  MLX dependency + an ML disk-detection (or strain) module + a parity fixture
  comparing it to the correlation method on a known dataset.
- **Do the §3 feasibility spike first**, and treat it as post-v1 unless it
  closes a v1 gap. ML that can't beat the validated correlation path on your
  data is not a delivery blocker.

---

## 6. Verification runs in two tracks (decided 2026-08-17)

The core finding of the v1.0 endgame: **the numeric suite and the human eye
catch disjoint classes of defect**, and the repo used to pretend the automation
covered both. It never did — see `docs/v2-scope.md` §6.2 for the evidence.

### Track A — numeric regression, headless, automated

`tools/run-tests.sh` and nothing else. Exact numbers, py4DSTEM parity, and
catching a change that moves a value it should not. This is what the automation
is genuinely good at, and it stays the gate for every `Core/` change.

### Track B — visual acceptance, human, checklist-driven

[`docs/visual-acceptance-checklist.md`](visual-acceptance-checklist.md). Run it
for **any change to what the app draws or where a control lives**, before any
tag, and after any macOS bump. The assistant writes the specific checklist; the
release owner drives the app once and sends screenshots; findings go to
`docs/open-items.md`. Ten to fifteen minutes, and it has beaten the full suite
twice on its own terms.

### The XCUITest QC playthrough is retired

`mac4DSTEMUITests/` + `tools/ui-qc-playthrough/` are **no longer the acceptance
test** and no longer maintained. It never produced a screenshot, never touched
a disk-detection control, recorded peak counts without judging them, could read
a stale count, and needed a Screen Recording grant it never had.

The code stays in the tree for now — deleting it is a separate call, tracked in
`docs/open-items.md`. **Do not spend a session repairing it.** Its eval-only
rule carries over to Track B unchanged: never modify app logic to make an
acceptance step pass; that is a *finding*, not a bug fix.

---

## 7. The `AppState` rule (binding from 2026-08-17)

**Every L-stage that touches `AppState` extracts one seam before it lands, at a
green test boundary.** Six stages, six extractions, no big-bang refactor. As an
aspiration this lost to every deadline in v1; as a per-stage cost it ships.

**What counts as an extraction.** A responsibility moved out **with its own
state**, behind a narrow interface — the shape of `AnalysisOperationController`
in `Core/Workflow/`. Splitting the file into `extension AppState { }` across
several files is **not** an extraction: same object, same mutable surface, every
method still able to touch every property. `ROADMAP.md` P3.2 bans it.

**The extracted type is itself `@Observable` and `AppState` holds it.** View
code changes at each extraction; that is the cost, and it is the point — thin
forwarding properties would preserve the view API while keeping the property
that caused the problem.

**Do not rank the seams by MARK section.** That was the plan on 2026-08-17
morning and the code refuted it the same afternoon: **172 of ~188 stored
properties live *before* the first `MARK`**, in the unmarked facade. The MARK
sections are where the *behaviour* is. `Fit-verification overlays` — the seam
this table used to name first, at 115 lines — owns **no state at all**: all six
members are pure projections of `calibration`, `descriptor`, `selectedScan`,
`strainMap` and `orientationMap`, so there is nothing for an `@Observable` type
to hold. `DPC` is the same. Ranking by section length measures method bulk and
finds seams that cannot be extracted as described.

**Rank by state ownership instead**, and prefer the cheapest true seam
available to the stage in hand:

1. **State the stage is *adding* goes into its own type from the start.** This
   is free — the alternative is adding to the facade and then extracting
   something unrelated to pay the same debt. **Precedent: L2's
   `App/DatasetResidency.swift`** (2026-08-17), which owns the residency mode,
   the resident flag and byte count, and the preload's progress, and which
   `AppState` holds with **no forwarding properties**.
2. **Then a cohesive group of facade properties**, moved with the methods that
   mutate them. Identify candidates by grepping stored properties in
   `AppState.swift` lines 1–1932, not by MARK.
3. **Calibration last, and not before L6.** It owns `calibration` +
   `provenance`, which everything reads.

---

## 8. Dataset policy (decided 2026-08-17)

| Dataset | Role |
|---|---|
| `sim_Au_data_all_binned` | **Primary** — simulated, known answer, the parity anchor |
| `downsample_Si_SiGe_exp` | **Primary** — experimental, where the real problems live (#46, #29, #18) |
| `Particle_1…bin8` | On demand — repeats Si_SiGe's failure mode at a different probe radius (≈10.6 px) |
| `polycrystal_2D_WS2` | On demand — cannot reach ACOM without a WS₂ model (#11) |

A coverage argument, not a speed one: one clean simulated case and one hard
experimental case cover the two failure modes that matter. Run the other two
when a change plausibly touches what makes them different.

## 9. What keeps a session agent-runnable (added 2026-08-28, S12)

**Most blockers here are access, not judgement.** On 2026-08-28 four of the
five live rows were owner-gated, and only one of them was gated on a
*decision* — the rest were waiting on a grant, a mounted disk or a file that
was not attached. A one-time setup converts a whole class of owner-only work
into work an agent can run while you do something else, so it is worth
separating the three kinds of block.

**One-time grants — do once, unblock a class.**

| Grant | What it unblocks | State on 2026-08-28 |
|---|---|---|
| **Full Disk Access** for the terminal running the agent | Reading `~/Library/Containers/`. Every sidecar, sandbox and TCC diagnosis is currently handed back to you as a one-line command to run and paste — the agent cannot see the container at all | **Not granted.** TCC blocks it even with the app sandbox off |
| Screen Recording + Accessibility | Track B rows written, driven *and* scored by the agent (TB1 sitting 1, S18's F1.32/F1.34) | Granted — but **re-grant after every Claude Code update**, it silently stops working |

**Standing data availability — leave it attached, not just for one run.**

| Thing | What it unblocks | State on 2026-08-28 |
|---|---|---|
| The NAS mounted | **S9b**'s NAS arm. Without both arms there is no discriminator, so the whole diagnosis waits | Mounted on demand only |
| The 17 GB DM4 on an attached external SSD | S9b's local arm — a real filesystem, so `mmap` behaves as it does locally — *and* it removes the disk constraint that has blocked this row | Not attached |
| One multi-GB cube reachable locally | TB1 sitting 3, and any real full-extent promote run | Largest local cube is 1.3 GB |
| **≥ 20 GB free on the boot disk** | The S0 preflight refuses below 8 GB and has refused in four sessions (S4, S8, TB1 s1, and one M1 near-miss) | 11–12 GB — one build away from refusing |

**Genuinely owner-only — do not route around these.**

- **The clean-account run** (TB1 sitting 4). The agent cannot create a macOS
  account and cannot drive an app in another user's session. Resetting the
  container in this account is *not* a substitute: the clean-account run has
  caught three defects a reset could not.
- **Signing, notarization, the tag** (S20), and `/code-review ultra` — billed
  and user-triggered.
- Every decision the release plan marks as yours (`docs/v2-release.md` §8's
  owner-decision list).

**Decisions block differently from access.** A decision costs you minutes and
unblocks one session; a grant costs you one setup and unblocks a class. Both are
worth clearing, but a decision left sitting is the more expensive of the two,
because nothing else can be substituted for it. Keep the decision queue short.

**When a session is part-gated, split it — do not wait.** S9's split into
**S9a** (needs no NAS and no spare disk; ran immediately) and **S9b** (keeps
the local-vs-NAS diagnosis; still waiting) is the model, and the split is what
let the guard ship months before the diagnosis it does not replace. State
plainly which half ran and which is still owed, and never let the half that
ran be written up as closing the half that did not.
