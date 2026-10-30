import AppKit
import CoreGraphics

/// Precise recent history of keyboard, click, scroll and pointer-movement input, on the same clock as the motion sensor.
///
/// Typing and clicking shake the laptop just like a tap, and macOS can report a key or click a little *after*
/// the vibration it caused, so tap filtering needs every event's exact time on both sides of a tap (not just
/// "seconds since the last event"). Key and button *releases* matter too: the trackpad clicks again on release.
/// Uses a listen-only event tap (Input Monitoring); falls back to the system's last-event times without it.
@MainActor
final class InputMonitor {
    enum Kind: String { case key, click, scroll, move }

    private(set) var isPrecise = false
    /// Tests turn this off so results never depend on the real keyboard.
    var allowsSystemFallback = true
    private var events: [(kind: Kind, time: Double)] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var lastMove: Double?

    func start() {
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
        var out = events.filter { kinds.contains($0.kind) && $0.time >= from && $0.time <= to }.map(\.time)
        guard allowsSystemFallback else { return out }
        // The system's last-event times need no permission. Always merge them in for keys unless the tap
        // provably sees keystrokes, and for everything when there is no tap at all.
        let fallbackKinds = isPrecise ? (seesKeys ? Set<Kind>() : kinds.intersection([.key])) : kinds
        out += systemTimes(fallbackKinds, from: from, to: to)
        return out
    }

    private func systemTimes(_ kinds: Set<Kind>, from: Double, to: Double) -> [Double] {
        guard !kinds.isEmpty else { return [] }
        let now = MachClock.now()
        var out: [Double] = []
        let map: [(Kind, [CGEventType])] = [
            (.key, [.keyDown, .keyUp, .flagsChanged]),
            (.click, [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]),
            (.scroll, [.scrollWheel]),
            (.move, [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]),
        ]
        for (kind, types) in map where kinds.contains(kind) {
            for type in types {
                let t = now - CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type)
                if t >= from && t <= to { out.append(t) }
            }
        }
        return out
    }
}
