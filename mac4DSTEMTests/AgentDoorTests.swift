//
//  AgentDoorTests.swift
//  The agent door (App/AgentDoor): the HTTP it reads and writes, who may ask, which answer a path gets, what a window says about
//  itself, the two pictures, and one run through the real listener on the loopback address.
//
//  The pictures are checked on their pixels and the listener through a real connection: a route that returned 200 with the wrong
//  bytes, or a door that listened but refused its own token, would pass any test that stopped at the function call.
//

import XCTest
import DSTEMCore
import DSTEMSession
import ImageIO
@testable import mac4DSTEM

@MainActor
final class AgentDoorTests: XCTestCase {

    // MARK: Reading a request

    func testAWholeRequestIsReadWithItsPathQueryAndHeaders() {
        let bytes = Data("GET /v1/windows/w1/result.png?scale=2 HTTP/1.1\r\nHost: 127.0.0.1:5000\r\nAuthorization: Bearer abc\r\n\r\n".utf8)
        guard case .request(let request) = AgentHTTP.parse(bytes) else { return XCTFail("not read as a request") }
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/v1/windows/w1/result.png")
        XCTAssertEqual(request.query, ["scale": "2"])
        XCTAssertEqual(request.headers["host"], "127.0.0.1:5000")
        XCTAssertEqual(request.headers["authorization"], "Bearer abc")
        XCTAssertTrue(request.body.isEmpty)
    }

    /// Bytes arrive in pieces: until the blank line and the stated body are there, the answer is "more", never a guess.
    func testARequestInPiecesWaitsForItsEndAndItsBody() {
        let whole = Data("POST /v1/x HTTP/1.1\r\nHost: h\r\nContent-Length: 5\r\n\r\nhello".utf8)
        for cut in [10, whole.count - 6, whole.count - 1] {
            XCTAssertEqual(AgentHTTP.parse(whole.prefix(cut)), .incomplete, "cut at \(cut)")
        }
        guard case .request(let request) = AgentHTTP.parse(whole) else { return XCTFail("not read as a request") }
        XCTAssertEqual(request.body, Data("hello".utf8))
        // A slice that does not start at index 0 reads the same.
        let padded = Data("xx".utf8) + whole
        XCTAssertEqual(AgentHTTP.parse(padded.dropFirst(2)), .request(request))
    }

    func testWhatIsNotARequestIsRefusedByName() {
        func malformed(_ text: String) -> Bool {
            if case .malformed = AgentHTTP.parse(Data(text.utf8)) { return true }
            return false
        }
        XCTAssertTrue(malformed("hello\r\n\r\n"))
        XCTAssertTrue(malformed("GET nopath HTTP/1.1\r\n\r\n"))
        XCTAssertTrue(malformed("GET / HTTP/1.1\r\nbroken header\r\n\r\n"))
        XCTAssertTrue(malformed("POST / HTTP/1.1\r\nContent-Length: many\r\n\r\n"))
        XCTAssertTrue(malformed("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"))
        XCTAssertTrue(malformed("POST / HTTP/1.1\r\nContent-Length: \(AgentHTTP.maximumBodyBytes + 1)\r\n\r\n"))
        XCTAssertTrue(malformed("GET /" + String(repeating: "a", count: AgentHTTP.maximumHeaderBytes + 10)), "headers that never end are cut off")
    }

    func testAResponseStatesItsLengthAndClosesTheConnection() throws {
        let response = AgentHTTPResponse.json(["b": 1, "a": "x"])
        let wire = String(decoding: response.serialized(), as: UTF8.self)
        XCTAssertTrue(wire.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(wire.contains("Content-Length: \(response.body.count)\r\n"))
        XCTAssertTrue(wire.contains("Connection: close\r\n"))
        XCTAssertTrue(wire.hasSuffix("\r\n\r\n{\"a\":\"x\",\"b\":1}"), "sorted keys, the body after one blank line")
        // A number JSON cannot carry is a 500 that says so, not an exception.
        XCTAssertEqual(AgentHTTPResponse.json(["x": Double.nan]).status, 500)
    }

    // MARK: Who may ask

    private func request(_ path: String = "/v1", method: String = "GET", token: String? = "secret", host: String = "127.0.0.1:5000",
                         origin: String? = nil, query: [String: String] = [:]) -> AgentHTTPRequest {
        var headers = ["host": host]
        if let token { headers["authorization"] = "Bearer \(token)" }
        if let origin { headers["origin"] = origin }
        return AgentHTTPRequest(method: method, path: path, query: query, headers: headers)
    }

    /// Mutation: drop any one of the three checks in `AgentDoorGate.refusal` and one line here goes red.
    func testOnlyTheTokenHolderOnThisMacPasses() {
        func status(_ request: AgentHTTPRequest) -> Int? { AgentDoorGate.refusal(for: request, token: "secret", port: 5000)?.status }
        XCTAssertNil(status(request()))
        XCTAssertNil(status(request(host: "localhost:5000")))
        XCTAssertEqual(status(request(token: nil)), 401)
        XCTAssertEqual(status(request(token: "secreT")), 401)
        XCTAssertEqual(status(request(token: "secret-and-more")), 401)
        XCTAssertEqual(status(request(host: "evil.example:5000")), 403, "a page that reached the port through its own DNS name")
        XCTAssertEqual(status(request(host: "127.0.0.1:5001")), 403)
        XCTAssertEqual(status(request(origin: "https://example.com")), 403, "a web page, token or not")
        XCTAssertEqual(AgentDoorGate.refusal(for: request(token: ""), token: "", port: 5000)?.status, 401, "an empty token opens nothing")
    }

    // MARK: Which answer a path gets

    private func windowWithResultAndPattern() -> AppState {
        let state = AppState()
        state.publishProduct(kind: "virtual_annulus", displayName: "Virtual image", valueUnits: "intensity",
                             payload: .scalar(FloatImage(width: 12, height: 10, pixels: (0..<120).map(Float.init))))
        state.currentPattern = DiffractionPattern(qy: 32, qx: 32, pixels: [Float](repeating: 5, count: 1024))   // flat: no green of its own
        return state
    }

    private func object(_ response: AgentHTTPResponse) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }

    func testTheDoorIsReadOnlyAndNamesItsRoutes() throws {
        XCTAssertEqual(AgentDoorRouter.respond(to: request(method: "POST"), windows: []).status, 405)
        XCTAssertEqual(AgentDoorRouter.respond(to: request("/"), windows: []).status, 404)
        XCTAssertEqual(AgentDoorRouter.respond(to: request("/v1/nothing"), windows: []).status, 404)
        let index = try object(AgentDoorRouter.respond(to: request("/v1"), windows: []))
        XCTAssertEqual(index["access"] as? String, "read-only")
        let routes = try XCTUnwrap(index["routes"] as? [String: String])
        XCTAssertNotNil(routes["/v1/windows/<id>/result.png"])
    }

    /// `current` is the one open window; with none or several the refusal says which there are.
    func testCurrentNamesTheOnlyWindow() throws {
        let one = AgentDoorRouter.Window(id: "w1", state: AppState()), two = AgentDoorRouter.Window(id: "w2", state: AppState())
        XCTAssertEqual(AgentDoorRouter.respond(to: request("/v1/windows/current"), windows: []).status, 404)
        XCTAssertEqual(AgentDoorRouter.respond(to: request("/v1/windows/current"), windows: [one]).status, 200)
        let several = AgentDoorRouter.respond(to: request("/v1/windows/current"), windows: [one, two])
        XCTAssertEqual(several.status, 409)
        XCTAssertTrue((try object(several)["error"] as? String ?? "").contains("w1"))
        XCTAssertEqual(AgentDoorRouter.respond(to: request("/v1/windows/w2"), windows: [one, two]).status, 200)
        XCTAssertEqual(AgentDoorRouter.respond(to: request("/v1/windows/w9"), windows: [one, two]).status, 404)
        let list = try object(AgentDoorRouter.respond(to: request("/v1/windows"), windows: [one, two]))
        XCTAssertEqual((list["windows"] as? [[String: Any]])?.compactMap { $0["id"] as? String }, ["w1", "w2"])
    }

    /// A window with nothing in it and one with a result both answer in valid JSON, and the result is named as the app names it.
    func testAWindowSaysWhatItShows() throws {
        XCTAssertTrue(JSONSerialization.isValidJSONObject(AppState().agentSnapshot(id: "w1")), "an empty window")
        let state = windowWithResultAndPattern()
        let snapshot = try object(AgentDoorRouter.respond(to: request("/v1/windows/w1"), windows: [.init(id: "w1", state: state)]))
        let result = try XCTUnwrap(snapshot["result"] as? [String: Any])
        XCTAssertEqual(result["kind"] as? String, "virtual_annulus")
        XCTAssertEqual(result["name"] as? String, "Virtual image")
        XCTAssertEqual(result["width"] as? Int, 12)
        XCTAssertEqual(result["image"] as? String, "/v1/windows/w1/result.png")
        let pattern = try XCTUnwrap(snapshot["pattern"] as? [String: Any])
        XCTAssertEqual(pattern["width"] as? Int, 32)
        XCTAssertNotNil(snapshot["calibration"] as? [String: Any])
        XCTAssertNotNil((snapshot["disk_detection"] as? [String: Any])?["parameters"] as? [String: Any])
        XCTAssertTrue(snapshot["dataset"] is NSNull, "no file is open in this window")
    }

    // MARK: The pictures

    private func decoded(_ response: AgentHTTPResponse) throws -> (width: Int, height: Int, rgba: [UInt8]) {
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.contentType, "image/png")
        XCTAssertEqual(Array(response.body.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "PNG signature")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(response.body as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let bytes = Array(UnsafeBufferPointer(start: pixels, count: image.width * image.height * 4))   // the top row first
        return (image.width, image.height, bytes)
    }

    /// The result picture is the export's figure: the same pixels `resultExportImage` makes, at the asked scale.
    func testTheResultPictureIsTheExportedFigure() throws {
        let state = windowWithResultAndPattern()
        let windows = [AgentDoorRouter.Window(id: "w1", state: state)]
        let expected = try state.resultExportImage(scale: 1).image
        let one = try decoded(AgentDoorRouter.respond(to: request("/v1/windows/w1/result.png"), windows: windows))
        XCTAssertEqual(one.width, expected.width); XCTAssertEqual(one.height, expected.height)
        let two = try decoded(AgentDoorRouter.respond(to: request("/v1/windows/w1/result.png", query: ["scale": "2"]), windows: windows))
        XCTAssertEqual(two.width, 2 * expected.width)
        let odd = try decoded(AgentDoorRouter.respond(to: request("/v1/windows/w1/result.png", query: ["scale": "40"]), windows: windows))
        XCTAssertEqual(odd.width, expected.width, "a scale outside 1...3 is 1")
        XCTAssertEqual(AgentDoorRouter.respond(to: request("/v1/windows/w1/result.png"), windows: [.init(id: "w1", state: AppState())]).status, 404,
                       "no result yet is said, not drawn")
    }

    /// In the Disks task the pattern carries the detected disks where the pane draws them, and in no other task.
    /// Mutation: `agentPatternOverlays` drops the peaks, or ignores the task - red.
    func testThePatternPictureCarriesTheDetectedDisksInTheDisksTask() throws {
        let state = windowWithResultAndPattern()
        state.currentPeaks = [BraggPeak(x: 8, y: 24, intensity: 1)]
        let windows = [AgentDoorRouter.Window(id: "w1", state: state)]
        func pattern() throws -> (width: Int, height: Int, rgba: [UInt8]) {
            try decoded(AgentDoorRouter.respond(to: request("/v1/windows/w1/pattern.png"), windows: windows))
        }
        state.navigation.analysisMode = .strain   // a task whose pane draws nothing over the pattern
        let bare = try pattern()
        state.navigation.analysisMode = .disks
        let marked = try pattern()
        XCTAssertEqual(marked.width, 512, "a 32 px pattern is enlarged 16x")
        XCTAssertEqual(bare.rgba.count, marked.rgba.count)
        // The pixels the Disks task added: the cross at the disk's centre (no probe kernel, so no radius to draw).
        var count = 0, sumX = 0.0, sumY = 0.0, greenest = 0
        for y in 0..<marked.height {
            for x in 0..<marked.width {
                let i = (y * marked.width + x) * 4
                guard marked.rgba[i] != bare.rgba[i] || marked.rgba[i + 1] != bare.rgba[i + 1] || marked.rgba[i + 2] != bare.rgba[i + 2] else { continue }
                count += 1; sumX += Double(x); sumY += Double(y)
                greenest = max(greenest, Int(marked.rgba[i + 1]) - Int(marked.rgba[i]))
            }
        }
        XCTAssertGreaterThan(count, 10, "the detected disk is drawn")
        XCTAssertLessThan(count, 400, "a cross, not a filled disc")
        XCTAssertEqual(sumX / Double(max(count, 1)), 8.5 * 16, accuracy: 1.5)
        XCTAssertEqual(sumY / Double(max(count, 1)), 24.5 * 16, accuracy: 1.5, "y down, as the pane draws it")
        XCTAssertGreaterThan(greenest, 30, "in the pane's green")
        state.navigation.analysisMode = .virtualDetector
        XCTAssertNotEqual(try pattern().rgba, bare.rgba, "the Virtual Detector task draws its detector instead")
        let disks = try object(AgentDoorRouter.respond(to: request("/v1/windows/w1/disks"), windows: windows))
        XCTAssertEqual((disks["disks"] as? [[String: Any]])?.first?["x"] as? Double, 8)
    }

    func testTheListsAnswerInJSON() throws {
        let windows = [AgentDoorRouter.Window(id: "w1", state: windowWithResultAndPattern())]
        let lineage = try object(AgentDoorRouter.respond(to: request("/v1/windows/w1/lineage"), windows: windows))
        XCTAssertNotNil(lineage["recipe"] as? [Any])
        XCTAssertNotNil(lineage["lineage"])
        XCTAssertNotNil(try object(AgentDoorRouter.respond(to: request("/v1/windows/w1/log"), windows: windows))["lines"] as? [String])
        XCTAssertEqual(AgentDoorRouter.respond(to: request("/v1/windows/w1/objects"), windows: windows).status, 404, "no phase map classified")
    }

    // MARK: The door itself

    func testWindowsAreNamedInOrderAndForgottenWhenTheyClose() {
        let door = AgentDoor(discoveryURL: nil)
        let first = AppState(), second = AppState()
        door.enroll(first); door.enroll(second); door.enroll(first)
        XCTAssertEqual(door.liveWindows.map(\.id), ["w1", "w2"])
        door.withdraw(first)
        XCTAssertEqual(door.liveWindows.map(\.id), ["w2"])
        door.enroll(first)
        XCTAssertEqual(door.liveWindows.map(\.id), ["w2", "w3"], "a name is never given twice")
    }

    func testTheStatusRowSaysWhatTheDoorIsDoing() {
        XCTAssertEqual(AgentSettingsSection.statusText(.off, requests: 0), "Off")
        XCTAssertEqual(AgentSettingsSection.statusText(.listening(port: 5000), requests: 0), "On (port 5000), no agent has asked yet")
        XCTAssertEqual(AgentSettingsSection.statusText(.listening(port: 5000), requests: 1), "On (port 5000), 1 request answered")
        XCTAssertEqual(AgentSettingsSection.statusText(.failed("no"), requests: 0), "Could not open: no")
    }

    /// The whole way once: the door opens on the loopback address, writes its file for this account only, answers the token holder,
    /// refuses a request without the token, and takes its file away when it closes.
    func testTheOpenDoorAnswersOverTheLoopbackAddress() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-door-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("agent-door.json")
        let door = AgentDoor(discoveryURL: file)
        let state = windowWithResultAndPattern()
        door.enroll(state)
        door.setEnabled(true)
        defer { door.setEnabled(false) }
        for _ in 0..<250 where door.status == .starting { try await Task.sleep(for: .milliseconds(20)) }
        guard case .listening(let port) = door.status else { return XCTFail("the door did not open: \(door.status)") }

        let record = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(record["port"] as? Int, Int(port))
        XCTAssertEqual(record["api"] as? Int, AgentDoor.apiVersion)
        let token = try XCTUnwrap(record["token"] as? String)
        XCTAssertEqual(token.count, 64)
        let permissions = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int)
        XCTAssertEqual(permissions & 0o077, 0, "nobody but this account reads the token")

        let session = URLSession(configuration: .ephemeral)
        var asked = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/windows")))
        asked.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: asked)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let list = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((list["windows"] as? [[String: Any]])?.first?["id"] as? String, "w1")
        XCTAssertEqual(door.requestCount, 1)

        var picture = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/windows/current/result.png")))
        picture.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (png, _) = try await session.data(for: picture)
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])

        let (_, refused) = try await session.data(for: URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/windows"))))
        XCTAssertEqual((refused as? HTTPURLResponse)?.statusCode, 401)
        XCTAssertEqual(door.requestCount, 2, "a refused request is not counted as answered")

        door.setEnabled(false)
        XCTAssertEqual(door.status, .off)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "a closed door leaves no file")
    }
}
