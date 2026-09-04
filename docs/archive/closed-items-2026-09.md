# Closed items — 2026-09 archive

Moved here from [`docs/open-items.md`](../open-items.md) as each closes,
enforcing that file's rule that closed items do not stay there. The 2026-08
file is a single dated move and stays closed; this is its September
successor rather than a second section inside it. Entries appear as they
last stood in the live file, with a closure note. **History, not guidance.**

---

## Status line leaks a full filesystem path — closed 2026-09-04

### ~~Status line leaks a full filesystem path~~ — **CLOSED 2026-09-04**

> ~330 characters including the absolute path, rendered raw in
> `StatusFooterView` and `ProductWorkspaceViews`' header progress; the
> archived checklist's screenshots (public docs) have carried it since
> 2026-08-19. Worth truncating for display while keeping the log copy.
> Still open.

**Closure.** Both named views were deleted with the AppKit window
(`d5786e2`), but the leak was not theirs. It came from the readers: three
error descriptions interpolated the absolute path they were handed —
`H5Error.cannotOpenFile`, `DM4Error.cannotOpen`, `VendorRawError.cannotOpen`
— and `AppState.present(_:)` puts `error.localizedDescription` on both the
window-modal alert and the status line. Every other status-line assignment
already used `lastPathComponent` or `descriptor.fileName`; these three were
the last route.

Fixed by naming the file instead of the path (`displayFileName`, one helper
in `Core/Data/FourDDataSource.swift`), pinned by three tests in
`ErrorRoutingTests` that were broken first. Deliberately left alone:
`H5Error.libraryUnavailable`, whose detail is `dlopen` failures over
app-install paths — no user data, and the only diagnostic for a bundled-HDF5
load failure. `DM4Error` keeps the underlying error that the v2 S7 audit
added to distinguish EPERM from ENOENT from a short read; only the enclosing
path is gone.
