# 011 — Status strip: reserved slot; throughput leaves the strip; a readout is not an event

Dates: 2026-09-04, 2026-09-12

Status: live; the 2026-09-04 reserved-slot form is narrowed by the 2026-09-12 entries; 034 (2026-09-21) moves throughput and the Performance rows to the bottom workspace's Run tab and adds a second reserved slot (the memory/residency glance)

## Decision

A status-bar number that ticks (elapsed / ETA) gets a constant reserved
frame (`LayoutPolicy.operationMetricsWidth`) and truncates inside it, held
for the whole operation — letting it be "as wide as it needs" was itself the
bug that produced a layout constraint loop. Throughput was later dropped
from the strip: Apple's own chrome never shows units-per-second, it was the
widest token in the line (180.9pt vs 113.6pt without it), and it is the one
of the three a user can infer from what remains. It survives in Info ›
Performance. Separately, `ActivityLog` gained a one-shot suppression so a
readout (e.g. scan-position on every cursor move) does not evict real events
(detection, import, phase map) from a 300-line capacity log — a status line
has two jobs, reporting what happened and showing where you are, and only
the first belongs in a log.

## Why

The constant is measured (`StatusBarMetricsTests`), not chosen. Throughput's
removal keeps the half of the 2026-09-04 decision that mattered: the numbers
a user waits on (elapsed, ETA) stay beside the bar. The log suppression was
adopted after measuring that a 330×330 scan offers 108 900 cursor-move
readouts against 300 lines of capacity.

## Governs

`LayoutPolicy.operationMetricsWidth`, `ActivityLog`'s one-shot suppression.

## Sources

- 2026-09-04 "A status-bar number that ticks gets a reserved slot, not its own size" (narrowed), log line 276
- 2026-09-12 "Throughput leaves the status strip", log line 1232
- 2026-09-12 "A readout is not an event", log line 1253
