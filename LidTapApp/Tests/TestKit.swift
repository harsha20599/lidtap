import AppKit
import Foundation

/// Minimal test runner (the Command Line Tools here have no working XCTest/SwiftPM).
@MainActor
enum T {
    struct Result { var suite: String; var name: String; var status: String; var detail: String }
    static var results: [Result] = []
    static var suite = ""
    static var current = ""
    static var failures = 0
    nonisolated static let fixtures = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        .appendingPathComponent("../Tests/Fixtures").standardized
    nonisolated static let artifacts: URL = {
        let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("test-artifacts")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func run(_ name: String, _ body: () throws -> Void) {
        current = name
        let before = failures
        let start = Date()
        do {
            try body()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            if failures == before {
                results.append(Result(suite: suite, name: name, status: "PASS", detail: "\(ms) ms"))
                print("  ✓ \(name) (\(ms) ms)")
            }
        } catch let s as Skip {
            results.append(Result(suite: suite, name: name, status: "SKIP", detail: s.reason))
            print("  ⊘ \(name): SKIPPED: \(s.reason)")
        } catch {
            fail("threw \(error)")
        }
    }

    static func fail(_ msg: String, file: String = #fileID, line: Int = #line) {
        failures += 1
        results.append(Result(suite: suite, name: current, status: "FAIL", detail: "\(msg) [\(file):\(line)]"))
        print("  ✗ \(current): \(msg) [\(file):\(line)]")
    }

    static func expect(_ cond: Bool, _ msg: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        if !cond { fail(msg(), file: file, line: line) }
    }

    static func note(_ msg: String) { print("      · \(msg)") }

    struct Skip: Error { let reason: String }

    /// Pumps AppKit events and the main run loop until `cond` holds or the timeout passes.
    /// (Plain RunLoop spinning never dispatches mouse/keyboard events to windows, as NSApp.run would.)
    @discardableResult
    static func wait(_ timeout: Double, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !cond() && Date() < end {
            if let ev = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true) {
                NSApp.sendEvent(ev)
            }
        }
        return cond()
    }

    static func sleep(_ seconds: Double) { _ = wait(seconds) { false } }

    static func tempDir(_ name: String) -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("lidtap-tests-\(name)-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    nonisolated static func loadDataset(_ file: String = "dataset_2x2.json") -> Dataset {
        let data = try! Data(contentsOf: fixtures.appendingPathComponent(file))
        return try! JSONDecoder().decode(Dataset.self, from: data)
    }

    static func summary() -> Int32 {
        let pass = results.filter { $0.status == "PASS" }.count
        let skip = results.filter { $0.status == "SKIP" }.count
        let failed = Set(results.filter { $0.status == "FAIL" }.map { "\($0.suite) / \($0.name)" })
        print("\n════ \(pass) passed · \(failed.count) failed · \(skip) skipped ════")
        for f in failed.sorted() { print("  FAILED: \(f)") }
        var md = "| Suite | Test | Result | Detail |\n|---|---|---|---|\n"
        for r in results { md += "| \(r.suite) | \(r.name) | \(r.status) | \(r.detail.replacingOccurrences(of: "|", with: "/")) |\n" }
        try? md.write(to: artifacts.appendingPathComponent("results.md"), atomically: true, encoding: .utf8)
        return failed.isEmpty ? 0 : 1
    }
}

/// Builds a live-shaped TapEvent from a recorded sample.
func event(from s: TapSample, id: Int, gated: String? = nil, noise: Double = 0) -> TapEvent {
    let j = { (rows: [[Double]], k: Double) in noise == 0 ? rows : rows.map { $0.map { $0 + Double.random(in: -k...k) } } }
    return TapEvent(id: id, time: MachClock.now(), date: Date(), g: j(s.g, noise), a: j(s.a, noise / 100),
                    peakG: s.peakG, peakA: s.peakA, lid: s.lid, threshold: 1, noise: 0.1, gated: gated)
}

/// Renders a SwiftUI view offscreen to a PNG in the artifacts folder.
@MainActor
@discardableResult
func snapshot<V: View>(_ view: V, size: CGSize, name: String, dark: Bool = true) -> URL? {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
        .environment(\.colorScheme, dark ? .dark : .light))
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.backgroundColor = dark ? NSColor(white: 0.12, alpha: 1) : .windowBackgroundColor
    host.layoutSubtreeIfNeeded()
    T.sleep(0.3)  // let SwiftUI settle animations and async state
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    let url = T.artifacts.appendingPathComponent("\(name).png")
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
    return url
}

import SwiftUI
