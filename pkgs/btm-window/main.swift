import AppKit
import SwiftTerm

// btm を SwiftTerm の端末ビューに載せて表示する窓。描画は CoreGraphics。
// sketchybar の system item のクリックで開閉する。btm が終了する、たとえば q を押すと、窓、つまりアプリも終了する。
// フォント、色、背景の透過とぼかし、枠なしは、config/wezterm/wezterm.lua と同じ値にしている。
//
// 窓は AeroSpace の管理外にして、今いる workspace の上に、画面いっぱいで重ねる。余白は AeroSpace の gap と同じ 4px。
// workspace を切り替えないので、開閉でちらつかない。管理外にする方法は pkgs/cavaviz と同じで、Window の accessibilitySubrole。
// AeroSpace の管理下だと、窓が閉じるたびに、AeroSpace がその窓の workspace へフォーカスを寄せ直し、
// 元の workspace に戻した後でも、workspace が何度も切り替わった。
//
// 開閉は SIGUSR1 で受け付ける。config/sketchybar/items/system.lua が送る。

// 起動直後の SIGUSR1 で、既定の動作、つまりプロセスの終了にならないよう、最初に無視する。受け付けるのは下の DispatchSource。
signal(SIGUSR1, SIG_IGN)

// 背景のぼかしは、wezterm の macos_window_background_blur と同じで、wezterm も使う非公開の CGS API で設定する。
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSetWindowBackgroundBlurRadius")
func CGSSetWindowBackgroundBlurRadius(_ connection: Int32, _ windowID: Int, _ radius: Int32) -> Int32

// fontName は wezterm.lua の config.font の "Moralerspace Neon HW" で、PostScript 名で指定する。
// backgroundOpacity と blurRadius は wezterm.lua の window_background_opacity と macos_window_background_blur。
// margin は modules/aerospace.nix の gaps の outer と同じ余白。
// verticalBias は行のグリッドを下へずらす量で、単位は pt。btm の最上行は文字、最下行は罫線なので、見かけの上下の余白を揃えるための値。
// 色は wezterm.lua の config.colors で、Iceberg Dark。
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

// ビルド時に bottom のパスへ置き換える。pkgs/btm-window/default.nix が行う。置き換わっていなければ PATH から探す。
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

// 枠なしの窓はキーボード入力を受けないので、canBecomeKey で受けるようにする。
// 既定の AXStandardWindow だと AeroSpace が窓を管理対象にする。accessibilitySubrole をそれ以外にして、管理外にする。
final class Window: NSWindow {
    override var canBecomeKey: Bool { true }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .systemFloatingWindow }
}

// 窓の大きさは行・桁の整数倍とは限らず、端末ビューをそのまま広げると、行・桁に満たない余りが、下と右にだけ空く。
// 上下左右に等しく分けて、中央に置く。
@MainActor
final class Container: NSView {
    weak var terminal: LocalProcessTerminalView?

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        centerTerminal()
    }

    // 余りの半分を 0.5pt、Retina の 1px 単位で切り捨てて、余白にする。切り捨てるので、余白を除いた大きさは
    // 使う大きさ以上、1pt 未満しか超えず、行・桁数は変わらない。
    // btm は、最上行に文字がセルの上端近くから描かれ、最下行に罫線がセルの中央に描かれるので、
    // 上下を等分しても、内容の下端の余白のほうが大きく見える。見かけを揃えるために、グリッドを下へずらす。
    // 余白の合計は変えない。ずらせる量は、下の余白の範囲まで。
    // frame の y は、下の余白。AppKit の原点は左下。
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

// Dock にアイコンを出さない。AeroSpace の管理外なので、.regular にする必要はない。
// wezterm.lua の window_decorations = "RESIZE" と同じで、タイトルバーを隠し、リサイズ枠だけ残す。
// 開く・閉じるときのアニメーションは、ちらつきの元になるので切る。
// 背景を透過させるには、窓を不透明でなくして、背景色を clear にする。
// 色空間を sRGB にすると、描画バッファが小さくなり、メモリが約 60MB 減る。既定は広色域。
// 背景の色、つまり透過した背景色は、端末ビューではなく、下に敷くコンテナの layer に塗らせる。
// 端末ビューの layer に塗らせると、端末ビューの下端の、行に満たない余りの帯、つまり cell の高さ未満だけ、
// 背景が二重に重なって、他より濃く見える。実測で、アルファ 0.7 が 0.91 相当になっていた。
// そのため、端末ビューの backgroundOpacity は 0 にして、既定の背景は塗らず、コンテナの色を見せる。
// sketchybar のクリックは、起動中のこのアプリへ SIGUSR1 を送る。
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
