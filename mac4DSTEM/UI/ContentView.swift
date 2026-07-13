import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showImporter = false
    @State private var showInspector = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var h5Types: [UTType] {
        [
            UTType(filenameExtension: "h5"),
            UTType(filenameExtension: "hdf5"),
            UTType(filenameExtension: "emd"),
            UTType(filenameExtension: "dm4"),
            UTType(filenameExtension: "dm3"),
            .data
        ].compactMap { $0 }
    }

    var body: some View {
        @Bindable var appState = appState
        // The analysis-mode switcher lives in the toolbar (always visible), so
        // the sidebar is free to hold just the active mode's controls — and can
        // now be hidden without losing mode switching.
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section("File") {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Open Dataset…", systemImage: "folder")
                    }
                    if appState.hasDataset {
                        Menu {
                            Button("Result Image as PNG…") { appState.exportResultImage() }
                            Button("Diffraction Pattern as PNG…") { appState.exportDiffractionImage() }
                            Button("Bragg Peaks as CSV…") { appState.exportBraggPeaksCSV() }
                                .disabled(appState.braggVectors == nil)
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if let descriptor = appState.descriptor, descriptor.is4D {
                    Section("Scan position") {
                        scanSlider(label: "X", value: appState.selectedScan.x,
                                   count: descriptor.rx) { x in
                            appState.selectScan(x: x, y: appState.selectedScan.y)
                        }
                        scanSlider(label: "Y", value: appState.selectedScan.y,
                                   count: descriptor.ry) { y in
                            appState.selectScan(x: appState.selectedScan.x, y: y)
                        }
                    }

                    Section("Display") {
                        Toggle("Log scale", isOn: $appState.logScale)
                        Picker("Colormap", selection: $appState.colormap) {
                            ForEach(ColormapKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                    }

                    // CBED pattern source (current / mean / max) lives here when
                    // the diffraction pane is the active (blue) one.
                    if appState.activePane == .diffraction {
                        Section("Pattern") {
                            if appState.meanPattern != nil {
                                Picker("Show", selection: $appState.patternDisplayMode) {
                                    ForEach(PatternDisplayMode.allCases) { m in
                                        Text(m.rawValue).tag(m)
                                    }
                                }
                                .pickerStyle(.segmented)
                            } else {
                                Button {
                                    Task { await appState.computeDPStatistics() }
                                } label: {
                                    Label("Compute Mean / Max", systemImage: "sum")
                                }
                                .disabled(appState.isBusy)
                                Text("One pass over the cube; also computed by origin calibration.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Calibration") {
                        LabeledContent("Aperture center",
                                       value: appState.calibration.originProvenance.displayName)
                            .font(.caption)
                            .help("Source of the center used by the virtual-detector aperture. Per-position fitted origins are reported separately.")

                        Picker("Origin fit", selection: $appState.originFitFunction) {
                            ForEach(OriginFitFunction.allCases) { fit in
                                Text(fit.rawValue).tag(fit)
                            }
                        }
                        Button {
                            Task { await appState.calibrateOrigin() }
                        } label: {
                            Label("Calibrate Origin", systemImage: "scope")
                        }
                        .disabled(appState.isBusy)
                        Button {
                            Task { await appState.calibrateRotation() }
                        } label: {
                            Label("Calibrate Rotation", systemImage: "rotate.3d")
                        }
                        .disabled(appState.isBusy)

                        if let radius = appState.calibration.probeRadius {
                            LabeledContent("Probe radius",
                                           value: String(format: "%.1f px", radius))
                                .font(.caption)
                        }
                        if let origin = appState.calibration.origin {
                            LabeledContent("Fit residual",
                                           value: String(format: "%.3f px RMS", origin.rmsResidual))
                                .font(.caption)
                        }
                        if let rotation = appState.calibration.rotationRad {
                            let transposed = (appState.calibration.transposeQR ?? false) ? " ⊤" : ""
                            LabeledContent("R–Q rotation",
                                           value: String(format: "%.1f°%@", rotation * 180 / .pi, transposed))
                                .font(.caption)
                            Button {
                                appState.flipRotation180()
                            } label: {
                                Label("Flip 180°", systemImage: "arrow.uturn.left.circle")
                            }
                            .help("The curl method can't tell θ from θ + 180°. If iDPC contrast is inverted, flip it here.")
                        }

                        // Pixel sizes: auto-filled from DM4 metadata, editable
                        // (and the only way in for plain HDF5). Drives the
                        // scale bars; 0 = uncalibrated (bars show px).
                        pixelSizeField("r px size",
                                       value: $appState.calibration.rPixelSize,
                                       units: $appState.calibration.rPixelUnits,
                                       defaultUnits: "nm")
                        pixelSizeField("q px size",
                                       value: $appState.calibration.qPixelSize,
                                       units: $appState.calibration.qPixelUnits,
                                       defaultUnits: "1/nm")
                    }

                    if appState.analysisMode == .virtualDetector {
                        if appState.activePane == .diffraction {
                            Section("Detector → real space") {
                                Picker("Shape", selection: $appState.virtualShape) {
                                    ForEach(VirtualShapeMode.allCases) { shape in
                                        Text(shape.rawValue).tag(shape)
                                    }
                                }
                                .pickerStyle(.segmented)

                                ForEach([DetectorPreset.brightField, .adf, .haadf]) { preset in
                                    Button(preset.rawValue) {
                                        appState.applyDetectorPreset(preset)
                                    }
                                }
                                Text("Drag the detector on the diffraction pane; the real-space image updates live.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        } else {
                            Section("Region → diffraction") {
                                Picker("Shape", selection: $appState.realSpaceShape) {
                                    ForEach(RegionShape.allCases) { shape in
                                        Text(shape.rawValue).tag(shape)
                                    }
                                }
                                .pickerStyle(.segmented)

                                if appState.realSpaceShape != .point, let d = appState.descriptor {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Radius  \(Int(appState.realSpaceRadius)) px").font(.caption)
                                        Slider(value: $appState.realSpaceRadius,
                                               in: 1...Float(max(d.rx, d.ry) / 2))
                                    }
                                }
                                Text(appState.realSpaceShape == .point
                                     ? "Drag on the real-space image to scrub the diffraction pattern."
                                     : "Drag the region on the real-space image; the summed pattern updates live.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    if appState.analysisMode == .dpc {
                        Section("DPC") {
                            Picker("Display", selection: $appState.dpcDisplay) {
                                ForEach(DPCDisplayMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            if !appState.calibration.hasFittedOrigin {
                                Text("Tip: calibrate the origin first — DPC shifts are measured against the fitted beam position.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else if !appState.calibration.hasRotation {
                                Text("Tip: calibrate the rotation for meaningful iDPC and vector direction.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    if appState.analysisMode == .disks {
                        Section("Disk detection") {
                            Button {
                                Task { await appState.generateProbeKernel() }
                            } label: {
                                Label("Generate Probe Kernel", systemImage: "circle.circle")
                            }
                            .disabled(appState.isBusy)
                            if let kernel = appState.probeKernel {
                                LabeledContent("Kernel radius",
                                               value: String(format: "%.1f px", kernel.probeRadius))
                                    .font(.caption)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "Correlation power  %.2f", appState.diskParams.corrPower))
                                    .font(.caption)
                                Slider(value: $appState.diskParams.corrPower, in: 0...1)
                            }
                            Picker("Subpixel", selection: $appState.diskParams.subpixel) {
                                ForEach(SubpixelMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            Stepper(value: $appState.diskParams.maxNumPeaks, in: 1...500) {
                                Text("Max peaks  \(appState.diskParams.maxNumPeaks)").font(.caption)
                            }

                            Button {
                                Task { await appState.runDiskDetection() }
                            } label: {
                                Label("Detect All Disks", systemImage: "rays")
                            }
                            .disabled(appState.isBusy)
                            if let count = appState.braggPeakCount {
                                LabeledContent("Peaks found", value: "\(count)").font(.caption)
                            }
                        }
                    }

                    if appState.analysisMode == .strain {
                        Section("Strain") {
                            Button {
                                Task { await appState.runStrainMapping() }
                            } label: {
                                Label("Compute Strain Map", systemImage: "arrow.up.left.and.arrow.down.right")
                            }
                            .disabled(appState.isBusy || appState.braggVectors == nil)
                            if appState.braggVectors == nil {
                                Text("Detect Bragg disks first (Disks mode → Detect All Disks).")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if appState.strainMap != nil {
                                Picker("Component", selection: $appState.strainComponent) {
                                    ForEach(StrainComponent.allCases) { component in
                                        Text(component.rawValue).tag(component)
                                    }
                                }
                            }
                        }
                    }

                    if appState.analysisMode == .acom {
                        Section("ACOM (orientation)") {
                            Picker("Crystal", selection: $appState.acomCrystal) {
                                ForEach(CrystalChoice.allCases) { choice in
                                    Text(choice.rawValue).tag(choice)
                                }
                            }
                            if appState.acomCrystal == .custom {
                                Picker("Element", selection: $appState.customZ) {
                                    ForEach(ScatteringFactors.supportedElements, id: \.self) { z in
                                        Text("\(ScatteringFactors.symbols[z] ?? "?")  (Z=\(z))").tag(z)
                                    }
                                }
                                Picker("Structure", selection: $appState.customStructure) {
                                    ForEach(Crystal.CubicStructure.allCases) { s in
                                        Text(s.rawValue).tag(s)
                                    }
                                }
                                HStack {
                                    Text("a (Å)").font(.caption)
                                    TextField("a", value: $appState.customLatticeA,
                                              format: .number.precision(.fractionLength(0...4)))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                }
                            }
                            Button {
                                Task { await appState.generateOrientationPlan() }
                            } label: {
                                Label("Generate Plan", systemImage: "cube.transparent")
                            }
                            .disabled(appState.isBusy)
                            if appState.hasOrientationPlan, let plan = appState.orientationPlan {
                                LabeledContent("Templates", value: "\(plan.count)").font(.caption)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "Å⁻¹ / pixel  %.4f", appState.acomScale)).font(.caption)
                                Slider(value: $appState.acomScale, in: 0.001...0.05)
                            }

                            Button {
                                Task { await appState.runACOM() }
                            } label: {
                                Label("Run ACOM", systemImage: "circle.grid.cross")
                            }
                            .disabled(appState.isBusy || appState.braggVectors == nil)
                            if appState.braggVectors == nil {
                                Text("Detect Bragg disks first (Disks → Detect All Disks).")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if appState.hasOrientationMap {
                                Picker("Display", selection: $appState.acomDisplay) {
                                    ForEach(ACOMDisplayMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("mac4DSTEM")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Group {
                        if appState.hasDataset {
                            HSplitView {
                                DiffractionView()
                                    .overlay(paneFocusBorder(active: appState.activePane == .diffraction))
                                    .contentShape(Rectangle())
                                    .onTapGesture { appState.activePane = .diffraction }
                                    .frame(minWidth: 220)
                                StemImageView()
                                    .overlay(paneFocusBorder(active: appState.activePane == .realSpace))
                                    .contentShape(Rectangle())
                                    .onTapGesture { appState.activePane = .realSpace }
                                    .frame(minWidth: 220)
                            }
                            .focusable()
                            .focusEffectDisabled()
                            .onKeyPress(phases: .down) { press in
                                handleArrowKey(press)
                            }
                        } else {
                            VStack(spacing: 12) {
                                Text("mac4DSTEM").font(.title)
                                Text(appState.statusText).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Output strip: rolling log of operations below the panes.
                    if appState.showLogPane && appState.hasDataset {
                        Divider()
                        logPane
                    }
                }
                // Hard floor so dragging the sidebar/inspector can't crush the
                // image panes into distorted slivers.
                .frame(minWidth: 480)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Inspector as an explicit, independent panel so it coexists
                // with the tools sidebar (both can be open at once).
                if showInspector {
                    Divider()
                    DatasetInspector()
                        .frame(width: 300)
                        .background(.background)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(appState.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation { columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly }
                    } label: {
                        Label("Toggle tools", systemImage: "sidebar.leading")
                    }
                    .help("Show or hide the tools panel")
                }
                ToolbarItem(placement: .principal) {
                    Picker("Analysis mode", selection: $appState.analysisMode) {
                        ForEach(AnalysisMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(!appState.hasDataset)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.showLogPane.toggle()
                    } label: {
                        Label("Toggle output", systemImage: "rectangle.bottomthird.inset.filled")
                    }
                    .help("Show or hide the output log below the image panes")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showInspector.toggle()
                    } label: {
                        Label("Toggle inspector", systemImage: "sidebar.trailing")
                    }
                    .help("Show or hide the inspector panel")
                }
            }
        }
        .onChange(of: appState.analysisMode) {
            Task { await appState.runCurrentAnalysis() }
        }
        .onChange(of: appState.virtualShape) {
            appState.commitApertureChange()
        }
        .onChange(of: appState.realSpaceShape) {
            appState.updateRealSpaceRegion()
        }
        .onChange(of: appState.realSpaceRadius) {
            appState.updateRealSpaceRegion()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: h5Types,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    appState.openFile(url: url)
                }
            case .failure(let error):
                appState.present(error)
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    /// One pixel-size calibration row: numeric field + units label.
    /// Entering a value > 0 calibrates (setting default units if none);
    /// clearing to 0 returns to uncalibrated ("px" scale bars).
    private func pixelSizeField(_ label: String,
                                value: Binding<Double?>,
                                units: Binding<String?>,
                                defaultUnits: String) -> some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            TextField("0", value: Binding(
                get: { value.wrappedValue ?? 0 },
                set: {
                    value.wrappedValue = $0 > 0 ? $0 : nil
                    if $0 > 0, units.wrappedValue == nil {
                        units.wrappedValue = defaultUnits
                    }
                }
            ), format: .number.precision(.fractionLength(0...6)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
            Text(units.wrappedValue ?? defaultUnits)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
        }
    }

    /// Rolling output log below the image panes (auto-scrolls to the latest).
    private var logPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(appState.logMessages.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: appState.logMessages.count) {
                proxy.scrollTo(appState.logMessages.count - 1, anchor: .bottom)
            }
        }
        .frame(height: 100)
        .background(Color.black.opacity(0.15))
    }

    /// Arrow keys step the selected scan position (Shift = 10 px steps).
    private func handleArrowKey(_ press: KeyPress) -> KeyPress.Result {
        guard let d = appState.descriptor else { return .ignored }
        let step = press.modifiers.contains(.shift) ? 10 : 1
        var x = appState.selectedScan.x
        var y = appState.selectedScan.y
        switch press.key {
        case .leftArrow:  x -= step
        case .rightArrow: x += step
        case .upArrow:    y -= step
        case .downArrow:  y += step
        default: return .ignored
        }
        appState.selectScan(x: min(max(0, x), d.rx - 1),
                            y: min(max(0, y), d.ry - 1))
        return .handled
    }

    /// Accent border marking the active pane.
    private func paneFocusBorder(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(active ? Color.accentColor : Color.clear, lineWidth: 2)
            .padding(1)
            .allowsHitTesting(false)
    }

    /// A labelled slider that scrubs one scan axis. `count` is the axis length;
    /// the callback receives the clamped integer index.
    private func scanSlider(label: String, value: Int, count: Int,
                            onChange: @escaping (Int) -> Void) -> some View {
        HStack {
            Text("\(label) \(value)")
                .font(.caption.monospaced())
                .frame(width: 44, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0.rounded())) }
                ),
                in: 0...Double(max(count - 1, 1)),
                step: 1
            )
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
