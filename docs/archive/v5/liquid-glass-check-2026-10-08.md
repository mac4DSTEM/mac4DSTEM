# Liquid Glass use check (read-only, 2026-10-08)

Scope: every glass or material use in `mac4DSTEM/` Swift sources, checked against Apple's SwiftUI and HIG pages (fetched through the Apple documentation MCP tool, 2026-10-08). Nothing was built or run. Every on-screen claim below is unverified until a drive is done.

Method: grep for `glassEffect`, `.glass`, `glassProminent`, `GlassEffectContainer`, `glassEffectID`, `buttonStyle(.glass`, `Material`, `ultraThin/thin/regular/thick Material`, `reduceTransparency`, `colorSchemeContrast`, `accessibilityReduceTransparency`. No SwiftUI `Material` value is used in code; the only "material" words are comments and the Materials Project type names. No code reads Reduce Transparency or Increase Contrast.

Sources (Apple documentation MCP paths, with public URLs):
- S1 Applying Liquid Glass to custom views: documentation/SwiftUI/applying-liquid-glass-to-custom-views.md — https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- S2 glassEffect(_:in:): documentation/SwiftUI/view/glasseffect-in.md — https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- S3 GlassEffectContainer: documentation/SwiftUI/glasseffectcontainer.md — https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- S4 Glass.interactive(_:): documentation/SwiftUI/glass/interactive.md — https://developer.apple.com/documentation/swiftui/glass/interactive(_:)
- S5 Glass: documentation/SwiftUI/glass.md — https://developer.apple.com/documentation/swiftui/glass
- S6 GlassButtonStyle: documentation/SwiftUI/glassbuttonstyle.md — https://developer.apple.com/documentation/swiftui/glassbuttonstyle
- S7 GlassProminentButtonStyle: documentation/SwiftUI/glassprominentbuttonstyle.md — https://developer.apple.com/documentation/swiftui/glassprominentbuttonstyle
- S8 Adopting Liquid Glass: documentation/TechnologyOverviews/adopting-liquid-glass.md — https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- S9 HIG Materials: documentation/HIG/materials.md — https://developer.apple.com/design/human-interface-guidelines/materials
- S10 HIG Buttons: documentation/HIG/buttons.md — https://developer.apple.com/design/human-interface-guidelines/buttons
- S11 HIG Color: documentation/HIG/color.md — https://developer.apple.com/design/human-interface-guidelines/color
- S12 accessibilityReduceTransparency: documentation/SwiftUI/environmentvalues/accessibilityreducetransparency.md — https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency

Key sourced rules (paraphrased):
- Glass goes on controls and navigation, not the content layer (S9). Use glass sparingly; limit it to the most important functional elements (S9, S8).
- Glass on custom views: glassEffect is applied after the modifiers that change appearance (S1). interactive() gives the press and hover response of standard buttons (S1, S4).
- GlassEffectContainer: spacing larger than the interior layout spacing makes shapes blend at rest; the container is for performance and morphing (S3, S1).
- glass and glassProminent button styles are the recommended route instead of hand-built glass (S8, S6, S7). Keep prominent buttons to one or two per view (S10). Apply colour to the background of prominent buttons, not to many controls (S11, S9).
- Test with Reduce Transparency and Increase Contrast; custom colours need an increased-contrast variant; system components adapt automatically (S8, S11, S12).

## Table

| file:line | what is glass | Apple says (source) | verdict | on-screen check |
|---|---|---|---|---|
| UI/InspectorRows.swift:519 | `InspectorAdaptiveButton`: `Button` with `.buttonStyle(.glass)` (inspector action buttons) | glass button style is the recommended route (S8, S6) | as documented; density is the risk (S9 "sparingly") | Light appearance, default contrast: rest, hover, press. Count how many glass buttons share one inspector screen. |
| UI/InspectorRows.swift:558 | `InspectorAdaptiveMenu`: `Menu` with `.buttonStyle(.glass)` (used at UI/PhaseMappingSettings.swift:437 "Add Phase") | S8 says buttons morph into menus, but none of the sourced pages say a Menu accepts the glass primitive style | UNVERIFIED: the sourced pages do not confirm a Menu draws glass from this style | Does the Menu draw a glass capsule like its neighbour `InspectorAdaptiveButton` at rest, hover and press, in light appearance? |
| UI/InspectorRows.swift:973 | `GlassEffectContainer(spacing: 6)` around the chip flow layout (`GlassChipGroup`) | container spacing must be below interior spacing so shapes do not blend at rest (S3, S1). Here 6 < chip gap 8: as documented. Line spacing is also 6, equal to the container spacing, which the sourced text does not cover. | as documented; wrapped rows are borderline | Let chips wrap onto a second row (narrow inspector). Check the two rows' capsules do not merge at rest. |
| UI/InspectorRows.swift:992 | selected chip tint: `base.tint((chip.tint ?? .accentColor).opacity(0.55))`, plus `.interactive(chip.enabled)` | tint suggests prominence (S1). Interactive matches standard buttons (S1, S4). HIG: colour sparingly; do not add colour to several controls at once (S11, S9) | interactive(): as documented. Tint on many chips at once: PITFALL | Turn on several multi-mode chips (Spectrum curves, Layers overlays). Count how many are tinted at the same time. |
| UI/InspectorRows.swift:1009-1010 | `.buttonStyle(.plain)` then `.glassEffect(glass, in: .capsule)` then `.disabled(!chip.enabled)` on each chip | S1: apply glassEffect after modifiers that change appearance. `.disabled` comes after glassEffect here | PITFALL candidate: disabled dimming may not reach the glass | Compare a disabled chip (Spectroscopy Layers "Per pixel" / "Windows" when their condition is off) with an enabled one, in light appearance. Is the disabled glass visibly dimmer? |
| UI/Spectroscopy/SpectroscopyInspectors.swift:65, 173, 323, 326, 329 | five `GlassChipGroup`s in one room: map mode, region tool, curves, scale, overlays | "sparingly"; limit glass to the most important functional elements (S9, S8) | PITFALL (density, judgment call for owner) | Open the Spectroscopy room with a dataset and the Layers section expanded. Count every glass surface visible at once. |
| UI/WorkspaceInspector.swift:114 (FROZEN SHELL) | `.glassEffect(.regular, in: .capsule)` behind the inspector tab capsule | regular variant for components with text; capsule is the default shape (S2, S9). Sits in the control layer, not content (S9) | as documented | Light appearance: tab labels legible over the capsule. Reduce Transparency and Increase Contrast: labels still readable. |
| UI/WorkspaceView.swift:272 (FROZEN SHELL) | toolbar run button `.buttonStyle(.glassProminent)` | glassProminent is the prominent glass style (S7). Keep one or two prominent buttons per view (S10). The owner decision (ADR 059) names this verb | as documented | Light appearance, enabled state: accent fill and glass read as the one prominent action. Toolbar items already take glass (S8). Check it does not double-layer (the sourced pages do not say). |
| UI/WorkspaceView.swift:274 (FROZEN SHELL) | disabled run button `.buttonStyle(.glass).disabled(true)` | glass style is documented (S6). The disabled look is not described in the sourced pages | UNVERIFIED: the disabled look is the reason for the choice (comment at :267-270, a drive finding) | Light appearance, disabled vs enabled: is "not ready" clear from the glass alone? |
| UI/Spectroscopy/MapRasters.swift:109-110 | `MapScaleBarView`: `.glassEffect(.regular, in: .rect(cornerRadius: 6))` over a map, then `.environment(\.colorScheme, .dark)` | HIG: do not use Liquid Glass in the content layer; a map is content (S9). Regular glass adapts to the background's luminance (S9). A forced `.dark` scheme overrides that adaptation (inference) | PITFALL: conflicts with the HIG content-layer rule. The code cites spec 2 D-8 as the decision. Forced dark is also not as documented. | Light appearance on a bright map and on a dark map: is the bar legible on both? Reduce Transparency: is it still legible? |
| UI/Spectroscopy/MapRasters.swift:107 | comment: "vibrant on the thin material" | no Material is used in the code (grep) | stale comment (wording only) | none (fix the wording when the file is next touched) |
| UI/Spectroscopy/MapsGridView.swift:672-676 | `overlayCapsule()`: `.glassEffect(.regular, in: .capsule)` plus `.environment(\.colorScheme, .dark)`; used at :176 ("Pick elements to map") and :186 (region caption) | same content-layer rule (S9); forced dark overrides adaptation (inference) | PITFALL: same as MapRasters | Light appearance: open ColorMix with no element ticked, and a region with a caption. Read both labels over a light map. |
| UI/ContentView.swift:171-173 (FROZEN SHELL) | comment only: toolbar items are system glass; bordered buttons in columns are `.glass` | matches S8 and the code (InspectorAdaptiveButton) | comment only; the "as in Xcode" claim is not in the sourced pages | none (comment, no UI) |
| UI/LayoutPolicy.swift:213 (FROZEN SHELL), UI/WorkspaceInspector.swift:80-82, 109 (FROZEN SHELL), UI/WorkspaceSidebar.swift:105 | comments only: glass capsule and "glass lives on the buttons" | none needed | comment only | none |
| (none) Reduce Transparency | no code reads `accessibilityReduceTransparency` (grep). Custom tints, forced-dark capsules and the chip group are the custom parts | system components adapt automatically; custom elements must be tested (S8, S12) | MISSING: no custom path, never tested | Reduce Transparency ON (see drive check 4). |
| (none) Increase Contrast | no code reads `colorSchemeContrast` (grep). Curve colours use system colours (.orange .blue .pink .secondary .primary, UI/Spectroscopy/SpectroscopyInspectors.swift:241-248) | custom colours need an increased-contrast variant; system colours adapt (S11) | MISSING for the 0.55 tint and forced-dark overlays; system colours OK | Increase Contrast ON (drive check 5). |

## Drive checks, in order

Rules that apply (repo CLAUDE.md): drive a scratch build with a pid-pinned process; never drive while the owner's copy runs; review every screenshot; the "Unverified on screen" row stays open until these are done. Turning on Reduce Transparency or Increase Contrast changes a system setting, so the owner does those toggles or gives an explicit yes first.

1. Light appearance, default contrast, Spectroscopy room with a dataset loaded, inspector open. Screenshot each glass group at rest and zoom in. Check: capsules do not merge (rows 973); 12 pt chip text legible on the glass; the selected chip's 55% tint still lets the label read.
2. Hover, press and keyboard on the chips. Hover each chip for the interactive response; Tab to a chip and press Space and Return; check the selected state through accessibility (isSelected). In single mode, tapping the chip that is on keeps it on. In multi mode, tapping toggles. Also check the inspector Menu (InspectorAdaptiveMenu, Add Phase): does it draw glass like its neighbouring button at rest, hover and press? (rows 519, 558, 992).
3. Disabled states, light appearance: a disabled chip (Per pixel / Windows when their condition is off) against an enabled one; then the toolbar run button enabled and disabled (frozen shell: view only, no edits). Check the disabled glass is visibly dimmer and "not ready" reads without the help text (rows 1009-1010, 272, 274).
4. Reduce Transparency ON (owner toggles it, or gives an explicit yes). Repeat checks 1 to 3. Judge: capsules become opaque and labels readable; tint on selected chips still reads; the scale bar and region caption stay legible on a bright map (rows 109, 672-676, 114).
5. Increase Contrast ON (same as 4). Judge: selected tint against label; capsule borders; system curve colours (orange, blue, pink) still distinct from each other.
6. Map overlays in light appearance: a map with the scale bar, the region caption, and the "Pick elements to map" capsule on a bright map and on a dark map. The forced-dark glass is the thing to judge (rows 109-110, 176, 186).
7. Density and tint count: Spectroscopy Layers with all five spectrum curves on and both overlays on. Count glass surfaces on screen and tinted chips at once. Judge against "sparingly" and "do not tint many controls" (rows 65-329, 992).
8. Frozen-shell check, view only: the toolbar run verb in light appearance next to the toolbar's own glass items; check whether the verb double-layers (row 272). Any change to frozen files needs an owner-accepted picture (ADR 035).

## Not settled by the sourced pages (do not claim)

- Whether a SwiftUI `Menu` accepts `.buttonStyle(.glass)` (row 558).
- Whether `.disabled` after `.glassEffect` dims the glass (rows 1009-1010).
- Whether a glass button inside a toolbar item double-layers (row 272).
- What Reduce Transparency and Increase Contrast do to the 0.55 tint and to `glassEffect` capsules in this app: Apple says the appearance changes, not how much.
- Whether HIG's "content layer" rule is meant to cover map overlays (row 109). The repo cites its owner decision D-8, which is the answer for the owner to confirm, not this check.

## Other notes (not glass)

- `GlassChipGroup` sets `.accessibilityIdentifier(identifier ?? "")`, so a nil identifier sets an empty one. Not glass; harmless, but worth a look.

## Supervisor check (2026-10-08)
- The HIG Materials page path resolved in the MCP but returned no body text to the supervisor; the content-layer rule is therefore cited
  from the reader, not re-read. Treat rows 109 and 672-676 as the reader's reading until a person opens the HIG page.
- The SwiftUI "Applying Liquid Glass to custom views" URL did not resolve by URL in the MCP (search by title instead); rows citing S1 rest
  on the reader's text.
