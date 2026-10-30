import AppKit
import CoreAudio
import CoreMediaIO

// MARK: - Microphones

/// Mutes every audio input device at the system level and restores each one exactly afterwards.
/// Works whatever meeting app is listening, because the app simply receives silence.
final class MicMuter {
    private struct Saved {
        let device: AudioDeviceID
        let mute: UInt32?
        let volumes: [(AudioObjectPropertyElement, Float32)]
    }

    private var saved: [Saved] = []
    private(set) var mutedCount = 0
    var isEngaged: Bool { !saved.isEmpty }

    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func inputDevices() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { id in
            var a = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
            var s: UInt32 = 0
            return AudioObjectGetPropertyDataSize(id, &a, 0, nil, &s) == noErr && s > 0
        }
    }

    private static func settable(_ id: AudioDeviceID, _ addr: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var ok: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &addr, &ok) == noErr && ok.boolValue
    }

    /// Mutes all inputs. Returns how many devices were silenced.
    @discardableResult
    func mute() -> Int {
        if saved.isEmpty {
            for id in Self.inputDevices() {
                var muteAddr = Self.address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput)
                var mute: UInt32?
                if Self.settable(id, &muteAddr) {
                    var v: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
                    if AudioObjectGetPropertyData(id, &muteAddr, 0, nil, &size, &v) == noErr { mute = v }
                }
                var volumes: [(AudioObjectPropertyElement, Float32)] = []
                for element in [kAudioObjectPropertyElementMain] + (1...8).map({ AudioObjectPropertyElement($0) }) {
                    var volAddr = Self.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, element)
                    guard Self.settable(id, &volAddr) else { continue }
                    var v: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
                    if AudioObjectGetPropertyData(id, &volAddr, 0, nil, &size, &v) == noErr { volumes.append((element, v)) }
                }
                if mute != nil || !volumes.isEmpty { saved.append(Saved(device: id, mute: mute, volumes: volumes)) }
            }
        }
        reassert()
        mutedCount = saved.count
        return mutedCount
    }

    /// Re-applies the mute (meeting apps with automatic gain may raise the volume again).
    func reassert() {
        for s in saved {
            if s.mute != nil {
                var a = Self.address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput)
                var one: UInt32 = 1
                AudioObjectSetPropertyData(s.device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &one)
            }
            for (element, _) in s.volumes {
                var a = Self.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, element)
                var zero: Float32 = 0
                AudioObjectSetPropertyData(s.device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &zero)
            }
        }
    }

    func restore() {
        for s in saved {
            for (element, value) in s.volumes {
                var a = Self.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, element)
                var v = value
                AudioObjectSetPropertyData(s.device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
            }
            if var m = s.mute {
                var a = Self.address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput)
                AudioObjectSetPropertyData(s.device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
            }
        }
        saved = []
        mutedCount = 0
    }
}

// MARK: - Cameras

enum Cameras {
    /// True if any camera is currently streaming to any app.
    static func anyRunning() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == noErr else { return false }
        for id in ids {
            var runAddr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var running: UInt32 = 0
            var got: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &runAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }
}

// MARK: - Meeting apps

/// A meeting the camera shortcut can be sent to.
struct MeetingTarget: Equatable {
    let name: String
    let bundleID: String
    let key: KeySender.Key
    let flags: CGEventFlags
    let isBrowserMeet: Bool

    static func == (a: MeetingTarget, b: MeetingTarget) -> Bool { a.bundleID == b.bundleID && a.isBrowserMeet == b.isBrowserMeet }
}

enum Meetings {
    private static let natives: [(String, [String], KeySender.Key, CGEventFlags)] = [
        ("Zoom", ["us.zoom.xos"], .v, [.maskCommand, .maskShift]),
        ("Microsoft Teams", ["com.microsoft.teams2", "com.microsoft.teams"], .o, [.maskCommand, .maskShift]),
        ("Webex", ["Cisco-Systems.Spark"], .v, [.maskCommand, .maskShift]),
    ]
    private static let browsers: [(String, String)] = [
        ("Google Chrome", "com.google.Chrome"), ("Microsoft Edge", "com.microsoft.edgemac"),
        ("Brave", "com.brave.Browser"), ("Safari", "com.apple.Safari"),
    ]

    /// Finds the meeting to act on: the frontmost meeting app first, then any running one,
    /// then a browser with a Google Meet tab (which this also brings to the front).
    static func locate() async -> MeetingTarget? {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if let native = nativeTarget(front: front, running: running) { return native }
        for (name, id) in browserOrder(front: front, running: running) {
            if await focusMeetTab(browserID: id) {
                return MeetingTarget(name: "Google Meet (\(name))", bundleID: id, key: .e, flags: .maskCommand, isBrowserMeet: true)
            }
        }
        return nil
    }

    /// The native meeting app to use: the frontmost one, else the first running one.
    static func nativeTarget(front: String?, running: Set<String>) -> MeetingTarget? {
        var candidates: [MeetingTarget] = []
        for (name, ids, key, flags) in natives {
            for id in ids where running.contains(id) {
                candidates.append(MeetingTarget(name: name, bundleID: id, key: key, flags: flags, isBrowserMeet: false))
            }
        }
        return candidates.first { $0.bundleID == front } ?? candidates.first
    }

    /// Running browsers to search for a Meet tab, frontmost first.
    static func browserOrder(front: String?, running: Set<String>) -> [(String, String)] {
        let present = browsers.filter { running.contains($0.1) }
        return present.filter { $0.1 == front } + present.filter { $0.1 != front }
    }

    /// Selects a meet.google.com tab and raises its window. Uses AppleScript (asks for Automation once).
    static func focusMeetTab(browserID: String) async -> Bool {
        let script: String
        if browserID == "com.apple.Safari" {
            script = """
            tell application id "com.apple.Safari"
              repeat with w in windows
                repeat with t in tabs of w
                  if URL of t contains "meet.google.com/" then
                    set current tab of w to t
                    set index of w to 1
                    return "ok"
                  end if
                end repeat
              end repeat
            end tell
            return "none"
            """
        } else {
            script = """
            tell application id "\(browserID)"
              repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                  set i to i + 1
                  if URL of t contains "meet.google.com/" then
                    set active tab index of w to i
                    set index of w to 1
                    return "ok"
                  end if
                end repeat
              end repeat
            end tell
            return "none"
            """
        }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", script]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = Pipe()
                do {
                    try p.run()
                    p.waitUntilExit()
                    let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    cont.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines) == "ok")
                } catch {
                    cont.resume(returning: false)
                }
            }
        }
    }

    /// Brings the meeting forward and sends its camera toggle shortcut.
    @MainActor
    static func toggleCamera(_ target: MeetingTarget) async {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first {
            app.unhide()
            app.activate()
        }
        for _ in 0..<20 where NSWorkspace.shared.frontmostApplication?.bundleIdentifier != target.bundleID {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(150))
        KeySender.press(target.key, flags: target.flags)
    }
}
