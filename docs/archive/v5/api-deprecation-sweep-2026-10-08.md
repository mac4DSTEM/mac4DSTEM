# API deprecation sweep (read-only), 2026-10-08

Scope: `mac4DSTEM/` Swift sources. Grep counts are call lines or mentions as stated; the
tree-wide recount is used where noted. Apple status comes from the Apple documentation
MCP tool (`search_apple_docs` then `expand_result`) on macOS. No repo files were edited and
nothing was built or run.

Headline: the docs confirm no deprecated API with a live call site that the compiler misses,
except the legacy LAPACK symbol form, which the build already clears with a flag. Two APIs are
soft-replaced: NumberFormatter and DateFormatter (docs recommend FormatStyle). Everything else
checked is not deprecated. About 60 candidates were grep-counted; 18 were looked up in the docs.
The rest are listed as unverified below and are not claimed.

## Confirmed in the docs (sorted by call-site count)

| API | Call sites | Examples (file:line) | Apple status | Documented replacement | Doc |
|---|---|---|---|---|---|
| `String(format:)` | 190 lines | `UI/MapSettings.swift:251`, `:889`, `:1263` | fine (no deprecation; docs give no FormatStyle replacement for `NSString init(format:_:)`) | none required | https://developer.apple.com/documentation/foundation/nsstring/init(format:_:) |
| `URL(fileURLWithPath:)` | 23 | `App/AppState+DatasetSession.swift:55`, `App/mac4DSTEMApp.swift:11`, `Session/OpenDatasetRegistry.swift:76` | fine (no banner; sibling `init(filePath:directoryHint:relativeTo:)` listed, not marked deprecated) | optional `URL(filePath:)`, not required | https://developer.apple.com/documentation/foundation/url/init(fileurlwithpath:) |
| vDSP C functions (`vDSP_conv`, `vDSP_vthres`, ...) | 46 non-comment call lines (98 mentions) | `Core/Analysis/DiskDetection.swift:1066`, `:1281` | fine for `vDSP_conv` (no banner, macOS 10.0+); `vDSP_vthres` page not retrieved | none documented | https://developer.apple.com/documentation/kernel/1532184-vdsp_conv |
| `URL.path` (property) | about 38 URL-named receivers (regex count; more `.path` overall) | `Core/ML/LearnedDiskDetector.swift:147`, `:149`, `Core/Data/BraggVectorEMDWriter.swift:571` | fine (no banner on `var path`); `path(percentEncoded:)` is macOS 13+ and newer, not a deprecation | `path(percentEncoded:)` optional | https://developer.apple.com/documentation/foundation/url/path-percentencoded |
| `Data(contentsOf:)` | 9 | `Core/ML/LearnedDiskDetector.swift:166`, `Core/Data/VendorRawReaders.swift:152`, `App/AppState+LabelImport.swift:32` | fine (`init(contentsOf:options:)`, macOS 10.10+, no banner) | none required | https://developer.apple.com/documentation/foundation/data/init(contentsof:options:) |
| `GeometryReader` | 16 | `UI/HistogramView.swift:121`, `UI/LineageGraphView.swift:55`, `UI/ImagePanes.swift:58` | fine (not deprecated) | measure-only use can be `onGeometryChange` (already used 4 times), but not a deprecation | https://developer.apple.com/documentation/swiftui/geometryreader |
| `onChange(of:)` | 36 | `UI/MapSettings.swift:323`, `UI/BottomWorkspace.swift:87`, `UI/ContentView.swift:79` | fine for this code: 0 single-parameter closures; the page for `onChange(of:perform:)` shows no deprecation banner | n/a | https://developer.apple.com/documentation/swiftui/view/onchange(of:perform:) |
| `NumberFormatter` | 4 constructors | `UI/HistogramView.swift:307`, `UI/SpectrumOnlyViews.swift:131`, `UI/Spectroscopy/QuantPanelView.swift:36`, `UI/Spectroscopy/SpectroscopyLogic.swift:450` | soft-replaced (not deprecated; docs Tip says use FormatStyle "rather than NumberFormatter") | `IntegerFormatStyle`, `FloatingPointFormatStyle`, `Decimal.FormatStyle` | https://developer.apple.com/documentation/foundation/numberformatter |
| `DateFormatter` | 2 constructors (about 8 mentions) | `UI/MaterialsProjectImportSheet.swift:251`, `App/ActivityLog.swift:110` | soft-replaced (docs Tip: use `Date.FormatStyle`) | `Date.FormatStyle` / `Date.VerbatimFormatStyle`; ISO 8601 stays `ISO8601DateFormatter` (used at `Core/Crystal/MaterialsProjectImport.swift:1001`) | https://developer.apple.com/documentation/foundation/dateformatter |
| `NSImage.lockFocus()` / `unlockFocus()` | 2 | `App/Colormaps.swift:105`, `:115` | fine (macOS 10.0+, no banner); AppKit, see the owner-rule note below | none required | https://developer.apple.com/documentation/appkit/nsimage/lockfocus |
| Accelerate legacy LAPACK `dsyevd_` | 2 | `Core/Analysis/DiffractionEmbedding.swift:774`, `:784` | deprecated legacy form without the flag (Package.swift comment: "`dsyevd_` alone compiles either way, with a deprecation warning"); the docs say the new interface needs `ACCELERATE_NEW_LAPACK`. Cleared here: `Package.swift:42` sets `-Xcc -DACCELERATE_NEW_LAPACK` for DSTEMCore, and the app links DSTEMCore (`mac4DSTEM.xcodeproj/project.pbxproj` lines 13, 325, 745) | new interface with `ACCELERATE_NEW_LAPACK` (keep the flag) | https://developer.apple.com/documentation/accelerate/sparse_matrix_property (note on the new interfaces) |
| `device.supportsFamily(_:)` | 1 | `Core/Compute/MetalEngine.swift:392` | fine (macOS 10.15+); the page for the feature-set API (`MTLFeatureSet`) says to use `supportsFamily`; 0 sites use the feature-set API | n/a | https://developer.apple.com/documentation/metal/mtldevice/supportsfamily(_:) |
| `MLModel.compileModel(at:)` (async) | 2 | `Core/ML/LearnedDiskDetector.swift:108`, `Training/ModelPackageWriter.swift:68` | fine (async form, macOS 13.0+) | n/a | https://developer.apple.com/documentation/coreml/mlmodel/compilemodel(at:) |
| `DispatchQueue.main.async` | 2 | `UI/BottomWorkspace.swift:97`, `UI/InspectorRows.swift:774` | fine (no banner on `DispatchQueue.main`) | Swift concurrency is a style choice, not a deprecation | https://developer.apple.com/documentation/dispatch/dispatchqueue/main |
| `FileHandle(forReadingAtPath:)` | 1 | `Core/Data/VendorRawReaders.swift:210` | fine (macOS 10.0+, no banner) | `init(forReadingFromURL:) throws` exists, not a deprecation | https://developer.apple.com/documentation/foundation/filehandle/init(forreadingatpath:) |

Grep-zero (no call sites, so nothing to fix): `foregroundColor(`, `.cornerRadius(` modifier
(the 30+ hits are `RoundedRectangle(cornerRadius:)` / `.clipShape(.rect(cornerRadius:))`, which are
fine), `accentColor(`, `NavigationView`, `navigationBarTitle`, `ActionSheet`, `@StateObject`,
`@ObservedObject`, `@Published`, `ObservableObject`, `UIColor`, `NSKeyedArchiver/Unarchiver`,
`kUTType`, `presentationMode`, `Timer.publish`, `AnyView`, `ImageRenderer`, `Text + Text`
concatenation, `NSAlert`, `NSApp.`, `NavigationLink`, `DispatchQueue.global`, `NSCursor`,
`String(contentsOf:)` without an encoding (the 8 sites pass `encoding: .utf8`, which is fine).

## Not confirmed (grep counted, not checked in the docs, or page not retrieved)

Not claimed as deprecated, and not verified: `NSColor(calibratedRed:green:blue:alpha:)`
(`App/Colormaps.swift:108`; search did not return the page); `CGColorSpaceCreateDeviceRGB`
(4, e.g. `UI/Spectroscopy/MapRasters.swift:131`; page found, not expanded); `makeBuffer(bytes:length:options:)`
(4, e.g. `Core/Compute/MetalEngine.swift:226`) and `makeBuffer(length:options:)` (2); `makeComputePipelineState(function:)`
(sync form, `MetalEngine.swift:186`); `alert(_:isPresented:actions:message:)` (2 sites: `UI/ContentView.swift:106`,
`UI/PreprocessSheet.swift:91`; only the `alert(isPresented:content:)` page was expanded, with no banner);
`FileManager.default` (41); `UserDefaults` (25); `MTKView` (15, e.g. `UI/MetalImageView.swift:135`);
`MPSGraph` (36); `UTType` (10); `Table(` (8); `fileImporter` (5); `confirmationDialog` (10); `Picker(` (49); `buttonStyle(` (38);
`help(` (180); `ProcessInfo` (25); `task_info`/`host_statistics64` (2 each); CBLAS `cblas_dsyrk` (`Core/Analysis/DiffractionEmbedding.swift:694`, covered by the flag).

## Fix order

1. Cheap and safe (display only, no scientific value changes): `DateFormatter` to `Date.FormatStyle`
   at `App/ActivityLog.swift:110` and `UI/MaterialsProjectImportSheet.swift:251`. Pin the output with a
   fixed-date string test before and after. Leave the ISO 8601 formatters alone.
2. Medium (displayed numbers; the grouping separator U+202F and locale must reproduce exactly):
   `NumberFormatter` to FormatStyle at `UI/HistogramView.swift:307`, `UI/SpectrumOnlyViews.swift:131`,
   `UI/Spectroscopy/QuantPanelView.swift:36`, `UI/Spectroscopy/SpectroscopyLogic.swift:450`. Pin
   en_US and de_DE expected strings in a unit test first. Parsing is already handled by
   `DecimalEntryFormat`; this is output only.
3. Keep, no action: legacy LAPACK `dsyevd_` in `Core/Analysis/DiffractionEmbedding.swift`. Do not remove
   `-DACCELERATE_NEW_LAPACK` from `Package.swift:42`. If the app target ever stops linking DSTEMCore, the
   deprecation warning returns.
4. Frozen shell: none of the rows needs a change inside `UI/ContentView.swift`, `UI/WorkspaceView.swift`,
   `UI/WorkspaceInspector.swift`, `UI/LayoutPolicy.swift` or `App/WorkspaceNavigation.swift`. The
   ContentView uses (`onGeometryChange` at :50, `onChange` at :55-84, `alert` at :106, `fileImporter` at :86)
   are not deprecated per the checks above. No item is marked "frozen shell: needs the owner's picture".

## Noticed, not deprecations (for the owner, not this sweep)

- AppKit in the app layer against the SwiftUI-only rule (owner, 2026-09-28): `NSOpenPanel` at
  `App/AppState+LabelImport.swift:17`, the NSImage/NSColor swatch in `App/Colormaps.swift:97-115`,
  `NSViewRepresentable` at `UI/MetalImageView.swift:322`, `NSWorkspace` at `App/mac4DSTEMApp.swift:11`.
  These are not deprecated; the question is the rule.
- `Data(contentsOf: url)` at `Core/Data/VendorRawReaders.swift:152` reads a whole file. If that path can
  see a file larger than RAM, it runs against the "never full-read a file bigger than RAM" rule.
  Confirm whether the input can be large before changing anything.

## Supervisor check (2026-10-08)
- CONFIRMED via the MCP: NumberFormatter's page carries the Tip "In Swift, you can use IntegerFormatStyle, FloatingPointFormatStyle, or
  Decimal.FormatStyle rather than NumberFormatter" — soft-replaced, not deprecated.
- FALSE ALARM: `Core/Data/VendorRawReaders.swift:152` `Data(contentsOf:)` reads the EMPAD **XML header** (parseXML), a few kB, not the cube;
  the RAM rule is not touched.
- The AppKit uses listed (NSOpenPanel in AppState+LabelImport, the NSImage swatch in Colormaps, NSWorkspace in mac4DSTEMApp) are candidates
  for the owner's SwiftUI-only rule (2026-09-28); `MetalImageView`'s NSViewRepresentable stays (no SwiftUI MTKView).
