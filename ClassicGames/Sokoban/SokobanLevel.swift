import Foundation

/// 把一关的文字图拆成墙、目标、箱子和人。记号沿用公开关卡的写法。
enum SokobanLevel {
    /// `#` 墙，`@` 人，`$` 箱子，`.` 目标，`*` 箱子在目标上，`+` 人在目标上，空格是地板。
    static func parsed(_ number: Int) -> (rows: Int, cols: Int, walls: Set<GridPoint>, targets: Set<GridPoint>, boxes: Set<GridPoint>, player: GridPoint) {
        let lines = SokobanLevels.pictures[number - 1]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var walls: Set<GridPoint> = []
        var targets: Set<GridPoint> = []
        var boxes: Set<GridPoint> = []
        var player: GridPoint?
        for (row, line) in lines.enumerated() {
            for (col, mark) in line.enumerated() {
                let point = GridPoint(row: row, col: col)
                switch mark {
                case "#":
                    walls.insert(point)
                case ".":
                    targets.insert(point)
                case "$":
                    boxes.insert(point)
                case "*":
                    boxes.insert(point)
                    targets.insert(point)
                case "@":
                    player = point
                case "+":
                    player = point
                    targets.insert(point)
                default:
                    break
                }
            }
        }
        let cols = lines.map(\.count).max() ?? 0
        // 公开关卡里箱子和目标一样多，人也只有一个。对不上就不要开这一局。
        precondition(player != nil, "第 \(number) 关没有人")
        precondition(boxes.count == targets.count, "第 \(number) 关箱子和目标数量不同")
        return (lines.count, cols, walls, targets, boxes, player!)
    }
}

/// 棋盘上的一格。行从上往下数，列从左往右数。
struct GridPoint: Hashable {
    var row: Int
    var col: Int

    /// 沿方向走一格后的位置。不检查墙和边界。
    func moving(_ direction: SokobanDirection) -> GridPoint {
        switch direction {
        case .up:
            return GridPoint(row: row - 1, col: col)
        case .down:
            return GridPoint(row: row + 1, col: col)
        case .left:
            return GridPoint(row: row, col: col - 1)
        case .right:
            return GridPoint(row: row, col: col + 1)
        }
    }
}

/// 推箱子的四个方向。滑动和方向按钮都进这一个枚举。
enum SokobanDirection {
    case up
    case down
    case left
    case right

    /// 棋盘摘要里的朝向。和按钮名字分开，避免和中文文案绑死。
    var name: String {
        switch self {
        case .up: "up"
        case .down: "down"
        case .left: "left"
        case .right: "right"
        }
    }
}
