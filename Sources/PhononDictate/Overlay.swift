import AppKit
import SwiftUI

final class OverlayModel: ObservableObject {
    enum Mode: Equatable {
        case recording(since: Date)
        case transcribing
        case message(String, symbol: String)
    }

    static let barCount = 36

    @Published var mode: Mode = .transcribing
    @Published var levels = [CGFloat](repeating: 0, count: OverlayModel.barCount)

    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(CGFloat(level))
    }

    func resetLevels() {
        levels = [CGFloat](repeating: 0, count: OverlayModel.barCount)
    }
}

/// A floating capsule at the bottom of the screen. It takes no focus and no clicks.
final class OverlayController {
    let model = OverlayModel()
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?
    private static let size = NSSize(width: 320, height: 90)

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
        model.resetLevels()
        show(.recording(since: Date()))
    }

    func showTranscribing() {
        show(.transcribing)
    }

    func flash(_ text: String, symbol: String = "exclamationmark.triangle.fill", seconds: Double = 2.5) {
        show(.message(text, symbol: symbol))
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            if panel.alphaValue == 0 { panel.orderOut(nil) }
        })
    }

    private func show(_ mode: OverlayModel.Mode) {
        hideWork?.cancel()
        hideWork = nil
        model.mode = mode
        if !panel.isVisible || panel.alphaValue < 1 {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: frame.midX - OverlayController.size.width / 2, y: frame.minY + 48))
            }
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: 12) {
            switch model.mode {
            case .recording(let since):
                Circle().fill(.red).frame(width: 8, height: 8)
                Waveform(levels: model.levels)
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(Self.elapsed(context.date.timeIntervalSince(since)))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            case .transcribing:
                ProgressView().controlSize(.small)
                Text("Transcribing…").font(.system(size: 13, weight: .medium))
            case .message(let text, let symbol):
                Image(systemName: symbol)
                Text(text).font(.system(size: 13, weight: .medium)).lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func elapsed(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Bars for the most recent input levels, newest on the right.
struct Waveform: View {
    var levels: [CGFloat]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: 3 + levels[i] * 25)
            }
        }
        .frame(height: 28)
        .animation(.linear(duration: 0.06), value: levels)
    }
}
