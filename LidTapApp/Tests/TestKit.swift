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

/// The same tap landing harder or softer: twist and jolt scaled together until its strength is `strength`.
func resized(_ e: TapEvent, strength: Double) -> TapEvent {
    let k = strength / max(e.strength, 1e-9)
    return TapEvent(id: e.id, time: e.time, date: e.date, g: e.g.map { $0.map { $0 * k } }, a: e.a.map { $0.map { $0 * k } },
                    peakG: e.peakG * k, peakA: e.peakA * k, lid: e.lid, threshold: e.threshold, noise: e.noise, gated: e.gated,
                    gateDetail: e.gateDetail, preMotion: e.preMotion)
}

func resized(_ s: TapSample, strength: Double) -> TapSample {
    let k = strength / max(TapStrength.strength(twist: s.peakG, impact: TapStrength.impact(s.a)), 1e-9)
    var out = s
    out.g = s.g.map { $0.map { $0 * k } }
    out.a = s.a.map { $0.map { $0 * k } }
    out.peakG = s.peakG * k
    out.peakA = s.peakA * k
    return out
}

/// A raw sensor recording from a real Mac: the sensor's own gyroscope (deg/s) and accelerometer (g) samples, with
/// the stretches of it named (e.g. "still", "z0" while the top-left corner is tapped, "typing").
///
/// Recordings are someone's own Mac and hands, so none is kept in the repository; tests that need one are skipped
/// without it. To use one, put two files in Tests/Fixtures:
///   <name>.json  {"rate": samples per second, "rows": row count, "segments": [{"name", "start", "end"}]} (seconds)
///   <name>.bin   raw DEFLATE of little-endian int32 rows [gx, gy, gz, ax, ay, az] in Q16.16, evenly spaced at
///                `rate`, each row stored as its difference from the row before
/// `tools/imu_probe.py` shows how to read the sensors.
struct RawStream {
    var rate: Double
    var gyro: [SIMD3<Double>]   // deg/s
    var accel: [SIMD3<Double>]  // g
    var segments: [(name: String, start: Double, end: Double)]

    func segment(_ name: String) -> (start: Double, end: Double) {
        let s = segments.first { $0.name == name }!
        return (s.start, s.end)
    }
}

extension T {
    /// `name` is a fixture, or with `directory` a recording anywhere (`<name>.json` beside `<name>.bin`).
    /// Throws `Skip` when the recording isn't there.
    nonisolated static func loadStream(_ name: String = "pro14_stream", in directory: URL? = nil) throws -> RawStream {
        let dir = directory ?? fixtures
        guard let json = try? Data(contentsOf: dir.appendingPathComponent("\(name).json")),
              let packed = try? Data(contentsOf: dir.appendingPathComponent("\(name).bin")) else {
            throw Skip(reason: "needs a raw recording, \(name).json and \(name).bin in \(directory == nil ? "Tests/Fixtures" : dir.path) (see RawStream)")
        }
        let meta = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let data = try (packed as NSData).decompressed(using: .zlib) as Data
        let rows = meta["rows"] as! Int
        precondition(data.count == rows * 24, "stream fixture is \(data.count) bytes, want \(rows * 24)")
        var gyro: [SIMD3<Double>] = [], accel: [SIMD3<Double>] = []
        var acc = [Int32](repeating: 0, count: 6)   // rows are stored as differences
        data.withUnsafeBytes { raw in
            for r in 0..<rows {
                for c in 0..<6 { acc[c] &+= Int32(littleEndian: raw.loadUnaligned(fromByteOffset: (r * 6 + c) * 4, as: Int32.self)) }
                gyro.append(SIMD3(Double(acc[0]), Double(acc[1]), Double(acc[2])) / 65536)
                accel.append(SIMD3(Double(acc[3]), Double(acc[4]), Double(acc[5])) / 65536)
            }
        }
        let segments = (meta["segments"] as! [[String: Any]]).map {
            (name: $0["name"] as! String, start: ($0["start"] as! NSNumber).doubleValue, end: ($0["end"] as! NSNumber).doubleValue)
        }
        return RawStream(rate: (meta["rate"] as! NSNumber).doubleValue, gyro: gyro, accel: accel, segments: segments)
    }
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
