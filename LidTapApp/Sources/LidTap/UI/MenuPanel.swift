import SwiftUI

/// Menu bar icon. Kept to a plain symbol: animated content in a MenuBarExtra label makes SwiftUI
/// re-render the status item in a tight loop.
struct MenuBarLabel: View {
    let app: AppModel

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel("LidTap")
    }

    private var symbol: String {
        if app.privacyGuard.isActive { return "eye.slash.fill" }
        if app.calibration != nil { return "scope" }
        if !app.config.enabled { return "hand.raised.slash" }
        return app.tapFlash ? "hand.tap.fill" : "hand.tap"
    }
}

struct MenuPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 0) {
            header(enabled: $app.config.enabled)
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            if let notice {
                noticeRow(notice).padding(.horizontal, 14).padding(.bottom, 10)
            }
            if app.config.hasProfiles {
                ProfileSwitcher().padding(.horizontal, 14).padding(.bottom, 10)
            }
            if app.isTrained {
                map.padding(.horizontal, 14).padding(.bottom, 12)
            } else {
                firstRun.padding(.horizontal, 14).padding(.bottom, 12)
            }
            Divider().padding(.horizontal, 8)
            VStack(spacing: 0) {
                MenuRow(title: String(localized: "Privacy Guard"), symbol: "eye.slash") { dismiss(); app.privacyGuard.toggle() }
                    .help(String(localized: "Mute every microphone, turn your meeting camera off and hide the screen"))
                if app.isTrained {
                    MenuRow(title: String(localized: "Calibrate Again…"), symbol: "scope") { dismiss(); app.startCalibration() }
                }
                MenuRow(title: String(localized: "Settings…"), symbol: "gearshape", shortcut: "⌘,") { dismiss(); app.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                MenuRow(title: String(localized: "Quit LidTap"), symbol: "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(6)
        }
        .frame(width: 300)
    }

    // MARK: Header

    private func header(enabled: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("LidTap").font(.headline)
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(DS.Motion.state, value: statusLine)
            }
            Spacer(minLength: 8)
            Toggle("LidTap", isOn: enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help(app.config.enabled ? String(localized: "Pause LidTap") : String(localized: "Resume LidTap"))
        }
    }

    private var statusLine: String {
        if let e = app.status.error, !e.isEmpty { return String(localized: "Motion sensor unavailable") }
        if app.status.rate < 50 { return String(localized: "Starting the motion sensor…") }
        if app.privacyGuard.isActive { return String(localized: "Privacy Guard is on") }
        if app.calibration != nil { return String(localized: "Calibrating") }
        if !app.config.enabled { return String(localized: "Paused") }
        if app.isTraining { return String(localized: "Learning your taps…") }
        guard app.isTrained else { return String(localized: "Not calibrated yet") }
        let acc = app.accuracy.map { String(localized: " · \(Int(($0 * 100).rounded()))% accurate") } ?? ""
        return String(localized: "Listening on \(app.grid.title)\(acc)")
    }

    // MARK: Notices

    private struct Notice { let symbol: String; let text: String; let button: String?; let action: (() -> Void)? }

    private var notice: Notice? {
        if let e = app.status.error, !e.isEmpty {
            return Notice(symbol: "exclamationmark.triangle.fill", text: e, button: nil, action: nil)
        }
        if !app.status.accessibility {
            return Notice(symbol: "hand.raised.fill", text: String(localized: "Allow Accessibility to switch desktops and control music."),
                          button: String(localized: "Allow…"), action: { Permissions.requestAccessibility(); Permissions.openPrivacyPane("Privacy_Accessibility") })
        }
        if let update = app.updater.available, app.updater.state == .available {
            return Notice(symbol: "arrow.down.circle.fill", text: String(localized: "LidTap \(update.version.description) is available."),
                          button: String(localized: "Update…"), action: { dismiss(); app.showUpdate() })
        }
        return nil
    }

    private func noticeRow(_ n: Notice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: n.symbol).foregroundStyle(.orange)
            Text(n.text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let b = n.button, let a = n.action { Button(b, action: a).controlSize(.small) }
        }
    }

    // MARK: Zones

    private var map: some View {
        DisplayMap(grid: app.grid, action: app.action(for:), style: .regular, ripple: app.ripple,
                   onSelect: { app.testAction(zone: $0) },
                   contextMenu: { zone in AnyView(ZoneActionMenu(zone: zone).environment(app)) })
    }

    private var firstRun: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app.config.hasProfiles
                 ? String(localized: "Calibrate “\(app.config.activeProfile?.name ?? "")” on this surface: tap each highlighted zone a few times. About two minutes.")
                 : String(localized: "Tap each highlighted zone a few times so LidTap learns your screen. About two minutes."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { dismiss(); app.startCalibration() } label: {
                Text(String(localized: "Calibrate")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

/// Right-click menu on a zone: reassign it in place.
struct ZoneActionMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let zone: Int

    var body: some View {
        let current = app.action(for: zone).kind
        Text(String(localized: "Zone \(zone + 1)"))
        ForEach(ActionKind.allCases.filter { !$0.needsChoice }) { kind in
            Button {
                app.setAction(ZoneAction(kind: kind), for: zone)
            } label: {
                Label(kind.title, systemImage: current == kind ? "checkmark" : kind.symbol)
            }
        }
        Divider()
        Button(String(localized: "Open App…")) { dismiss(); app.showSettings(pane: "zones", zone: zone, choose: .openApp) }
        Button(String(localized: "Run Shortcut…")) { dismiss(); app.showSettings(pane: "zones", zone: zone, choose: .runShortcut) }
    }
}

/// A menu-style row: full width, highlights on hover like a menu item, with an optional shortcut.
struct MenuRow: View {
    let title: String
    let symbol: String
    var shortcut: String?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(hover ? Color.white : .secondary)
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(hover ? Color.white.opacity(0.85) : Color.secondary) }
            }
            .font(.body)
            .foregroundStyle(hover ? Color.white : .primary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(hover ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
