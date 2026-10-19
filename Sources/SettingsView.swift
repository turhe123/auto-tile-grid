import AppKit
import ServiceManagement
import SwiftUI

/// Hosts the SwiftUI settings form in a regular AppKit window and brings it to the front.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    private init() {}

    func show(state: AppState) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(state: state)))
            w.title = "AutoTileGrid Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The settings form: hotkeys, layout, exclusions, launch at login and support.
struct SettingsView: View {
    @ObservedObject var state: AppState
    @AppStorage(Prefs.mode) private var modeRaw = TileMode.equalGrid.rawValue
    @AppStorage(Prefs.gap) private var gap = 8.0
    @AppStorage(Prefs.margin) private var margin = 8.0
    @AppStorage(Prefs.ratio) private var ratio = 0.6
    @AppStorage(Prefs.excluded) private var excludedRaw = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var excluded: [String] { excludedRaw.split(separator: "\n").map(String.init) }

    var body: some View {
        Form {
            Section {
                if state.isTrusted {
                    Label("Accessibility access granted", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Accessibility access is required to move windows. Hotkeys do nothing until it is granted.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Open System Settings → Privacy & Security → Accessibility and enable AutoTileGrid.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Grant Access…") { state.requestAccess() }
                    }
                }
            }

            Section("Hotkeys") {
                LabeledContent("Tile / cycle mode") {
                    HotKeyRecorder(keyCodeKey: Prefs.tileKeyCode, modsKey: Prefs.tileMods,
                                   labelKey: Prefs.tileLabel, state: state)
                }
                LabeledContent("Undo last tiling") {
                    HotKeyRecorder(keyCodeKey: Prefs.undoKeyCode, modsKey: Prefs.undoMods,
                                   labelKey: Prefs.undoLabel, state: state)
                }
                Text("Press the tile hotkey again without moving any window to cycle to the next mode.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Layout") {
                Picker("Default mode", selection: $modeRaw) {
                    ForEach(TileMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Stepper(value: $gap, in: 0...64, step: 1) {
                    LabeledContent("Inner gap", value: "\(Int(gap)) pt")
                }
                Stepper(value: $margin, in: 0...128, step: 1) {
                    LabeledContent("Outer margin", value: "\(Int(margin)) pt")
                }
                LabeledContent("Main window ratio") {
                    HStack {
                        Slider(value: $ratio, in: 0.3...0.8, step: 0.05)
                        Text("\(Int((ratio * 100).rounded()))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                Text("Used by Main Left and Main Top.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Excluded apps") {
                if excluded.isEmpty {
                    Text("No excluded apps.").foregroundStyle(.secondary)
                }
                ForEach(excluded, id: \.self) { bundleID in
                    HStack {
                        Text(appName(for: bundleID))
                        Text(bundleID).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) { remove(bundleID) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add App…", action: addApp)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Button("Support / Donate ❤️") {
                    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        var list = excluded
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !list.contains(id) { list.append(id) }
        }
        excludedRaw = list.joined(separator: "\n")
    }

    private func remove(_ bundleID: String) {
        excludedRaw = excluded.filter { $0 != bundleID }.joined(separator: "\n")
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not update login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// A click-to-record shortcut field that stores a Carbon key code, modifiers and display label.
struct HotKeyRecorder: View {
    let keyCodeKey: String
    let modsKey: String
    let labelKey: String
    let state: AppState

    @State private var recording = false
    @State private var monitor: Any?
    @State private var display = ""

    var body: some View {
        Button(recording ? "Type shortcut… (Esc cancels)" : display) {
            recording ? stop() : start()
        }
        .frame(minWidth: 140)
        .onAppear { display = currentLabel() }
        .onDisappear { stop() }
    }

    private func currentLabel() -> String {
        let d = UserDefaults.standard
        return HotKeyService.modifierSymbols(UInt32(d.integer(forKey: modsKey))) + (d.string(forKey: labelKey) ?? "?")
    }

    private func start() {
        recording = true
        state.suspendHotKeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc
            let mods = HotKeyService.carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else { NSSound.beep(); return nil }
            let d = UserDefaults.standard
            d.set(Int(event.keyCode), forKey: keyCodeKey)
            d.set(Int(mods), forKey: modsKey)
            d.set(Self.keyName(for: event), forKey: labelKey)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { state.reloadHotKeys() }
        recording = false
        display = currentLabel()
    }

    private static func keyName(for event: NSEvent) -> String {
        switch event.keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let chars = event.charactersIgnoringModifiers?.uppercased() ?? ""
            return chars.isEmpty ? "Key \(event.keyCode)" : chars
        }
    }
}
