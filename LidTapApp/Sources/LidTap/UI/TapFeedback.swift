import AppKit
import SwiftUI

/// Click-through panel over the laptop display: a ripple spreads from the tapped zone and a small glass label
/// names what happened. Quiet enough to hold up on the hundredth tap.
@MainActor
final class TapFeedback {
    static let shared = TapFeedback()

    private var panel: NSPanel?
    private let model = FeedbackModel()
    private var hideWork: DispatchWorkItem?

    @Observable final class FeedbackModel {
        var zone: Int?
        var grid = Grid(rows: 2, cols: 2)
        var action: ZoneAction?
        var token = 0
    }

    func show(zone: Int?, grid: Grid, action: ZoneAction?) {
        guard let screen = NSScreen.builtIn else { return }
        if panel == nil {
            let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .popUpMenu
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.appearance = NSAppearance(named: .darkAqua)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.contentView = NSHostingView(rootView: FeedbackView(model: model))
            panel = p
        }
        panel?.setFrame(screen.frame, display: false)
        model.zone = zone
        model.grid = grid
        model.action = action
        model.token += 1
        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let panel = self?.panel else { return }
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 },
                                                     completionHandler: { panel.orderOut(nil) })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: work)
    }
}

private struct FeedbackView: View {
    let model: TapFeedback.FeedbackModel
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            if let zone = model.zone, let action = model.action {
                let w = geo.size.width / CGFloat(model.grid.cols), h = geo.size.height / CGFloat(model.grid.rows)
                let rect = CGRect(x: CGFloat(zone % model.grid.cols) * w, y: CGFloat(zone / model.grid.cols) * h, width: w, height: h)
                let tint = action.kind == .none ? Color.white : action.kind.tint
                ZStack {
                    Ripple(color: tint, trigger: model.token)
                        .frame(width: min(w, h) * 0.9, height: min(w, h) * 0.9)
                    Label {
                        Text(action.title).font(.title3.weight(.semibold))
                    } icon: {
                        ActionGlyph(action: action, size: 20)
                    }
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .floatingGlassCapsule()
                    .scaleEffect(reduceMotion || shown ? 1 : 0.92)
                    .opacity(shown ? 1 : 0)
                }
                .position(x: rect.midX, y: rect.midY)
            } else {
                Label("Not sure which zone. Tap again", systemImage: "questionmark.circle")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .floatingGlassCapsule()
                    .opacity(shown ? 1 : 0)
                    .position(x: geo.size.width / 2, y: geo.size.height - 96)
            }
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: model.token) {
            shown = false
            withAnimation(DS.Motion.feedback) { shown = true }
        }
    }
}
