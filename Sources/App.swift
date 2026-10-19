import SwiftUI

/// App entry point: a menu-bar-only app with a grid icon.
@main
struct AutoTileGridApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("AutoTileGrid", systemImage: "square.grid.2x2") {
            MenuContent(state: state)
        }
    }
}

/// The menu bar dropdown: permission row, tiling actions, mode submenu, settings and quit.
struct MenuContent: View {
    @ObservedObject var state: AppState
    @AppStorage(Prefs.mode) private var modeRaw = TileMode.equalGrid.rawValue
    @AppStorage(Prefs.tileMods) private var tileMods = 0
    @AppStorage(Prefs.tileLabel) private var tileLabel = "T"
    @AppStorage(Prefs.undoMods) private var undoMods = 0
    @AppStorage(Prefs.undoLabel) private var undoLabel = "Z"

    var body: some View {
        if !state.isTrusted {
            Button("⚠️ Grant Access… (Accessibility required)") { state.requestAccess() }
            Divider()
        }
        Button("Tile Now   \(HotKeyService.modifierSymbols(UInt32(tileMods)))\(tileLabel)") { state.tileNow() }
            .disabled(!state.isTrusted)
        Menu("Mode") {
            ForEach(TileMode.allCases) { mode in
                Toggle(mode.title, isOn: Binding(
                    get: { modeRaw == mode.rawValue },
                    set: { _ in state.select(mode) }
                ))
            }
        }
        Button("Undo Last Tiling   \(HotKeyService.modifierSymbols(UInt32(undoMods)))\(undoLabel)") { state.undo() }
            .disabled(!state.canUndo || !state.isTrusted)
        Divider()
        Button("Settings…") { SettingsWindowController.shared.show(state: state) }
            .keyboardShortcut(",")
        Button("Support / Donate ❤️") {
            NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
        }
        Divider()
        Button("Quit AutoTileGrid") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
