//
//  ContentView.swift
//  Role: The main window. A three-panel layout — Sidebar | (Diffraction |
//        Result) | Inspector — with an instrument-style toolbar, a status bar,
//        the file importer, and the global error alert.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var showImporter = false
    @State private var showInspector = true

    // .h5 / .hdf5 have no guaranteed system UTType; fall back to generic data.
    private var h5Types: [UTType] {
        [UTType(filenameExtension: "h5"),
         UTType(filenameExtension: "hdf5"),
         UTType(filenameExtension: "emd"),
         .data].compactMap { $0 }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(showImporter: $showImporter)
        } detail: {
            HSplitView {
                DiffractionView()
                    .frame(minWidth: 280)
                StemImageView()
                    .frame(minWidth: 280)
            }
            .frame(minWidth: 600, minHeight: 420)
            .toolbar { toolbarContent }
            .inspector(isPresented: $showInspector) {
                DatasetInspector()
            }
            .safeAreaInset(edge: .bottom) { statusBar }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: h5Types,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let u = urls.first { app.openFile(url: u) }
            case .failure(let err):  app.present(err)
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { app.errorMessage != nil },
                                    set: { if !$0 { app.errorMessage = nil } })) {
            Button("OK", role: .cancel) { app.errorMessage = nil }
        } message: {
            Text(app.errorMessage ?? "")
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Analysis",
                   selection: Binding(get: { app.analysisMode },
                                      set: { app.changeMode($0) })) {
                ForEach(AnalysisMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Choose an analysis. Strain / Ptycho / ACOM arrive in later stages.")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $app.logScale) {
                Label("Log", systemImage: "function")
            }
            .toggleStyle(.button)
            .help("Log scale (essential for CBED)")

            Picker("Colormap", selection: $app.colormap) {
                ForEach(ColormapKind.allCases) { Text($0.displayName).tag($0) }
            }
            .frame(width: 150)

            Button {
                showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 14) {
            if app.isBusy {
                ProgressView().controlSize(.small)
            }
            Text(app.statusText)
                .lineLimit(1)
            Spacer()
            Text("scan (x: \(app.selectedScan.x), y: \(app.selectedScan.y))")
                .monospaced()
            if let (lo, hi) = app.patternMinMax {
                Text(String(format: "I[min %.3g, max %.3g]", lo, hi))
                    .monospaced()
            }
            Text(gpuName)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private var gpuName: String {
        MetalEngine.shared.device.name
    }
}
