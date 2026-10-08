import AppKit
import SwiftTerm

// btm を SwiftTerm の端末ビュー (CoreGraphics 描画) に載せて表示する窓。
// sketchybar の system item のクリックで開き、btm が終了すると窓 (アプリ) も終了する。
// 見た目 (フォント、色、背景の透過とぼかし、枠なし) は config/wezterm/wezterm.lua と同じ値にしている。
// 窓の大きさは決めない。AeroSpace がタイル管理して、gap を含めた大きさにする。

// 背景のぼかし (wezterm の macos_window_background_blur) は、wezterm も使う非公開の CGS API で設定する
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSetWindowBackgroundBlurRadius")
func CGSSetWindowBackgroundBlurRadius(_ connection: Int32, _ windowID: Int, _ radius: Int32) -> Int32

enum Style {
    // AeroSpace が、この窓を workspace A へ移すために見る固定のタイトル (modules/aerospace.nix)
    static let title = "btm-monitor"
    // wezterm.lua: config.font = "Moralerspace Neon HW" (PostScript 名で指定する)
    static let fontName = "MoralerspaceNeonHW-Regular"
    static let fontSize: CGFloat = 14
    // wezterm.lua: window_background_opacity、macos_window_background_blur
    static let backgroundOpacity: CGFloat = 0.7
    static let blurRadius: Int32 = 20
    // wezterm.lua: config.colors (Iceberg Dark)
    static let foreground = "#c6c8d1"
    static let background = "#161821"
    static let selection = "#1e2132"
    static let ansi = ["#1e2132", "#e27878", "#b4be82", "#e2a478", "#84a0c6", "#a093c7", "#89b8c2", "#c6c8d1"]
    static let brights = ["#6b7089", "#e98989", "#c0ca8e", "#e9b189", "#91afd7", "#ada0d3", "#95c4ce", "#d2d4de"]
}

// ビルド時に bottom のパスへ置き換える (pkgs/btm-window/default.nix)。置き換わっていなければ PATH から探す
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

// 枠なしの窓はキーボード入力を受けないので、受けるようにする
final class Window: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class Host: NSObject, NSApplicationDelegate, LocalProcessTerminalViewDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    // タイトルは AeroSpace の判定に使う固定値のままにする (btm からの変更は無視)
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        NSApp.terminate(nil)
    }
    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        FileHandle.standardError.write(Data("btm-window: btm を起動できません: \(error)\n".utf8))
        exit(1)
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

MainActor.assumeIsolated {
    let app = NSApplication.shared
    // .regular にしないと、AeroSpace が窓をタイル管理せず floating にする (Dock にアイコンが出る。wezterm と同じ)
    app.setActivationPolicy(.regular)
    app.mainMenu = makeMenu()
    let host = Host()
    app.delegate = host

    let window = Window(
        contentRect: NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false)
    // wezterm.lua: window_decorations = "RESIZE" (タイトルバーを隠し、リサイズ枠だけ残す)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
        window.standardWindowButton(button)?.isHidden = true
    }
    window.title = Style.title
    // 背景を透過させるには、窓を不透明でなくして、背景色を clear にする
    window.isOpaque = false
    window.backgroundColor = .clear
    // 色空間を sRGB にすると、描画バッファが小さくなり、メモリが約 60MB 減る (既定は広色域)
    window.colorSpace = .sRGB

    let terminal = LocalProcessTerminalView(frame: window.contentView?.bounds ?? .zero)
    terminal.autoresizingMask = [.width, .height]
    terminal.processDelegate = host
    window.contentView = terminal
    terminal.font = NSFont(name: Style.fontName, size: Style.fontSize)
        ?? NSFont.monospacedSystemFont(ofSize: Style.fontSize, weight: .regular)
    terminal.nativeForegroundColor = nsColor(Style.foreground)
    terminal.nativeBackgroundColor = nsColor(Style.background)
    terminal.backgroundOpacity = Style.backgroundOpacity
    terminal.caretColor = nsColor(Style.foreground)
    terminal.caretTextColor = nsColor(Style.background)
    terminal.selectedTextBackgroundColor = nsColor(Style.selection)
    terminal.installColors((Style.ansi + Style.brights).map(termColor))
    terminal.setCursorStyle(.steadyBar)

    window.makeKeyAndOrderFront(nil)
    _ = CGSSetWindowBackgroundBlurRadius(CGSMainConnectionID(), window.windowNumber, Style.blurRadius)
    app.activate(ignoringOtherApps: true)

    var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
    if btmPath.hasPrefix("@") {
        environment.append("PATH=" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"))
        terminal.startProcess(executable: "/usr/bin/env", args: ["btm"], environment: environment)
    } else {
        terminal.startProcess(executable: btmPath, args: [], environment: environment)
    }
    app.run()
}
