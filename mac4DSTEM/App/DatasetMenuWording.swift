//
//  DatasetMenuWording.swift
//  The Dataset menu's session items. They said "Session Sidecar" while the panel they open says "Save Session": one word
//  for the file that keeps a dataset's analysis.
//

enum DatasetMenuWording {
    static let saveResult = "Save Current Result to Session"
    static let saveCalibration = "Save Calibration to Session"
    static let allowAccess = "Allow Access to Session File…"
    static let change = "Change Session File…"
    static let ignore = "Ignore Session…"
    static let all = [saveResult, saveCalibration, allowAccess, change, ignore]
}
