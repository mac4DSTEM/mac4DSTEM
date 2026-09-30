# The decision sheet of 2026-09-30 — the owner's 21 answers, verbatim

The sheet: the artifact "mac4DSTEM Decisions" (each card: the problem in plain words, the options with effort and risk,
the session's recommendation, an independent advisor's second opinion — `advisor-read.md` beside this file — and "if you
never decide"). The owner answered by option and pasted the result; ADR 050 records what each answer means. His paste:

```
mac4DSTEM decisions, 2026-09-30 night
review — Start the cloud review: Start it now
D1a — Phase-match tolerance stays as shipped: Keep
A1 — Aperture drag: orange row + Restore, no dialog: Keep, and park the file's centre too
A6 — "In memory" wording in a frozen file: Ratify, and allow the empty-circle fix
A7 — R–Q sign on old exports: label, don't guess: Keep label-only; you re-export Si-SiGe once
A2 — "Fit anyway" mark restored from the session history: Keep
A3 — Built-in crystal library kept: Keep, and fix the name-shadowing order  note: i may change this later, i am not happy with the bloat it causes for no reason
A5 — The real-data gate fails without data: Keep (fail closed)
G — v1.0.0 session files: disks are re-detected: Keep the refusal
K — Three earlier delegated choices: Keep all three
Ds20 — Orientation candidate F: check the scale first: Run the check at the true scale, and adopt the rule "a failed reproduction closes an item"
F — The Thronsen licence email: Nothing until a port is planned  [not the recommendation]  note: we can keep this out of the repo at this point as we are not porting anything. we compare our approach to theirs but this is nothing that touches a licence. remove the Thronsen licence issue from the repo, this is not longer relevant
Jdm4 — Read one Si-SiGe.dm4 pattern's width × height in GMS: Leave it  [not the recommendation]
train — Train again with the File probe kernel: Run it  note: this feature has to be good, we have a lot more computation power and we have the ANE, lets turn this into a useful feature for users, this is a priority.
unfiltered — Your "unfiltered" cubes are hot-pixel filtered: First: do any numbers you report read those pixels?  note: preprocessing our own raw data (e.g from dm4 files) is now possible with this hardware, this has to be part ov v4.1.0, if we slept on this we have to include this in a session, can#t be to complicated, we can orient ourselfs on py4DSTEM. basically we load the raw cube and do all the calibrations maybe also with the option to crop, bin or stride and store the result as a .h5 file. this provessed file can then be used with mac4DSTEM directly or binned/cropped on load. familiarize yourself with the process how py4dstem dies it and we need to add buttons and maybe its own popup just like with open with options for prepros.
ptycho — Ptychography: finish it or remove it: Finish, and also diagnose the difference map  [not the recommendation]  note: i want them both to be aprt of this app. our goal is to have feature parity with py4DSTEM, this is very important for the product. figure this one out and deliver both, correct, compare with py4dstem, figure out a way to get a ground trough, these featureas are important
Bs21 — Ring-shaped beams: fix the default, or name the limit: Take the patch with the reviewer's five fixes  note: tae my decision here but think about the following, maybe we find a better decision: i dont see why we cant figure this one out? py4DSTEM does it, no? figure out why and how and we fix this, no fancy solutions but we need to get a hold of this problem without compromising the detection for normal probes, as the bullseye will be very rare on 4DSTEM anyways
A4 — Q calibration can pick the wrong ring — on your own zone axis: The badge reads "unchecked" when the ratio disagrees; check the app path on the demo cube and on your raw Al–Mg–Si cube
H — The polish list from the drives: Look at the two landed controls and ratify; one room session for the rest; the bin-2 defect reproduced before v4.1
C14 — Beam-centre self-check on ring-shaped beams: Build the number (log and a test), no verdict change
R — Keep the cube in memory?: Mock a per-open "Keep in memory" toggle showing the size against RAM  note: i think speed is a big plus, we claim to ahve live processing, this would almost alow this, we should defenetly have this option of keeping the cube in memory and explore the new options that gives us, as GPU and CPU can access in no time, we implement this and explore new possiblities beyond v4.1
```
