import Foundation
import Observation

/// 2048 的一格。标识保持不变时，界面才能把这一格滑到新位置。
struct Tile2048: Identifiable, Equatable {
    let id: UUID
    var value: Int
    var row: Int
    var col: Int
}

/// 2048 的四个方向。滑动和方向按钮都进这里。
enum Direction2048 {
    case up
    case down
    case left
    case right
}

/// 2048 这一局。滑动、合并和生成新块都在这里，不写最高纪录。
@MainActor
@Observable
final class Game2048Model {
    private(set) var tiles: [Tile2048] = []
    private(set) var score = 0
    private(set) var isOver = false
    private(set) var reached2048 = false

    init() {
        spawn()
        spawn()
    }

    /// 复制当前棋盘给自动下完用，不再额外生成开局的两块。
    private init(tiles: [Tile2048], score: Int, isOver: Bool, reached2048: Bool) {
        self.tiles = tiles
        self.score = score
        self.isOver = isOver
        self.reached2048 = reached2048
    }

    /// 结束时显示「结束」。没结束但出现过 2048 时显示「达成」，棋盘还能继续。
    var banner: String? {
        if isOver { return "结束" }
        if reached2048 { return "达成" }
        return nil
    }

    /// 按一行 16 个数公布棋盘，0 是空格。
    var token: String {
        "score:\(score);over:\(isOver);cells:\(cells.map(String.init).joined(separator: ","))"
    }

    /// 走一步。没有格子移动就不生成新块，分数也不变。结束后不再接受操作。
    func move(_ direction: Direction2048) {
        guard !isOver else { return }
        let before = tiles
        let vertical = direction == .up || direction == .down
        let forward = direction == .left || direction == .up
        var gained = 0
        var next: [Tile2048] = []
        for index in 0..<4 {
            let line = tiles.filter { vertical ? $0.col == index : $0.row == index }
            let collapsed = collapse(line, vertical: vertical, forward: forward, lineIndex: index)
            gained += collapsed.gained
            next.append(contentsOf: collapsed.tiles)
        }
        guard !sameBoard(before, next) else { return }
        tiles = next
        score += gained
        if tiles.contains(where: { $0.value >= 2048 }) {
            reached2048 = true
        }
        spawn()
        if !canMove() {
            isOver = true
        }
    }

    /// 用和按钮相同的走法一直下，直到四个方向都不能动。
    /// 先在临时棋盘上走完再一次写回，避免中途刷新把还没落定的分数写成纪录。
    func playUntilStuck() {
        guard !isOver else { return }
        let trial = Game2048Model(
            tiles: tiles,
            score: score,
            isOver: false,
            reached2048: reached2048
        )
        trial.runUntilStuck()
        tiles = trial.tiles
        reached2048 = trial.reached2048
        score = trial.score
        isOver = trial.isOver
    }

    /// 在这份棋盘上连续走，直到四个方向都不能动。步数上限只防止规则写错时停不下来。
    private func runUntilStuck() {
        let order: [Direction2048] = [.up, .right, .down, .left]
        var steps = 0
        while !isOver, steps < 2000 {
            let before = tiles
            let beforeScore = score
            var moved = false
            for direction in order {
                move(direction)
                if tiles != before || score != beforeScore {
                    moved = true
                    break
                }
            }
            if !moved {
                isOver = true
                break
            }
            steps += 1
        }
    }

    /// 回到两块新数字，本局分数归零。最高纪录留在外框。
    func restart() {
        tiles = []
        score = 0
        isOver = false
        reached2048 = false
        spawn()
        spawn()
    }

    /// 把一行或一列先滑到边上，再把相邻相同数字合成一次。
    private func collapse(
        _ line: [Tile2048],
        vertical: Bool,
        forward: Bool,
        lineIndex: Int
    ) -> (tiles: [Tile2048], gained: Int) {
        let sorted = line.sorted { lhs, rhs in
            let leftIndex = vertical ? lhs.row : lhs.col
            let rightIndex = vertical ? rhs.row : rhs.col
            return forward ? leftIndex < rightIndex : leftIndex > rightIndex
        }
        var kept: [Tile2048] = []
        var gained = 0
        var index = 0
        while index < sorted.count {
            if index + 1 < sorted.count, sorted[index].value == sorted[index + 1].value {
                var merged = sorted[index]
                merged.value *= 2
                gained += merged.value
                kept.append(merged)
                index += 2
            } else {
                kept.append(sorted[index])
                index += 1
            }
        }
        for offset in kept.indices {
            let position = forward ? offset : 3 - offset
            if vertical {
                kept[offset].row = position
                kept[offset].col = lineIndex
            } else {
                kept[offset].row = lineIndex
                kept[offset].col = position
            }
        }
        return (kept, gained)
    }

    /// 有效移动后，在一个空位放 2 或 4。2 的概率是 0.9。
    private func spawn() {
        var empty: [(Int, Int)] = []
        for row in 0..<4 {
            for col in 0..<4 where tile(row: row, col: col) == nil {
                empty.append((row, col))
            }
        }
        guard let spot = empty.randomElement() else { return }
        let value = Double.random(in: 0..<1) < 0.9 ? 2 : 4
        tiles.append(Tile2048(id: UUID(), value: value, row: spot.0, col: spot.1))
    }

    /// 还有空位，或者相邻有相同数字，就还能动。
    private func canMove() -> Bool {
        if tiles.count < 16 { return true }
        for row in 0..<4 {
            for col in 0..<4 {
                guard let value = tile(row: row, col: col)?.value else { return true }
                if col < 3, tile(row: row, col: col + 1)?.value == value { return true }
                if row < 3, tile(row: row + 1, col: col)?.value == value { return true }
            }
        }
        return false
    }

    private func tile(row: Int, col: Int) -> Tile2048? {
        tiles.first { $0.row == row && $0.col == col }
    }

    private var cells: [Int] {
        var grid = Array(repeating: 0, count: 16)
        for tile in tiles {
            grid[tile.row * 4 + tile.col] = tile.value
        }
        return grid
    }

    private func sameBoard(_ lhs: [Tile2048], _ rhs: [Tile2048]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let left = lhs.sorted { $0.id.uuidString < $1.id.uuidString }
        let right = rhs.sorted { $0.id.uuidString < $1.id.uuidString }
        return zip(left, right).allSatisfy { pair in
            pair.0.id == pair.1.id && pair.0.row == pair.1.row && pair.0.col == pair.1.col && pair.0.value == pair.1.value
        }
    }
}

extension GameID {
    /// 2048 的登记标识。
    static let game2048 = GameID(rawValue: "game2048")
}
