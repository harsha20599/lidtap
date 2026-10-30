import AppKit
import SwiftUI

// MARK: - Tokens

/// LidTap's design language. Native structure everywhere; the identity is the Display Map (the laptop screen
/// drawn at its real proportions, split into zones by hairlines) and the ripple that answers every tap.
enum DS {
    static let space: (xs: CGFloat, s: CGFloat, m: CGFloat, l: CGFloat, xl: CGFloat) = (4, 8, 12, 20, 32)
    /// The drawn display is always a dark panel, in light and dark mode alike, as the real screen is.
    static let screen = Color(red: 0.075, green: 0.078, blue: 0.09)
    static let hairline = Color.white.opacity(0.12)

    enum Motion {
        static let feedback = Animation.snappy(duration: 0.12)
        static let state = Animation.smooth(duration: 0.25)
        static let overlayIn = Animation.smooth(duration: 0.3)
        static let overlayOut = Animation.easeOut(duration: 0.2)
        static let ripple = 0.55
    }
}

extension NSScreen {
    /// The laptop's own display (where taps happen), falling back to the main screen.
    static var builtIn: NSScreen? {
        screens.first { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return CGDisplayIsBuiltin(id) != 0
        } ?? main
    }

    static var builtInAspect: CGFloat {
        guard let s = builtIn else { return 1.54 }
        return s.frame.width / max(s.frame.height, 1)
    }
}

// MARK: - Liquid Glass with a material fallback

extension View {
    /// Liquid Glass on macOS 26+, a regular material before. Only for controls floating over full-screen
    /// surfaces (calibration, Privacy Guard, tap feedback): never on settings content.
    @ViewBuilder
    func floatingGlass(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func floatingGlassCapsule() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self.background(.regularMaterial, in: Capsule())
        }
    }
}

// MARK: - Action glyph

/// An action's symbol in its own hue (or the chosen app's icon). No tile, no gradient.
struct ActionGlyph: View {
    let action: ZoneAction
    var size: CGFloat = 16

    var body: some View {
        if action.kind == .openApp, let id = action.appBundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: size * 1.35, height: size * 1.35)
        } else {
            Image(systemName: action.kind.symbol)
                .font(.system(size: size, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(action.kind.tint)
                .frame(width: size * 1.35, height: size * 1.35)
        }
    }
}

// MARK: - Ripple (the answer to a tap)

/// A ring that spreads from the centre of a zone. Fires whenever `trigger` changes.
struct Ripple: View {
    let color: Color
    let trigger: Int
    @State private var progress: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let d = max(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: d, height: d)
                    .scaleEffect(reduceMotion ? 1 : 0.15 + progress * 0.95)
                    .opacity(reduceMotion ? (1 - progress) * 0.6 : (1 - progress) * 0.9)
                Circle()
                    .strokeBorder(color.opacity(0.6), lineWidth: 1)
                    .frame(width: d, height: d)
                    .scaleEffect(reduceMotion ? 1 : 0.05 + progress * 0.6)
                    .opacity(reduceMotion ? 0 : (1 - progress) * 0.7)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            progress = 0
            withAnimation(.easeOut(duration: DS.Motion.ripple)) { progress = 1 }
        }
    }
}

// MARK: - Display Map (the signature)

/// The laptop display at its real proportions, split into zones by hairlines. Used on every surface.
struct DisplayMap: View {
    enum Style { case compact, regular, large }

    let grid: Grid
    let action: (Int) -> ZoneAction
    var style: Style = .regular
    var selected: Int?
    /// Zone index and a counter: bump the counter to ripple that zone.
    var ripple: (zone: Int, id: Int)?
    /// Optional 0–1 reliability per zone: tints each zone from red (unreliable) to its own hue.
    var reliability: [Int: Double]?
    var onSelect: ((Int) -> Void)?
    var contextMenu: ((Int) -> AnyView)?

    @State private var hovered: Int?

    private var corner: CGFloat { style == .compact ? 8 : style == .regular ? 12 : 16 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width / CGFloat(grid.cols), h = geo.size.height / CGFloat(grid.rows)
            ZStack(alignment: .topLeading) {
                DS.screen
                ForEach(0..<grid.count, id: \.self) { i in
                    zone(i, size: CGSize(width: w, height: h))
                        .frame(width: w, height: h)
                        .offset(x: CGFloat(i % grid.cols) * w, y: CGFloat(i / grid.cols) * h)
                }
                hairlines(w: w, h: h, size: geo.size)
                if style == .large {
                    Capsule().fill(Color.black).frame(width: geo.size.width * 0.12, height: 7)
                        .frame(maxWidth: .infinity).padding(.top, 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
        }
        .aspectRatio(NSScreen.builtInAspect, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zones on your screen")
    }

    private func hairlines(w: CGFloat, h: CGFloat, size: CGSize) -> some View {
        Path { p in
            for c in 1..<max(grid.cols, 1) { p.move(to: CGPoint(x: CGFloat(c) * w, y: 0)); p.addLine(to: CGPoint(x: CGFloat(c) * w, y: size.height)) }
            for r in 1..<max(grid.rows, 1) { p.move(to: CGPoint(x: 0, y: CGFloat(r) * h)); p.addLine(to: CGPoint(x: size.width, y: CGFloat(r) * h)) }
        }
        .stroke(DS.hairline, lineWidth: 1)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func zone(_ i: Int, size: CGSize) -> some View {
        let a = action(i)
        let isSelected = selected == i, isHovered = hovered == i
        let hue: Color = reliability.map { r in r[i].map { $0 >= 0.9 ? a.kind.tint : $0 >= 0.75 ? Color.orange : Color.red } ?? .gray } ?? a.kind.tint
        let wash = reliability != nil ? 0.32 : (isSelected ? 0.26 : isHovered ? 0.2 : 0.12)
        let showLabel = style != .compact && size.width > 84 && size.height > 54
        ZStack {
            Rectangle().fill(a.kind == .none && reliability == nil ? Color.white.opacity(isHovered ? 0.05 : 0) : hue.opacity(wash))
            VStack(spacing: style == .large ? 8 : 4) {
                if let r = reliability {
                    Text(r[i].map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                        .font(.system(style == .large ? .title2 : .headline, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                } else {
                    ActionGlyph(action: a, size: style == .compact ? 13 : style == .regular ? 17 : 24)
                }
                if showLabel {
                    Text(a.title)
                        .font(style == .large ? .callout.weight(.medium) : .caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                }
            }
            if style != .compact {
                Text("\(i + 1)")
                    .font(.system(size: style == .large ? 11 : 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.38))
                    .padding(style == .large ? 9 : 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let ripple, ripple.zone == i { Ripple(color: a.kind == .none ? .white : a.kind.tint, trigger: ripple.id) }
            if isSelected {
                Rectangle().strokeBorder(Color.accentColor, lineWidth: 2).padding(1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? i : (hovered == i ? nil : hovered) }
        .onTapGesture { onSelect?(i) }
        .contextMenu { if let contextMenu { contextMenu(i) } }
        .help("Zone \(i + 1): \(a.title)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zone \(i + 1), \(a.title)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .animation(DS.Motion.feedback, value: isHovered)
        .animation(DS.Motion.state, value: isSelected)
    }
}

// MARK: - Live motion (real sensor data, never ornament)

/// Twist strength over the last few seconds with the trigger level; taps are marked where they fired.
struct MotionTrace: View {
    let detector: TapDetector
    var seconds = 4.0
    var showsAxes = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
            Canvas { ctx, size in
                let snap = detector.scopeSnapshot(seconds: seconds)
                guard let tEnd = snap.t.last else { return }
                let x = { (t: Double) in size.width * (1 - (tEnd - t) / seconds) }
                let peak = max(snap.threshold * 1.6, (snap.mag.max() ?? 0) * 1.1)
                let baseline = showsAxes ? size.height * 0.62 : size.height
                if showsAxes {
                    let range = max(2, snap.gyro.map { max(abs($0.x), abs($0.y), abs($0.z)) }.max() ?? 0) * 1.15
                    let mid = size.height * 0.28
                    let colors: [Color] = [.red, .green, .blue]
                    for axis in 0..<3 {
                        var p = Path()
                        for (i, t) in snap.t.enumerated() {
                            let pt = CGPoint(x: x(t), y: mid - CGFloat(snap.gyro[i][axis] / range) * (mid - 4))
                            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                        }
                        ctx.stroke(p, with: .color(colors[axis].opacity(0.75)), lineWidth: 1)
                    }
                    ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: baseline + 6)); $0.addLine(to: CGPoint(x: size.width, y: baseline + 6)) },
                               with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
                }
                let top = showsAxes ? baseline + 10 : 2.0
                let y = { (v: Double) in size.height - 1 - (size.height - 1 - top) * min(v / peak, 1) }
                var line = Path()
                for (i, t) in snap.t.enumerated() {
                    let pt = CGPoint(x: x(t), y: y(snap.mag[i]))
                    i == 0 ? line.move(to: pt) : line.addLine(to: pt)
                }
                ctx.stroke(line, with: .color(.primary.opacity(0.7)), lineWidth: 1.1)
                let ty = y(snap.threshold)
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: ty)); $0.addLine(to: CGPoint(x: size.width, y: ty)) },
                           with: .color(.accentColor.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                for t in snap.taps {
                    let px = x(t)
                    ctx.fill(Path(ellipseIn: CGRect(x: px - 2.5, y: ty - 2.5, width: 5, height: 5)), with: .color(.accentColor))
                }
            }
        }
        .accessibilityLabel("Live motion from the sensor")
    }
}

/// One tap's gyro window, for the Detection pane.
struct TapWaveform: View {
    let gyro: [[Double]]

    var body: some View {
        Canvas { ctx, size in
            guard gyro.count > 1 else { return }
            let m = max(0.5, gyro.map { $0.map(abs).max() ?? 0 }.max() ?? 0) * 1.1
            let colors: [Color] = [.red, .green, .blue]
            for axis in 0..<3 {
                var p = Path()
                for (i, r) in gyro.enumerated() {
                    let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(gyro.count - 1), y: size.height / 2 - CGFloat(r[axis] / m) * (size.height / 2 - 2))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                ctx.stroke(p, with: .color(colors[axis].opacity(0.8)), lineWidth: 1.1)
            }
        }
        .accessibilityHidden(true)
    }
}

extension ModelReport {
    /// Share of each zone's taps that cross-validation put in the right zone.
    var zoneReliability: [Int: Double] {
        guard let cm = confusion else { return [:] }
        var out: [Int: Double] = [:]
        for (i, label) in labels.enumerated() {
            guard let z = zoneIndex(label) else { continue }
            let total = cm[i].reduce(0, +)
            if total > 0 { out[z] = Double(cm[i][i]) / Double(total) }
        }
        return out
    }
}
