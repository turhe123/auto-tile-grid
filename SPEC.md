# AutoTileGrid — specification

**Tagline:** One hotkey tiles all visible windows on a screen into a tidy grid, with layout cycling.

**Category:** Window Management

**Inspired by (paid):** Mosaic ($14.99 one-time)

**Frameworks:** SwiftUI, AppKit, ApplicationServices, CoreGraphics, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

(1) What the paid app does. Mosaic from Light Pillar is a window manager listed by MacPaw at 14.99 dollars and on Setapp, built around arranging many windows quickly. Automatic tiling is the feature that tiling fans on forums keep asking for in a lightweight form without learning a full tiling window manager, and it appears across window manager comparison guides. Our version offers instant auto-tiling of the current screen's windows with a few layout modes.

(2) Feature set. A global hotkey tiles all standard, non-minimized windows on the screen under the mouse. Layout modes are Equal Grid, Main Left with a stack on the right, Main Top with a row below, and Columns. Pressing the hotkey again cycles to the next mode. A second hotkey restores the previous frames of all windows touched by the last tiling. The user can exclude apps from tiling, and can set the inner gap and outer margin in points. Main-window ratio is configurable for the two main modes.

(3) UI spec. MenuBarExtra with a grid icon. Menu items: Tile Now, a mode submenu with checkmarks, Undo Last Tiling, Settings and Quit. The Settings window has fields for tile hotkey, undo hotkey, default mode picker, inner gap stepper, outer margin stepper, main ratio slider, excluded apps list with add button, and launch at login toggle. A brief overlay label at the screen center names the mode just applied, fading after one second. Empty state: if there are fewer than two eligible windows, show the label Nothing to tile and do nothing. Without Accessibility permission, the menu shows a Grant Access row and the hotkeys do nothing.

(4) Technical approach. Determine eligible windows by listing running regular applications from NSWorkspace and, for each, reading the AXWindows attribute using AXUIElement, filtering by role window, subrole standard window, not minimized and not full screen, and whose frame center lies in the target screen. Tiling math is a pure function from count, mode, visible frame, gap and margin to an array of rectangles, which keeps the code small and testable. Sorting windows by their current top-left position gives stable, predictable assignment so that windows do not jump unpredictably between runs. Apply frames by setting position, size, then position again. Use Carbon hotkeys for global shortcuts. Store previous frames in memory keyed by process identifier and window index for undo. Persist preferences with AppStorage. Request Accessibility trust with AXIsProcessTrustedWithOptions. Launch at login with SMAppService.

(5) Edge cases. Windows with minimum sizes larger than their cell will not shrink, so read back the size afterward and leave overlap rather than loop forever. Dialogs and sheets are excluded by subrole. Apps that are slow to answer Accessibility calls need a messaging timeout, set with AXUIElementSetMessagingTimeout to a few hundred milliseconds. Skip windows on other Spaces since they are not returned. For very large window counts above about sixteen, fall back to the grid with smaller cells and warn in the label. Always clamp rectangles to whole points to avoid blurry edges.
