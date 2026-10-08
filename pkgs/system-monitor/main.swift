import AppKit

// システムの状態を表示する窓 (btm の画面の再現。閲覧のみ)。sketchybar の system item のクリックで開閉する。
// 履歴 (グラフの過去 60 秒) は sketchybar-system-helper が常に貯めていて (config/sketchybar/helper/system.c)、
// この窓は、開いた時にそれを読んで描く。窓を開いている間だけ動き、閉じるとプロセスごと終了する。
// プロセスの表だけは、窓が開いている間に、自分で収集する (Processes.swift)。
//
// 見た目 (フォント、色、背景の透過とぼかし、枠なし) は config/wezterm/wezterm.lua と同じ値にしている (Grid.swift の Theme)。
// 窓は AeroSpace の管理外にして、今いる workspace の上に、画面いっぱい (AeroSpace の gap と同じ 4px の余白) で重ねる。
// 管理外にする方法は pkgs/cavaviz と同じ (Window の accessibilitySubrole)。
// 閉じるのは q か Esc。sketchybar からは pkill で終了させる (items/system.lua)。
//
// 確認用の環境変数:
//   SYSTEM_MONITOR_DUMP=<桁>x<行>  窓を出さずに、その大きさの画面を文字で標準出力へ書いて終わる。
//   SYSTEM_MONITOR_PNG=<パス>      窓を出して、2 秒後に、画面を PNG に書いて終わる。

// 背景のぼかしは、wezterm も使う非公開の CGS API で設定する
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSetWindowBackgroundBlurRadius")
func CGSSetWindowBackgroundBlurRadius(_ connection: Int32, _ windowID: Int, _ radius: Int32) -> Int32

enum Settings {
    // modules/aerospace.nix の gaps (outer) と同じ余白
    static let margin: CGFloat = 4
    /// 履歴の読み出す数。グラフは 60 秒分と、左端の補間のための 1 点があれば足りる
    static let historySamples = 90
}

func makeSnapshot(collector: ProcessCollector, history: History?) -> Snapshot {
    var load = [Double](repeating: 0, count: 3)
    getloadavg(&load, 3)
    var fs = statfs()
    var diskName = ""
    if statfs("/", &fs) == 0 {
        diskName = withUnsafePointer(to: &fs.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }
    return Snapshot(
        samples: history?.recent(limit: Settings.historySamples) ?? [], loadAverage: load,
        processes: collector.harvest(), diskName: diskName)
}

if let spec = ProcessInfo.processInfo.environment["SYSTEM_MONITOR_DUMP"] {
    let size = spec.split(separator: "x").compactMap { Int($0) }
    let collector = ProcessCollector()
    let history = History()
    collector.refresh()
    Thread.sleep(forTimeInterval: 0.5)
    collector.refresh()
    let buffer = CellBuffer(cols: size.first ?? 200, rows: size.dropFirst().first ?? 55)
    Dashboard().render(into: buffer, snapshot: makeSnapshot(collector: collector, history: history))
    print(buffer.dump())
    exit(0)
}

final class Window: NSWindow {
    // 枠なしの窓はキーボード入力を受けないので、受けるようにする
    override var canBecomeKey: Bool { true }
    // 既定の AXStandardWindow だと AeroSpace が窓を管理対象にする。それ以外にして、管理外にする
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .systemFloatingWindow }

    override func keyDown(with event: NSEvent) {
        // q、Esc で終了する
        if event.keyCode == 53 || event.charactersIgnoringModifiers == "q" {
            NSApp.terminate(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class Controller: NSObject, NSApplicationDelegate {
    let collector = ProcessCollector()
    let history = History()
    let dashboard = Dashboard()
    var window: Window!
    var view: GridView!
    var snapshot: Snapshot?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// マウスカーソルのある画面の、メニューバー (sketchybar の場所) と Dock を除いた範囲に、余白を空けて置く
    func targetFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800))
            .insetBy(dx: Settings.margin, dy: Settings.margin)
    }

    func start() {
        let view = GridView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        // 背景 (透過した背景色) は、窓の全面に敷くビューの layer に塗らせる
        view.layer?.backgroundColor = Theme.nsColor(Theme.background).withAlphaComponent(Theme.backgroundOpacity).cgColor
        view.onResize = { [weak self] in self?.layoutAndRender() }
        self.view = view

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
        window.title = "system-monitor"
        // 開く・閉じるときのアニメーションは、ちらつきの元になるので切る
        window.animationBehavior = .none
        // 背景を透過させるには、窓を不透明でなくして、背景色を clear にする
        window.isOpaque = false
        window.backgroundColor = .clear
        // 色空間を sRGB にすると、描画バッファが小さくなり、メモリが減る (既定は広色域)
        window.colorSpace = .sRGB
        window.contentView = view
        self.window = window

        // 最初の更新で、プロセスの一覧を作る (CPU% は、2 回目の更新から値が出る)
        collector.refresh()
        snapshot = makeSnapshot(collector: collector, history: history)

        window.setFrame(targetFrame(), display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        _ = CGSSetWindowBackgroundBlurRadius(CGSMainConnectionID(), window.windowNumber, Theme.blurRadius)
        layoutAndRender()

        if let path = ProcessInfo.processInfo.environment["SYSTEM_MONITOR_PNG"] {
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let view = self?.view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                    exit(0)
                }
            }
        }

        // 2 回目は 0.5 秒後 (CPU% の計算に、最低 0.2 秒の間隔が要る)。その後は 1 秒ごと
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
                Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
            }
        }
    }

    func tick() {
        collector.refresh()
        snapshot = makeSnapshot(collector: collector, history: history)
        render()
    }

    /// 窓の大きさに合わせて、格子の行・桁を決め直して描く
    func layoutAndRender() {
        let size = view.gridSize(for: view.frame.size)
        if size.cols != view.buffer.cols || size.rows != view.buffer.rows {
            view.buffer = CellBuffer(cols: size.cols, rows: size.rows)
        }
        view.layoutGrid()
        render()
    }

    func render() {
        guard let snapshot else { return }
        dashboard.render(into: view.buffer, snapshot: snapshot)
        view.needsDisplay = true
    }
}

@MainActor
func makeMenu() -> NSMenu {
    let main = NSMenu()
    let appItem = NSMenuItem()
    main.addItem(appItem)
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    return main
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    // Dock にアイコンを出さない (AeroSpace の管理外なので、.regular にする必要はない)
    app.setActivationPolicy(.accessory)
    app.mainMenu = makeMenu()
    let controller = Controller()
    app.delegate = controller
    controller.start()
    app.run()
}
