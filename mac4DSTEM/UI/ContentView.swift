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
                        Label("Open .h5 File", systemImage: "folder")
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

                    Section("Calibration") {
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
                        }
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
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            HStack(spacing: 0) {
                Group {
                    if appState.hasDataset {
                        HSplitView {
                            DiffractionView()
                                .overlay(paneFocusBorder(active: appState.activePane == .diffraction))
                                .contentShape(Rectangle())
                                .onTapGesture { appState.activePane = .diffraction }
                                .frame(minWidth: 260)
                            StemImageView()
                                .overlay(paneFocusBorder(active: appState.activePane == .realSpace))
                                .contentShape(Rectangle())
                                .onTapGesture { appState.activePane = .realSpace }
                                .frame(minWidth: 260)
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
