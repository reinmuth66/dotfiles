import AppKit

// 文字セルの格子 (端末の画面に相当) と、それを窓に描くビュー。
// btm の表示を再現するために、btm (ratatui) と同じ「文字セルに文字と色を置く」作りにしている (Widgets.swift)。
// 罫線 (─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼) と点字 (U+2800〜) は、フォントのグリフではなく、セルの寸法に合わせて自前で描く
// (隣のセルと継ぎ目なくつながり、フォントの有無にも左右されない)。

/// 色は 16 色のパレットの番号 (0〜7 が ANSI、8〜15 が明るい色)。-1 は「なし」
struct CellStyle: Equatable {
    var fg: Int8 = 7
    var bg: Int8 = -1
    var bold = false

    init(fg: Int8 = 7, bg: Int8 = -1, bold: Bool = false) {
        self.fg = fg
        self.bg = bg
        self.bold = bold
    }
}

struct Cell {
    /// Unicode のスカラー値。0 は、幅 2 の文字の右半分 (描かない)
    var scalar: UInt32 = 32
    var style = CellStyle()
}

struct Rect {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var right: Int { x + width }
    var bottom: Int { y + height }
    var isEmpty: Bool { width <= 0 || height <= 0 }

    func inset(_ n: Int) -> Rect {
        Rect(x: x + n, y: y + n, width: max(0, width - 2 * n), height: max(0, height - 2 * n))
    }
}

/// 文字の表示幅 (セルの数)。東アジアの全角・絵文字は 2、結合文字は 0
func cellWidth(_ scalar: Unicode.Scalar) -> Int {
    let v = scalar.value
    if v < 0x300 { return 1 }
    switch v {
    case 0x0300...0x036F, 0x200B...0x200F, 0xFE00...0xFE0F: return 0
    case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
        0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60,
        0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD:
        return 2
    default: return 1
    }
}

func textWidth(_ s: String) -> Int {
    s.unicodeScalars.reduce(0) { $0 + cellWidth($1) }
}

/// 幅 width に収まるように切り詰める。収まらないときは、末尾を「…」にする (btm の truncate_to_text と同じ)
func truncate(_ s: String, to width: Int) -> String {
    if textWidth(s) <= width { return s }
    if width <= 0 { return "" }
    var out = ""
    var used = 0
    for u in s.unicodeScalars {
        let w = cellWidth(u)
        if used + w > width - 1 { break }
        out.unicodeScalars.append(u)
        used += w
    }
    return out + "…"
}

final class CellBuffer {
    let cols: Int
    let rows: Int
    var cells: [Cell]

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        cells = Array(repeating: Cell(), count: cols * rows)
    }

    func clear() {
        for i in cells.indices { cells[i] = Cell() }
    }

    func put(_ x: Int, _ y: Int, _ scalar: UInt32, _ style: CellStyle) {
        guard x >= 0, y >= 0, x < cols, y < rows else { return }
        cells[y * cols + x] = Cell(scalar: scalar, style: style)
    }

    func put(_ x: Int, _ y: Int, _ ch: Character, _ style: CellStyle) {
        put(x, y, ch.unicodeScalars.first!.value, style)
    }

    /// x, y から文字列を置く。maxWidth を超える分は置かない。使ったセルの数を返す
    @discardableResult
    func text(_ x: Int, _ y: Int, _ s: String, _ style: CellStyle, maxWidth: Int = Int.max) -> Int {
        var used = 0
        for u in s.unicodeScalars {
            let w = cellWidth(u)
            if w == 0 { continue }
            if used + w > maxWidth { break }
            put(x + used, y, u.value, style)
            if w == 2 { put(x + used + 1, y, 0, style) }
            used += w
        }
        return used
    }

    /// 範囲を空白にして、背景を塗る
    func fill(_ r: Rect, _ style: CellStyle) {
        for yy in r.y..<max(r.y, r.bottom) {
            for xx in r.x..<max(r.x, r.right) { put(xx, yy, 32, style) }
        }
    }

    /// 範囲の背景色だけを変える (文字は残す)。選択行の強調に使う
    func restyle(_ r: Rect, _ style: CellStyle) {
        for yy in max(0, r.y)..<min(rows, max(r.y, r.bottom)) {
            for xx in max(0, r.x)..<min(cols, max(r.x, r.right)) {
                cells[yy * cols + xx].style = style
            }
        }
    }

    /// 文字を並べた、確認用の文字列 (SYSTEM_MONITOR_DUMP)
    func dump() -> String {
        var lines: [String] = []
        for y in 0..<rows {
            var line = ""
            for x in 0..<cols {
                let s = cells[y * cols + x].scalar
                if s == 0 { continue }
                line.unicodeScalars.append(Unicode.Scalar(s) ?? " ")
            }
            while line.hasSuffix(" ") { line.removeLast() }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

// 配色と書体は、config/wezterm/wezterm.lua (Iceberg Dark) と同じ
enum Theme {
    // wezterm.lua: config.font = "Moralerspace Neon HW" (PostScript 名で指定する)
    static let fontName = "MoralerspaceNeonHW-Regular"
    static let boldFontName = "MoralerspaceNeonHW-Bold"
    static let fontSize: CGFloat = 14
    // wezterm.lua: window_background_opacity、macos_window_background_blur
    static let backgroundOpacity: CGFloat = 0.7
    static let blurRadius: Int32 = 20
    // wezterm.lua: config.colors
    static let background = "#161821"
    static let ansi = ["#1e2132", "#e27878", "#b4be82", "#e2a478", "#84a0c6", "#a093c7", "#89b8c2", "#c6c8d1"]
    static let brights = ["#6b7089", "#e98989", "#c0ca8e", "#e9b189", "#91afd7", "#ada0d3", "#95c4ce", "#d2d4de"]

    static func nsColor(_ hex: String) -> NSColor {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return NSColor(
            srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
            blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    static let palette: [NSColor] = (ansi + brights).map(nsColor)
}

/// 罫線の各方向の線の有無 (細線のみ)
private func boxSegments(_ v: UInt32) -> (left: Bool, right: Bool, up: Bool, down: Bool)? {
    switch v {
    case 0x2500: return (true, true, false, false)  // ─
    case 0x2502: return (false, false, true, true)  // │
    case 0x250C: return (false, true, false, true)  // ┌
    case 0x2510: return (true, false, false, true)  // ┐
    case 0x2514: return (false, true, true, false)  // └
    case 0x2518: return (true, false, true, false)  // ┘
    case 0x251C: return (false, true, true, true)  // ├
    case 0x2524: return (true, false, true, true)  // ┤
    case 0x252C: return (true, true, false, true)  // ┬
    case 0x2534: return (true, true, true, false)  // ┴
    case 0x253C: return (true, true, true, true)  // ┼
    default: return nil
    }
}

/// 点字 (U+2800 + ビット) の 8 つの点の位置 (列, 行)。ビットは Unicode の点 1〜8
private let brailleDots: [(bit: UInt32, col: Int, row: Int)] = [
    (0x01, 0, 0), (0x02, 0, 1), (0x04, 0, 2), (0x40, 0, 3),
    (0x08, 1, 0), (0x10, 1, 1), (0x20, 1, 2), (0x80, 1, 3),
]

@MainActor
final class GridView: NSView {
    var buffer: CellBuffer
    let font: NSFont
    let boldFont: NSFont
    let cellW: CGFloat
    let cellH: CGFloat
    /// セルの下端から、ベースラインまでの距離
    let baseline: CGFloat
    /// 格子の左下の位置 (端末ビューの中央寄せ。窓の大きさは、行・桁の整数倍とは限らない)
    private(set) var originX: CGFloat = 0
    private(set) var originY: CGFloat = 0
    private var lineCache: [UInt64: CTLine] = [:]

    /// 大きさが変わったときの呼び出し (行・桁を決め直して描く)
    var onResize: (() -> Void)?

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }

    override init(frame: NSRect) {
        font = NSFont(name: Theme.fontName, size: Theme.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: Theme.fontSize, weight: .regular)
        boldFont = NSFont(name: Theme.boldFontName, size: Theme.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: Theme.fontSize, weight: .bold)
        let ctFont = font as CTFont
        let ascent = CTFontGetAscent(ctFont)
        let descent = CTFontGetDescent(ctFont)
        let leading = CTFontGetLeading(ctFont)
        var glyph = CTFontGetGlyphWithName(ctFont, "M" as CFString)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)
        cellW = advance.width > 0 ? advance.width : 8
        cellH = ceil(ascent + descent + leading)
        baseline = descent + (cellH - (ascent + descent)) / 2
        buffer = CellBuffer(cols: 1, rows: 1)
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 窓の大きさに収まる行・桁の数
    func gridSize(for size: NSSize) -> (cols: Int, rows: Int) {
        (max(1, Int(floor(size.width / cellW))), max(1, Int(floor(size.height / cellH))))
    }

    /// 余りの半分を 0.5pt (Retina の 1px) 単位で切り捨てて、上下左右の余白にする
    func layoutGrid() {
        let size = frame.size
        originX = max(0, floor((size.width - CGFloat(buffer.cols) * cellW) / 2 * 2) / 2)
        let spareY = size.height - CGFloat(buffer.rows) * cellH
        originY = max(0, floor(spareY / 2 * 2) / 2)
    }

    private func line(for scalar: UInt32, style: CellStyle) -> CTLine? {
        guard let u = Unicode.Scalar(scalar) else { return nil }
        let key = UInt64(scalar) << 16 | UInt64(UInt8(bitPattern: style.fg)) << 1 | (style.bold ? 1 : 0)
        if let cached = lineCache[key] { return cached }
        let color = style.fg >= 0 ? Theme.palette[Int(style.fg)] : Theme.palette[7]
        let attributed = NSAttributedString(
            string: String(Character(u)),
            attributes: [.font: style.bold ? boldFont : font, .foregroundColor: color])
        let line = CTLineCreateWithAttributedString(attributed)
        lineCache[key] = line
        return line
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let scale = window?.backingScaleFactor ?? 2
        let lw = max(1 / scale, (cellW / 9 * scale).rounded() / scale)
        ctx.setShouldAntialias(true)

        for row in 0..<buffer.rows {
            let y = originY + CGFloat(buffer.rows - 1 - row) * cellH
            for col in 0..<buffer.cols {
                let cell = buffer.cells[row * buffer.cols + col]
                let rect = CGRect(x: originX + CGFloat(col) * cellW, y: y, width: cellW, height: cellH)
                if cell.style.bg >= 0 {
                    ctx.setFillColor(Theme.palette[Int(cell.style.bg)].cgColor)
                    ctx.fill(rect)
                }
                let v = cell.scalar
                if v == 32 || v == 0 { continue }
                let fg = Theme.palette[Int(max(0, cell.style.fg))]
                if let seg = boxSegments(v) {
                    ctx.setFillColor(fg.cgColor)
                    drawBox(ctx, seg, rect, lw: lw, scale: scale)
                } else if v >= 0x2800 && v <= 0x28FF {
                    ctx.setFillColor(fg.cgColor)
                    drawBraille(ctx, v - 0x2800, rect)
                } else if let line = line(for: v, style: cell.style) {
                    ctx.textPosition = CGPoint(x: rect.minX, y: rect.minY + baseline)
                    CTLineDraw(line, ctx)
                }
            }
        }
    }

    private func drawBox(
        _ ctx: CGContext, _ seg: (left: Bool, right: Bool, up: Bool, down: Bool), _ r: CGRect,
        lw: CGFloat, scale: CGFloat
    ) {
        let cx = (r.midX * scale).rounded() / scale
        let cy = (r.midY * scale).rounded() / scale
        let half = lw / 2
        if seg.left { ctx.fill(CGRect(x: r.minX, y: cy - half, width: cx - r.minX + half, height: lw)) }
        if seg.right { ctx.fill(CGRect(x: cx - half, y: cy - half, width: r.maxX - cx + half, height: lw)) }
        if seg.up { ctx.fill(CGRect(x: cx - half, y: cy - half, width: lw, height: r.maxY - cy + half)) }
        if seg.down { ctx.fill(CGRect(x: cx - half, y: r.minY, width: lw, height: cy - r.minY + half)) }
    }

    private func drawBraille(_ ctx: CGContext, _ bits: UInt32, _ r: CGRect) {
        if bits == 0 { return }
        let d = min(r.width / 2, r.height / 4) * 0.62
        for dot in brailleDots where bits & dot.bit != 0 {
            let cx = r.minX + (CGFloat(dot.col) + 0.5) * r.width / 2
            // 点字の行は上から数える。座標は下から
            let cy = r.maxY - (CGFloat(dot.row) + 0.5) * r.height / 4
            ctx.fillEllipse(in: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d))
        }
    }
}
