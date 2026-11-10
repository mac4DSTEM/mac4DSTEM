//
//  FeedbackLinks.swift
//  Role: where Help > Send Feedback and Help > mac4DSTEM Support go. Feedback is an email the person writes and sends from their
//        own mail app, addressed to the project, with the app and macOS versions prefilled so a report names its build. The app
//        itself sends nothing (the privacy label stays "Data Not Collected").
//

import Foundation

nonisolated enum FeedbackLinks {
    static let address = "mail@mac4dstem.com"
    static let support = URL(string: "https://mac4dstem.com/support.html")

    /// "5.2.1 (41)" from the bundle; "unknown" for a bundle without a version (a test host).
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "unknown" }
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }

    /// The `mailto:` link: subject and a first line with the two versions, then room to write. Pure, so it is tested.
    static func mail(appVersion: String, systemVersion: String) -> URL? {
        var link = URLComponents()
        link.scheme = "mailto"
        link.path = address
        link.queryItems = [
            URLQueryItem(name: "subject", value: "mac4DSTEM feedback"),
            URLQueryItem(name: "body", value: "\n\nmac4DSTEM \(appVersion), macOS \(systemVersion)"),
        ]
        return link.url
    }

    static var mail: URL? {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return mail(appVersion: appVersion, systemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    }
}
