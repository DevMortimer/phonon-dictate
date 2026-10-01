import AppKit
import SwiftUI

/// The first-launch window: a breathing ribbon, the three setup steps, and the live log line.
struct SetupView: View {
    @ObservedObject var engine: Engine
    let shortcut: String
    let ribbon: RibbonInput
    let close: () -> Void

    static let ink = Color(red: 0.055, green: 0.055, blue: 0.07)
    private static let green = Color(red: 0.36, green: 0.86, blue: 0.56)
    private static let red = Color(red: 1.0, green: 0.5, blue: 0.5)

    private var failure: String? {
        if case .failed(let message) = engine.state { return message }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RibbonView(input: ribbon, active: true)
                .frame(height: 76)
                .padding(.horizontal, -12)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 18)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Engine.steps.indices, id: \.self) { i in stepRow(i) }
            }
            .padding(.top, 24)

            footer.padding(.top, 28)
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(width: 460)
        .background(Self.ink)
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.25), value: engine.state)
        .animation(.easeOut(duration: 0.25), value: engine.step)
        .onChange(of: engine.state) { _, state in
            ribbon.synthetic = state == .installing || state == .checking
            if state == .ready { ribbon.excite() }
            ribbon.flatten = failure == nil ? 0 : 1
        }
    }

    private var title: String {
        switch engine.state {
        case .ready: return "Ready to dictate"
        case .failed: return "Setup stopped"
        default: return "Setting up Phonon Dictate"
        }
    }

    private var subtitle: String {
        switch engine.state {
        case .ready: return "The speech engine and Phonon-2 are on this Mac. From now on, everything runs offline."
        case .failed: return failure ?? ""
        default: return "This happens once. The app installs its speech engine and downloads Phonon-2, about 1.2 GB in total. On a slow connection this can take several minutes."
        }
    }

    private enum StepState { case done, running, pending, failed }

    private func stepState(_ i: Int) -> StepState {
        switch engine.state {
        case .ready: return .done
        case .failed: return i < engine.step ? .done : i == engine.step ? .failed : .pending
        default: return i < engine.step ? .done : i == engine.step ? .running : .pending
        }
    }

    @ViewBuilder
    private func stepRow(_ i: Int) -> some View {
        let state = stepState(i)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ZStack {
                switch state {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Self.green)
                case .running: ProgressView().controlSize(.small).scaleEffect(0.8)
                case .pending: Image(systemName: "circle").foregroundStyle(.white.opacity(0.35))
                case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Self.red)
                }
            }
            .font(.system(size: 15))
            .frame(width: 18, height: 18)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

            VStack(alignment: .leading, spacing: 4) {
                Text(Engine.steps[i])
                    .font(.system(size: 14, weight: state == .running ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(state == .pending ? 0.5 : 0.92))
                if (state == .running || state == .failed), !engine.detail.isEmpty {
                    // Literal output of the running command.
                    Text(engine.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            switch engine.state {
            case .ready:
                Text("Press \(shortcut) in any app to start.")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            case .failed:
                Spacer()
                Button("Open Setup Log") { NSWorkspace.shared.open(engine.setupLog) }
                Button("Try Again") { engine.setup() }.keyboardShortcut(.defaultAction)
            default:
                Text("You can close this window. Setup continues, and the menu-bar item shows the progress.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Button("Hide", action: close)
            }
        }
    }
}
