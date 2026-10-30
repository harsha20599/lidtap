import AppKit
import ApplicationServices
import IOKit

/// Drives the installed LidTap.app through its --test-hooks interface, with its own data folder.
@MainActor
func endToEndTests() {
    T.suite = "End to end"
    print("\n▶ End to end (installed ~/Applications/LidTap.app)")
    let appURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/LidTap.app")
    guard FileManager.default.fileExists(atPath: appURL.path) else {
        T.run("installed app") { throw T.Skip(reason: "LidTap.app not installed") }
        return
    }

    // Isolated data: your real taps, zone actions chosen so nothing destructive happens.
    let dir = T.tempDir("e2e")
    let store = Store(directory: dir)
    store.save(T.loadDataset())
    var cfg = AppConfig()
    cfg.actions = ["z0": ZoneAction(kind: .openApp, appBundleID: "com.apple.calculator", appName: "Calculator"),
                   "z1": ZoneAction(kind: .none), "z2": ZoneAction(kind: .none), "z3": ZoneAction(kind: .privacyGuard)]
    cfg.playSounds = false
    store.save(cfg)

    let userInstanceWasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "dev.lidtap.LidTap").isEmpty
    for a in NSRunningApplication.runningApplications(withBundleIdentifier: "dev.lidtap.LidTap") { a.terminate() }
    T.wait(3) { NSRunningApplication.runningApplications(withBundleIdentifier: "dev.lidtap.LidTap").isEmpty }

    let launch = Process()
    launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    launch.arguments = ["-n", "-a", appURL.path, "--env", "LIDTAP_DATA_DIR=\(dir.path)", "--args", "--test-hooks"]
    try? launch.run()
    launch.waitUntilExit()

    func status() -> [String: Any] {
        guard let d = try? Data(contentsOf: store.statusURL) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }
    func last() -> [String: Any] { status()["last"] as? [String: Any] ?? [:] }
    func send(_ cmd: String, _ label: String = "") {
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("dev.lidtap.test"), object: nil,
                                                                    userInfo: ["cmd": cmd, "label": label], deliverImmediately: true)
    }
    var pid: pid_t = 0
    let calculator = "com.apple.calculator"
    let calcWasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: calculator).isEmpty
    let overlayLevel = Int(CGWindowLevelForKey(.screenSaverWindow))

    T.run("launches, streams the sensor under its own identity, trains") {
        T.expect(T.wait(20) { (status()["trained"] as? Bool) == true && ((status()["rate"] as? Double) ?? 0) > 500 },
                 "status: \(status())")
        let s = status()
        pid = pid_t(s["pid"] as? Int ?? 0)
        T.note("pid \(pid), rate \(s["rate"] ?? "-") Hz, model \(s["model"] ?? "-") \(Int(((s["accuracy"] as? Double) ?? 0) * 100))%, accessibility \(s["accessibility"] ?? "-")")
    }
    guard pid != 0 else { return cleanup() }

    // The status item lives in the app's "extras" menu bar; find it through Accessibility (it is not a normal window).
    func statusItem() -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(pid)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar else { return nil }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success else { return nil }
        return (kids as? [AXUIElement])?.first
    }

    T.run("menu bar item is present") {
        T.expect(T.wait(5) { statusItem() != nil }, "no status item in the menu bar")
    }

    T.run("clicking the menu bar icon opens the panel") {
        guard let item = statusItem() else { throw T.Skip(reason: "status item not found") }
        let before = Set(windows(pid: pid).map(\.id))
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        let opened = T.wait(3) { windows(pid: pid).contains { !before.contains($0.id) && $0.bounds.width >= 300 && $0.bounds.width < 400 } }
        T.expect(opened, "panel did not open")
        if let panel = windows(pid: pid).first(where: { !before.contains($0.id) && $0.bounds.width >= 300 && $0.bounds.width < 400 }) {
            T.sleep(0.8)
            capture(windowID: panel.id, name: "e2e_menu_panel")
            T.note("panel \(Int(panel.bounds.width))×\(Int(panel.bounds.height))")
        }
        AXUIElementPerformAction(item, kAXPressAction as CFString)  // close it again
        T.sleep(0.6)
    }

    // Finds a control by its accessibility title or label anywhere under `el`.
    func findControl(_ el: AXUIElement, named name: String, depth: Int = 0) -> AXUIElement? {
        guard depth < 25 else { return nil }
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXLabelValueAttribute] {
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let s = v as? String, s.hasPrefix(name) { return el }
        }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids) == .success else { return nil }
        for k in (kids as? [AXUIElement]) ?? [] { if let f = findControl(k, named: name, depth: depth + 1) { return f } }
        return nil
    }

    T.run("Settings… in the menu closes the menu as Settings opens") {
        guard let item = statusItem() else { throw T.Skip(reason: "status item not found") }
        let isPanel = { (w: WindowInfo) in w.bounds.width >= 300 && w.bounds.width < 400 }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        T.expect(T.wait(3) { windows(pid: pid).contains(where: isPanel) }, "panel did not open")
        T.sleep(0.5)
        var settingsRow: AXUIElement?
        var wins: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &wins)
        for w in (wins as? [AXUIElement]) ?? [] { if let f = findControl(w, named: "Settings") { settingsRow = f; break } }
        guard let settingsRow else { throw T.Skip(reason: "Settings… row not found through Accessibility") }
        AXUIElementPerformAction(settingsRow, kAXPressAction as CFString)
        T.expect(T.wait(4) { windows(pid: pid).contains { $0.layer == 0 && $0.bounds.width >= 880 } }, "Settings did not open")
        T.expect(T.wait(2) { !windows(pid: pid).contains(where: isPanel) }, "menu panel stayed open over Settings")
        // Close Settings again so later tests start clean.
        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        script.arguments = ["-e", "tell application \"System Events\" to tell (first process whose unix id is \(pid)) to keystroke \"w\" using command down"]
        try? script.run(); script.waitUntilExit()
        T.sleep(0.5)
    }

    T.run("moving the pointer blocks taps; a still pointer doesn't") {
        let start = CGEvent(source: nil)?.location ?? .zero
        let src = CGEventSource(stateID: .hidSystemState)
        let mover = Thread {
            for i in 0..<30 {
                let p = CGPoint(x: start.x + Double(i % 6), y: start.y)
                CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
                usleep(16_000)
            }
            CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        mover.start()
        T.sleep(0.25)
        send("tap", "z1")
        T.wait(3) { (last()["outcome"] as? String) != nil && (last()["detail"] as? String)?.contains("pointer") == true }
        T.note("while moving: \(last())")
        T.expect(last()["outcome"] as? String == "ignored" && (last()["detail"] as? String)?.contains("pointer") == true,
                 "tap while the pointer moved: \(last())")
        T.sleep(1.5)
        send("tap", "z1")
        T.wait(3) { (last()["detail"] as? String) == "Nothing" }
        T.expect(last()["detail"] as? String == "Nothing", "tap with a still pointer: \(last())")
    }

    T.run("tap on zone 1 opens Calculator and shows feedback") {
        if let c = NSRunningApplication.runningApplications(withBundleIdentifier: calculator).first { c.hide() }
        send("tap", "z0")
        T.expect(T.wait(6) { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == calculator }, "Calculator not frontmost")
        let feedback = windows(pid: pid).first { $0.layer == Int(CGWindowLevelForKey(.popUpMenuWindow)) }
        T.wait(3) { (last()["label"] as? String) == "z0" }  // status.json refreshes once a second
        if let feedback { capture(windowID: feedback.id, name: "e2e_tap_feedback") }
        T.note("last: \(last())")
        T.expect(last()["outcome"] as? String == "acted" && last()["label"] as? String == "z0", "status last \(last())")
    }

    T.run("zone with 'Nothing' does nothing") {
        send("tap", "z1")
        T.wait(3) { (last()["label"] as? String) == "z1" }
        T.expect(last()["detail"] as? String == "Nothing", "last \(last())")
    }

    T.run("gated and guarded taps don't act; guard zone toggles Privacy Guard") {
        let mic = micState()
        send("tap", "z3")
        T.expect(T.wait(4) { (status()["guardActive"] as? Bool) == true }, "guard did not engage from its zone")
        T.sleep(0.8)
        let overlays = windows(pid: pid).filter { $0.layer == overlayLevel }
        T.expect(overlays.count == NSScreen.screens.count, "overlays \(overlays.count)")
        if let o = overlays.first { capture(windowID: o.id, name: "e2e_privacy_guard") }
        T.expect(micState() != mic || mic.values.allSatisfy(\.isEmpty), "mic not muted by the app")
        send("tap", "z0")
        T.wait(3) { (last()["outcome"] as? String) == "guarded" }
        T.expect(last()["outcome"] as? String == "guarded", "tap while guarded: \(last())")
        send("tap", "z3")
        T.expect(T.wait(4) { (status()["guardActive"] as? Bool) == false }, "guard zone did not release")
        T.sleep(0.6)
        T.expect(micState() == mic, "mic not restored by the app")
        T.expect(windows(pid: pid).allSatisfy { $0.layer != overlayLevel }, "overlay left on screen")
    }

    T.run("Privacy Guard dismisses with a click") {
        send("guard")
        T.expect(T.wait(4) { (status()["guardActive"] as? Bool) == true }, "guard hook did not engage")
        T.sleep(0.8)
        click(at: CGPoint(x: NSScreen.screens[0].frame.midX, y: NSScreen.screens[0].frame.midY + 200))
        T.expect(T.wait(4) { (status()["guardActive"] as? Bool) == false }, "click did not dismiss the guard")
    }

    T.run("Settings window opens and renders") {
        send("settings")
        T.expect(T.wait(4) { windows(pid: pid).contains { $0.layer == 0 && $0.bounds.width >= 880 } }, "settings window missing")
        if let w = windows(pid: pid).first(where: { $0.layer == 0 && $0.bounds.width >= 880 }) {
            T.sleep(0.8)
            capture(windowID: w.id, name: "e2e_settings")
        }
    }

    T.run("calibration window covers the laptop screen; Esc-equivalent closes it") {
        send("calibrate")
        T.expect(T.wait(4) { windows(pid: pid).contains { $0.layer == overlayLevel } }, "calibration window missing")
        T.sleep(0.6)
        if let w = windows(pid: pid).first(where: { $0.layer == overlayLevel }) {
            capture(windowID: w.id, name: "e2e_calibration")
            T.note("calibration window \(Int(w.bounds.width))×\(Int(w.bounds.height))")
        }
        send("endCalibration")
        T.expect(T.wait(3) { windows(pid: pid).allSatisfy { $0.layer != overlayLevel } }, "calibration window did not close")
    }

    T.run("installed app's watchdog recovers the sensor after power-down") {
        var it: io_iterator_t = 0
        IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &it)
        var drivers: [io_service_t] = []
        while case let s = IOIteratorNext(it), s != 0 { drivers.append(s) }
        IOObjectRelease(it)
        defer { for d in drivers { IOObjectRelease(d) } }
        for d in drivers { IORegistryEntrySetCFProperty(d, "SensorPropertyReportingState" as CFString, NSNumber(value: 0)) }
        let dropped = T.wait(3) { ((status()["rate"] as? Double) ?? 999) < 50 }
        if !dropped { throw T.Skip(reason: "sensor kept streaming after power-down request") }
        let recovered = T.wait(15) { ((status()["rate"] as? Double) ?? 0) > 500 }
        T.note("dropped \(dropped), recovered \(recovered)")
        if !recovered { for d in drivers { IORegistryEntrySetCFProperty(d, "SensorPropertyReportingState" as CFString, NSNumber(value: 1)) } }
        T.expect(recovered, "app did not recover the sensor within 15 s")
    }

    T.run("idle cost: CPU and memory over 20 s") {
        func sample() -> (cpu: Double, rss: Double) {
            let p = Process(), out = Pipe()
            p.executableURL = URL(fileURLWithPath: "/bin/ps")
            p.arguments = ["-o", "%cpu=,rss=", "-p", "\(pid)"]
            p.standardOutput = out
            try? p.run(); p.waitUntilExit()
            let parts = (String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
            return parts.count == 2 ? (parts[0], parts[1] / 1024) : (-1, -1)
        }
        for w in windows(pid: pid) where w.layer == 0 { _ = w }  // settings window stays open: worst case (live scope)
        var cpus: [Double] = []
        let m0 = sample().rss
        for _ in 0..<10 { T.sleep(2); cpus.append(sample().cpu) }
        let m1 = sample().rss
        let avg = cpus.reduce(0, +) / Double(cpus.count)
        T.note(String(format: "CPU avg %.1f%% (max %.1f%%), memory %.0f → %.0f MB", avg, cpus.max() ?? 0, m0, m1))
        T.expect(avg < 15, "idle CPU \(avg)%")
        T.expect(m1 - m0 < 40, "memory grew \(m1 - m0) MB in 20 s")
    }

    cleanup()

    func cleanup() {
        if pid != 0 { kill(pid, SIGTERM) }
        T.wait(3) { NSRunningApplication(processIdentifier: pid) == nil }
        if !calcWasRunning { NSRunningApplication.runningApplications(withBundleIdentifier: calculator).first?.terminate() }
        if userInstanceWasRunning {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", appURL.path]
            try? p.run()
        }
        try? FileManager.default.removeItem(at: dir)
    }
}
