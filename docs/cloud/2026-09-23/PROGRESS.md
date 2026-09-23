# Cloud session 2026-09-23: precipitate objects, progress

Branch `cloud/2026-09-23-precipitate-objects`, cut from `origin/main` at `075c044`.
Last updated: 2026-09-23, end of session.

## Task state

| Task | State | Why |
|---|---|---|
| T1–T6 | **Not started** | The brief `docs/cloud/2026-09-23-brief.md` does not exist (B1), and the only permitted data source can't be reached from this container (B2). |
| PROGRESS.md / SUMMARY.md / PR | Done | This file, `SUMMARY.md`, one PR to `main`, left unmerged. |

## Blockers, with evidence

**B1: the brief is missing.** Checked 2026-09-23 around 08:15 UTC, after `git fetch origin`:

- `git ls-tree -r --name-only origin/main | grep -i cloud` returned nothing. No `docs/cloud/` exists on `main`.
- `git log --all --oneline -- 'docs/cloud/*'` returned nothing. The path is in no commit on any fetched ref.
- GitHub `list_branches` lists only `main` (`075c044`). The only PR, #1 (`ai-analysis`), is closed.
- `find / -name '*2026-09-23*'` turned up no brief. There is no stash.
- No doc in the repo mentions `docs/cloud`, `cloud-analysis` or `precipitate-objects`.

**B2: Zenodo is blocked by the environment's network policy.** The egress proxy rejects the CONNECT (HTTP 403) for `zenodo.org:443` and for `doi.org:443`. To reproduce:

```sh
curl -sS -m 30 -o /dev/null -w '%{http_code}\n' https://zenodo.org/api/records/6645396
# curl: (56) CONNECT tunnel failed, response 403
curl -sS "$HTTPS_PROXY/__agentproxy/status"   # recentRelayFailures: zenodo.org:443 connect_rejected
```

PyPI can be reached: `numpy`, `h5py` and `scipy` installed. There is no Swift toolchain (`which swift` is empty; Linux container), so `tools/phase-map-probe` and every other Swift harness cannot run here in any case.

## Choices made (the conservative option each time)

1. **T1–T6 were not reconstructed.** The repo's own precipitate next steps are listed in `SUMMARY.md` only as pointers, not as tasks. Writing six tasks under the brief's numbering would claim to know the owner's intent, and a reader of the PR could mistake them for the brief.
2. **No data was downloaded** from any source. I did not try a mirror; the brief allows Zenodo 6645396 only.
3. **`tools/cloud-analysis/` was not created.** `tools/run-tests.sh` `inventory` fails on any `tools/` directory not classified in its lists (lines 114–121), and `run-tests.sh` is outside this session's write scope. With no analysis to run, a new directory would only break the inventory gate on the branch. The reachability check is the code block above.
4. **Branch and push.** The owner's session message names `cloud/2026-09-23-precipitate-objects` and asks for a push after each task and one PR. I followed that over the harness default branch and over `CLAUDE.md`'s "main only / ask before push", because this message is newer and specific to this session. I unset the branch's upstream (`origin/main`) so that a bare `git push` cannot reach `main`.
5. **No live doc touched.** `docs/status.md`, `docs/open-items.md`, `ROADMAP.md` and `CLAUDE.md` are unchanged. The inventory's markdown-line and handoff counts are unaffected: `docs/cloud/**` is not a truth doc (`run-tests.sh` lines 336–340).

## To rerun

1. Commit the brief to `main`, or to this branch, at `docs/cloud/2026-09-23-brief.md`.
2. Allow `zenodo.org` in the cloud environment's network settings (Edit environment → Network access). Add `doi.org` too if the brief resolves the DOI.
3. If any task needs a Swift probe, run it on a Mac. This Linux container has no Swift.
