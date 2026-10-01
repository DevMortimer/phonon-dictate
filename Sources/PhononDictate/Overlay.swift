import AppKit
import SwiftUI

final class OverlayModel: ObservableObject {
    enum Tone { case neutral, success, error }

    enum Mode: Equatable {
        case recording(since: Date)
        case transcribing
        case message(String, symbol: String, tone: Tone)
    }

    @Published var mode: Mode = .transcribing
    @Published var visible = false
    let ribbon = RibbonInput()
}

/// A floating pill at the bottom of the screen. It takes no focus and no clicks.
final class OverlayController {
    let model = OverlayModel()
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?
    private static let size = NSSize(width: 400, height: 120)

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: OverlayController.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: OverlayView(model: model))
        host.frame = NSRect(origin: .zero, size: OverlayController.size)
        panel.contentView = host
    }

    func showRecording() {
        model.ribbon.meter = Meter(level: 0, low: 0, mid: 0, high: 0)
        model.ribbon.flatten = 0
        model.ribbon.sweep = 0
        show(.recording(since: Date()))
    }

    func showTranscribing() {
        model.ribbon.meter = Meter(level: 0, low: 0, mid: 0, high: 0)
        model.ribbon.flatten = 1
        model.ribbon.sweep = 1
        show(.transcribing)
    }

    func flash(_ text: String, symbol: String = "exclamationmark.triangle.fill", tone: OverlayModel.Tone = .error, seconds: Double = 2.5) {
        show(.message(text, symbol: symbol, tone: tone))
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        model.visible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.model.visible else { return }
            self.panel.orderOut(nil)
        }
    }

    private func show(_ mode: OverlayModel.Mode) {
        hideWork?.cancel()
        hideWork = nil
        if model.visible {
            model.mode = mode
            return
        }
        model.mode = mode
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - OverlayController.size.width / 2, y: frame.minY + 24))
        }
        panel.orderFrontRegardless()
        DispatchQueue.main.async { self.model.visible = true }
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    private static let ink = Color(red: 0.055, green: 0.055, blue: 0.07)
    private static let recordRed = Color(red: 1.0, green: 0.3, blue: 0.33)
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private var showsRibbon: Bool {
        switch model.mode {
        case .recording, .transcribing: return true
        case .message: return false
        }
    }

    var body: some View {
        content
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background {
                Capsule().fill(Self.ink)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.09), lineWidth: 1))
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            .scaleEffect(model.visible || reduceMotion ? 1 : 0.6)
            .blur(radius: model.visible || reduceMotion ? 0 : 8)
            .opacity(model.visible ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.72), value: model.visible)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.8), value: model.mode)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        if showsRibbon {
            HStack(spacing: 12) {
                if case .recording = model.mode {
                    Circle().fill(Self.recordRed).frame(width: 7, height: 7)
                        .transition(.scale.combined(with: .opacity))
                }
                RibbonView(input: model.ribbon, active: model.visible)
                    .frame(width: 200, height: 44)
                    .accessibilityLabel("Voice level")
                switch model.mode {
                case .recording(let since):
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Text(Self.elapsed(context.date.timeIntervalSince(since)))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .transition(.opacity)
                default:
                    Text("Transcribing")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .transition(.opacity)
                }
            }
        } else if case .message(let text, let symbol, let tone) = model.mode {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Self.color(tone))
                    .symbolEffect(.bounce, value: text)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }
            .fixedSize()
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private static func color(_ tone: OverlayModel.Tone) -> Color {
        switch tone {
        case .neutral: return .white.opacity(0.85)
        case .success: return Color(red: 0.36, green: 0.86, blue: 0.56)
        case .error: return Color(red: 1.0, green: 0.72, blue: 0.32)
        }
    }

    static func elapsed(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
