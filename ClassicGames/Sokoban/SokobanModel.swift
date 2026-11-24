import Foundation
import Observation

/// 每一关自己的最少步数。键带关卡号，重开和返回都不清。
enum SokobanRecords {
    /// 没有纪录时返回空。0 是合法成绩，和还没过关分开。
    static func best(level: Int) -> Int? {
        let key = storageKey(level)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: key)
    }

    /// 这一段里已经写下最少步数的关数。没有数字不算已过。
    static func clearedCount(from start: Int, through end: Int) -> Int {
        (start...end).reduce(0) { count, level in
            count + (best(level: level) == nil ? 0 : 1)
        }
    }

    /// 只有更少的步数才替换这一关的纪录。
    @discardableResult
    static func record(level: Int, steps: Int) -> Int {
        if let best = best(level: level), steps >= best {
            return best
        }
        UserDefaults.standard.set(steps, forKey: storageKey(level))
        return steps
    }

    /// 和总纪录用同一前缀，检查时清掉推箱子会把各关一起清掉。
    private static func storageKey(_ level: Int) -> String {
        "classicgames.best.sokoban.\(level)"
    }
}

/// 推箱子这一局的状态。管当前关的走动、过关和换关，不改别的关的纪录。
@MainActor
@Observable
final class SokobanModel {
    private(set) var levelNumber = 1
    private(set) var rows = 0
    private(set) var cols = 0
    private(set) var walls: Set<GridPoint> = []
    private(set) var targets: Set<GridPoint> = []
    private(set) var boxes: Set<GridPoint> = []
    private(set) var player = GridPoint(row: 0, col: 0)
    private(set) var steps = 0
    private(set) var won = false
    private(set) var levelBest: Int?

    private var initialBoxes: Set<GridPoint> = []
    private var initialPlayer = GridPoint(row: 0, col: 0)

    init() {
        load(1)
    }

    /// 走一步。顶墙、顶箱子但箱子前方走不通，都不算步。过关后不再移动。
    func move(_ direction: SokobanDirection) {
        guard !won else { return }
        let next = player.moving(direction)
        guard contains(next), !walls.contains(next) else { return }
        if boxes.contains(next) {
            let beyond = next.moving(direction)
            guard contains(beyond), !walls.contains(beyond), !boxes.contains(beyond) else { return }
            boxes.remove(next)
            boxes.insert(beyond)
        }
        player = next
        steps += 1
        // 箱子和目标必须正好重合。有箱子没到位，或目标还空着，都不算过关。
        if boxes == targets {
            won = true
            levelBest = SokobanRecords.record(level: levelNumber, steps: steps)
        }
    }

    /// 人和箱子回到这一关的原位，步数归零。不改已经写下的纪录，也不换关。
    func restart() {
        boxes = initialBoxes
        player = initialPlayer
        steps = 0
        won = false
    }

    /// 打开编号对应的关。这一局丢掉，各关纪录保留。
    func load(_ number: Int) {
        let clamped = min(max(number, 1), SokobanLevels.count)
        let level = SokobanLevel.parsed(clamped)
        levelNumber = clamped
        rows = level.rows
        cols = level.cols
        walls = level.walls
        targets = level.targets
        boxes = level.boxes
        player = level.player
        initialBoxes = level.boxes
        initialPlayer = level.player
        steps = 0
        won = false
        levelBest = SokobanRecords.best(level: clamped)
    }

    /// 过关后进入下一关。还没过关，或已经是最后一关，就停在原地。
    func advance() {
        guard won, levelNumber < SokobanLevels.count else { return }
        load(levelNumber + 1)
    }

    /// 给界面和模拟器检查用的棋盘摘要。箱子按行列排序，避免集合顺序抖动。
    var token: String {
        let boxText = boxes.sorted { lhs, rhs in
            lhs.row == rhs.row ? lhs.col < rhs.col : lhs.row < rhs.row
        }
        .map { "\($0.row),\($0.col)" }
        .joined(separator: "|")
        return "level:\(levelNumber);player:\(player.row),\(player.col);boxes:\(boxText);steps:\(steps);won:\(won)"
    }

    private func contains(_ point: GridPoint) -> Bool {
        point.row >= 0 && point.col >= 0 && point.row < rows && point.col < cols
    }
}

extension GameID {
    /// 推箱子的登记标识。
    static let sokoban = GameID(rawValue: "sokoban")
}
