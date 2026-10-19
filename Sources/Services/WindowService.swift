import AppKit
import ApplicationServices

/// A tileable window discovered through the Accessibility API.
struct TileWindow {
    let element: AXUIElement
    let pid: pid_t
    let index: Int
    var frame: CGRect
}

/// Identifies a window for undo: owning process plus its index in that app's AXWindows list.
struct WindowKey: Hashable {
    let pid: pid_t
    let index: Int
}

/// Enumerates eligible windows and reads/writes their frames via AXUIElement.
enum WindowService {
    /// Seconds to wait for a slow app to answer an Accessibility call.
    static let messagingTimeout: Float = 0.3

    /// The screen currently containing the mouse pointer.
    static func screenUnderMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
    }

    /// Converts a Cocoa (bottom-left origin) rect to Accessibility (top-left origin) space.
    static func axRect(fromCocoa r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? r.maxY
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Standard, non-minimized, non-fullscreen windows whose centre lies on `screen`,
    /// sorted by their current top-left position for stable assignment.
    static func eligibleWindows(on screen: NSScreen, excludedBundleIDs: Set<String>) -> [TileWindow] {
        let screenRect = axRect(fromCocoa: screen.frame)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && !$0.isTerminated
                && $0.processIdentifier != ownPID
                && !excludedBundleIDs.contains($0.bundleIdentifier ?? "")
        }

        var result: [TileWindow] = []
        for app in apps {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
            guard let windows = attribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for (index, window) in windows.enumerated() {
                AXUIElementSetMessagingTimeout(window, messagingTimeout)
                guard attribute(window, kAXRoleAttribute) as? String == kAXWindowRole as String,
                      attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole as String,
                      (attribute(window, kAXMinimizedAttribute) as? Bool) != true,
                      (attribute(window, "AXFullScreen") as? Bool) != true,
                      let frame = frame(of: window),
                      screenRect.contains(CGPoint(x: frame.midX, y: frame.midY))
                else { continue }
                result.append(TileWindow(element: window, pid: pid, index: index, frame: frame))
            }
        }
        return result.sorted {
            $0.frame.minY != $1.frame.minY ? $0.frame.minY < $1.frame.minY : $0.frame.minX < $1.frame.minX
        }
    }

    /// Reads a window's frame in Accessibility coordinates.
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let posValue = attribute(window, kAXPositionAttribute),
              let sizeValue = attribute(window, kAXSizeAttribute),
              CFGetTypeID(posValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    /// Applies a frame as position → size → position (the second move fixes
    /// windows that were clamped while still at their old size), then reads back
    /// the real frame. Windows with a large minimum size simply keep it and overlap.
    @discardableResult
    static func setFrame(_ rect: CGRect, of window: AXUIElement) -> CGRect? {
        var origin = rect.origin
        var size = rect.size
        if let pos = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
        }
        if let sz = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sz)
        }
        if let pos = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
        }
        return frame(of: window)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
