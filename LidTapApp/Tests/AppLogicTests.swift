import CoreGraphics
import Foundation

/// AppModel end to end with a temporary data folder, no UI, and actions recorded instead of performed.
@MainActor
final class AppHarness {
    let dir: URL
    let app: AppModel
    var performed: [ZoneAction] = []

    init(name: String, dataset: Dataset? = T.loadDataset(), config: AppConfig? = nil) {
        dir = T.tempDir(name)
        var store = Store(directory: dir)
        store.usesTrash = false
        if let dataset { store.save(dataset) }
        if let config { store.save(config) }
        app = AppModel(store: store, presentsUI: false)
        app.input.allowsSystemFallback = false  // input history comes only from what a test records
        app.privacyGuard.muteMic = false
        app.privacyGuard.stopCamera = false
        app.performAction = { [unowned self] action in
            self.performed.append(action)
            if action.kind == .privacyGuard { self.app.privacyGuard.toggle() }
            return nil
        }
    }

    func train() -> Bool {
        app.retrain()
        return T.wait(30) { app.isTrained && !app.isTraining }
    }

    func tap(_ label: String, gated: String? = nil) {
        app.handle(app.replayEvent(label: label, gated: gated)!)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }
}

@MainActor
func appLogicTests() {
    T.suite = "App logic"
    print("\n▶ App logic")

    T.run("loads your data and trains the best model") {
        let h = AppHarness(name: "train")
        T.expect(h.app.dataset.samples.count == 60, "samples \(h.app.dataset.samples.count)")
        T.expect(h.train(), "model did not train within 30 s")
        T.note("active model \(h.app.activeKind?.title ?? "-"), accuracy \(Int((h.app.accuracy ?? 0) * 100))%")
        T.expect((h.app.accuracy ?? 0) >= 0.85, "accuracy \(h.app.accuracy ?? 0)")
        T.expect(h.app.config.actions.count == 4, "default actions for 2×2: \(h.app.config.actions.count)")
    }

    T.run("each zone's tap runs that zone's action") {
        let h = AppHarness(name: "dispatch")
        guard h.train() else { return T.fail("no model") }
        var right = 0, total = 0
        for zone in 0..<4 {
            for _ in 0..<15 {
                h.performed.removeAll()
                h.tap(zoneLabel(zone))
                total += 1
                let r = h.app.lastRecord!
                if r.outcome == .acted && r.label == zoneLabel(zone) && h.performed == [h.app.action(for: zone)] { right += 1 }
                if h.app.privacyGuard.isActive { h.app.privacyGuard.release() }
            }
        }
        T.note("correct zone + action: \(right)/\(total)")
        T.expect(Double(right) / Double(total) >= 0.85, "only \(right)/\(total) taps ran the right action")
    }

    T.run("gated taps never act") {
        let h = AppHarness(name: "gated")
        guard h.train() else { return T.fail("no model") }
        for reason in ["typing", "click", "scroll", "lid moved"] { h.tap("z0", gated: reason) }
        T.expect(h.performed.isEmpty, "gated taps performed \(h.performed.count) actions")
        T.expect(h.app.recent.prefix(4).allSatisfy { $0.outcome == .ignored }, "gated taps not recorded as ignored")
    }

    T.run("typing filter: keys before or after a tap, and typing bursts") {
        let h = AppHarness(name: "inputgate")
        guard h.train() else { return T.fail("no model") }
        var clock = MachClock.now()
        @MainActor func tap(_ label: String, keys: [Double] = [], clicks: [Double] = [], moves: [Double] = []) -> TapRecord.Outcome? {
            clock += 10  // each simulated tap 10 s after the last, so input from one never touches the next
            let r = h.app.replayEvent(label: label)!
            let ev = TapEvent(id: r.id, time: clock, date: r.date, g: r.g, a: r.a, peakG: r.peakG, peakA: r.peakA,
                              lid: r.lid, threshold: r.threshold, noise: r.noise, gated: nil)
            for k in keys { h.app.input.record(.key, at: ev.time + k) }
            for c in clicks { h.app.input.record(.click, at: ev.time + c) }
            for m in moves { h.app.input.record(.move, at: ev.time + m) }
            h.app.handle(ev)
            return h.app.lastRecord?.outcome
        }
        T.expect(tap("z0", keys: [-0.05]) == .ignored, "key 50 ms before the tap should ignore it")
        T.expect(tap("z0", keys: [0.08]) == .ignored, "key 80 ms after the tap (typing reported late) should ignore it")
        T.expect(tap("z0", keys: [-1.2, -0.9, -0.6]) == .ignored, "typing burst should ignore the tap")
        T.expect(tap("z0", clicks: [0.12]) == .ignored, "trackpad click/release just after should ignore it")
        T.expect(tap("z0", moves: [-0.25, -0.15, -0.05]) == .ignored, "a tap while the pointer is moving should be ignored")
        T.expect(tap("z0", moves: [0.1]) == .ignored, "a pointer move just after the tap should ignore it")
        T.expect(tap("z1", moves: [-0.8]) != .ignored, "a pointer move 0.8 s earlier should not block a tap")
        T.sleep(0.01)
        T.expect(tap("z1", keys: [-0.6]) != .ignored, "a single key 0.6 s earlier should not block a tap")
        T.expect(tap("z1", keys: [0.3]) != .ignored, "a key 0.3 s after should not block a tap")
        T.note("ignore reason example: \(h.app.recent.dropFirst(2).first?.detail ?? "-")")
    }

    T.run("calibration: keys never block taps, clicks on Undo/Stop do; bump step records everything") {
        let h = AppHarness(name: "calgate")
        h.app.startCalibration(perZone: 18, block: 1)
        let before = h.app.dataset.samples.count
        var ev = h.app.replayEvent(label: h.app.calibration!.target!)!
        h.app.input.record(.key, at: ev.time + 0.014)   // the key-after-tap pattern seen on this Mac
        h.app.handle(ev)
        T.expect(h.app.dataset.samples.count == before + 1, "a key right after a calibration tap blocked it")
        ev = h.app.replayEvent(label: h.app.calibration!.target!)!
        h.app.input.record(.click, at: ev.time - 0.05)  // clicking Undo shakes the laptop too
        h.app.handle(ev)
        T.expect(h.app.dataset.samples.count == before + 1, "a click on the calibration controls was recorded as a tap")
        ev = h.app.replayEvent(label: h.app.calibration!.target!)!
        h.app.input.record(.move, at: ev.time - 0.1)
        h.app.handle(ev)
        T.expect(h.app.dataset.samples.count == before + 1, "a tap while moving the pointer was recorded in calibration")
        h.app.startNoiseRecording(seconds: 30)
        ev = h.app.replayEvent(label: "z0")!
        h.app.input.record(.key, at: ev.time + 0.02)
        h.app.handle(ev)
        T.expect(h.app.count(for: noiseLabel) == 1, "typing during the bump step was not recorded as a bump")
        h.app.endCalibration()
    }

    T.run("stillness: a tap that starts while the screen is still moving is ignored") {
        let h = AppHarness(name: "still")
        guard h.train() else { return T.fail("no model") }
        @MainActor func tap(pre: Double) -> TapRecord.Outcome? {
            let r = h.app.replayEvent(label: "z0")!
            h.app.handle(TapEvent(id: r.id, time: r.time, date: r.date, g: r.g, a: r.a, peakG: r.peakG, peakA: r.peakA, lid: r.lid,
                                  threshold: 1.2, noise: 0.15, gated: nil, preMotion: pre))
            return h.app.lastRecord?.outcome
        }
        T.expect(tap(pre: 0.3) != .ignored, "a tap from a still screen was ignored")
        T.expect(tap(pre: 1.0) == .ignored, "a tap during motion (typing, wobble) was not ignored")
        T.note(h.app.lastRecord?.detail ?? "")
    }

    T.run("calibration counts only clean taps (too-soft taps are asked again)") {
        let h = AppHarness(name: "soft")
        h.app.startCalibration(perZone: 18, block: 1)
        let n = h.app.dataset.samples.count
        let r = h.app.replayEvent(label: h.app.calibration!.target!)!
        h.app.handle(resized(r, strength: 1.2))
        // Kept (unused) as evidence of how hard taps land on this Mac, but not counted.
        T.expect(h.app.calibration?.position == 0 && h.app.calibration?.flash == .ignored("too soft"), "a calibration tap of strength 1.2 was counted")
        T.expect(h.app.dataset.samples.count == n + 1 && h.app.softTapCount == 1, "soft tap not kept as unused evidence")
        h.app.handle(resized(r, strength: 4))
        T.expect(h.app.calibration?.position == 1 && h.app.dataset.samples.count == n + 2, "a crisp calibration tap was not counted")
        h.app.endCalibration()
    }

    T.run("Privacy Guard only fires when the recogniser is at least 85% sure") {
        let h = AppHarness(name: "guardconf")
        guard h.train() else { return T.fail("no model") }
        h.app.config.minConfidence = 0.3
        var fired: [Double] = []
        for _ in 0..<40 {
            h.performed.removeAll()
            h.tap("z3")  // the Privacy Guard zone in the default 2×2 layout
            if h.performed.contains(where: { $0.kind == .privacyGuard }) { fired.append(h.app.lastRecord?.confidence ?? 0) }
            if h.app.privacyGuard.isActive { h.app.privacyGuard.release() }
        }
        T.note("fired \(fired.count)/40, lowest confidence \(fired.min().map { String(format: "%.2f", $0) } ?? "-")")
        T.expect(fired.allSatisfy { $0 >= 0.85 }, "Privacy Guard fired below 85% confidence")
    }

    T.run("confidence floor: unsure taps say so instead of acting") {
        let h = AppHarness(name: "confidence")
        guard h.train() else { return T.fail("no model") }
        h.app.config.minConfidence = 0.999
        h.performed.removeAll()
        for _ in 0..<5 { h.tap("z1") }
        let rejected = h.app.recent.prefix(5).filter { $0.outcome == .rejected }.count
        T.expect(rejected >= 4 && h.performed.count <= 1, "with a 99.9% floor, \(rejected)/5 rejected and \(h.performed.count) acted")
        h.app.config.minConfidence = 0.6
        h.performed.removeAll()
        for _ in 0..<5 { h.tap("z1") }
        T.expect(h.performed.count >= 4, "with a 60% floor only \(h.performed.count)/5 acted")
    }

    T.run("strength coaching: soft live taps never act; training uses only crisp taps") {
        var ds = T.loadDataset()
        // Add 12 soft (strength 1.5) taps, deliberately labelled as zone 1, that would poison training if used.
        for i in 0..<12 {
            var s = resized(ds.samples[30 + i], strength: 1.5)
            s.id = 1000 + i; s.label = "z0"
            ds.samples.append(s)
        }
        let h = AppHarness(name: "strength", dataset: ds)
        T.expect(h.app.softTapCount == 12 && h.app.usableCount(for: "z0") == 15, "soft \(h.app.softTapCount), usable z0 \(h.app.usableCount(for: "z0"))")
        guard h.train() else { return T.fail("no model") }
        T.expect(h.app.report?.sampleCount == 60, "trained on \(h.app.report?.sampleCount ?? 0) taps, want the 60 crisp ones")
        T.expect((h.app.accuracy ?? 0) >= 0.9, "accuracy \(h.app.accuracy ?? 0) with soft taps excluded")
        let r = h.app.replayEvent(label: "z1")!
        h.performed.removeAll()
        h.app.handle(resized(r, strength: 2.0))
        T.expect(h.performed.isEmpty && h.app.lastRecord?.outcome == .rejected, "a live tap of strength 2 acted")
        // Zone 1's typical tap is still a crisp one (15 crisp against 12 soft), so the limit stays well above the soft ones.
        T.expect(h.app.minTapStrength > 2.2, "learned limit \(h.app.minTapStrength) on a Mac whose taps are strength 7")
        h.app.config.autoTapStrength = false
        h.app.config.minTapStrength = 1.0
        T.expect(T.wait(10) { h.app.report?.sampleCount == 72 && !h.app.isTraining }, "lowering the minimum did not retrain with all taps")
    }

    T.run("tap strength limit: learned from this Mac's taps, between 1 and 3.5 °/s") {
        T.expect(TapStrength.learned(from: []) == 1.0, "no taps yet")
        T.expect(TapStrength.learned(from: [7, 6, 8, 9, 5]) == 3.5, "13-inch Air taps keep the 3.5 °/s limit")
        T.expect(abs(TapStrength.learned(from: [2.4, 1.8, 2.1, 2.0, 1.6, 2.6]) - 2.05 / 2) < 1e-9, "16-inch taps \(TapStrength.learned(from: [2.4, 1.8, 2.1, 2.0, 1.6, 2.6]))")
        T.expect(TapStrength.learned(from: [1.1, 1.2, 1.0]) == 1.0, "never below 1")
        T.expect(TapStrength.strength(twist: 0.6, impact: 0.012) == 4 && TapStrength.strength(twist: 7, impact: 0.012) == 7, "twist or jolt, whichever is larger")
    }

    T.run("16-inch MacBook Pro: weak screen taps calibrate, train and act") {
        // The same taps, as a heavier Mac feels them: a quarter of the twist and of the jolt (median 1.8 °/s instead of 7).
        var ds = T.loadDataset()
        for i in ds.samples.indices where ds.samples[i].label != noiseLabel {
            ds.samples[i].peakG *= 0.25
            ds.samples[i].peakA *= 0.25
            ds.samples[i].g = ds.samples[i].g.map { $0.map { $0 * 0.25 } }
            ds.samples[i].a = ds.samples[i].a.map { $0.map { $0 * 0.25 } }
        }
        let h = AppHarness(name: "big-mac", dataset: ds)
        T.expect(h.app.minTapStrength < 1.6 && h.app.softTapCount < 10, "limit \(h.app.minTapStrength), \(h.app.softTapCount) taps refused")
        guard h.train() else { return T.fail("no model") }
        T.note("accuracy with quarter-strength taps \(Int((h.app.accuracy ?? 0) * 100))%")
        T.expect((h.app.accuracy ?? 0) >= 0.8, "accuracy \(h.app.accuracy ?? 0)")
        h.performed.removeAll()
        for _ in 0..<5 { h.tap("z1") }
        T.expect(h.performed.count >= 4, "only \(h.performed.count)/5 weak live taps acted")

        // A new calibration on this Mac counts its 1.8 °/s taps instead of calling them too soft.
        h.app.startCalibration(perZone: 20, block: 1)
        let before = h.app.calibration!.position
        for _ in 0..<3 { h.tap(h.app.calibration!.target!) }
        T.expect(h.app.calibration!.position >= before + 2, "calibration refused weak taps: position \(h.app.calibration!.position)")
        h.app.endCalibration()

        // The hand-set limit still wins when automatic is off.
        h.app.config.autoTapStrength = false
        h.app.config.minTapStrength = 3.5
        h.performed.removeAll()
        h.tap("z1")
        T.expect(h.performed.isEmpty && h.app.lastRecord?.outcome == .rejected, "hand-set limit of 3.5 ignored")
    }

    T.run("14-inch MacBook Pro: real light taps calibrate, train and are told apart") {
        // Taps recorded on a real 14" Pro, found by the detector and fed to a first calibration in the order made.
        let (taps, _) = labelledTaps(in: try T.loadStream())
        let h = AppHarness(name: "pro14", dataset: nil)
        h.app.startCalibration(perZone: 30, block: 30)
        var refused = 0
        for (label, e) in taps {
            // Calibration asks for one corner at a time; steer it to the corner this tap was made on.
            guard var cal = h.app.calibration, let i = cal.sequence[cal.position...].firstIndex(of: label) else { continue }
            cal.sequence.swapAt(cal.position, i)
            h.app.calibration = cal
            let before = cal.position
            h.app.handle(TapEvent(id: e.id, time: MachClock.now(), date: Date(), g: e.g, a: e.a, peakG: e.peakG, peakA: e.peakA, lid: 110,
                                  threshold: e.threshold, noise: e.noise, gated: nil, preMotion: e.preMotion))
            if h.app.calibration?.position == before { refused += 1 }
        }
        h.app.endCalibration()
        let used = (0..<4).map { h.app.usableCount(for: zoneLabel($0)) }
        T.note(String(format: "%d taps felt, %d refused in calibration · learned limit %.2f · usable per corner %@", taps.count, refused, h.app.minTapStrength, "\(used)"))
        // The far top corner lands softest (a few of its taps sit at the trigger and are asked again, as designed).
        T.expect(used.allSatisfy { $0 >= 3 }, "usable taps per corner \(used)")
        T.expect(Double(used.reduce(0, +)) >= 0.75 * Double(taps.count), "only \(used.reduce(0, +)) of \(taps.count) real taps were usable")
        T.expect(T.wait(30) { h.app.isTrained && !h.app.isTraining }, "no model from the Pro's taps")
        let acc = h.app.accuracy ?? 0
        T.note("cross-validated accuracy on \(h.app.report?.sampleCount ?? 0) taps: \(Int((acc * 100).rounded()))% (\(h.app.activeKind?.title ?? "-"))")
        T.expect(acc >= 0.7, "accuracy \(acc) on the Pro's own taps")
    }

    T.run("Left / Right: four-corner taps regroup into two sides, no new calibration") {
        let h = AppHarness(name: "regroup")
        guard h.train() else { return T.fail("no model") }
        let four = h.app.accuracy ?? 0
        T.expect(h.app.canRegroupLeftRight, "a 2×2 calibration should be regroupable")
        h.app.regroupLeftRight()
        T.expect(h.app.grid == .leftRight && h.app.dataset.samples.count == 60, "grid \(h.app.grid.title), \(h.app.dataset.samples.count) taps")
        T.expect(h.app.count(for: "z0") == 30 && h.app.count(for: "z1") == 30, "sides \(h.app.count(for: "z0")) / \(h.app.count(for: "z1"))")
        T.expect(h.app.config.actions.count == 2 && h.app.action(for: 0).kind == .desktopLeft && h.app.action(for: 1).kind == .desktopRight, "two-zone actions \(h.app.config.actions)")
        T.expect(T.wait(30) { h.app.report?.grid == .leftRight && !h.app.isTraining }, "did not retrain on two sides")
        T.note("four corners \(Int((four * 100).rounded()))% → two sides \(Int(((h.app.accuracy ?? 0) * 100).rounded()))%")
        T.expect((h.app.accuracy ?? 0) >= 0.93 && !h.app.canRegroupLeftRight, "two-side accuracy \(h.app.accuracy ?? 0)")
        // Taps made top-right and bottom-right now both run the right-hand action.
        let right = T.loadDataset().samples.filter { $0.label == "z1" || $0.label == "z3" }
        h.performed.removeAll()
        for (i, s) in right.prefix(20).enumerated() { h.app.handle(event(from: s, id: 7000 + i, noise: 0.02)) }
        T.expect(h.performed.filter { $0.kind == .desktopRight }.count >= 18 && !h.performed.contains { $0.kind == .desktopLeft },
                 "right-side taps ran \(h.performed.map(\.kind.rawValue))")
        // It survives a restart, like any other calibration.
        h.app.flushSave()
        let again = AppModel(store: Store(directory: h.dir), presentsUI: false)
        T.expect(again.grid == .leftRight && again.dataset.samples.count == 60 && again.config.actions.count == 2, "regrouped layout not saved")
    }

    T.run("Left / Right: a three-column grid drops its middle column; one side alone can't regroup") {
        var ds = T.loadDataset()
        ds.grid = Grid(rows: 2, cols: 3)   // read the same taps as columns 0, 1, 2, 0 (for the bookkeeping only)
        let h = AppHarness(name: "regroup3", dataset: ds)
        h.app.regroupLeftRight()
        T.expect(h.app.grid == .leftRight && h.app.count(for: "z0") == 30 && h.app.count(for: "z1") == 15 && h.app.dataset.samples.count == 45,
                 "sides \(h.app.count(for: "z0")) / \(h.app.count(for: "z1")) of \(h.app.dataset.samples.count)")
        var left = T.loadDataset()
        left.samples.removeAll { $0.label == "z1" || $0.label == "z3" }
        let one = AppHarness(name: "regroup-one", dataset: left)
        T.expect(!one.app.canRegroupLeftRight, "taps on one side only can't make two sides")
        one.app.regroupLeftRight()
        T.expect(one.app.grid == Grid(rows: 2, cols: 2), "regrouped anyway")
        // A fresh Left / Right calibration asks for both sides.
        one.app.startCalibration(grid: .leftRight)
        T.expect(one.app.grid == .leftRight && Set(one.app.calibration?.sequence ?? []) == ["z0", "z1"] && one.app.calibration?.sequence.count == 30
                    && one.app.config.actions.count == 2, "Left / Right calibration \(one.app.calibration?.sequence.count ?? 0) taps")
        one.app.endCalibration()
    }

    T.run("Left / Right is suggested when four corners score low and the two sides score well") {
        func report(full: Double, sides: Double?, grid: Grid = Grid(rows: 2, cols: 2)) -> ModelReport {
            var acc = [Layouts.full: full]
            if let sides { acc[Layouts.leftRight] = sides }
            return ModelReport(sampleCount: 60, grid: grid, labels: [], layouts: [], scores: [ModelScore(kind: .logreg, accuracy: acc)], best: .logreg,
                               confusion: nil, learning: [], trainedAt: Date())
        }
        T.expect(report(full: 0.78, sides: 0.92).leftRightGain(.logreg) == 0.92, "a 14-inch Pro's scores should suggest it")
        T.expect(report(full: 0.95, sides: 0.98).leftRightGain(.logreg) == nil, "a reliable grid needs no suggestion")
        T.expect(report(full: 0.70, sides: 0.75).leftRightGain(.logreg) == nil, "two sides that are also unreliable aren't worth suggesting")
        T.expect(report(full: 0.84, sides: 0.88).leftRightGain(.logreg) == nil, "a small gain isn't worth losing two zones")
        T.expect(report(full: 0.78, sides: nil, grid: .leftRight).leftRightGain(.logreg) == nil, "already on Left / Right")
    }

    T.run("14-inch MacBook Pro: its real taps regroup into two sides and train") {
        let (taps, _) = labelledTaps(in: try T.loadStream())
        var ds = Dataset()
        for (i, t) in taps.enumerated() where t.event.strength >= 1 {
            ds.samples.append(TapSample(id: i + 1, label: t.label, wall: 0, lid: 110, peakG: t.event.peakG, peakA: t.event.peakA, g: t.event.g, a: t.event.a))
        }
        let h = AppHarness(name: "pro14-sides", dataset: ds)
        guard h.train() else { return T.fail("no model") }
        let four = h.app.accuracy ?? 0, predicted = h.app.report?.accuracy(h.app.activeKind ?? .logreg, Layouts.leftRight) ?? 0
        h.app.regroupLeftRight()
        T.expect(T.wait(30) { h.app.report?.grid == .leftRight && !h.app.isTraining }, "did not retrain")
        T.note("four corners \(Int((four * 100).rounded()))% → two sides \(Int(((h.app.accuracy ?? 0) * 100).rounded()))% (predicted \(Int((predicted * 100).rounded()))%) on \(h.app.report?.sampleCount ?? 0) taps")
        T.expect((h.app.accuracy ?? 0) >= 0.75, "two-side accuracy \(h.app.accuracy ?? 0) on the Pro")
    }

    T.run("first calibration on a weak-tap Mac: soft taps are kept and the limit settles") {
        let h = AppHarness(name: "first-cal", dataset: nil)
        h.app.startCalibration(perZone: 10, block: 1)
        let template = T.loadDataset().samples.first { $0.label == "z0" }!
        var id = 5000
        @MainActor func tap(_ strength: Double) {
            id += 1
            h.app.handle(resized(event(from: template, id: id), strength: strength))
        }
        for x in [3.0, 3.3, 2.9, 3.1, 3.0, 3.4] { tap(x) }
        T.expect(h.app.calibration?.position == 6, "weak but steady taps refused: position \(h.app.calibration?.position ?? -1)")
        tap(1.2)  // a fumbled tap, far softer than this Mac's usual
        T.expect(h.app.calibration?.position == 6 && h.app.dataset.samples.count == 7, "fumble counted, or not kept as evidence")
        T.expect(h.app.softTapCount == 1, "soft count \(h.app.softTapCount)")
        h.app.undoLastCalibrationTap()  // removes the last counted tap, not the fumble
        T.expect(h.app.calibration?.position == 5 && h.app.dataset.samples.contains { abs(h.app.strength(of: $0) - 1.2) < 0.05 } && h.app.dataset.samples.count == 6,
                 "undo removed the wrong sample")
        h.app.endCalibration()
    }

    T.run("volume, mute and shortcut actions") {
        for k in [ActionKind.volumeUp, .volumeDown, .mute] {
            T.expect(k.group == "Sound" && k.needsAccessibility && k.hasSystemFeedback && !k.needsChoice, "\(k) metadata")
        }
        T.expect(ActionKind.runShortcut.needsChoice && !ActionKind.runShortcut.needsAccessibility, "shortcut metadata")
        let sc = ZoneAction(kind: .runShortcut, shortcutName: "Stop Distractions")
        T.expect(sc.title == "Stop Distractions" && sc.isComplete && !ZoneAction(kind: .runShortcut).isComplete, "shortcut title or completeness")
        let data = try! JSONEncoder().encode(["z0": sc, "z1": ZoneAction(kind: .volumeUp)])
        let back = try! JSONDecoder().decode([String: ZoneAction].self, from: data)
        T.expect(back["z0"] == sc && back["z1"]?.kind == .volumeUp, "round trip \(back)")
        let old = try! JSONDecoder().decode(ZoneAction.self, from: Data(#"{"kind":"openApp","appBundleID":"com.apple.calculator"}"#.utf8))
        T.expect(old.shortcutName == nil && old.isComplete, "older zone action did not load")

        let h = AppHarness(name: "new-actions")
        guard h.train() else { return T.fail("no model") }
        h.app.setAction(ZoneAction(kind: .volumeDown), for: 1)
        h.performed.removeAll()
        h.tap("z1")
        T.expect(h.performed.last?.kind == .volumeDown, "zone 2 did not turn the volume down: \(h.performed)")
        T.expect(!Shortcuts.list().isEmpty || !FileManager.default.fileExists(atPath: Shortcuts.tool.path), "shortcuts list empty")
    }

    T.run("strength coaching: calibration meter sees every tap, recorded or not") {
        let h = AppHarness(name: "meter")
        h.app.startCalibration(perZone: 18, block: 1)
        let r = h.app.replayEvent(label: h.app.calibration!.target!)!
        h.app.handle(resized(r, strength: 2.2))
        T.expect(abs((h.app.calibration?.lastStrength ?? 0) - 2.2) < 1e-6 && h.app.calibration?.strengthID == 1, "meter missed a soft tap")
        h.app.handle(resized(r, strength: 6.5))
        T.expect(abs((h.app.calibration?.lastStrength ?? 0) - 6.5) < 1e-6 && h.app.calibration?.position == 1, "meter or progress wrong after a crisp tap")
        h.app.endCalibration()
    }

    T.run("paused app ignores taps") {
        let h = AppHarness(name: "paused")
        guard h.train() else { return T.fail("no model") }
        h.app.config.enabled = false
        h.tap("z0")
        T.expect(h.performed.isEmpty, "acted while paused")
    }

    T.run("unfamiliar taps are rejected without acting") {
        let h = AppHarness(name: "reject")
        guard h.train() else { return T.fail("no model") }
        var rejected = 0
        for i in 0..<20 {
            let g = (0..<TapDetector.n).map { _ in (0..<3).map { _ in Double.random(in: -4...4) } }
            h.app.handle(TapEvent(id: 900 + i, time: MachClock.now(), date: Date(), g: g, a: g.map { $0.map { $0 / 500 } },
                                  peakG: 6, peakA: 0.01, lid: 130, threshold: 1, noise: 0.1, gated: nil))
            if h.app.lastRecord?.outcome == .rejected { rejected += 1 }
        }
        T.note("random windows rejected \(rejected)/20, actions run \(h.performed.count)")
        T.expect(rejected >= 18, "only \(rejected)/20 rejected")
    }

    T.run("untrained app records taps without acting") {
        let h = AppHarness(name: "untrained", dataset: nil)
        h.app.handle(TapEvent(id: 1, time: 0, date: Date(), g: T.loadDataset().samples[0].g, a: T.loadDataset().samples[0].a,
                              peakG: 5, peakA: 0.01, lid: nil, threshold: 1, noise: 0.1, gated: nil))
        T.expect(h.app.lastRecord?.outcome == .untrained && h.performed.isEmpty, "untrained tap outcome \(String(describing: h.app.lastRecord?.outcome))")
    }

    T.run("Privacy Guard: other zones ignored, guard zone releases it") {
        let h = AppHarness(name: "guard")
        guard h.train() else { return T.fail("no model") }
        let guardZone = (0..<4).first { h.app.action(for: $0).kind == .privacyGuard }!
        h.app.privacyGuard.engage()
        T.expect(h.app.privacyGuard.isActive, "guard did not engage")
        h.performed.removeAll()
        let other = zoneLabel((guardZone + 2) % 4)  // a zone in the other row: never confused in your data
        for _ in 0..<5 { h.tap(other) }
        T.expect(h.performed.isEmpty, "zone actions ran while guarded: \(h.performed.map(\.title))")
        T.expect(h.app.recent.prefix(5).allSatisfy { $0.outcome == .guarded || $0.outcome == .rejected }, "taps while guarded not marked guarded")
        for _ in 0..<5 where h.app.privacyGuard.isActive { h.tap(zoneLabel(guardZone)) }
        T.expect(!h.app.privacyGuard.isActive, "tapping the guard zone did not release Privacy Guard")
    }

    T.run("full calibration flow: taps → noise → train → done") {
        let h = AppHarness(name: "calib")
        let before = h.app.dataset.samples.count
        h.app.startCalibration(perZone: 17, block: 1)  // each zone has 15, so 2 more each
        guard let cal = h.app.calibration else { return T.fail("calibration did not start") }
        T.expect(cal.sequence.count == 8, "sequence length \(cal.sequence.count), want 8")
        T.expect(Set(cal.sequence) == Set((0..<4).map(zoneLabel)), "sequence must cover every zone")
        // A gated tap during calibration is flashed and not recorded.
        h.tap("z0", gated: "typing")
        T.expect(h.app.calibration?.position == 0 && h.app.calibration?.flash == .ignored("typing"), "gated calibration tap was counted")
        while let target = h.app.calibration?.target { h.tap(target) }
        T.expect(h.app.calibration?.phase == .noisePrompt, "phase after taps \(String(describing: h.app.calibration?.phase))")
        T.expect(h.app.dataset.samples.count == before + 8, "samples \(h.app.dataset.samples.count), want \(before + 8)")
        h.app.startNoiseRecording(seconds: 0.5)
        for _ in 0..<3 { h.tap("z1") }  // anything during the noise phase is labelled noise
        T.expect(h.app.count(for: noiseLabel) == 3, "noise samples \(h.app.count(for: noiseLabel))")
        T.expect(T.wait(30) { h.app.calibration?.phase == .done }, "never reached done: \(String(describing: h.app.calibration?.phase))")
        T.expect(h.app.isTrained && h.app.report?.labels.contains(noiseLabel) == true, "model not retrained with noise class")
        h.app.endCalibration()
        T.expect(h.app.calibration == nil, "calibration not ended")
    }

    T.run("undo removes the last calibration tap") {
        let h = AppHarness(name: "undo")
        h.app.startCalibration(perZone: 16, block: 1)
        let t = h.app.calibration!.target!
        h.tap(t)
        let n = h.app.dataset.samples.count
        h.app.undoLastCalibrationTap()
        T.expect(h.app.dataset.samples.count == n - 1 && h.app.calibration?.position == 0, "undo did not revert")
        h.app.endCalibration()
    }

    T.run("switching grid clears zone taps, keeps noise, resets actions") {
        let h = AppHarness(name: "grid")
        h.app.startCalibration(perZone: 15)
        h.app.startNoiseRecording(seconds: 30)
        h.tap("z0")
        h.app.endCalibration()
        h.app.startCalibration(grid: Grid(rows: 3, cols: 3), perZone: 5)
        T.expect(h.app.grid == Grid(rows: 3, cols: 3), "grid not switched")
        T.expect(h.app.dataset.zoneTapCount == 0 && h.app.count(for: noiseLabel) == 1, "zone taps \(h.app.dataset.zoneTapCount), noise \(h.app.count(for: noiseLabel))")
        T.expect(h.app.config.actions.count == 9 && h.app.action(for: 8).kind == .privacyGuard, "3×3 default actions")
        T.expect(!h.app.isTrained, "old model kept after grid change")
        T.expect(h.app.calibration?.sequence.count == 45, "3×3 × 5 sequence \(h.app.calibration?.sequence.count ?? 0)")
        h.app.endCalibration()
    }

    T.run("data and settings persist across restarts") {
        let h = AppHarness(name: "persist")
        h.app.setAction(ZoneAction(kind: .openApp, appBundleID: "com.apple.calculator", appName: "Calculator"), for: 2)
        h.app.config.detector.k = 9
        h.app.config.rejectFactor = 2.7
        h.app.startCalibration(perZone: 16, block: 1)
        h.tap(h.app.calibration!.target!)
        h.app.endCalibration()
        T.sleep(0.8)  // dataset saves are debounced
        let again = AppModel(store: Store(directory: h.dir), presentsUI: false)
        T.expect(again.dataset.samples.count == 61, "reloaded samples \(again.dataset.samples.count)")
        T.expect(again.action(for: 2).appBundleID == "com.apple.calculator", "zone action not persisted")
        T.expect(again.config.detector.k == 9 && again.config.rejectFactor == 2.7, "settings not persisted")
        T.expect(again.detector.settings.k == 9, "detector did not pick up saved settings")
    }

    T.run("delete a zone's taps and clear everything") {
        let h = AppHarness(name: "delete")
        h.app.deleteSamples(label: "z0")
        T.expect(h.app.count(for: "z0") == 0 && h.app.dataset.samples.count == 45, "delete zone")
        T.expect(T.wait(20) { !h.app.isTraining }, "retrain after delete hung")
        h.app.clearData()
        T.expect(h.app.dataset.samples.isEmpty && !h.app.isTrained, "clear all")
    }

    T.run("clearing data while a model trains doesn't bring the old model back") {
        let h = AppHarness(name: "clear-race")
        h.app.retrain()
        T.expect(h.app.isTraining, "training did not start")
        h.app.clearData()
        T.expect(!h.app.isTraining, "still marked as training after clear")
        T.sleep(3)  // long enough for the abandoned training to finish
        T.expect(!h.app.isTrained && h.app.report == nil, "model trained on deleted taps came back")
    }

    T.run("quitting writes taps that were still waiting to be saved") {
        let h = AppHarness(name: "flush")
        h.app.startCalibration()
        h.tap(h.app.calibration!.target!)
        h.app.flushSave()  // what applicationWillTerminate does, before the 400 ms debounce
        let again = AppModel(store: Store(directory: h.dir), presentsUI: false)
        T.expect(again.dataset.samples.count == 61, "saved samples \(again.dataset.samples.count)")
    }

    T.run("a stale noise timer doesn't end a newer noise recording") {
        let h = AppHarness(name: "noise-timer")
        h.app.startCalibration()
        h.app.startNoiseRecording(seconds: 0.4)
        h.app.startNoiseRecording(seconds: 30)  // restarted: the first timer must not finish this one
        T.sleep(0.8)
        if case .noise = h.app.calibration?.phase {} else { T.fail("phase \(String(describing: h.app.calibration?.phase))") }
        h.app.endCalibration()
    }

    T.run("corrupt files are moved aside, not overwritten") {
        let dir = T.tempDir("corrupt")
        try! "{ this is not json".write(to: dir.appendingPathComponent("dataset.json"), atomically: true, encoding: .utf8)
        try! "[1,2".write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        let app = AppModel(store: Store(directory: dir), presentsUI: false)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        T.note("files after load: \(files.sorted())")
        T.expect(app.dataset.samples.isEmpty && app.config == { var c = AppConfig(); c.actions = ZoneAction.defaults(for: Grid(rows: 2, cols: 2)); return c }(), "defaults not used")
        T.expect(files.filter { $0.contains("corrupt") }.count == 2, "corrupt files not preserved: \(files)")
        try? FileManager.default.removeItem(at: dir)
    }

    T.run("older/partial config files still load (missing keys use defaults)") {
        let dir = T.tempDir("partial")
        try! #"{"enabled": false, "detector": {"k": 4}}"#.write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        let cfg = Store(directory: dir).loadConfig()
        T.expect(!cfg.enabled && cfg.detector.k == 4 && cfg.detector.minThreshold == 1 && cfg.rejectFactor == AppConfig.defaultRejectFactor && cfg.guardMutesMic, "partial config \(cfg)")
        try? FileManager.default.removeItem(at: dir)
    }

    T.run("settings from before the stricter default: an untouched reject factor of 2 becomes 1.2, once") {
        let dir = T.tempDir("migrate")
        func load(_ json: String) -> AppConfig {
            try! json.write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
            return Store(directory: dir).loadConfig()
        }
        let old = load(#"{"rejectFactor": 2, "profiles": [{"id": "desk", "name": "Desk", "settings": {"rejectFactor": 2}}, {"id": "lap", "name": "Lap", "settings": {"rejectFactor": 3.5}}], "activeProfileID": "desk"}"#)
        T.expect(old.rejectFactor == 1.2 && old.profiles[0].settings.rejectFactor == 1.2 && old.profiles[1].settings.rejectFactor == 3.5 && old.settingsVersion == AppConfig.currentVersion,
                 "old file: \(old.rejectFactor), profiles \(old.profiles.map(\.settings.rejectFactor))")
        T.expect(load(#"{"rejectFactor": 2.6}"#).rejectFactor == 2.6, "a reject factor the user chose was changed")
        // Saved again, the file is current: choosing 2.0 afterwards sticks.
        var chosen = old
        chosen.rejectFactor = 2.0
        Store(directory: dir).save(chosen)
        T.expect(Store(directory: dir).loadConfig().rejectFactor == 2.0, "a deliberate 2.0 was migrated again")
        try? FileManager.default.removeItem(at: dir)
    }

    T.run("keyboard and pointer are seen without Input Monitoring, from the system's last-event times") {
        let m = InputMonitor()
        m.allowsSystemFallback = false   // no real keyboard: the test polls by hand with a scripted system
        var now = 1000.0
        var script: [(time: Double, type: CGEventType)] = []
        for i in 0..<8 {   // eight keystrokes, 150 ms apart, each held 60 ms
            script.append((1000.1 + 0.15 * Double(i), .keyDown))
            script.append((1000.16 + 0.15 * Double(i), .keyUp))
        }
        script.append((1001.5, .leftMouseDown))
        script.append((1001.56, .leftMouseUp))
        script.append((1001.8, .scrollWheel))
        m.secondsSinceLast = { type in script.last { $0.type == type && $0.time <= now }.map { now - $0.time } ?? 1e9 }
        m.record(.click, at: 1001.5)   // the event tap delivered this one too: it must not count twice
        while now < 1002 { m.poll(now: now); now += 0.04 }
        let keys = m.times([.key], from: 1000, to: 1002), clicks = m.times([.click], from: 1000, to: 1002)
        T.expect(keys.count == 16, "\(keys.count) of 16 key events kept")
        T.expect(clicks.count == 2 && m.times([.scroll], from: 1001.7, to: 1001.9).count == 1, "\(clicks.count) clicks")
        T.expect(keys.allSatisfy { k in script.contains { abs($0.time - k) < 1e-6 } }, "key times are not the events' own times")
        // Keys LidTap presses itself are left out.
        m.ignoreKeys(from: 1003, for: 0.6)
        script.append((1003.2, .keyDown))
        script.append((1003.25, .keyUp))
        script.append((1003.9, .keyDown))
        now = 1003
        while now < 1004 { m.poll(now: now); now += 0.04 }
        T.expect(m.times([.key], from: 1003, to: 1004) == [1003.9], "own keys kept: \(m.times([.key], from: 1003, to: 1004))")
    }

    T.run("the keys an action presses don't make the next tap look like typing") {
        let h = AppHarness(name: "ownkeys")
        guard h.train() else { return T.fail("no model") }
        var t = MachClock.now() + 500
        // Stand in for "Desktop Right": four key events (modifier and arrow, down and up) a moment after the tap.
        h.app.performAction = { action in
            h.performed.append(action)
            for dt in [0.19, 0.2, 0.21, 0.22] { h.app.input.record(.key, at: t + dt) }
            return nil
        }
        @MainActor func tap() -> TapRecord.Outcome? {
            let r = h.app.replayEvent(label: "z1")!
            h.app.handle(TapEvent(id: r.id, time: t, date: r.date, g: r.g, a: r.a, peakG: r.peakG, peakA: r.peakA, lid: r.lid, threshold: 1, noise: 0.1, gated: nil))
            return h.app.lastRecord?.outcome
        }
        T.expect(tap() == .acted, "first tap did not act")
        t += 0.7
        T.expect(tap() == .acted, "a second tap 0.7 s later was \(h.app.lastRecord?.detail ?? "-")")
        // The user's own typing still counts.
        t += 10
        for dt in [-0.9, -0.7, -0.5, -0.1] { h.app.input.record(.key, at: t + dt) }
        T.expect(tap() == .ignored, "typing before a tap no longer ignores it")
    }

    T.run("learns what typing feels like: keystrokes the sensor felt become not-a-tap examples") {
        let h = AppHarness(name: "learn")
        guard h.train() else { return T.fail("no model") }
        var t = MachClock.now() + 2000
        @MainActor func event(typing: Bool, shortcut: Bool = false) {
            t += 5
            if typing { for dt in [-1.2, -1.1, -0.9, -0.8, -0.5, -0.4, -0.1, 0.02] { h.app.input.record(.key, at: t + dt) } }
            if shortcut { for dt in [-0.95, -0.9, -0.85, -0.8] { h.app.input.record(.key, at: t + dt) } }   // ⌘-Tab, then a tap
            let r = h.app.replayEvent(label: "z0")!
            h.app.handle(TapEvent(id: r.id, time: t, date: r.date, g: r.g, a: r.a, peakG: r.peakG, peakA: r.peakA, lid: r.lid, threshold: 1, noise: 0.1, gated: nil))
        }
        T.expect(h.app.learnedLimit == 60, "limit \(h.app.learnedLimit) with 60 taps")
        event(typing: false, shortcut: true)
        T.expect(h.app.lastRecord?.outcome == .ignored && h.app.dataset.learnedCount == 0, "a tap after a shortcut was kept as a non-tap")
        h.app.config.learnFromTyping = false
        event(typing: true)
        T.expect(h.app.dataset.learnedCount == 0, "learned with the setting off")
        h.app.config.learnFromTyping = true
        h.app.startCalibration(perZone: 16, block: 1)
        event(typing: true)
        h.app.endCalibration()   // (calibration took that event as a tap, as it takes anything that isn't a click)
        T.expect(h.app.dataset.learnedCount == 0, "learned during calibration")
        let before = h.app.dataset.samples.count
        T.expect(T.wait(30) { h.app.report?.sampleCount == before && !h.app.isTraining }, "calibration's retrain did not finish")
        for _ in 0..<14 { event(typing: true) }
        T.expect(h.app.dataset.learnedCount == 14 && h.app.report?.sampleCount == before && h.performed.isEmpty, "learned \(h.app.dataset.learnedCount), acted \(h.performed.count)")
        event(typing: true)   // the fifteenth retrains
        T.expect(T.wait(30) { h.app.report?.sampleCount == before + 15 && !h.app.isTraining }, "no retrain after 15 (\(h.app.report?.sampleCount ?? 0) samples)")
        T.expect(h.app.count(for: noiseLabel) == 15 && h.app.dataset.samples.filter { $0.auto == true }.allSatisfy { $0.label == noiseLabel }, "learned examples are not bumps")
        for _ in 0..<60 { event(typing: true) }
        T.expect(h.app.dataset.learnedCount == 60, "kept \(h.app.dataset.learnedCount), limit 60")
        h.app.flushSave()
        T.expect(Store(directory: h.dir).loadDataset().learnedCount == 60, "learned examples not saved as such")
    }

    T.run("model choice and reject factor apply live") {
        let h = AppHarness(name: "choice")
        guard h.train() else { return T.fail("no model") }
        h.app.config.modelChoice = ModelKind.centroid.rawValue
        T.expect(T.wait(10) { h.app.activeKind == .centroid }, "switching model did not refit (active \(String(describing: h.app.activeKind)))")
        // Absurdly strict: everything is unfamiliar. (Not 0.01: a replayed tap sits that close to the tap it was
        // made from about one time in seventeen, which made this test fail now and then.)
        h.app.config.rejectFactor = 0.0001
        h.tap("z1")
        T.expect(h.app.lastRecord?.outcome == .rejected, "strict reject factor not applied: \(h.app.lastRecord.map { "\($0.outcome) \($0.label ?? "-") \($0.detail)" } ?? "no record")")
    }

    T.run("tap handling latency (features + predict + dispatch)") {
        let h = AppHarness(name: "latency")
        guard h.train() else { return T.fail("no model") }
        let events = (0..<100).map { _ in h.app.replayEvent(label: zoneLabel(Int.random(in: 0..<4)))! }
        let t0 = Date()
        for e in events { h.app.handle(e); if h.app.privacyGuard.isActive { h.app.privacyGuard.release() } }
        let ms = Date().timeIntervalSince(t0) * 1000 / 100
        T.note(String(format: "%.2f ms per tap on the main thread", ms))
        T.expect(ms < 15, "handling a tap takes \(ms) ms")
    }
}
