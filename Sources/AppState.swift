import AppKit
import ApplicationServices
import Carbon

/// UserDefaults keys shared by `@AppStorage` views and the tiling engine.
enum Prefs {
    static let mode = "mode"
    static let gap = "innerGap"
    static let margin = "outerMargin"
    static let ratio = "mainRatio"
    static let excluded = "excludedBundleIDs" // newline-separated
    static let tileKeyCode = "tileKeyCode", tileMods = "tileModifiers", tileLabel = "tileKeyLabel"
    static let undoKeyCode = "undoKeyCode", undoMods = "undoModifiers", undoLabel = "undoKeyLabel"

    static func registerDefaults() {
        let ctrlOpt = controlKey | optionKey
        UserDefaults.standard.register(defaults: [
            mode: TileMode.equalGrid.rawValue, gap: 8.0, margin: 8.0, ratio: 0.6, excluded: "",
            tileKeyCode: kVK_ANSI_T, tileMods: ctrlOpt, tileLabel: "T",
            undoKeyCode: kVK_ANSI_Z, undoMods: ctrlOpt, undoLabel: "Z",
        ])
    }

    static var excludedSet: Set<String> {
        Set((UserDefaults.standard.string(forKey: excluded) ?? "")
            .split(separator: "\n").map(String.init))
    }
}

/// Central controller: owns permission state, hotkeys, tiling, cycling and undo.
final class AppState: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var canUndo = false

    /// Frames before the last tiling (or the first tiling of a cycle), for undo.
    private var snapshot: [WindowKey: (element: AXUIElement, frame: CGRect)] = [:]
    /// Frames as they ended up after the last tiling; used to detect "press again to cycle".
    private var lastApplied: [(element: AXUIElement, frame: CGRect)] = []
    private var trustTimer: Timer?

    private let tileHotKeyID: UInt32 = 1
    private let undoHotKeyID: UInt32 = 2

    init() {
        Prefs.registerDefaults()
        reloadHotKeys()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            if trusted != self.isTrusted { self.isTrusted = trusted }
        }
    }

    var mode: TileMode {
        get { TileMode(rawValue: UserDefaults.standard.string(forKey: Prefs.mode) ?? "") ?? .equalGrid }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Prefs.mode); objectWillChange.send() }
    }

    // MARK: Hotkeys

    func reloadHotKeys() {
        let d = UserDefaults.standard
        HotKeyService.shared.register(id: tileHotKeyID, keyCode: UInt32(d.integer(forKey: Prefs.tileKeyCode)),
                                      modifiers: UInt32(d.integer(forKey: Prefs.tileMods))) { [weak self] in
            self?.tileFromHotKey()
        }
        HotKeyService.shared.register(id: undoHotKeyID, keyCode: UInt32(d.integer(forKey: Prefs.undoKeyCode)),
                                      modifiers: UInt32(d.integer(forKey: Prefs.undoMods))) { [weak self] in
            self?.undo()
        }
    }

    /// Temporarily disables hotkeys (e.g. while recording a new shortcut).
    func suspendHotKeys() {
        HotKeyService.shared.unregister(id: tileHotKeyID)
        HotKeyService.shared.unregister(id: undoHotKeyID)
    }

    /// First press applies the current mode; pressing again while the layout is untouched cycles.
    private func tileFromHotKey() {
        refreshTrust()
        guard isTrusted, let screen = WindowService.screenUnderMouse() else { return }
        let windows = WindowService.eligibleWindows(on: screen, excludedBundleIDs: Prefs.excludedSet)
        let cycling = isUnchangedSinceLastTiling(windows)
        if cycling { mode = mode.next }
        tile(windows, on: screen, keepSnapshot: cycling)
    }

    // MARK: Actions

    func tileNow() {
        refreshTrust()
        guard isTrusted, let screen = WindowService.screenUnderMouse() else { return }
        let windows = WindowService.eligibleWindows(on: screen, excludedBundleIDs: Prefs.excludedSet)
        tile(windows, on: screen, keepSnapshot: isUnchangedSinceLastTiling(windows))
    }

    func select(_ newMode: TileMode) {
        mode = newMode
        tileNow()
    }

    func undo() {
        refreshTrust()
        guard isTrusted, !snapshot.isEmpty else { return }
        for entry in snapshot.values { WindowService.setFrame(entry.frame, of: entry.element) }
        snapshot.removeAll()
        lastApplied.removeAll()
        canUndo = false
        OverlayController.shared.show("Restored", on: WindowService.screenUnderMouse())
    }

    func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        isTrusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !isTrusted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshTrust() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
    }

    // MARK: Tiling

    private func tile(_ windows: [TileWindow], on screen: NSScreen, keepSnapshot: Bool) {
        guard windows.count >= 2 else {
            OverlayController.shared.show("Nothing to tile", on: screen)
            return
        }
        let d = UserDefaults.standard
        let area = WindowService.axRect(fromCocoa: screen.visibleFrame)
        let rects = TilingLayout.frames(count: windows.count, mode: mode, in: area,
                                        gap: CGFloat(d.double(forKey: Prefs.gap)),
                                        margin: CGFloat(d.double(forKey: Prefs.margin)),
                                        ratio: CGFloat(d.double(forKey: Prefs.ratio)))
        guard rects.count == windows.count else { return }

        if !keepSnapshot || snapshot.isEmpty {
            snapshot = Dictionary(windows.map { (WindowKey(pid: $0.pid, index: $0.index), ($0.element, $0.frame)) },
                                  uniquingKeysWith: { first, _ in first })
        }
        lastApplied = zip(windows, rects).map { window, rect in
            (window.element, WindowService.setFrame(rect, of: window.element) ?? rect)
        }
        canUndo = true

        let overflow = windows.count > TilingLayout.maxWindowsForModes
        let label = overflow ? "Equal Grid — \(windows.count) windows, small cells" : mode.title
        OverlayController.shared.show(label, on: screen)
    }

    /// True when the same windows still sit exactly where the last tiling left them.
    private func isUnchangedSinceLastTiling(_ windows: [TileWindow]) -> Bool {
        guard !lastApplied.isEmpty, windows.count == lastApplied.count else { return false }
        return windows.allSatisfy { window in
            lastApplied.contains { entry in
                CFEqual(entry.element, window.element)
                    && abs(entry.frame.minX - window.frame.minX) < 2 && abs(entry.frame.minY - window.frame.minY) < 2
                    && abs(entry.frame.width - window.frame.width) < 2 && abs(entry.frame.height - window.frame.height) < 2
            }
        }
    }
}
