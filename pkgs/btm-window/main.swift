import AppKit
import SwiftTerm

// A window that shows btm in a SwiftTerm terminal view. Drawing is CoreGraphics.
// Opened and closed by clicking sketchybar's system item. When btm exits, e.g. on pressing q, the window, i.e. the app, also exits.
// Font, color, background transparency and blur, and borderless use the same values as config/wezterm/wezterm.lua.
//
// The window is outside AeroSpace's management and overlays the current workspace at full screen. The margin is 4px, the same as AeroSpace's gap.
// The workspace is not switched, so there is no flicker on open/close. The way to put it outside management is the same as pkgs/cavaviz: the Window's accessibilitySubrole.
// If under AeroSpace's management, each time the window closes AeroSpace re-focuses the workspace of that window,
// and the workspace switched many times even after returning to the original workspace.
//
// Open/close is received via SIGUSR1. Sent by config/sketchybar/items/system.lua.

// Ignore it first so that a SIGUSR1 right after launch does not trigger the default action, i.e. terminating the process. It is accepted by the DispatchSource below.
signal(SIGUSR1, SIG_IGN)

// The background blur is the same as wezterm's macos_window_background_blur, set with a private CGS API that wezterm also uses.
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSetWindowBackgroundBlurRadius")
func CGSSetWindowBackgroundBlurRadius(_ connection: Int32, _ windowID: Int, _ radius: Int32) -> Int32

// fontName is config.font "Moralerspace Neon HW" in wezterm.lua, specified by PostScript name.
// backgroundOpacity and blurRadius are window_background_opacity and macos_window_background_blur in wezterm.lua.
// margin is the same margin as the outer of gaps in modules/aerospace.nix.
// verticalBias is the amount to shift the row grid downward, in pt. btm's top row is text and bottom row is a rule line, so this is a value to even out the apparent top/bottom margins.
// Colors are config.colors in wezterm.lua, Iceberg Dark.
enum Style {
    static let title = "btm-monitor"
    static let fontName = "MoralerspaceNeonHW-Regular"
    static let fontSize: CGFloat = 14
    static let backgroundOpacity: CGFloat = 0.7
    static let blurRadius: Int32 = 20
    static let margin: CGFloat = 4
    static let verticalBias: CGFloat = 0
    static let foreground = "#c6c8d1"
    static let background = "#161821"
    static let selection = "#1e2132"
    static let ansi = ["#1e2132", "#e27878", "#b4be82", "#e2a478", "#84a0c6", "#a093c7", "#89b8c2", "#c6c8d1"]
    static let brights = ["#6b7089", "#e98989", "#c0ca8e", "#e9b189", "#91afd7", "#ada0d3", "#95c4ce", "#d2d4de"]
}

// Replaced with bottom's path at build time. pkgs/btm-window/default.nix does this. If not replaced, look it up from PATH.
let btmPath = "@btm@"

func rgb(_ hex: String) -> (UInt16, UInt16, UInt16) {
    let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
    return (UInt16((v >> 16) & 255), UInt16((v >> 8) & 255), UInt16(v & 255))
}
func termColor(_ hex: String) -> Color {
    let c = rgb(hex)
    return Color(red8: c.0, green8: c.1, blue8: c.2)
}
func nsColor(_ hex: String) -> NSColor {
    let c = rgb(hex)
    return NSColor(srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
}

// A borderless window does not receive keyboard input, so make it receive it with canBecomeKey.
// With the default AXStandardWindow, AeroSpace makes the window a managed target. Set accessibilitySubrole to anything else to put it outside management.
final class Window: NSWindow {
    override var canBecomeKey: Bool { true }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .systemFloatingWindow }
}

// The window size is not necessarily an integer multiple of rows/columns, and if the terminal view were simply stretched, the remainder less than a row/column would be left only at the bottom and right.
// Divide it equally top/bottom/left/right and place it at the center.
@MainActor
final class Container: NSView {
    weak var terminal: LocalProcessTerminalView?

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        centerTerminal()
    }

    // Half of the remainder is truncated to 0.5pt, i.e. Retina 1px units, to make the margin. Because it is truncated, the size excluding the margin
    // exceeds the size used by less than 1pt, and the row/column count does not change.
    // In btm, the top row's text is drawn from near the cell's top edge and the bottom row's rule line is drawn at the cell's center,
    // so even if split equally top/bottom, the margin below the content looks larger. To even out the appearance, shift the grid downward.
    // The total margin is unchanged. The amount that can be shifted is up to the bottom margin.
    // The frame's y is the bottom margin. AppKit's origin is bottom-left.
    func centerTerminal() {
        guard let terminal, bounds.width >= 1, bounds.height >= 1 else { return }
        terminal.frame = bounds
        let used = terminal.getOptimalFrameSize()
        let dx = max(0, floor((bounds.width - used.width) / 2 * 2) / 2)
        let dy = max(0, floor((bounds.height - used.height) / 2 * 2) / 2)
        let shift = min(Style.verticalBias, dy)
        terminal.frame = NSRect(
            x: dx, y: dy - shift,
            width: bounds.width - 2 * dx, height: bounds.height - 2 * dy)
    }
}

@MainActor
final class Host: NSObject, NSApplicationDelegate, LocalProcessTerminalViewDelegate {
    var window: NSWindow?
    var terminal: LocalProcessTerminalView?
    var signalSource: DispatchSourceSignal?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    // Ignore changes to the title from btm and keep it fixed
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        NSApp.terminate(nil)
    }
    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        FileHandle.standardError.write(Data("btm-window: btm を起動できません: \(error)\n".utf8))
        exit(1)
    }

    func targetFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)).insetBy(dx: Style.margin, dy: Style.margin)
    }

    func show() {
        guard let window else { return }
        window.setFrame(targetFrame(), display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggle() {
        if NSApp.isActive, window?.isKeyWindow == true {
            terminal?.terminate()
            NSApp.terminate(nil)
        } else {
            show()
        }
    }
}

@MainActor
func makeMenu() -> NSMenu {
    let main = NSMenu()
    let appItem = NSMenuItem(); main.addItem(appItem)
    let appMenu = NSMenu(); appItem.submenu = appMenu
    appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let editItem = NSMenuItem(); main.addItem(editItem)
    let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    return main
}

// Do not show an icon in the Dock. It is outside AeroSpace's management, so there is no need for .regular.
// Same as window_decorations = "RESIZE" in wezterm.lua: hide the title bar and keep only the resize border.
// Open/close animations are turned off because they cause flicker.
// To make the background transparent, make the window non-opaque and set the background color to clear.
// Setting the color space to sRGB shrinks the drawing buffer and reduces memory by about 60MB. The default is wide gamut.
// The background color, i.e. the transparent background color, is painted not by the terminal view but by the layer of the container laid beneath it.
// If the terminal view's layer paints it, only the strip at the bottom of the terminal view that is a remainder less than a row, i.e. less than the cell height,
// gets the background doubled up and looks darker than elsewhere. Measured, alpha 0.7 was equivalent to 0.91.
// So set the terminal view's backgroundOpacity to 0, do not paint the default background, and show the container's color.
// sketchybar's click sends SIGUSR1 to this running app.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.mainMenu = makeMenu()
    let host = Host()
    app.delegate = host

    let window = Window(
        contentRect: .zero,
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
        window.standardWindowButton(button)?.isHidden = true
    }
    window.title = Style.title
    window.animationBehavior = .none
    window.isOpaque = false
    window.backgroundColor = .clear
    window.colorSpace = .sRGB

    let container = Container(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    container.wantsLayer = true
    container.layer?.backgroundColor = nsColor(Style.background).withAlphaComponent(Style.backgroundOpacity).cgColor

    let terminal = LocalProcessTerminalView(frame: container.bounds)
    terminal.processDelegate = host
    container.terminal = terminal
    container.addSubview(terminal)
    window.contentView = container
    window.makeFirstResponder(terminal)
    terminal.font = NSFont(name: Style.fontName, size: Style.fontSize)
        ?? NSFont.monospacedSystemFont(ofSize: Style.fontSize, weight: .regular)
    terminal.nativeForegroundColor = nsColor(Style.foreground)
    terminal.nativeBackgroundColor = nsColor(Style.background)
    terminal.backgroundOpacity = 0
    terminal.caretColor = nsColor(Style.foreground)
    terminal.caretTextColor = nsColor(Style.background)
    terminal.selectedTextBackgroundColor = nsColor(Style.selection)
    terminal.installColors((Style.ansi + Style.brights).map(termColor))
    terminal.setCursorStyle(.steadyBar)

    host.window = window
    host.terminal = terminal

    let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
    source.setEventHandler { MainActor.assumeIsolated { host.toggle() } }
    source.resume()
    host.signalSource = source

    host.show()
    _ = CGSSetWindowBackgroundBlurRadius(CGSMainConnectionID(), window.windowNumber, Style.blurRadius)

    var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
    if btmPath.hasPrefix("@") {
        environment.append("PATH=" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"))
        terminal.startProcess(executable: "/usr/bin/env", args: ["btm"], environment: environment)
    } else {
        terminal.startProcess(executable: btmPath, args: [], environment: environment)
    }
    app.run()
}
