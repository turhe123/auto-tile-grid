import CoreGraphics

/// The available tiling layouts, in hotkey cycling order.
enum TileMode: String, CaseIterable, Identifiable {
    case equalGrid, mainLeft, mainTop, columns

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equalGrid: return "Equal Grid"
        case .mainLeft: return "Main Left"
        case .mainTop: return "Main Top"
        case .columns: return "Columns"
        }
    }

    /// The mode that follows this one when cycling.
    var next: TileMode {
        let all = TileMode.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}

/// Pure tiling math: maps a window count and layout mode onto whole-point rectangles.
/// Rectangles use a top-left origin with y growing downward (Accessibility coordinates).
enum TilingLayout {
    /// Above this count every mode falls back to the equal grid.
    static let maxWindowsForModes = 16

    static func frames(count: Int, mode: TileMode, in area: CGRect,
                       gap: CGFloat, margin: CGFloat, ratio: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let r = area.insetBy(dx: max(0, margin), dy: max(0, margin))
        guard r.width > 0, r.height > 0 else { return [] }
        let g = max(0, gap)
        let ratio = min(max(ratio, 0.2), 0.8)
        let effective = count > maxWindowsForModes ? .equalGrid : mode

        var rects: [CGRect]
        if count == 1 {
            rects = [r]
        } else {
            switch effective {
            case .equalGrid:
                rects = grid(count: count, in: r, gap: g)
            case .columns:
                rects = split(r, count: count, gap: g, horizontal: true)
            case .mainLeft:
                let mainW = (r.width - g) * ratio
                let main = CGRect(x: r.minX, y: r.minY, width: mainW, height: r.height)
                let stack = CGRect(x: main.maxX + g, y: r.minY, width: r.width - mainW - g, height: r.height)
                rects = [main] + split(stack, count: count - 1, gap: g, horizontal: false)
            case .mainTop:
                let mainH = (r.height - g) * ratio
                let main = CGRect(x: r.minX, y: r.minY, width: r.width, height: mainH)
                let row = CGRect(x: r.minX, y: main.maxY + g, width: r.width, height: r.height - mainH - g)
                rects = [main] + split(row, count: count - 1, gap: g, horizontal: true)
            }
        }
        return rects.map(integral)
    }

    /// Row-major grid; the last row stretches its cells to fill the full width.
    private static func grid(count: Int, in r: CGRect, gap: CGFloat) -> [CGRect] {
        let cols = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(cols)))
        let rowRects = split(r, count: rows, gap: gap, horizontal: false)
        var result: [CGRect] = []
        for (rowIndex, rowRect) in rowRects.enumerated() {
            let inRow = min(cols, count - rowIndex * cols)
            result += split(rowRect, count: inRow, gap: gap, horizontal: true)
        }
        return result
    }

    /// Splits a rectangle into `count` equal slices separated by `gap`.
    private static func split(_ r: CGRect, count: Int, gap: CGFloat, horizontal: Bool) -> [CGRect] {
        guard count > 0 else { return [] }
        let total = (horizontal ? r.width : r.height) - gap * CGFloat(count - 1)
        let size = max(1, total / CGFloat(count))
        return (0..<count).map { i in
            let offset = CGFloat(i) * (size + gap)
            return horizontal
                ? CGRect(x: r.minX + offset, y: r.minY, width: size, height: r.height)
                : CGRect(x: r.minX, y: r.minY + offset, width: r.width, height: size)
        }
    }

    /// Snaps edges to whole points to avoid blurry window edges.
    private static func integral(_ r: CGRect) -> CGRect {
        let x0 = r.minX.rounded(), y0 = r.minY.rounded()
        let x1 = r.maxX.rounded(), y1 = r.maxY.rounded()
        return CGRect(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0))
    }
}
