import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showInspector = true

    var body: some View {
        NavigationSplitView {
            List {
                Section("File") {
                    Button {
                        appState.statusText = "File importer will be wired after HDF5 support is migrated."
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
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
