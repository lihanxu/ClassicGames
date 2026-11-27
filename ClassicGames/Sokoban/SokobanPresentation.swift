import Foundation

/// Exact board bounds, no minimum cell clamp and no board scrolling.
struct SokobanBoardFit {
    let cell: Double
    let gap: Double
    let width: Double
    let height: Double
    /// Historical size gate used by isolation tests. The v3.0 play canvas always
    /// draws asset tiles regardless of this value.
    static func usesDetailedArtwork(rows: Int, cols: Int, cell: Double) -> Bool {
        rows > 0 && cols > 0 && rows <= 12 && cols <= 12 && cell.isFinite && cell >= 28
    }

    static func calculate(width: Double, height: Double, rows: Int, cols: Int, maxCell: Double? = nil, gap: Double? = nil) -> Self {
        let r = Double(max(rows, 1)), c = Double(max(cols, 1))
        let w = max(0, width), h = max(0, height)
        let gap = gap ?? (min(w/c, h/r) < 20 ? 0.5 : 1.0)
        var cell = max(0, min((w-gap*(c-1))/c, (h-gap*(r-1))/r))
        if let maxCell { cell = min(cell, max(0, maxCell)) }
        return Self(cell: cell, gap: gap, width: c*cell+(c-1)*gap, height: r*cell+(r-1)*gap)
    }
    /// Rendering mask only. Never trims or changes the canonical level data.
    static func exterior(rows: Int, cols: Int, walls: Set<GridPoint>) -> Set<GridPoint> {
        guard rows > 0, cols > 0 else { return [] }
        var outside: Set<GridPoint> = [], queue: [GridPoint] = []
        func append(_ p: GridPoint) {
            guard p.row >= 0, p.col >= 0, p.row < rows, p.col < cols,
                  !walls.contains(p), outside.insert(p).inserted else { return }
            queue.append(p)
        }
        for r in 0..<rows { append(GridPoint(row:r,col:0)); append(GridPoint(row:r,col:cols-1)) }
        for c in 0..<cols { append(GridPoint(row:0,col:c)); append(GridPoint(row:rows-1,col:c)) }
        var head = 0
        while head < queue.count {
            let p = queue[head]; head += 1
            for d in [SokobanDirection.up,.right,.down,.left] { append(p.moving(d)) }
        }
        return outside
    }
}

/// Render-only square mapping. Never changes canonical rows/cols or save data.
/// Inner playable area is N×N with N = max(rows, cols), then a 1-cell outer wall
/// makes a (N+2)×(N+2) visual board.
struct SokobanVisualGrid {
    let inner: Int
    let originRow: Int
    let originCol: Int
    var side: Int { inner + 2 }

    static func make(rows: Int, cols: Int) -> Self {
        let inner = max(max(rows, cols), 1)
        return Self(inner: inner, originRow: (inner - rows) / 2, originCol: (inner - cols) / 2)
    }

    func map(_ point: GridPoint) -> GridPoint {
        GridPoint(row: point.row + originRow + 1, col: point.col + originCol + 1)
    }

    func isOuterWall(row: Int, col: Int) -> Bool {
        row == 0 || col == 0 || row == side - 1 || col == side - 1
    }

    /// Level-space point for an inner visual cell, or `nil` when the cell is the
    /// decorative ring or N×N padding outside the original rows×cols.
    func levelPoint(visualRow: Int, visualCol: Int, rows: Int, cols: Int) -> GridPoint? {
        guard !isOuterWall(row: visualRow, col: visualCol) else { return nil }
        let point = GridPoint(row: visualRow - 1 - originRow, col: visualCol - 1 - originCol)
        guard point.row >= 0, point.col >= 0, point.row < rows, point.col < cols else { return nil }
        return point
    }
}

/// Render-only floor classification. Never changes canonical geometry or saves.
enum SokobanFloorPaint: Equatable {
    case blocked
    case walkable
    case target

    var isActive: Bool { self == .walkable || self == .target }

    /// `#` walls, flood-reachable exterior blanks, and N×N padding are blocked.
    /// Only interior walkable cells stay cream; targets keep the green star tile.
    static func paint(
        _ point: GridPoint,
        rows: Int,
        cols: Int,
        walls: Set<GridPoint>,
        targets: Set<GridPoint>,
        exterior: Set<GridPoint>
    ) -> SokobanFloorPaint {
        let inside = point.row >= 0 && point.col >= 0 && point.row < rows && point.col < cols
        if !inside || walls.contains(point) || exterior.contains(point) { return .blocked }
        if targets.contains(point) { return .target }
        return .walkable
    }

    static func paint(
        visualRow: Int,
        visualCol: Int,
        grid: SokobanVisualGrid,
        rows: Int,
        cols: Int,
        walls: Set<GridPoint>,
        targets: Set<GridPoint>,
        exterior: Set<GridPoint>
    ) -> SokobanFloorPaint? {
        if grid.isOuterWall(row: visualRow, col: visualCol) { return nil }
        guard let point = grid.levelPoint(visualRow: visualRow, visualCol: visualCol, rows: rows, cols: cols) else {
            return .blocked
        }
        return paint(point, rows: rows, cols: cols, walls: walls, targets: targets, exterior: exterior)
    }
}

enum SokobanSwipe {
    static func direction(dx: Double, dy: Double) -> SokobanDirection? {
        guard dx.isFinite, dy.isFinite, max(abs(dx),abs(dy)) >= 16 else { return nil }
        if abs(dx) >= abs(dy)*1.35 { return dx > 0 ? .right : .left }
        if abs(dy) >= abs(dx)*1.35 { return dy > 0 ? .down : .up }
        return nil
    }
}
