# Driving mac4DSTEM as an agent — what the 2026-09-01 pass learned

Companion to `docs/visual-acceptance-checklist.md`. This file is method only:
it exists so the next agent does not re-derive it. Every rule below cost time.

## Input: you need TWO mechanisms, chosen by target

| Target | Use | Why |
|---|---|---|
| Buttons, toolbar items, menu items | `CGEvent` (real click) | Works reliably |
| SwiftUI `DisclosureGroup` rows, `Picker`/pop-up rows, List/outline rows | **System Events element click** (`click at {x,y}`) | `CGEvent` silently does NOT toggle these |
| Image panes (`NSViewRepresentable`), drags, the split divider | `CGEvent` (2026-08-27) | element click silently does nothing |

**Both directions are real.** 2026-08-27 recorded that element clicks die on
`NSViewRepresentable` panes. 2026-09-01 found the complement: four `CGEvent`
clicks on *Fit diagnostics & advanced correction* did nothing, and a **control
test on the *Display* disclosure failed the same way** — proving the input
method, not a hit-target defect. One System Events element click opened it.
**Run the control before filing a hit-target bug.**

## Always assert frontmost before clicking

A blind click went into another app once. Wrap every click:

```zsh
osascript -e 'tell application "System Events" to set frontmost of process "mac4DSTEM" to true'
sleep 1.5
FRONT=$(osascript -e 'tell application "System Events" to return name of first process whose frontmost is true')
[[ "$FRONT" != "mac4DSTEM" ]] && { echo "ABORT: $FRONT"; exit 1; }
```

With two windows open, both near-fullscreen, **you will lose track of which is
frontmost** — a ⌘O intended for one window landed in the other. Check the
sidebar's dataset card before trusting any reading.

## Scroll every scrollable surface to its END before reporting an absence

The costliest error of 2026-09-01. A 50×200 result on a 128×128 cube looked like
an unwarned shape mismatch; the warnings were real, correct, and **six sections
below the fold** in an inspector that is closed by default. *Absence of a warning
is a claim about a whole surface, not the visible part of it.*

## Check the source condition before believing the screen

Two false findings avoided this way:
- **F1.40's** outlier line renders only when `excludedFraction > 0.005`. Its
  absence on Si_SiGe is correct, not a failure.
- **F1.41's** Q-shell line needs `qCalibration.selfCheckSummary`, i.e. a
  Calibrate-Q-from-crystal run; and its button needs `hasCurrentBraggVectors`.

**Rows do not state their preconditions.** Read the `if let` that guards the
string you are looking for.

## Coordinates

`screencapture` returns 2× Retina pixels; `CGEvent` takes logical points.
**logical = image_pixel / 2.** Crop with `screencapture -R x,y,w,h` in logical
points. To measure a divider or edge precisely, sample a horizontal strip and
look for the colour transition — that is how the 144.0 pt sidebar was measured.

## Verify the build before driving

The `.app` bundle directory's mtime is **stale and misleading**. Check
`Contents/MacOS/mac4DSTEM`:

```zsh
stat -f '%Sm' "$APP/Contents/MacOS/mac4DSTEM"
```

## Layout traps that will waste a sitting

- **The sidebar divider persists across windows and can restore at 144 pt**
  (declared min is 250). At that width the whole Calibration section truncates to
  "Ori… Missing" / "Elli… Missing". Drag it wider **before** reading anything.
- A **new window opens at the 1080 pt minimum width** with the welcome screen's
  entry buttons **below the fold** — they scroll into view.
- Once a dataset is loaded, *Open with Options…*, Recents and *Try Demo Data* are
  unreachable in that window. **⌘N** is the escape.
- Readiness rows are single-line and truncate mid-sentence, including the
  actionable half. Widen the sidebar, or read the string from source.

## Do not

- Run `tools/run-tests.sh unit` while driving — one defaults domain, two drivers.
- Write large exports (a reduced datacube from sim_Au is ~500 MB) without asking;
  this Mac runs near its disk floor.
- Copy datasets into `References/training_dataset/` — the gate globs `*.h5` there.
