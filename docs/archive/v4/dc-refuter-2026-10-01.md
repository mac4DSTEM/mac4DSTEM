# Lane DC — independent refuter (Gate B, Opus), 2026-10-01: HOLDS WITH CORRECTIONS

- **Clamp operator HOLDS**: `min(|O|, 1)` with the phase kept, on the complex object, once per iteration after the object and
  probe updates — py4DSTEM's `_object_threshold_constraint` (`ptychographic_constraints.py:29-57, 467-471`); pure-phase sets
  amplitude 1 as py4DSTEM does; the object clamp runs under fix-probe as in py4DSTEM. Gap recomputed from the lane's JSON vs R1's
  `py-df-600-auto`: off 0.08641, on 0.01741 (8 iterations, graphene). Default flipped in `SingleslicePtychographyOptions` and
  `PtychographySettings`; provenance has carried `constrain_object_amplitude` since v1.0.0, so every saved record states its
  clamp and Apply restores it; no settings persistence or ptychography replay recorder, so no old session re-runs silently.
- **Harness re-pin HOLDS**: `reference.py`'s first run is the unclamped operator; the clamp is set off explicitly there, the
  clamped block keeps its own comparison; no bar moved; truth rows identical to the digit.
- **DM removal HOLDS**: no method, projection parameter or key remains (grep); an old DM record parses to a retired marker and
  Apply changes nothing (tested); the probe tool's `dmap` refuses with a usage message.
- **Corrections**: (1) add an Apply test with "false" (applied, broken first); (2) "phase unharmed" overstated — on a strongly
  absorbing synthetic the clamp costs ≤ 0.006 Pearson (0.9791 → 0.9734), as in py4DSTEM; (3) "within 1.7 %" is at 8 iterations
  — the clamped gap grows from iteration 4 (2.2e-3 → 1.7e-2; 2.3e-2 at 32 on V2); py4DSTEM's `fix_probe_com` stays off in the
  app (5e-4 on graphene), so not parity by default in general; (4) archived scripts (`slot2-r-record-2026-10-01/graphene.sh`
  `ptycho dmap`; R1's `ptycho gd` without a flag) reproduce only at their own commit; (5) the benchmark's GD rows now include
  the clamp's O(N) pass — not exactly comparable to `bench.json`.
