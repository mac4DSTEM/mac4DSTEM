# Mac App Store listing: mac4DSTEM

Approved by Paul on 2026-11-05 for the first submission (5.2.0); names, subtitles and screenshots are his.

One plain UTF-8 file per App Store Connect field. Counts are characters (`wc -m`), no trailing newline in the limited fields.

- `name.txt`: 9 / 30
- `subtitle.txt`: 28 / 30
- `promotional-text.txt`: 147 / 170
- `description.txt`: 2787 / 4000 (plain text, no markdown)
- `keywords.txt`: 93 / 100 (comma-separated, no spaces after commas; no word from the name or subtitle, which Apple indexes already, and no other product names)
- `whats-new.txt`: 35 / 4000 (Apple does not show What's New for a first version; this is for the record and the first update)
- `category.txt`: primary Education, secondary Productivity (no limit)
- `urls.txt`: support, marketing and privacy policy URLs on mac4dstem.com (no limit)
- `age-rating.txt`: questionnaire answers, all None, rating 4+ (no limit)
- `app-privacy.txt`: Data Not Collected, with the Materials Project reasoning (no limit)
- `review-notes.txt`: 1371 / 4000

Every claim comes from the README, CHANGELOG or mac4dstem.com as of 2026-11-05; nothing from the roadmap.

## State

5.2.0 is the first version in App Store Connect (Apple ID 6831377995): build 5.2.0 (10) uploaded and submitted for
review on 2026-11-06, set to manual release. The steps are in `tools/release/README.md`, "The App Store submission".

## Media

Three screenshots and three App Previews, all from the public py4DSTEM Si/SiGe tutorial dataset. The master files are
kept outside this repository, in the maintainer's private release archive, together with their SHA-256 checksums.

- Screenshots, 2880 × 1800 PNG, Display P3, no alpha channel, in store order: strain ε_xx over the SiGe layers; Bragg
  disks with the Bragg vector map; virtual annular dark field.
- App Previews, 1920 × 1080, 30 fps, H.264, silent stereo track, each about 25 s, in store order: "Both spaces, live"
  (poster frame at 10 s), "Open only what you need" (16 s), "From disks to maps" (17 s).
