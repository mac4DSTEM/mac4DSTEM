# X3 notes — "Preprocess Raw Data…" (mock only; no code written)

**Picture:** mock.html (entry points; State A picked+preview; B filled+output size; C writing). Rows are today's wording.

**Entry:** File menu item "Preprocess Raw Data…" (mac4DSTEMApp.swift:128, replaces "Preprocess & Export DataCube…"); toolbar DatasetMenu (WorkspaceView.swift:177, below Open with Options…); sidebar Dataset section when no dataset is open (WorkspaceSidebar.swift:26-33). One new row per surface, 3 rows total, no new control kinds.

**Flow:** pick file (NSOpenPanel, same as Open) -> LoadConfigurator-style preview (PendingLoad machinery, LoadConfigurator.swift:50-55, :105) -> crop by drag on the two panes -> stride, bin, hot-pixel -> Size/output shape -> Destination -> Write (NSSavePanel today, ResultExport.swift:44) -> progress row -> closes with a status line.

**Reuse (one shared section, not two copies):** extract `previews`/`cropPane` (LoadConfigurator.swift:105-300), `binSection` (:368), `sizeSection` (:402) as a shared reduction form; Load = that form + keep-in-memory + Load; Preprocess = same form + Scan stride + Hot pixels (ExportSheet.swift:151-160, :203-223) + Output + Write. ExportSheet's own crop/binning Steppers (:136-200, 8 of them) and Output preview (:225) are removed. Writer/options unchanged (CalibratedDataCubeExportOptions, ExportSheet.swift:279; ResultExport.swift:32).

**Cost (rows/pt):** sheet = configurator geometry (LayoutPolicy.configuratorSheet) not exportSheet 540x460/600x700 (LayoutPolicy.swift:217). Scrolling Form: Source 1, Stride 1, Bin 2-3, Hot pixels 2 (+caption), Size 6, Output 2 = ~16 rows vs Export today ~22 (readiness 6+, crop 5-6 steppers, bin 6 steppers). Net: -8 stepper rows, +2 rows (Source file, Destination), +1 progress row. Net markdown/LOC negative if the shared extraction lands. Frozen shell files untouched: ContentView.swift:84/:100 sheet hook is one line (frozen -> owner must accept that edit; or route through the existing pendingLoad sheet).

**Removed/merged:** "Preprocess & Export DataCube…" menu item (:128), toolbar item (:177), ExportSheet crop steppers, duplicated binning caption/warning (ExportSheet.swift:196 vs LoadConfigurator.swift:372/:387 — two spellings of the same sentence; keep configurator's + trim note).

**Open questions**
1. Calibration readiness: a raw file has no session calibration, so the section can't show. Options: (a) drop it from this sheet; keep it only when the source is the open dataset (door 2); (b) drop everywhere, write uncalibrated with one caption. Recommend (a): the writer takes the session's calibration when it exists, and no value is invented.
2. The open-dataset door (File > Preprocess... when a cube is open): (a) same sheet, source pre-filled with the open file, readiness shown; (b) leave the old ExportSheet. Recommend (a): one sheet, otherwise the crop/bin duplication returns. Caveat: an open reduced view exports the view's frame (ResultExport.swift:33-38), not the file's — the pre-filled source must say "current view".
3. After Write: (a) just a status line; (b) status line + "Open the result" button. Recommend (a) — ADR 049, no new controls; the owner opens it with Open Dataset.
4. Preview for a 28 GB file: configurator preview is sampled (LoadConfigurator.swift:212); a DM4 with no cheap sample may show "No preview available" (:219) — sheet still works from the exact Size rows. Recommend accept; X1's drive will say if the DM4 path previews at all.
