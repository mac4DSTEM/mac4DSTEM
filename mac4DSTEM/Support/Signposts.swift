//
//  Signposts.swift
//  Role: the app's own timings. An `os_signpost` interval around each heavy action (open the demo, Re-calibrate Origin, the virtual
//        image, Detect All Disks, strain, Auto ID, Quantify) in one subsystem, so `PerformanceJourney` reads them with
//        `XCTOSSignpostMetric` and Instruments shows them. No numerics, no state; free when nothing listens. (macTEM's `Signposts`.)
//

import os

enum Signposts {
    static let subsystem = "com.mac4dstem.mac4DSTEM"
    static let category = "performance"
    private static let log = OSLog(subsystem: subsystem, category: category)

    struct Interval: Sendable {
        fileprivate let id: OSSignpostID
        fileprivate let name: StaticString
    }

    static func begin(_ name: StaticString) -> Interval {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return Interval(id: id, name: name)
    }

    static func end(_ interval: Interval) {
        os_signpost(.end, log: log, name: interval.name, signpostID: interval.id)
    }
}
