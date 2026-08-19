# S1 — the session sidecar under the sandbox

**History, not guidance.** Archived 2026-08-19 when S1 closed; moved out of
`docs/open-items.md` under the §1 discipline (closed items leave that file
immediately — it is loaded by every session and its length taxes all of them).

This is the full investigation: five hypotheses, two of them refuted by review,
the pre-registration written before its answer was known, and the denial finally
observed in the running app. Kept because the *method* is the valuable part —
particularly the pre-registration, and the Gate B correction to
`tools/sidecar-error-detail-test` that stopped the diagnosis being sent the
wrong way by one wrong errno.

What shipped is recorded in `docs/v2-release.md` §9 under S1. What is still open
stayed in `docs/open-items.md`: the concurrent-HDF5 crash, the fabricated
provenance on pre-2026-08-18 sidecars, and the status-line path leak.

---

- **A session sidecar that provably opens fine can still fail to restore.**
  Seen 2026-08-18 opening `downsample_Si_SiGe_exp.h5` from
  `References/training_dataset/`: `Could not restore
  downsample_Si_SiGe_exp.mac4dstem.h5: HDF5 export failed while opening the
  session sidecar` (`AppState.loadSessionSnapshot`, the `.hdf5("opening the
  session sidecar")` case in `BraggVectorEMDWriter.WriterError`, thrown when
  `H5Fopen` itself returns negative). The sidecar is not corrupt — `h5ls -r`
  round-trips its whole tree (calibration, a Bragg-vector result, a strain
  result) with exit 0, and it is a real 2026-08-07 session, not a stray file.
  **The first hypothesis recorded here was a concurrency race. A review agent
  refuted its causal claim on 2026-08-18** — a third instance of this repo's
  documented failure mode, and the reason the rule is *review the diagnosis, not
  just the code*.

  **What survived the review.** The bundled library really is unsafe — its
  embedded `H5build_settings` reads HDF5 2.1.1, `Threadsafety: OFF` — and the two
  loaders really do share one instance: both `dlopen` the identical
  `Bundle.main.privateFrameworksURL/libhdf5.dylib` with `RTLD_LOCAL`
  (`H5Reader.swift:137,216` and the writer's matching `candidateLibraryPaths()`),
  so dyld returns one refcounted image with one copy of the globals.

  **What was refuted: the race window does not exist on the path where the
  failure was seen.** `activate` awaits `loadSessionSnapshot`
  (`AppState.swift:2134`) *before* `loadCurrentPattern` (`:2135`),
  `buildDatasetPreview` (`:2149`) and `preloadResidentCube` (`:2150`). Preview
  sampling runs fifteen lines later, not concurrently; the calibration read has
  already returned. The `Task.detached` at `AppState.swift:2324` moves the open
  off the actor but its `.value` is awaited with no second HDF5 call in flight.
  (A genuine concurrent window does exist elsewhere — a previous dataset's
  `preloadResidentCube` is not cancelled when a new open starts, and
  `datasetEpoch` guards state updates rather than in-flight work — but that is a
  different window and not the reported situation.)

  **The hypothesis that fits every observed fact better: the sandbox, and a
  stale bookmark.** The app is sandboxed with only
  `com.apple.security.files.user-selected.read-write`
  (`mac4DSTEM/mac4DSTEM.entitlements`); `h5ls` succeeds because Terminal is not
  sandboxed. The *source* file was picked in a panel; the **sidecar is a sibling
  the user never picked**, reachable only through a security-scoped bookmark
  keyed on the absolute source path (`Support/ResultExport.swift:136-139`).
  **This repo moved into `mac4DSTEM_Organization/`, so every bookmark keyed on an
  old absolute path is now stale.** That predicts the exact observed shape:
  `FileManager.fileExists` passes (`AppState.swift:2321`,
  `BraggVectorEMDWriter.swift:491`) because the sandbox grants
  `file-read-metadata` far more broadly than `file-read-data`, and then `H5Fopen`
  returns negative on `EACCES` (`BraggVectorEMDWriter.swift:498`).

  **A confirmed bug either way, and it is why this was undiagnosable:**
  `H5Reader.swift:164-166` calls `H5Eset_auto2(H5E_DEFAULT, nil, nil)`, which —
  because the instance is shared — silences HDF5's error stack **process-wide,
  including for `BraggVectorEMDWriter`, which never opts in**. The one line that
  would distinguish "Permission denied" from "unable to lock file" is suppressed.
  Fix this regardless of which hypothesis wins.

  **The experiment that decides it costs one minute: open the same file three
  times from a cold launch.** A sandbox denial is deterministic, a race is not.
  Three failures ⇒ bookmark/sandbox; roughly one in three ⇒ the race is live and
  *then* build the hammer fixture. **Do not write threading code before running
  this.**

  **S1, 2026-08-18/19 — the instrument is built; the experiment has NOT been
  run.** Gate D was entered from the top rather than from this entry, and the
  independent diagnosis converged on the same hypothesis. What changed:

  - **The error now says why.** `HDF5WriteLibrary.currentErrorStack()` reads the
    error stack with `H5Eprint2` into an `open_memstream` and keeps the innermost
    frame plus its minor code; `hdf5Failure(_:_:)` attaches it. Turning the
    automatic printer off never cleared the stack — the reason was always
    retrievable and simply unread, so **no silencing had to be removed** and
    discovery-time probing stays as quiet as before. Applied to the six sidecar
    **read** throw sites only (`loadSession`, `loadResultMap(id:)`,
    `loadRGBAResultMap(id:)`); the other 62 `WriterError.hdf5` sites are
    untouched and belong to S7's `try?`/error-honesty sweep.
  - **The message no longer claims an export.** `.hdf5` rendered as *"HDF5
    export failed while …"* on a read path — the owner was told an export failed
    during an open. Now *"HDF5 failed while …"*. **The string quoted in F1.3f and
    in `docs/load-pipeline-plan.md` is therefore historical**; a current build
    prints the new wording followed by `— HDF5 reported: …`.
  - **Fixture: `tools/sidecar-error-detail-test`** (in `scientific`). Runs the
    format failure against two denial shapes, each in both orders (a stale stack
    cannot masquerade as a fresh one) and each both before and after installing
    `H5Eset_auto2(H5E_DEFAULT, nil, nil)` — the app's actual condition and the
    round that matters. Verified by breaking it: with the capture returning nil,
    20 assertions go red and every case collapses to the identical pre-S1
    sentence.

    **The first version of this fixture was wrong in the way this repo keeps
    getting caught, and the Gate D second reader found it (2026-08-19).** It used
    a `chmod 000` file as "the direct analogue of the sandbox denial" and
    asserted `errno = 13 / Permission denied`. **Measured: a sandbox denial is
    `errno = 1 … 'Operation not permitted'` (EPERM); `chmod 000` is `errno = 13`
    (EACCES).** The fixture would have gone red on the one case it existed to
    cover, and the Track B row derived from it told the observer that
    `Permission denied` meant "sandbox" — which would have made them rule the
    sandbox OUT on the single run that decides S1. Now the denial case runs under
    `sandbox-exec` and the POSIX case is kept separately, never as a stand-in.
    Two further traps found while fixing it, both of which made the case pass or
    fail for the wrong reason: the denied file must be a **real** HDF5 file (an
    8-byte signature stub makes HDF5 report `bad byte number in an address`
    before it reports the refusal), and the profile must name the **resolved**
    path (`$WORK` is `/var/folders/…`, the kernel matches `/private/var/…`, and a
    `literal` rule against the unresolved form silently matches nothing).
  - **A truncated or corrupt sidecar (H4) is dead**, re-confirmed independently:
    both sidecars in `References/training_dataset/` open cleanly under `h5py`
    (and `h5ls -r`, `h5dump -n`, `h5stat`), complete trees. Neither carries the
    `mac4dstem_load_specification` attribute — **but "they are full-extent
    sessions" does NOT follow, and saying so was wrong.** The attribute was
    introduced 2026-08-18 in `4e01c24` (L6) and both files were written
    2026-08-07 and 2026-08-14; the writer that produced them could not emit it,
    so their specification is **unknown, not full-extent**. The
    `mac4dstem_session_schema` stamp is `"5"` in both but has been `"5"` since
    2026-07-16 (`e184404`), so it does not discriminate either. The operational
    conclusion survives and is stronger: *these two files cannot exercise
    F1.3f's crop path*, and F1.3f needs a sidecar saved from a cropped view.
  - **The race (H5) stays refuted**, on the reasoning already recorded above.

  **The next action is a datum, not code, and it is cheaper than the three cold
  opens.** The stale-bookmark hypothesis is decidable by reading one preferences
  domain: keys are `session-sidecar-bookmark.` + base64 of the **absolute source
  path** (`Support/ResultExport.swift:136-139`). If a key exists for the old
  pre-move path and none for the `mac4DSTEM_Organization/` path, the hypothesis
  is confirmed without launching anything. The agent's shell cannot read it —
  TCC protects app containers even with its sandbox disabled — so the release
  owner runs:

  ```sh
  defaults read com.mac4dstem.mac4DSTEM | grep -o 'session-sidecar-bookmark\.[A-Za-z0-9+/=]*' \
    | sed 's/session-sidecar-bookmark\.//' | while read k; do echo "$k" | base64 -d; echo; done
  ```

  Then, and only then, the three cold opens — now worth running, because the
  message finally carries `Permission denied` / `file signature not found` /
  `unable to lock file` instead of the same sentence in every case.

  **C10 — the operative cause, established 2026-08-19 and confirmed by the
  second reader.** Not the repo move. Commit `1e5727d` (2026-08-14 16:36)
  changed `PRODUCT_BUNDLE_IDENTIFIER` from `com.paullobpreis.mac4DSTEM` to
  `com.mac4dstem.mac4DSTEM`. **The identifier keys the sandbox container**, so
  the app got a new, empty one — and therefore empty `UserDefaults`, so
  `resolvedSessionSidecarURL` returns nil for every dataset at every path.
  Read directly out of the old container, which is still on disk:

      ~/Library/Containers/com.paullobpreis.mac4DSTEM/.../com.paullobpreis.mac4DSTEM.plist
      session-sidecar-bookmark.<base64> -> /Users/paullobpreis/GitHub/mac4DSTEM/References/training_dataset/downsample_Si_SiGe_exp.h5
      session-sidecar-bookmark.<base64> -> /Users/paullobpreis/GitHub/mac4DSTEM/References/training_dataset/sim_Au_data_all_binned.h5

  Exactly the two affected datasets, keyed by absolute source path, in the OLD
  container and at the OLD path — over-determined, either alone sufficient.
  `WorkspaceRecovery` also uses `UserDefaults.standard`, so no bookmark store
  survives. **The repo-move explanation should be struck, not demoted:** the new
  container was created 2026-08-15 00:47, after the move, so nothing was ever
  bookmarked under the new identifier at any path.

  **Still not observed: the denial itself.** With no bookmark the code falls back
  to the derived sibling path, and that read is *inferred* to be refused. The
  sandbox asymmetry it depends on is real and measured — `application.sb:508`
  carries a blanket `(allow file-read-metadata)`, and under `sandbox-exec` with
  the bundled libhdf5, `fileExists` returns true while `H5Fopen` returns -1 — but
  nobody has watched the app be denied. **One cold open now settles it, and its
  value is the reason string, not the count of three.**

  **A cheaper discriminator than the cold open, pre-registered 2026-08-19
  BEFORE its answer was known.** The release owner was asked to open a dataset
  and save a session, and to report whether a save panel appeared. The answer
  did not reach the session (the reply carried the unfilled template), so the
  branches are written down here first — the point of pre-registration is that
  neither outcome can be retrofitted into the diagnosis after the fact.

  Why this probe is decisive and costs less than three cold opens:
  `writableSessionSidecarURL` (`Support/ResultExport.swift:106-108`) shows an
  `NSSavePanel` **only** when `resolvedSessionSidecarURL` returns nil, and that
  function returns nil exactly when the cache is cold *and* no bookmark is in
  `UserDefaults` (`:81-84`). The panel is therefore a direct, user-visible
  readout of the one predicate C10 asserts.

  | Observation | Reads out | Consequence for C10 |
  |---|---|---|
  | **A save panel appeared** | `resolvedSessionSidecarURL` returned nil ⇒ no bookmark under the current identifier | C10 **confirmed** on the save path. The restore failure is the no-bookmark fallback, and S1's fix proceeds as diagnosed. Still not observed: the denial reason string on the fallback read — a cold open is then worth one run for the reason, not the count. |
  | **It saved silently, no panel** | A bookmark resolved, or the cache was warm within the session | C10's central claim — "`resolvedSessionSidecarURL` returns nil for every dataset at every path" — is **refuted**, and the empty-container reasoning does not by itself explain the restore failure. No fix lands; the diagnosis reopens, and the next question is which store survived the identifier change. **Caveat that must not be skipped:** a *second* save in the same app session is silent either way, because `scopedSessionSidecarURL` is cached in memory (`:80`). Only the **first** save after a cold launch reads out the bookmark store. |

  Neither branch licenses touching `recordedLoadSpecification` yet — under
  Gate D a fix may land only on a link that survived its own refutation test,
  and this link has not yet been observed either way.

  **ANSWERED 2026-08-19, branch A — and it is weaker evidence than the
  pre-registration assumed.** The release owner ran it on an Xcode build
  (`open -a` launches the installed release, not the build under test — a
  separate lesson, now in the `track-b` skill). The panel appeared: title
  *"Choose Session Sidecar"*, message *"Choose the companion file mac4DSTEM may
  update and reopen"*, i.e. `writableSessionSidecarURL`
  (`Support/ResultExport.swift:106-115`) took its `NSSavePanel` branch, so
  `resolvedSessionSidecarURL` returned nil. First save of that launch, so the
  in-memory cache caveat does not apply. Cancelled, so nothing was written
  (`09:26:50 Session sidecar save cancelled`).

  **Why it discriminates less than intended, said plainly rather than glossed:**
  the dataset driven was `calibrationData_bullseyeProbe.h5`, and the bookmark key
  is base64 of the **absolute source path** (`ResultExport.swift:136-139`). That
  file appears in no bookmark under *either* bundle identifier — the old
  container held keys for exactly two files, `downsample_Si_SiGe_exp.h5` and
  `sim_Au_data_all_binned.h5`, both at their pre-move paths. So a panel is what
  you would see whether C10 is true or false, and this run **confirms the
  predicate** (`resolvedSessionSidecarURL` returns nil here) **without testing
  the cause**. The cause still rests entirely on the plist read, which is
  unchanged and still good evidence. What is new is that the predicate has now
  been observed in the running app rather than only inferred.

  **And the link S1's fix actually turns on remains unobserved: the denial.**
  Nobody has yet watched the fallback read of the derived sibling path be
  refused. That matters because it selects the fix: if the fallback read is
  refused, the fix is about scoped access; if it would succeed, the restore
  failure has another cause and `recordedLoadSpecification` reading the derived
  path is fine as it stands. Gate D does not let a fix land on that.

  **The one experiment that settles it, and it pays twice.** Save the sidecar for
  the currently loaded *cropped* view — `calibrationData_bullseyeProbe.h5`,
  scan rows 24–99 / columns 12–59, detector rows 76–120 / columns 37–91 — then
  quit, relaunch cold, and reopen that file.
  - Restores correctly ⇒ the whole C10 chain is confirmed end to end, because the
    only thing that changed is that a bookmark now exists.
  - Fails ⇒ the message now carries `— HDF5 reported: …` (S1's first half), and
    that string **is** the denial nobody has seen.

  Either way the saved sidecar is the artefact **F1.3f has been blocked on**: a
  sidecar written from a cropped view, which neither file in
  `References/training_dataset/` can provide (both predate the
  `mac4dstem_load_specification` attribute). Opening one of those two training
  datasets is the other route to the denial string, since each has a sidecar
  sibling on disk and no bookmark under the current identifier.

  ---

  ## C10 IS CONFIRMED END TO END — the denial was observed 2026-08-19, 09:34:27

  The release owner took the second route, opening `sim_Au_data_all_binned.h5`
  (cropped, binned 2x) on an Xcode build. The app logged, verbatim:

      Could not restore sim_Au_data_all_binned.mac4dstem.h5: HDF5 failed while
      opening the session sidecar — HDF5 reported: unable to open file: name =
      '/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/
      training_dataset/sim_Au_data_all_binned.mac4dstem.h5', errno = 1,
      error message = 'Operation not permitted', flags = 0, o_flags = 0

  **`errno = 1` / `Operation not permitted` is EPERM**, and
  `tools/sidecar-error-detail-test` pins exactly that marker
  (`let deniedMarker = mode == .posix ? "errno = 13" : "errno = 1,"`). Every link
  of C10 is now observed rather than inferred:

  1. bundle-identifier change emptied the container — plist read, 2026-08-19;
  2. no bookmark resolves — the save panel appeared, 09:26;
  3. the code falls back to the derived sibling path — the error names that exact
     path, `<source>.mac4dstem.h5` beside the cube;
  4. **that read is refused by the sandbox** — EPERM, 09:34:27.

  **The step-4 inference stated correctly, because the first version of it was
  affirming the consequent** (Gate D, 2026-08-19). The fixture establishes
  *sandbox denial ⇒ EPERM*, not the converse; calling EPERM "the sandbox
  signature" claims a biconditional nobody proved. What licenses the conclusion
  is that EPERM is a kernel MAC-policy refusal and every other MAC policy was
  excluded **on this path, individually**: no SIP, no TCC location, no ACLs
  (`ls -le` clean on both sidecars), no `uchg`/`schg` flags, mode 644 owned by
  the user (which would give EACCES anyway), and not HDF5's lock path — the
  message is libhdf5's `open(2)` format string with `o_flags = 0`, not `unable to
  lock file`. Quarantine was the one real confound and is also excluded: both
  sidecars carry `com.apple.quarantine 0082;…;mac4DSTEM`, but the *source* cube
  carries `0083;…;Safari` and **was read successfully in the same directory at
  the same instant** — which also kills every folder-, volume- and mount-level
  explanation at once. With those gone the sandbox is the only MAC policy left.
  That is a sound argument; "EPERM means sandbox" is not, and the difference
  matters the next time someone sees EPERM somewhere else.

  It also confirms the `fileExists` / `H5Fopen` asymmetry the hypothesis rested
  on: the sidecar was *found* (the code reached `H5Fopen` and named the file) and
  then *refused*, which is `file-read-metadata` allowed where `file-read-data` is
  not, precisely as predicted from `application.sb:508`.

  **The Gate B correction to that fixture is what saved this conclusion.** The
  first version asserted `errno = 13` / `Permission denied` (a `chmod 000`
  stand-in). Had it shipped, the derived Track B row would have told the observer
  that "Permission denied" means sandbox — and on seeing *"Operation not
  permitted"* they would have ruled the sandbox **out**, which is the wrong
  answer. The refutation on 2026-08-19 changed the outcome of the very experiment
  the fixture existed to support.

  **The 09:34:27 sidecar no longer exists, and the record has to say so.**
  `References/training_dataset/sim_Au_data_all_binned.mac4dstem.h5` now has
  btime == mtime == **2026-08-19 09:35:21**, 54 seconds after the denial, 2.69 MB
  — a newly written file, almost certainly the save the pre-registration asked
  for. Three consequences, none of them optional to record (Gate D, 2026-08-19):
  (a) the artefact the denial was observed against is gone, so that exact
  experiment is **not reproducible** — the log line above is now the whole of the
  evidence; (b) a bookmark for that dataset very likely exists under the current
  identifier, so C10's link 2 is **false for `sim_Au` going forward** and the
  only clean un-bookmarked reproducer left is `downsample_Si_SiGe_exp.h5` (its
  sidecar untouched since 2026-08-07, 6.38 MB); (c) the 2026-08-14 sim_Au session
  may have been overwritten — one of the two artefacts C10's plist evidence names,
  and one of the two candidates for the fabricated-provenance question below.

  **S1's fix is therefore unblocked under Gate D**, and the diagnosis it may land
  on is: `recordedLoadSpecification` (`AppState.swift:1416-1431`) reads the
  sidecar through the derived path only, never through `resolvedSessionSidecarURL`,
  so it cannot benefit from a bookmark even when one exists. Note the armed
  hazard recorded below before touching it — `resolvedSessionSidecarURL` ignores
  its `descriptor` when the cache is warm (`ResultExport.swift:81`), which
  "arms itself the moment one does" resolve.


---

## Closed alongside it

  - ~~**`resolvedSessionSidecarURL` ignores its `descriptor` when the cache is
    warm.**~~ **FIXED 2026-08-19 in S1.** The cache moved into
    `App/SessionSidecarLocator.swift` and is keyed by source path, so a warm
    grant can never be handed to a different dataset; `openDemoFixture`'s missing
    clear is neutralised by the keying rather than by remembering to call
    `release()`. Pinned by
    `SessionSidecarLocatorTests.testAWarmGrantIsNeverHandedToADifferentDataset`,
    verified by breaking the key check. It had to be fixed in the same change
    that fixed the bookmark, because S1 is what makes a grant resolve at all —
    it would have armed itself exactly then.

  ~~**Not fixed, deliberately:** `recordedLoadSpecification` still reads the
  derived sibling path (`AppState.swift:1419`) while `loadSessionSnapshot` reads
  the bookmark-resolved one (`:2319-2320`) — two readers of the same sidecar
  disagreeing about which file to open. Confirmed by reading, but Gate D forbids
  landing the fix on a diagnosis that has not yet survived its experiment, and
  the AppState seam is owed by whichever session lands it.~~

  **FIXED 2026-08-19, once the diagnosis did survive its experiment.** The denial
  was observed at 09:34:27, so Gate D's condition was met; the seam
  (`App/SessionSidecarLocator.swift`) was extracted and both readers now go
  through its single derivation. The wording above is kept struck rather than
  deleted because it records why the fix waited — that restraint is the point of
  the gate, not an oversight to tidy away.

---

## The defect Track B found after the fix had landed

- ~~**"Save Calibration to Session Sidecar" wrote the file but never persisted
  the access grant.**~~ **FOUND BY TRACK B F1.3h AND FIXED, 2026-08-19.** The two
  publish paths in `Support/ResultExport.swift` were indistinguishable to the
  user and differed in exactly one thing: `saveCurrentResultToSessionSidecar`
  called `storeSessionBookmark` after publishing, and
  `saveCalibrationToSessionSidecar` did not. So saving a calibration granted
  access for that launch only; on the next launch no bookmark resolved, the app
  fell back to the derived sibling, and the sandbox refused it — the exact C10
  failure, re-created by the save path itself.

  **The sting: S1's own refusal message named the broken path as the remedy** —
  *"Save the session once (File ▸ Save Calibration to Session Sidecar) and choose
  that file, which grants access for future opens."* The app printed an
  instruction that could not work, and the release owner followed it.

  Observed cleanly: the sidecar written at 13:48:19 carries
  `{"scanCrop":{"height":12,"width":32,"xOffset":24,"yOffset":8}}` — the crop
  recorded correctly — and the reopen 17 seconds later was denied with
  `errno = 1`. It also explains why 11:26 worked and 13:48 did not: the earlier
  save went through the *result* path, which stored a bookmark.

  Fixed by giving both paths one `rememberSidecarGrant` helper. **Not caught by
  any automated test, and could not have been:** driving it needs `NSSavePanel`
  and a real HDF5 write, and the difference was a missing CALL, not wrong logic.
  Track B caught what the suite structurally cannot — worth remembering the next
  time the visual pass looks expensive.
