import AppKit
import CoreGraphics

/// Precise recent history of keyboard, click, scroll and pointer-movement input, on the same clock as the motion sensor.
///
/// Typing and clicking shake the laptop just like a tap, and macOS can report a key or click a little *after*
/// the vibration it caused, so tap filtering needs every event's exact time on both sides of a tap (not just
/// "seconds since the last event"). Key and button *releases* matter too: the trackpad clicks again on release.
/// Uses a listen-only event tap (Input Monitoring). Without that permission the tap delivers nothing at all, so
/// the monitor also asks the system, 25 times a second, when each kind of event last happened (which needs no
/// permission) and keeps those times too. Asking only at the moment of a tap is not enough: by then the last key
/// is usually a later one, and a typist's keystrokes went on to be read as taps.
@MainActor
final class InputMonitor {
    enum Kind: String { case key, click, scroll, move }

    private(set) var isPrecise = false
    /// Tests turn this off so results never depend on the real keyboard.
    var allowsSystemFallback = true
    /// Seconds since the system last saw an event of a type (tests replace it with a script).
    var secondsSinceLast: (CGEventType) -> Double = { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
    private var events: [(kind: Kind, time: Double)] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var lastMove: Double?
    private var pollTimer: Timer?
    private var lastPolled: [UInt32: Double] = [:]
    private var ownKeys: (from: Double, to: Double)?

    private static let polled: [(Kind, [CGEventType])] = [
        (.key, [.keyDown, .keyUp, .flagsChanged]),
        (.click, [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]),
        (.scroll, [.scrollWheel]),
        (.move, [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]),
    ]

    /// Keys LidTap presses itself (a zone's action switching desktops, say) are not the user typing: key events
    /// from `time` for `seconds` are left out, so they can't make the next tap look like typing.
    func ignoreKeys(from time: Double, for seconds: Double) { ownKeys = (time, time + seconds) }

    /// Records every kind of event the system has seen since the last poll.
    func poll(now: Double = MachClock.now()) {
        for (kind, types) in Self.polled {
            for type in types {
                let t = now - secondsSinceLast(type)
                // The same event again (still the latest of its type), or one the event tap already delivered.
                if let last = lastPolled[type.rawValue], abs(t - last) < 0.004 { continue }
                lastPolled[type.rawValue] = t
                if t < now - 5 || events.contains(where: { $0.kind == kind && abs($0.time - t) < 0.004 }) { continue }
                record(kind, at: t)
            }
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if let self, self.allowsSystemFallback { self.poll() } }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func start() {
        startPolling()
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                    .otherMouseDown, .otherMouseUp, .scrollWheel,
                                    .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: { _, type, event, user in
            let monitor = Unmanaged<InputMonitor>.fromOpaque(user!).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.handle(type, event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Log.app.notice("No event tap: tap filtering uses the system's last-input times")
            return
        }
        if !CGPreflightListenEventAccess() {
            Log.app.notice("Input Monitoring not granted: keystrokes come from the system's last-key time")
            CGRequestListenEventAccess()
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isPrecise = true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let kind: Kind
        switch type {
        case .keyDown, .keyUp, .flagsChanged: kind = .key
        case .scrollWheel: kind = .scroll
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: kind = .move
        default: kind = .click
        }
        // CGEvent timestamps are nanoseconds on the mach clock, the same clock as the sensor reports.
        let t = event.timestamp > 0 ? Double(event.timestamp) / 1e9 : MachClock.now()
        record(kind, at: t)
    }

    /// Adds an event (also used by tests).
    func record(_ kind: Kind, at time: Double) {
        if kind == .key, let own = ownKeys, time >= own.from, time <= own.to { return }
        // The pointer reports up to 120 moves a second; one every 20 ms is plenty to know it was moving.
        if kind == .move, let last = lastMove, abs(time - last) < 0.02 { return }
        if kind == .move { lastMove = time }
        events.append((kind, time))
        let cutoff = time - 5
        if let first = events.first, first.time < cutoff { events.removeAll { $0.time < cutoff } }
    }

    /// Whether keystrokes reach the event tap. Without Input Monitoring, macOS still delivers clicks and scrolls
    /// to a listen-only tap but silently drops every key event.
    var seesKeys: Bool { isPrecise && CGPreflightListenEventAccess() }

    /// Times of events of the given kinds within [from, to].
    func times(_ kinds: Set<Kind>, from: Double, to: Double) -> [Double] {
        // Catch up first: anything since the last poll, 40 ms ago at most.
        if allowsSystemFallback { poll() }
        return events.filter { kinds.contains($0.kind) && $0.time >= from && $0.time <= to }.map(\.time)
    }
}
