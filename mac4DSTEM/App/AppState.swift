import Foundation

struct SimpleError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

/// A real-space scan position. x is the scan column and y is the scan row.
struct ScanPos: Equatable {
    var x: Int
    var y: Int
}

/// The virtual-detector aperture in detector pixels.
struct Aperture: Equatable {
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float

    init(centerX: Float = 0, centerY: Float = 0, inner: Float = 0, outer: Float = 20) {
        self.centerX = centerX
        self.centerY = centerY
        self.inner = inner
        self.outer = outer
    }
}

enum PatternDisplayMode: String, CaseIterable, Identifiable {
    case current = "Current"
    case mean = "Mean"
    case max = "Max"

    var id: String { rawValue }
}

enum VirtualShapeMode: String, CaseIterable, Identifiable {
    case annulus = "Annulus"
    case rectangle = "Rectangle"
    case point = "Point"

    var id: String { rawValue }
}

enum DPCDisplayMode: String, CaseIterable, Identifiable {
    case magnitude = "Magnitude"
    case angle = "Angle"
    case colorWheel = "Color Wheel"
    case idpc = "iDPC"

    var id: String { rawValue }
}

enum AnalysisMode: String, CaseIterable, Identifiable {
    case virtualDetector = "Virtual Det"
    case dpc = "DPC"
    case disks = "Disks"
    case strain = "Strain"
    case ptychography = "Ptycho"
    case acom = "ACOM"

    var id: String { rawValue }

    var isAvailable: Bool {
        self == .virtualDetector || self == .dpc || self == .disks
    }
}

@Observable
final class AppState {
    private var reader: H5Reader?
    private var fourD: FourDArray?
    private var openURL: URL?

    var datasets: [DatasetDescriptor] = []
    var descriptor: DatasetDescriptor?
    var selectedScan = ScanPos(x: 0, y: 0)
    var acceleratingVoltage: Double?

    var currentPattern: DiffractionPattern?
    var resultImage: FloatImage?
    var resultRGBA: RGBAImage?

    var meanPattern: DiffractionPattern?
    var maxPattern: DiffractionPattern?
    var patternDisplayMode: PatternDisplayMode = .current {
        didSet { patternVersion &+= 1 }
    }

    var calibration = Calibration()
    var patternVersion = 0
    var resultVersion = 0

    var aperture = Aperture()
    var virtualShape: VirtualShapeMode = .annulus
    var dpcDisplay: DPCDisplayMode = .magnitude
    var colormap: ColormapKind = .viridis {
        didSet {
            patternVersion &+= 1
            resultVersion &+= 1
        }
    }
    var logScale = true {
        didSet { patternVersion &+= 1 }
    }
    var analysisMode: AnalysisMode = .virtualDetector

    var isBusy = false
    var statusText = "No file loaded"
    var errorMessage: String?

    var displayedPattern: DiffractionPattern? {
        switch patternDisplayMode {
        case .current: return currentPattern
        case .mean: return meanPattern ?? currentPattern
        case .max: return maxPattern ?? currentPattern
        }
    }

    var patternMinMax: (Float, Float)? { displayedPattern?.minMax }

    var hasDataset: Bool { descriptor?.is4D == true }

    func changeMode(_ mode: AnalysisMode) {
        guard mode.isAvailable else { return }
        analysisMode = mode
    }

    func openFile(url: URL) {
        Task { await openFileAsync(url: url) }
    }

    func selectDataset(_ descriptor: DatasetDescriptor) {
        guard let reader else { return }
        Task { await activate(descriptor: descriptor, reader: reader) }
    }

    func openManualPath(_ datasetPath: String) {
        guard let reader else {
            present(SimpleError("Open a file before entering a dataset path."))
            return
        }

        Task {
            isBusy = true
            defer { isBusy = false }

            do {
                let descriptor = try await reader.describe(path: datasetPath)
                if !datasets.contains(where: { $0.datasetPath == descriptor.datasetPath }) {
                    datasets.append(descriptor)
                }
                await activate(descriptor: descriptor, reader: reader)
            } catch {
                present(error)
            }
        }
    }

    func selectScan(x: Int, y: Int) {
        selectedScan = ScanPos(x: x, y: y)
        Task { await loadCurrentPattern() }
    }

    func present(_ error: Error) {
        errorMessage = error.localizedDescription
        statusText = "Error: \(error.localizedDescription)"
    }

    private func openFileAsync(url: URL) async {
        isBusy = true
        statusText = "Opening \(url.lastPathComponent)..."
        errorMessage = nil
        defer { isBusy = false }

        if let openURL {
            openURL.stopAccessingSecurityScopedResource()
        }

        let accessed = url.startAccessingSecurityScopedResource()
        openURL = accessed ? url : nil

        do {
            let reader = try H5Reader(path: url.path)
            let descriptor = try await reader.discoverPrimaryDataset()
            self.reader = reader
            datasets = [descriptor]
            await activate(descriptor: descriptor, reader: reader)
        } catch {
            present(error)
        }
    }

    private func activate(descriptor: DatasetDescriptor, reader: H5Reader) async {
        guard descriptor.is4D else {
            present(H5Error.unsupportedRank(descriptor.shape.count))
            return
        }

        self.descriptor = descriptor
        fourD = FourDArray(reader: reader, descriptor: descriptor)
        selectedScan = ScanPos(x: 0, y: 0)
        aperture = Aperture(
            centerX: Float(descriptor.qx) / 2,
            centerY: Float(descriptor.qy) / 2,
            inner: 0,
            outer: Float(min(descriptor.qx, descriptor.qy)) / 4
        )
        acceleratingVoltage = await reader.readDoubleAttribute("accelerating_voltage")
        meanPattern = nil
        maxPattern = nil
        resultImage = nil
        resultRGBA = nil

        await loadCurrentPattern()
        statusText = "Loaded \(descriptor.fileName) at \(descriptor.datasetPath)"
    }

    private func loadCurrentPattern() async {
        guard let descriptor, let fourD else { return }

        do {
            currentPattern = try await fourD.pattern(ry: selectedScan.y, rx: selectedScan.x)
            patternVersion &+= 1
            statusText = "Pattern x \(selectedScan.x), y \(selectedScan.y) from \(descriptor.fileName)"
        } catch {
            present(error)
        }
    }
}
