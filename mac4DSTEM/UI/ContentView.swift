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
        NavigationSplitView {
            List {
                Section("File") {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Open .h5 File", systemImage: "folder")
                    }
                }

                Section("Analysis") {
                    Picker("Mode", selection: Bindable(appState).analysisMode) {
                        ForEach(AnalysisMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("mac4DSTEM")
        } detail: {
            VStack(spacing: 12) {
                Text("mac4DSTEM")
                    .font(.title)
                Text(appState.statusText)
                    .foregroundStyle(.secondary)
                if appState.currentPattern != nil {
                    Text("Dataset loaded. Metal display migration is next.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
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
}

#Preview {
    ContentView()
        .environment(AppState())
}
