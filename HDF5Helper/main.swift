//
//  main.swift (HDF5Helper)
//  Role: the HDF5 helper XPC service. libhdf5 runs here, not in the app: a crafted file that crashes or hangs it ends
//        this process and the app gets an error sentence (docs/hdf5-helper.md). The work is `HDF5HelperService`
//        (DSTEMCore), the same code the unit tests drive in process.
//

import DSTEMCore
import Foundation

nonisolated final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service = HDF5HelperService(isolated: true)

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HDF5HelperXPC.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

let delegate = HelperListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
