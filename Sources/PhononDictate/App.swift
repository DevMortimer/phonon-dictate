import AppKit
import Combine
import SwiftUI

@main
enum Main {
    static func main() {
        signal(SIGPIPE, SIG_IGN) // a worker that exits early must not kill the app
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let store = Store()
    private lazy var engine = Engine(root: store.root)
    private lazy var controller = DictationController(store: store, engine: engine, settings: settings)
    private let hotKey = HotKey(id: 1)
    private var hotKeyError: String?
    private var statusItem: NSStatusItem!
    private var windows: [String: NSWindow] = [:]
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller.$phase.sink { [weak self] phase in
            DispatchQueue.main.async { self?.updateIcon(phase) }
        }.store(in: &subscriptions)
        settings.$shortcut.combineLatest(settings.$capturingShortcut)
            .sink { [weak self] shortcut, capturing in self?.registerHotKey(shortcut, enabled: !capturing) }
            .store(in: &subscriptions)
        settings.$recordingRetentionDays.combineLatest(settings.$historyRetentionDays).dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.controller.applyRetention() } }
            .store(in: &subscriptions)

        controller.applyRetention()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.controller.applyRetention()
        }
        engine.setup()
    }

    private func registerHotKey(_ shortcut: Shortcut, enabled: Bool) {
        guard enabled else {
            hotKey.unregister()
            return
        }
        let ok = hotKey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            self?.controller.toggle()
        }
        hotKeyError = ok ? nil : "\(shortcut.display) is used by another app"
    }

    private func updateIcon(_ phase: DictationController.Phase) {
        let name = phase == .recording ? "waveform.circle.fill" : "waveform"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Phonon Dictate")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status: String
        if let hotKeyError {
            status = hotKeyError
        } else if engine.state != .ready {
            status = engine.state.description
        } else {
            switch controller.phase {
            case .idle: status = "Press \(settings.shortcut.display) to dictate"
            case .recording: status = "Recording…"
            case .transcribing: status = "Transcribing…"
            }
        }
        menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))

        let toggleTitle = controller.phase == .recording ? "Stop Dictation" : "Start Dictation"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleDictation), keyEquivalent: "")
        toggle.target = self
        toggle.isEnabled = controller.phase != .transcribing && engine.state == .ready
        menu.addItem(toggle)
        menu.addItem(.separator())

        let recent = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        for entry in store.history.suffix(10).reversed() {
            let title = entry.text.count > 60 ? String(entry.text.prefix(60)) + "…" : entry.text
            let item = NSMenuItem(title: title, action: #selector(copyEntry(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.text
            item.toolTip = "Copy"
            recentMenu.addItem(item)
        }
        if recentMenu.items.isEmpty {
            recentMenu.addItem(NSMenuItem(title: "No transcripts yet", action: nil, keyEquivalent: ""))
        }
        recent.submenu = recentMenu
        menu.addItem(recent)
        addItem(menu, "History…", #selector(showHistory))
        addItem(menu, "Open Recordings Folder", #selector(openRecordings))
        menu.addItem(.separator())
        addItem(menu, "Settings…", #selector(showSettings), key: ",")
        addItem(menu, "Quit Phonon Dictate", #selector(quit), key: "q")
    }

    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func toggleDictation() { controller.toggle() }

    @objc private func copyEntry(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func openRecordings() { NSWorkspace.shared.open(store.recordingsDir) }

    @objc private func showHistory() {
        show("history", title: "History", resizable: true, HistoryView(store: store))
    }

    @objc private func showSettings() {
        show("settings", title: "Phonon Dictate Settings", resizable: false,
             SettingsView(settings: settings, engine: engine, store: store) { [weak self] in self?.showHistory() })
    }

    @objc private func quit() {
        controller.cancel()
        NSApp.terminate(nil)
    }

    private func show<V: View>(_ id: String, title: String, resizable: Bool, _ view: V) {
        let window = windows[id] ?? {
            var style: NSWindow.StyleMask = [.titled, .closable]
            if resizable { style.insert(.resizable) }
            let w = NSWindow(contentRect: .zero, styleMask: style, backing: .buffered, defer: false)
            w.title = title
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: view)
            w.center()
            windows[id] = w
            return w
        }()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
