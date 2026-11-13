import Foundation

@MainActor
func localizationTests() {
    T.suite = "Localization"
    guard let language = ProcessInfo.processInfo.environment["LIDTAP_TEST_LANGUAGE"] else {
        T.run("bundled language") { throw T.Skip(reason: "run scripts/test-localization.sh for both languages") }
        return
    }
    let chinese = language == "zh-Hans"
    T.run("macOS selects bundled interface strings") {
        T.expect(ActionKind.playPause.title == (chinese ? "播放 / 暂停" : "Play / Pause"), "wrong action title: \(ActionKind.playPause.title)")
        T.expect(SettingsPane.permissions.title == (chinese ? "权限" : "Permissions"), "wrong settings title")
    }
    T.run("interpolation preserves and reorders arguments") {
        let count = 12, grid = "2×2"
        let result = String(localized: "\(count) taps on \(grid)")
        T.expect(result == (chinese ? "2×2 布局，共 12 次敲击" : "12 taps on 2×2"), result)
        let percent = 95
        let accuracy = String(localized: "\(percent)% of taps land in the right zone")
        T.expect(accuracy == (chinese ? "95% 的敲击能正确识别区域" : "95% of taps land in the right zone"), accuracy)
    }
    T.run("localized presentation keeps persisted keys stable") {
        T.expect(ActionKind.playPause.rawValue == "playPause", "action identifier changed")
        T.expect(Layouts.full == "Full grid", "layout identifier changed")
        T.expect(L10n.layout(Layouts.full) == (chinese ? "完整网格" : "Full grid"), "layout label missing")
        let custom = ZoneAction(kind: .openApp, appBundleID: "dev.example", appName: "My custom app")
        T.expect(custom.title == "My custom app", "user app name translated")
    }
    T.run("permission explanation is localized") {
        let value = Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String ?? ""
        T.expect(value.hasPrefix(chinese ? "LidTap 需要" : "LidTap brings"), value)
    }
}
