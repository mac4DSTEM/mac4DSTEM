import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showImporter = false
    @State private var showInspector = true

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
        return NavigationSplitView {
            List {
                Section("File") {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Open .h5 File", systemImage: "folder")
                    }
                }

                Section("Analysis") {
                    Picker("Mode", selection: $appState.analysisMode) {
                        ForEach(AnalysisMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
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
                }
            }
            .navigationTitle("mac4DSTEM")
        } detail: {
            Group {
                if appState.hasDataset {
                    DiffractionView()
                } else {
                    VStack(spacing: 12) {
                        Text("mac4DSTEM").font(.title)
                        Text(appState.statusText).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
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
            .inspector(isPresented: $showInspector) {
                DatasetInspector()
            }
            .toolbar {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
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
