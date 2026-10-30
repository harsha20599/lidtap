import AppKit
import SwiftUI

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none, desktopLeft, desktopRight, newNote, playPause, nextTrack, previousTrack, openApp, privacyGuard
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Nothing"
        case .desktopLeft: "Desktop Left"
        case .desktopRight: "Desktop Right"
        case .newNote: "New Note"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        case .openApp: "Open App"
        case .privacyGuard: "Privacy Guard"
        }
    }

    var detail: String {
        switch self {
        case .none: "This zone does nothing"
        case .desktopLeft: "Switch to the Space on the left"
        case .desktopRight: "Switch to the Space on the right"
        case .newNote: "Open Notes with a fresh note"
        case .playPause: "Play or pause whatever is playing"
        case .nextTrack: "Skip to the next track"
        case .previousTrack: "Go back a track"
        case .openApp: "Launch an app, or bring it to the front"
        case .privacyGuard: "Mute, camera off and blur the screen"
        }
    }

    var symbol: String {
        switch self {
        case .none: "minus"
        case .desktopLeft: "rectangle.lefthalf.inset.filled.arrow.left"
        case .desktopRight: "rectangle.righthalf.inset.filled.arrow.right"
        case .newNote: "square.and.pencil"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.end.fill"
        case .previousTrack: "backward.end.fill"
        case .openApp: "arrow.up.forward.app"
        case .privacyGuard: "eye.slash"
        }
    }

    /// Each action wears the hue of the Mac app or feature it belongs to (Spaces, Notes, Music, Privacy).
    var tint: Color {
        switch self {
        case .none: Color(nsColor: .tertiaryLabelColor)
        case .desktopLeft, .desktopRight: .blue
        case .newNote: .yellow
        case .playPause, .nextTrack, .previousTrack: .pink
        case .openApp: .teal
        case .privacyGuard: .indigo
        }
    }

    /// Short group used to organise the action picker.
    var group: String {
        switch self {
        case .none: "None"
        case .desktopLeft, .desktopRight: "Desktop"
        case .playPause, .nextTrack, .previousTrack: "Music"
        case .newNote, .openApp: "Apps"
        case .privacyGuard: "Privacy"
        }
    }

    /// Whether the action synthesises key events (needs Accessibility permission).
    var needsAccessibility: Bool {
        switch self {
        case .desktopLeft, .desktopRight, .newNote, .playPause, .nextTrack, .previousTrack: true
        // Privacy Guard's blur and mic mute work without it; only the camera shortcut needs it (reported in the overlay).
        case .none, .openApp, .privacyGuard: false
        }
    }
}

struct ZoneAction: Codable, Equatable, Hashable {
    var kind: ActionKind = .none
    var appBundleID: String?
    var appName: String?

    var title: String {
        if kind == .openApp, let appName { return appName }
        return kind.title
    }

    static func defaults(for grid: Grid) -> [String: ZoneAction] {
        let layout: [ActionKind]
        switch (grid.rows, grid.cols) {
        case (2, 2): layout = [.desktopLeft, .desktopRight, .playPause, .privacyGuard]
        case (2, 3): layout = [.desktopLeft, .newNote, .desktopRight, .previousTrack, .playPause, .privacyGuard]
        case (3, 3): layout = [.desktopLeft, .newNote, .desktopRight, .previousTrack, .playPause, .nextTrack, .openApp, .none, .privacyGuard]
        default: layout = []
        }
        var out: [String: ZoneAction] = [:]
        for i in 0..<grid.count { out[zoneLabel(i)] = ZoneAction(kind: i < layout.count ? layout[i] : .none) }
        return out
    }
}
