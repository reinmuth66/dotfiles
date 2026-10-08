import Darwin
import Foundation

// btm の画面 (config は modules/bottom.nix) を、文字セルの格子に描く。
// レイアウト、罫線、グラフ (点字)、表の列幅、数字の書式は、btm 0.14 のソースと同じ規則にしている。
// 参照した btm のソース: src/canvas/components/{time_series,data_table}、src/canvas/widgets、src/widgets、src/utils。
// 閲覧のみ (選択・ソート・検索・スクロールなどの操作は無い)。

struct Snapshot {
    /// 履歴のサンプル (古い順)。最後が現在
    var samples: [Sample]
    var loadAverage: [Double]
    var processes: [ProcessHarvest]
    /// "/" のデバイス名 (/dev/disk3s1s1)
    var diskName: String
}

// MARK: - 数字の書式 (btm の src/utils/data_units.rs、conversion.rs)

private let kibi = 1024.0

func binaryBytes(_ bytes: UInt64) -> (Double, String) {
    let b = Double(bytes)
    if b < kibi { return (b, "B") }
    if b < kibi * kibi { return (b / kibi, "KiB") }
    if b < kibi * kibi * kibi { return (b / (kibi * kibi), "MiB") }
    if b < kibi * kibi * kibi * kibi { return (b / (kibi * kibi * kibi), "GiB") }
    return (b / (kibi * kibi * kibi * kibi), "TiB")
}

func decimalBytes(_ bytes: UInt64) -> (Double, String) {
    let b = Double(bytes)
    if b < 1e3 { return (b, "B") }
    if b < 1e6 { return (b / 1e3, "KB") }
    if b < 1e9 { return (b / 1e6, "MB") }
    if b < 1e12 { return (b / 1e9, "GB") }
    return (b / 1e12, "TB")
}

/// 値の接頭辞 (10 進)。ネットワークの速度の「K」「M」
func unitPrefix(_ value: UInt64) -> (Double, String) {
    let v = Double(value)
    if v < 1e3 { return (v, "") }
    if v < 1e6 { return (v / 1e3, "K") }
    if v < 1e9 { return (v / 1e6, "M") }
    if v < 1e12 { return (v / 1e9, "G") }
    return (v / 1e12, "T")
}

func binaryByteString(_ value: UInt64) -> String {
    let (v, unit) = binaryBytes(value)
    return String(format: value >= 1 << 30 ? "%.1f%@" : "%.0f%@", v, unit)
}

func decimalBytePerSecondString(_ value: UInt64) -> String {
    let (v, unit) = decimalBytes(value)
    return String(format: value >= 1_000_000_000 ? "%.1f%@/s" : "%.0f%@/s", v, unit)
}

func formatTime(_ secs: UInt64) -> String {
    let days = secs / 86400
    let hours = secs / 3600
    let minutes = secs / 60
    if days > 0 { return "\(days)d \(hours % 24)h \(minutes % 60)m" }
    if hours > 0 { return "\(hours)h \(minutes % 60)m \(secs % 60)s" }
    if minutes > 0 { return String(format: "%dm %d.%02ds", minutes, secs % 60, 0) }
    return String(format: "%d.%03ds", secs, 0)
}

// MARK: - スタイル (btm の既定の配色。色は Theme のパレットの番号)

private enum Colors {
    static let text: Int8 = 7  // Gray
    static let highlight: Int8 = 12  // LightBlue
    static let black: Int8 = 0
    static let ram: Int8 = 13  // LightMagenta
    static let swap: Int8 = 11  // LightYellow
    static let rx: Int8 = 13
    static let tx: Int8 = 11
    static let avg: Int8 = 1  // Red
    static let all: Int8 = 2  // Green
    // cpu_colour_styles
    static let cores: [Int8] = [13, 11, 14, 10, 12, 6, 2, 4]
}

private let textStyle = CellStyle(fg: Colors.text)
private let headerStyle = CellStyle(fg: Colors.highlight, bold: true)
private let selectedStyle = CellStyle(fg: Colors.black, bg: Colors.highlight)

// MARK: - ブロック (枠線とタイトル)

private func drawBlock(_ b: CellBuffer, _ r: Rect, title: String?, selected: Bool) {
    if r.width < 2 || r.height < 2 { return }
    let style = CellStyle(fg: selected ? Colors.highlight : Colors.text)
    for x in (r.x + 1)..<(r.right - 1) {
        b.put(x, r.y, "─", style)
        b.put(x, r.bottom - 1, "─", style)
    }
    for y in (r.y + 1)..<(r.bottom - 1) {
        b.put(r.x, y, "│", style)
        b.put(r.right - 1, y, "│", style)
    }
    b.put(r.x, r.y, "┌", style)
    b.put(r.right - 1, r.y, "┐", style)
    b.put(r.x, r.bottom - 1, "└", style)
    b.put(r.right - 1, r.bottom - 1, "┘", style)
    if let title {
        // タイトルの文字は枠線の色ではなく、テキストの色 (widget_title_style)
        b.text(r.x + 1, r.y, title, textStyle, maxWidth: max(0, r.width - 2))
    }
}

// MARK: - 表 (btm の DataTable)

enum ColumnBound {
    case follow
    case soft(Double?)
    case hard(Int)
}

struct TableColumn {
    var header: String
    var bound: ColumnBound
    var sortable = true

    /// ヘッダーの長さ (バイト数。ソートできる列は、矢印の分の 1 を足す)
    var headerLength: Int { header.utf8.count + (sortable ? 1 : 0) }
}

/// btm の calculate_column_widths。desired は、データの最大の長さ (ソフトな幅の列で使う)
func calculateColumnWidths(_ columns: [TableColumn], desired: [Int], total: Int, leftToRight: Bool) -> [Int] {
    var left = total
    var widths: [Int] = []
    let order = leftToRight ? Array(columns.indices) : columns.indices.reversed()
    columnLoop: for i in order {
        let column = columns[i]
        let width: Int
        switch column.bound {
        case .soft(let maxPercentage):
            let minWidth = column.headerLength
            if minWidth > left { break columnLoop }
            let want = max(desired[i], minWidth)
            let softLimit = max(maxPercentage.map { Int(ceil($0 * Double(total))) } ?? want, minWidth)
            width = min(min(softLimit, want), left)
        case .hard(let n):
            width = n
        case .follow:
            width = column.headerLength
        }
        // 収まらない列や、幅 0 の列で打ち切る
        if width > left || width == 0 { break columnLoop }
        left = max(0, left - (width + 1))
        widths.append(width)
    }
    if widths.isEmpty { return [] }
    if !leftToRight { widths.reverse() }
    // 余りの幅を、各列に分ける
    var numDist = widths.count
    let perSlot = left / numDist
    left %= numDist
    for i in widths.indices {
        if numDist == 0 { break }
        if left > 0 {
            widths[i] += perSlot + 1
            left -= 1
        } else {
            widths[i] += perSlot
        }
        numDist -= 1
    }
    return widths
}

struct TableRow {
    /// 列ごとの文字。nil の列は、飛ばす (btm の CPU 表の「All」)
    var cells: [String?]
    var style = textStyle
    var highlighted = false
}

private let tableGapHeightLimit = 7

private func drawTable(
    _ b: CellBuffer, _ r: Rect, title: String?, selected: Bool, columns: [TableColumn], widths: [Int],
    sortIndex: Int?, descending: Bool, rows: [TableRow]
) {
    drawBlock(b, r, title: title, selected: selected)
    let inner = r.inset(1)
    if inner.isEmpty { return }
    let showHeader = inner.height > 1
    let gap = (!showHeader || r.height < tableGapHeightLimit) ? 0 : 1
    let headerHeight = showHeader ? 1 : 0

    if showHeader {
        var x = inner.x
        for (i, width) in widths.enumerated() {
            var header = columns[i].header
            if i == sortIndex { header += descending ? "▼" : "▲" }
            b.text(x, inner.y, truncate(header, to: width), headerStyle, maxWidth: width)
            x += width + 1
        }
    }

    let numRows = inner.height - gap - headerHeight
    if numRows <= 0 { return }
    for (n, row) in rows.prefix(numRows).enumerated() {
        let y = inner.y + headerHeight + gap + n
        var x = inner.x
        for (i, width) in widths.enumerated() where i < row.cells.count {
            if let cell = row.cells[i] {
                b.text(x, y, truncate(cell, to: width), row.style, maxWidth: width)
            }
            x += width + 1
        }
        if row.highlighted {
            b.restyle(Rect(x: inner.x, y: y, width: inner.width, height: 1), selectedStyle)
        }
    }
}

// MARK: - 時系列グラフ (btm の TimeChart。点字で描く)

private struct Series {
    /// 古い順の (時刻 (秒), 値)
    var points: [(time: Double, value: Double)]
    var color: Int8
    /// 凡例の文字。nil のときは凡例に出さない
    var name: String?
}

/// 点字の格子。1 セルが 2 x 4 の点。同じセルに別の色が来たら、セルごと新しい色で置き換える (btm と同じ)
private final class BrailleGrid {
    let width: Int
    let height: Int
    var pattern: [UInt8]
    var color: [Int8]

    // 点の位置 (列 + 2 * 行) から、点字のビットへ
    private static let dotBits: [UInt8] = [0x01, 0x08, 0x02, 0x10, 0x04, 0x20, 0x40, 0x80]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pattern = Array(repeating: 0, count: width * height)
        color = Array(repeating: -1, count: width * height)
    }

    func paint(_ x: Int, _ y: Int, _ c: Int8) {
        let index = (y / 4) * width + x / 2
        guard index >= 0, index < pattern.count else { return }
        let bit = BrailleGrid.dotBits[(x % 2) + 2 * (y % 4)]
        if color[index] >= 0 {
            if color[index] != c {
                color[index] = c
                pattern[index] = bit
            } else {
                pattern[index] |= bit
            }
        } else {
            color[index] = c
            pattern[index] = bit
        }
    }
}

private struct Painter {
    let grid: BrailleGrid
    let xBounds: (Double, Double)
    let yBounds: (Double, Double)

    /// 座標を点の位置にする。範囲の外は nil
    func point(_ x: Double, _ y: Double) -> (Int, Int)? {
        let (left, right) = xBounds
        let (bottom, top) = yBounds
        if x < left || x > right || y < bottom || y > top { return nil }
        let width = right - left
        let height = top - bottom
        if width <= 0 || height <= 0 { return nil }
        let rx = Double(grid.width * 2)
        let ry = Double(grid.height * 4)
        return (Int(((x - left) * (rx - 1) / width).rounded()), Int(((top - y) * (ry - 1) / height).rounded()))
    }

    func points(_ coords: [(Double, Double)], _ c: Int8) {
        for (x, y) in coords {
            if let (px, py) = point(x, y) { grid.paint(px, py, c) }
        }
    }

    func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ c: Int8) {
        guard let (ax, ay) = point(x1, y1), let (bx, by) = point(x2, y2) else { return }
        let dx = abs(bx - ax)
        let dy = abs(by - ay)
        if dx == 0 {
            for y in min(ay, by)...max(ay, by) { grid.paint(ax, y, c) }
        } else if dy == 0 {
            for x in min(ax, bx)...max(ax, bx) { grid.paint(x, ay, c) }
        } else if dy < dx {
            if ax > bx { low(bx, by, ax, ay, c) } else { low(ax, ay, bx, by, c) }
        } else if ay > by {
            high(bx, by, ax, ay, c)
        } else {
            high(ax, ay, bx, by, c)
        }
    }

    private func low(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, _ c: Int8) {
        let dx = x2 - x1
        let dy = abs(y2 - y1)
        var d = 2 * dy - dx
        var y = y1
        for x in x1...x2 {
            grid.paint(x, y, c)
            if d > 0 {
                y = y1 > y2 ? max(0, y - 1) : y + 1
                d -= 2 * dx
            }
            d += 2 * dy
        }
    }

    private func high(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, _ c: Int8) {
        let dx = abs(x2 - x1)
        let dy = y2 - y1
        var d = 2 * dx - dy
        var x = x1
        for y in y1...y2 {
            grid.paint(x, y, c)
            if d > 0 {
                x = x1 > x2 ? max(0, x - 1) : x + 1
                d -= 2 * dy
            }
            d += 2 * dx
        }
    }
}

/// 左端の x での y の値 (btm の interpolate_point)
private func interpolate(older: (Double, Double), newer: (Double, Double), x: Double) -> Double {
    let slope = (newer.1 - older.1) / (newer.0 - older.0)
    return max(0, older.1 + (x - older.0) * slope)
}

private func drawPoints(_ painter: Painter, _ series: [Series], leftEdge: Double) {
    for s in series {
        guard let current = s.points.last?.time else { continue }
        // 新しい順。x は、現在からの経過時間 (ミリ秒、負)
        let pts: [(Double, Double)] = s.points.reversed().map {
            (-(((current - $0.time) * 1000).rounded(.down)), $0.value)
        }
        if pts.count < 2 { continue }
        for i in 0..<(pts.count - 1) {
            let curr = pts[i]
            let next = pts[i + 1]
            if curr.0 == leftEdge {
                painter.points([curr], s.color)
                break
            } else if next.0 < leftEdge {
                let y = interpolate(older: next, newer: curr, x: leftEdge)
                painter.line(curr.0, curr.1, leftEdge, y, s.color)
                break
            } else {
                painter.line(curr.0, curr.1, next.0, next.1, s.color)
            }
        }
    }
}

/// 凡例の大きさの上限 (グラフの範囲に対する割合)
private struct LegendLimits {
    var widthNumerator: Int
    var widthDenominator: Int
    var heightNumerator = 3
    var heightDenominator = 4
}

private let displayTimeMs = 60_000.0

private func drawTimeChart(
    _ b: CellBuffer, _ r: Rect, title: String, selected: Bool, yLabels: [String], yMax: Double,
    series: [Series], legend: LegendLimits?
) {
    drawBlock(b, r, title: title, selected: selected)
    let area = r.inset(1)
    if area.isEmpty { return }

    // y 軸のラベルと軸 (x 軸のラベルは、hide_time で隠す)
    let labelWidth = min(yLabels.map { textWidth($0) }.max() ?? 0, area.width / 3)
    var x = area.x
    let labelX = x
    x += labelWidth
    var axisX: Int?
    if x + 1 < area.right {
        axisX = x
        x += 1
    }
    guard x < area.right else { return }
    let graph = Rect(x: x, y: area.y, width: area.right - x, height: area.height)

    if yLabels.count >= 2 {
        for (i, label) in yLabels.enumerated() {
            let dy = i * (graph.height - 1) / (yLabels.count - 1)
            let y = graph.bottom - 1 - dy
            b.text(labelX, y, label, textStyle, maxWidth: labelWidth)
        }
    }
    if let axisX {
        for y in graph.y..<graph.bottom { b.put(axisX, y, "│", textStyle) }
    }

    // 点字のキャンバス
    let grid = BrailleGrid(width: graph.width, height: graph.height)
    let painter = Painter(grid: grid, xBounds: (-displayTimeMs, 0), yBounds: (0, yMax))
    drawPoints(painter, series, leftEdge: -displayTimeMs)
    for row in 0..<graph.height {
        for col in 0..<graph.width {
            let i = row * graph.width + col
            if grid.pattern[i] != 0 {
                b.put(graph.x + col, graph.y + row, 0x2800 + UInt32(grid.pattern[i]), CellStyle(fg: grid.color[i]))
            }
        }
    }

    // 凡例 (右上)
    guard let legend else { return }
    let named = series.compactMap { s in s.name.map { ($0, s.color) } }
    if named.isEmpty { return }
    let maxLegendWidth = graph.width * legend.widthNumerator / legend.widthDenominator
    let maxLegendHeight = graph.height * legend.heightNumerator / legend.heightDenominator
    let maxEntries = min(named.count, max(0, maxLegendHeight - 2))
    let visible = Array(named.prefix(maxEntries))
    guard let widest = visible.map({ textWidth($0.0) }).max(), let narrowest = visible.map({ textWidth($0.0) }).min(),
        widest > 0, maxLegendWidth >= narrowest + 2, maxEntries > 0
    else { return }
    let legendWidth = min(widest + 2, maxLegendWidth)
    let legendHeight = maxEntries + 2
    if graph.height - legendHeight < 0 { return }
    let box = Rect(x: graph.right - legendWidth, y: graph.y, width: legendWidth, height: legendHeight)
    b.fill(box, CellStyle())
    // 凡例の枠線は、グラフと同じ色
    for xx in (box.x + 1)..<(box.right - 1) {
        b.put(xx, box.y, "─", textStyle)
        b.put(xx, box.bottom - 1, "─", textStyle)
    }
    for yy in (box.y + 1)..<(box.bottom - 1) {
        b.put(box.x, yy, "│", textStyle)
        b.put(box.right - 1, yy, "│", textStyle)
    }
    b.put(box.x, box.y, "┌", textStyle)
    b.put(box.right - 1, box.y, "┐", textStyle)
    b.put(box.x, box.bottom - 1, "└", textStyle)
    b.put(box.right - 1, box.bottom - 1, "┘", textStyle)
    for (i, entry) in visible.enumerated() {
        let text = truncate(entry.0, to: legendWidth - 2)
        b.text(box.x + 1, box.y + 1 + i, text, CellStyle(fg: entry.1), maxWidth: legendWidth - 2)
    }
}

// MARK: - 各ウィジェット

/// btm の network_graph.rs の adjust_network_data_point (線形、10 進接頭辞、bit)
private func networkAxis(maxEntry: Double) -> (yMax: Double, labels: [String]) {
    let upper = maxEntry == 0 ? 1.0 : maxEntry * 1.5
    let scaled: Double
    let prefix: String
    if upper < 1e3 {
        (scaled, prefix) = (maxEntry, "")
    } else if upper < 1e6 {
        (scaled, prefix) = (maxEntry / 1e3, "K")
    } else if upper < 1e9 {
        (scaled, prefix) = (maxEntry / 1e6, "M")
    } else if upper < 1e12 {
        (scaled, prefix) = (maxEntry / 1e9, "G")
    } else {
        (scaled, prefix) = (maxEntry / 1e12, "T")
    }
    let raw = [
        "0\(prefix)b", String(format: "%.1f", scaled * 0.5), String(format: "%.1f", scaled),
        String(format: "%.1f", scaled * 1.5),
    ]
    return (upper, raw.map { String(repeating: " ", count: max(0, 5 - $0.count)) + $0 })
}

private func memoryLabel(_ name: String, used: UInt64, total: UInt64) -> String {
    if total == 0 { return "\(name):   0%   0.0B/0.0B" }
    let (_, unit) = binaryBytes(total)
    let denominator: Double
    switch unit {
    case "B": denominator = 1
    case "KiB": denominator = kibi
    case "MiB": denominator = kibi * kibi
    case "GiB": denominator = kibi * kibi * kibi
    default: denominator = kibi * kibi * kibi * kibi
    }
    return String(
        format: "%@:%3.0f%%   %.1f%@/%.1f%@", name, Double(used) / Double(total) * 100, Double(used) / denominator,
        unit, Double(total) / denominator, unit)
}

final class Dashboard {
    // 列幅は btm と同じく、最初の描画と、大きさが変わったときだけ、データから決める
    private var processWidths: [Int] = []
    private var processWidthsSize = (cols: 0, rows: 0)

    func render(into b: CellBuffer, snapshot: Snapshot) {
        b.clear()
        let leftWidth = b.cols / 2
        let rightWidth = b.cols - leftWidth
        let third = b.rows / 3
        let diskHeight = Int((Double(b.rows) / 14).rounded())

        let cpuRect = Rect(x: 0, y: 0, width: leftWidth, height: third)
        let memRect = Rect(x: 0, y: third, width: leftWidth, height: third)
        let netRect = Rect(x: 0, y: third * 2, width: leftWidth, height: b.rows - third * 2)
        let diskRect = Rect(x: leftWidth, y: 0, width: rightWidth, height: diskHeight)
        let procRect = Rect(x: leftWidth, y: diskHeight, width: rightWidth, height: b.rows - diskHeight)

        drawCPU(b, cpuRect, snapshot)
        drawMemory(b, memRect, snapshot)
        drawNetwork(b, netRect, snapshot)
        drawDisk(b, diskRect, snapshot)
        drawProcesses(b, procRect, snapshot)
    }

    // MARK: CPU

    private func drawCPU(_ b: CellBuffer, _ r: Rect, _ snapshot: Snapshot) {
        let legendWidth = Int(Double(r.width) * 0.15)
        var graphRect = r
        var legendRect: Rect?
        if legendWidth >= 6 {
            graphRect.width = r.width - legendWidth
            legendRect = Rect(x: r.x + graphRect.width, y: r.y, width: legendWidth, height: r.height)
        }

        let load = snapshot.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " ")
        let samples = snapshot.samples
        let avg = Series(points: samples.map { ($0.time, $0.cpu) }, color: Colors.avg, name: nil)
        drawTimeChart(
            b, graphRect, title: " CPU ─ \(load) ", selected: false, yLabels: ["  0%", "100%"], yMax: 100.5,
            series: [avg], legend: nil)

        guard let legendRect else { return }
        let cores = samples.last?.cores ?? []
        let average = samples.last?.cpu ?? 0
        var rows: [TableRow] = [TableRow(cells: ["All", nil], style: CellStyle(fg: Colors.all))]
        rows.append(TableRow(cells: ["AVG", String(format: "%.0f%%", average)], style: CellStyle(fg: Colors.avg), highlighted: true))
        for (i, usage) in cores.enumerated() {
            let color = Colors.cores[i % Colors.cores.count]
            rows.append(TableRow(cells: ["CPU\(i)", String(format: "%.0f%%", usage)], style: CellStyle(fg: color)))
        }
        let columns = [
            TableColumn(header: "CPU", bound: .soft(0.5), sortable: false),
            TableColumn(header: "Use", bound: .soft(0.5), sortable: false),
        ]
        let inner = legendRect.inset(1)
        let widths = calculateColumnWidths(columns, desired: [1, 3], total: inner.width, leftToRight: false)
        drawTable(
            b, legendRect, title: nil, selected: false, columns: columns, widths: widths, sortIndex: nil,
            descending: false, rows: rows)
    }

    // MARK: メモリ

    private func drawMemory(_ b: CellBuffer, _ r: Rect, _ snapshot: Snapshot) {
        let samples = snapshot.samples
        var series = [
            Series(
                points: samples.map { ($0.time, $0.ramTotal == 0 ? 0 : Double($0.ramUsed) / Double($0.ramTotal) * 100) },
                color: Colors.ram,
                name: samples.last.map { memoryLabel("RAM", used: $0.ramUsed, total: $0.ramTotal) })
        ]
        // スワップが無いとき (総量 0) は、btm と同じく線も凡例も出さない
        if let last = samples.last, last.swapTotal > 0 {
            series.append(
                Series(
                    points: samples.map { ($0.time, $0.swapTotal == 0 ? 0 : Double($0.swapUsed) / Double($0.swapTotal) * 100) },
                    color: Colors.swap, name: memoryLabel("SWP", used: last.swapUsed, total: last.swapTotal)))
        }
        drawTimeChart(
            b, r, title: " Memory ", selected: false, yLabels: ["  0%", "100%"], yMax: 100.5, series: series,
            legend: LegendLimits(widthNumerator: 3, widthDenominator: 4))
    }

    // MARK: ネットワーク

    private func drawNetwork(_ b: CellBuffer, _ r: Rect, _ snapshot: Snapshot) {
        let samples = snapshot.samples
        // y 軸の最大は、表示している 60 秒間の受信と送信の最大
        var maxEntry = 0.0
        if let last = samples.last {
            for s in samples where s.time >= last.time - displayTimeMs / 1000 {
                maxEntry = max(maxEntry, Double(s.netRx), Double(s.netTx))
            }
        }
        let axis = networkAxis(maxEntry: maxEntry)

        func label(_ name: String, rate: UInt64, total: UInt64) -> String {
            let (v, prefix) = unitPrefix(rate)
            let rateLabel = String(format: "%.1f%@b/s", v, prefix)
            let padded = rateLabel + String(repeating: " ", count: max(0, 10 - rateLabel.count))
            let (tv, tunit) = decimalBytes(total / 8)
            return "\(name): \(padded) All: \(String(format: "%.1f%@", tv, tunit))"
        }
        let last = samples.last
        let series = [
            Series(
                points: samples.map { ($0.time, Double($0.netRx)) }, color: Colors.rx,
                name: last.map { label("RX", rate: $0.netRx, total: $0.netTotalRx) }),
            Series(
                points: samples.map { ($0.time, Double($0.netTx)) }, color: Colors.tx,
                name: last.map { label("TX", rate: $0.netTx, total: $0.netTotalTx) }),
        ]
        drawTimeChart(
            b, r, title: " Network ", selected: false, yLabels: axis.labels, yMax: axis.yMax, series: series,
            legend: LegendLimits(widthNumerator: 9, widthDenominator: 10))
    }

    // MARK: ディスク

    private func drawDisk(_ b: CellBuffer, _ r: Rect, _ snapshot: Snapshot) {
        let columns = [
            TableColumn(header: "Disk(d)", bound: .soft(0.2)),
            TableColumn(header: "Mount(m)", bound: .soft(0.2)),
            TableColumn(header: "Used(u)", bound: .hard(8)),
            TableColumn(header: "Free(n)", bound: .hard(8)),
            TableColumn(header: "Total(t)", bound: .hard(9)),
            TableColumn(header: "Used%(p)", bound: .hard(9)),
            TableColumn(header: "R/s(r)", bound: .hard(10)),
            TableColumn(header: "W/s(w)", bound: .hard(11)),
        ]
        var rows: [TableRow] = []
        var desired = Array(repeating: 0, count: columns.count)
        if let s = snapshot.samples.last, s.diskTotal > 0 {
            func size(_ v: UInt64) -> String {
                let (n, unit) = decimalBytes(v)
                return String(format: "%.0f%@", n, unit)
            }
            let summed = s.diskUsed + s.diskFree
            let usedPercent = summed > 0 ? String(format: "%.1f%%", Double(s.diskUsed) / Double(summed) * 100) : "N/A"
            let read = s.diskRead >= 0 ? decimalBytePerSecondString(UInt64(s.diskRead)) : "N/A"
            let written = s.diskWritten >= 0 ? decimalBytePerSecondString(UInt64(s.diskWritten)) : "N/A"
            let cells = [snapshot.diskName, "/", size(s.diskUsed), size(s.diskFree), size(s.diskTotal), usedPercent, read, written]
            rows.append(TableRow(cells: cells))
            desired[0] = snapshot.diskName.utf8.count
            desired[1] = 1
        }
        let inner = r.inset(1)
        let widths = calculateColumnWidths(columns, desired: desired, total: inner.width, leftToRight: true)
        drawTable(
            b, r, title: " Disks ", selected: false, columns: columns, widths: widths, sortIndex: 0,
            descending: false, rows: rows)
    }

    // MARK: プロセス

    private struct ProcessRow {
        var pid: Int32
        var name: String
        var cpu: Float
        var memory: UInt64
        var time: UInt64
        var user: String?
        var state: String
    }

    /// btm のツリー表示 (src/widgets/process_table.rs の get_tree_data)。メモリの降順
    private func treeRows(_ processes: [ProcessHarvest]) -> [ProcessRow] {
        var byPid: [Int32: ProcessHarvest] = [:]
        for p in processes { byPid[p.pid] = p }
        let sortedPids = byPid.keys.sorted()
        var children: [Int32: [Int32]] = [:]
        for pid in sortedPids {
            if let parent = byPid[pid]?.parentPid { children[parent, default: []].append(pid) }
        }
        // 親が無い、または親が一覧に無いプロセスが、根
        let orphans = sortedPids.filter { pid in
            if let parent = byPid[pid]?.parentPid, byPid[parent] != nil { return false }
            return true
        }

        func row(_ pid: Int32, prefix: String) -> ProcessRow {
            let p = byPid[pid]!
            return ProcessRow(
                pid: pid, name: prefix + p.name, cpu: p.cpuPercent, memory: p.memory, time: p.time, user: p.user,
                state: p.state)
        }
        func memory(_ pid: Int32) -> UInt64 { byPid[pid]?.memory ?? 0 }

        var data: [ProcessRow] = []
        var prefixes: [String] = []
        // 根: メモリの降順 (同じなら pid の昇順)。スタックの末尾が先頭の行
        var stack = orphans.sorted { memory($0) > memory($1) }.reversed().map { $0 }
        var lengthStack = [stack.count]
        while let pid = stack.popLast(), !lengthStack.isEmpty {
            lengthStack[lengthStack.count - 1] -= 1
            let isLast = lengthStack[lengthStack.count - 1] == 0
            let prefix = prefixes.isEmpty ? "" : prefixes.joined() + (isLast ? "└" : "├") + "─ "
            data.append(row(pid, prefix: prefix))

            let kids = (children[pid] ?? []).filter { byPid[$0] != nil }
            if prefixes.isEmpty {
                prefixes.append("")
            } else {
                prefixes.append(isLast ? "   " : "│  ")
            }
            // 子: 昇順に並べて、スタックの末尾から取る (= メモリの大きい順)
            let ordered = kids.enumerated().sorted {
                memory($0.element) != memory($1.element) ? memory($0.element) < memory($1.element) : $0.offset < $1.offset
            }.map(\.element)
            lengthStack.append(ordered.count)
            stack.append(contentsOf: ordered)

            while let left = lengthStack.last, left == 0 {
                lengthStack.removeLast()
                if !prefixes.isEmpty { prefixes.removeLast() }
            }
        }
        return data
    }

    private func drawProcesses(_ b: CellBuffer, _ r: Rect, _ snapshot: Snapshot) {
        let rows = treeRows(snapshot.processes)
        let columns = [
            TableColumn(header: "PID(p)", bound: .follow),
            TableColumn(header: "Name(n)", bound: .soft(0.3)),
            TableColumn(header: "CPU%(c)", bound: .follow),
            TableColumn(header: "Mem(m)", bound: .follow),
            TableColumn(header: "Time", bound: .follow),
            TableColumn(header: "User", bound: .soft(0.05)),
            TableColumn(header: "State", bound: .hard(9)),
        ]
        let inner = r.inset(1)
        if processWidths.isEmpty || processWidthsSize.cols != b.cols || processWidthsSize.rows != b.rows {
            // 列ごとの文字の最大の長さ (バイト数。State は、btm が 1 文字の表記で数える)
            var desired = Array(repeating: 0, count: columns.count)
            for p in rows {
                let texts = [
                    String(p.pid), p.name, String(format: "%.1f%%", p.cpu), binaryByteString(p.memory), formatTime(p.time),
                    p.user ?? "N/A", "?",
                ]
                for i in texts.indices { desired[i] = max(desired[i], texts[i].utf8.count) }
            }
            processWidths = calculateColumnWidths(columns, desired: desired, total: inner.width, leftToRight: true)
            processWidthsSize = (b.cols, b.rows)
        }
        let tableRows = rows.map { p in
            TableRow(cells: [
                String(p.pid), p.name, String(format: "%.1f%%", p.cpu), binaryByteString(p.memory), formatTime(p.time),
                p.user ?? "N/A", p.state,
            ])
        }
        // 既定のウィジェットなので、枠線を強調する (btm の default_widget_type = "proc")
        drawTable(
            b, r, title: " Processes ", selected: true, columns: columns, widths: processWidths, sortIndex: 3,
            descending: true, rows: tableRows)
    }
}
