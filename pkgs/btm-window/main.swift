import AppKit
import SwiftTerm

// btm を SwiftTerm の端末ビュー (CoreGraphics 描画) に載せて表示する窓。
// sketchybar の system item のクリックで開閉する。btm が終了する (q など) と、窓 (アプリ) も終了する。
// 見た目 (フォント、色、背景の透過とぼかし、枠なし) は config/wezterm/wezterm.lua と同じ値にしている。
//
// 窓は AeroSpace の管理外にして、今いる workspace の上に、画面いっぱい (AeroSpace の gap と同じ 4px の余白) で重ねる。
// workspace を切り替えないので、開閉でちらつかない。管理外にする方法は pkgs/cavaviz と同じ (Window の accessibilitySubrole)。
// AeroSpace の管理下だと、窓が閉じるたびに、AeroSpace がその窓の workspace へフォーカスを寄せ直し、
// 元の workspace に戻した後でも、workspace が何度も切り替わった。
//
// 開閉は SIGUSR1 で受け付ける (config/sketchybar/items/system.lua): 窓が最前面なら閉じ、そうでなければ前面に出す。

// 起動直後の SIGUSR1 で、既定の動作 (プロセスの終了) にならないよう、最初に無視する。受け付けるのは下の DispatchSource
signal(SIGUSR1, SIG_IGN)

// 背景のぼかし (wezterm の macos_window_background_blur) は、wezterm も使う非公開の CGS API で設定する
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSetWindowBackgroundBlurRadius")
func CGSSetWindowBackgroundBlurRadius(_ connection: Int32, _ windowID: Int, _ radius: Int32) -> Int32

enum Style {
    static let title = "btm-monitor"
    // wezterm.lua: config.font = "Moralerspace Neon HW" (PostScript 名で指定する)
    static let fontName = "MoralerspaceNeonHW-Regular"
    static let fontSize: CGFloat = 14
    // wezterm.lua: window_background_opacity、macos_window_background_blur
    static let backgroundOpacity: CGFloat = 0.7
    static let blurRadius: Int32 = 20
    // modules/aerospace.nix の gaps (outer) と同じ余白
    static let margin: CGFloat = 4
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

final class Window: NSWindow {
    // 枠なしの窓はキーボード入力を受けないので、受けるようにする
    override var canBecomeKey: Bool { true }
    // 既定の AXStandardWindow だと AeroSpace が窓を管理対象にする。それ以外にして、管理外にする
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .systemFloatingWindow }
}

@MainActor
final class Host: NSObject, NSApplicationDelegate, LocalProcessTerminalViewDelegate {
    var window: NSWindow?
    var terminal: LocalProcessTerminalView?
    var signalSource: DispatchSourceSignal?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    // タイトルは btm からの変更を無視して、固定のままにする
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        NSApp.terminate(nil)
    }
    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        FileHandle.standardError.write(Data("btm-window: btm を起動できません: \(error)\n".utf8))
        exit(1)
    }

    // マウスカーソルのある画面の、メニューバー (sketchybar の場所) と Dock を除いた範囲に、余白を空けて置く
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

    // 最前面で見えているなら閉じ、そうでなければ (他のアプリの後ろにあるなど) 前に出す
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

MainActor.assumeIsolated {
    let app = NSApplication.shared
    // Dock にアイコンを出さない (AeroSpace の管理外なので、.regular にする必要はない)
    app.setActivationPolicy(.accessory)
    app.mainMenu = makeMenu()
    let host = Host()
    app.delegate = host

    let window = Window(
        contentRect: .zero,
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false)
    // wezterm.lua: window_decorations = "RESIZE" (タイトルバーを隠し、リサイズ枠だけ残す)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
        window.standardWindowButton(button)?.isHidden = true
    }
    window.title = Style.title
    // 開く・閉じるときのアニメーションは、ちらつきの元になるので切る
    window.animationBehavior = .none
    // 背景を透過させるには、窓を不透明でなくして、背景色を clear にする
    window.isOpaque = false
    window.backgroundColor = .clear
    // 色空間を sRGB にすると、描画バッファが小さくなり、メモリが約 60MB 減る (既定は広色域)
    window.colorSpace = .sRGB

    let terminal = LocalProcessTerminalView(frame: .zero)
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

    host.window = window
    host.terminal = terminal

    // sketchybar のクリックは、起動中のこのアプリへ SIGUSR1 を送る
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
