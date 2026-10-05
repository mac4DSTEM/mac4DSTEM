// Scratch reproduction (2026-10-05): what the shipped H5Reader discovery does with Velox .emd files.
import Foundation
@main struct VeloxRepro {
    static func main() async {
        for path in CommandLine.arguments.dropFirst() {
            let name = (path as NSString).lastPathComponent
            do {
                let r = try H5Reader(path: path)
                let d = try await r.discoverPrimaryDataset()
                print("OPENED\t\(name)\t\(d.datasetPath)\t\(d.shape)\tstoredRank \(d.storedRank)")
            } catch { print("REFUSED\t\(name)\t\(error)") }
        }
    }
}
