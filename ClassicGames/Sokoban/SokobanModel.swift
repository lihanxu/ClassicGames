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
    /// 脸朝的方向。开局、重开和换关是下。顶墙不改。
    private(set) var facing: SokobanDirection = .down
    /// 这次过关是否写入纪录。正式的一步才算；看解造成的过关不算。
    private(set) var winCounts = false

    private var initialBoxes: Set<GridPoint> = []
    private var initialPlayer = GridPoint(row: 0, col: 0)
    private var undoStack: [SokobanFrame] = []
    private var redoStack: [SokobanFrame] = []
    /// 中途局面。和最高纪录、每关最少步数都不是同一个键。
    private static let resumeKey = "classicgames.sokoban.resume"
    /// 启动参数只在这一进程里生效一次。返回后再进入不能把刚写下的局面清掉。
    private static var didHonorResetArgument = false

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if !Self.didHonorResetArgument {
            Self.didHonorResetArgument = true
            if let index = arguments.firstIndex(of: "-reset-game"),
               arguments.indices.contains(index + 1),
               arguments[index + 1] == GameID.sokoban.rawValue {
                UserDefaults.standard.removeObject(forKey: Self.resumeKey)
            }
        }
        let injected = arguments.firstIndex(of: "-sokoban-resume").flatMap { index -> String? in
            arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        }
        let stored = injected ?? UserDefaults.standard.string(forKey: Self.resumeKey)
        if let stored {
            if !applyResume(stored) {
                load(1, persist: true)
            }
            return
        }
        load(1, persist: false)
    }

    /// 走一步。顶墙、顶箱子但箱子前方走不通，都不算步。过关后不再移动。成功才记入撤销。
    func move(_ direction: SokobanDirection) {
        _ = step(direction, countsOnWin: true)
    }

    /// 退回上一格。栈空或已经是开局则不变。不改纪录，也不换关。
    @discardableResult
    func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(currentFrame)
        restore(previous)
        persist()
        return true
    }

    /// 把刚撤销的那一格放回来。没有可重做的步则不变。
    @discardableResult
    func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(currentFrame)
        restore(next)
        persist()
        return true
    }

    /// 成功的一格。先记下走之前的局面，再改人和箱子。过关且参加比较时才写本关纪录。
    @discardableResult
    private func step(_ direction: SokobanDirection, countsOnWin: Bool) -> Bool {
        guard !won else { return false }
        let next = player.moving(direction)
        guard contains(next), !walls.contains(next) else { return false }
        var nextBoxes = boxes
        if nextBoxes.contains(next) {
            let beyond = next.moving(direction)
            guard contains(beyond), !walls.contains(beyond), !nextBoxes.contains(beyond) else { return false }
            nextBoxes.remove(next)
            nextBoxes.insert(beyond)
        }
        undoStack.append(currentFrame)
        redoStack.removeAll()
        boxes = nextBoxes
        facing = direction
        player = next
        steps += 1
        if boxes == targets {
            won = true
            winCounts = countsOnWin
            if countsOnWin {
                levelBest = SokobanRecords.record(level: levelNumber, steps: steps)
            }
        }
        persist()
        return true
    }

    /// 走之前的一帧。撤销和重做只换这帧，不写纪录。
    private var currentFrame: SokobanFrame {
        SokobanFrame(player: player, boxes: boxes, steps: steps, facing: facing, won: won, counts: winCounts)
    }

    /// 把人和箱子、步数、朝向、过关放回这一帧。
    private func restore(_ frame: SokobanFrame) {
        player = frame.player
        boxes = frame.boxes
        steps = frame.steps
        facing = frame.facing
        won = frame.won
        winCounts = frame.counts
    }

    /// 点到一格。先走不推箱子的最短路；没有这种路才沿直线推开挡路的箱子。走不到就完全不变。
    /// 返回的每一格给画面接着播，模型在返回前已经停在终局。
    func walkTo(_ target: GridPoint) -> [SokobanStep] {
        guard !won else { return [] }
        guard contains(target), !walls.contains(target), !boxes.contains(target), target != player else { return [] }
        let directions: [SokobanDirection]
        if let walk = shortestWalk(to: target) {
            directions = walk
        } else if let line = straightPush(to: target) {
            directions = line
        } else {
            return []
        }
        var taken: [SokobanStep] = []
        for direction in directions {
            let stepsBefore = steps
            let boxesBefore = boxes
            move(direction)
            // 演算已经确认整段走得通。中途失败就不再继续，避免写下半段。
            guard steps > stepsBefore else { break }
            taken.append(SokobanStep(direction: direction, pushed: boxes != boxesBefore))
        }
        return taken
    }

    /// 不推箱子的最短路。步数少优先，其次转弯少，再按上、右、下、左。第一步不算转弯。
    private func shortestWalk(to target: GridPoint) -> [SokobanDirection]? {
        var best: [GridPoint: [SokobanDirection]] = [player: []]
        var queue: [GridPoint] = [player]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            let path = best[current] ?? []
            for direction in SokobanDirection.walkOrder {
                let next = current.moving(direction)
                guard contains(next), !walls.contains(next), !boxes.contains(next) else { continue }
                let candidate = path + [direction]
                if let existing = best[next], !candidate.isBetterWalk(than: existing) {
                    continue
                }
                best[next] = candidate
                queue.append(next)
            }
        }
        let path = best[target] ?? []
        return path.isEmpty ? nil : path
    }

    /// 同一行或同一列，把挡路的箱子整段推开。任一步走不通，或人最后站不进所点的格，就作废。
    private func straightPush(to target: GridPoint) -> [SokobanDirection]? {
        let direction: SokobanDirection
        if target.row == player.row {
            guard target.col != player.col else { return nil }
            direction = target.col > player.col ? .right : .left
        } else if target.col == player.col {
            direction = target.row > player.row ? .down : .up
        } else {
            return nil
        }
        var simPlayer = player
        var simBoxes = boxes
        var simWon = won
        var directions: [SokobanDirection] = []
        while simPlayer != target {
            if simWon { return nil }
            let next = simPlayer.moving(direction)
            guard contains(next), !walls.contains(next) else { return nil }
            if simBoxes.contains(next) {
                let beyond = next.moving(direction)
                guard contains(beyond), !walls.contains(beyond), !simBoxes.contains(beyond) else { return nil }
                simBoxes.remove(next)
                simBoxes.insert(beyond)
            }
            simPlayer = next
            directions.append(direction)
            if simBoxes == targets {
                simWon = true
            }
        }
        return directions.isEmpty ? nil : directions
    }

    /// 人和箱子回到这一关的原位，步数归零。不改已经写下的纪录，也不换关。这一关的撤销和重做都空。
    func restart() {
        boxes = initialBoxes
        player = initialPlayer
        steps = 0
        won = false
        facing = .down
        winCounts = false
        undoStack.removeAll()
        redoStack.removeAll()
        persist()
    }

    /// 打开编号对应的关。这一局丢掉，各关纪录保留，并写下这一关的开局。
    func load(_ number: Int) {
        load(number, persist: true)
    }

    /// 换到这一关的开局。第一次进入且没有存档时不写入。
    private func load(_ number: Int, persist shouldPersist: Bool) {
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
        facing = .down
        winCounts = false
        undoStack.removeAll()
        redoStack.removeAll()
        levelBest = SokobanRecords.best(level: clamped)
        if shouldPersist {
            persist()
        }
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
        return "level:\(levelNumber);player:\(player.row),\(player.col);boxes:\(boxText);steps:\(steps);won:\(won);face:\(facing.name)"
    }

    /// 把当前局面写进 UserDefaults。不写最高纪录，也不写每关最少步数。
    private func persist() {
        let text = SokobanResume.encode(
            level: levelNumber,
            player: player,
            boxes: boxes,
            steps: steps,
            facing: facing,
            won: won,
            counts: winCounts,
            undo: undoStack,
            redo: redoStack
        )
        UserDefaults.standard.set(text, forKey: Self.resumeKey)
    }

    /// 读回一局。关号、朝向或箱子数量不对就拒绝，调用方改回第 1 关开局。不写纪录。
    private func applyResume(_ raw: String) -> Bool {
        guard let parsed = SokobanResume.parse(raw) else { return false }
        let level = SokobanLevel.parsed(parsed.level)
        let boxCount = level.boxes.count
        guard parsed.boxes.count == boxCount,
              parsed.undo.allSatisfy({ $0.boxes.count == boxCount }),
              parsed.redo.allSatisfy({ $0.boxes.count == boxCount }) else { return false }
        levelNumber = parsed.level
        rows = level.rows
        cols = level.cols
        walls = level.walls
        targets = level.targets
        boxes = parsed.boxes
        player = parsed.player
        initialBoxes = level.boxes
        initialPlayer = level.player
        steps = parsed.steps
        facing = parsed.facing
        won = parsed.won
        winCounts = parsed.counts
        undoStack = parsed.undo
        redoStack = parsed.redo
        levelBest = SokobanRecords.best(level: parsed.level)
        return true
    }

    private func contains(_ point: GridPoint) -> Bool {
        point.row >= 0 && point.col >= 0 && point.row < rows && point.col < cols
    }
}

/// 走之前的局面。过关标记只说明这一帧是否已经过关，以及这次过关要不要参加纪录比较。
private struct SokobanFrame {
    var player: GridPoint
    var boxes: Set<GridPoint>
    var steps: Int
    var facing: SokobanDirection
    var won: Bool
    var counts: Bool
}

extension GameID {
    /// 推箱子的登记标识。
    static let sokoban = GameID(rawValue: "sokoban")
}

/// 点地走出的一格。推了箱子就没有脚步声。
struct SokobanStep {
    var direction: SokobanDirection
    var pushed: Bool
}

extension Array where Element == SokobanDirection {
    /// 步数少、转弯少，再按上、右、下、左。第一步不算转弯。
    func isBetterWalk(than other: [SokobanDirection]) -> Bool {
        if count != other.count { return count < other.count }
        if turnCount != other.turnCount { return turnCount < other.turnCount }
        for index in indices where self[index] != other[index] {
            let order = SokobanDirection.walkOrder
            let mine = order.firstIndex(of: self[index]) ?? 0
            let theirs = order.firstIndex(of: other[index]) ?? 0
            return mine < theirs
        }
        return false
    }

    /// 方向和上一步不同的次数。第一步没有上一步，不算。
    private var turnCount: Int {
        guard count > 1 else { return 0 }
        return zip(self, dropFirst()).reduce(0) { total, pair in
            total + (pair.0 == pair.1 ? 0 : 1)
        }
    }
}

/// 中途局面编成一行。字段用竖线分开，栈里的每一帧用分号分开。
private enum SokobanResume {
    struct Parsed {
        var level: Int
        var player: GridPoint
        var boxes: Set<GridPoint>
        var steps: Int
        var facing: SokobanDirection
        var won: Bool
        var counts: Bool
        var undo: [SokobanFrame]
        var redo: [SokobanFrame]
    }

    /// 把这一局和两套栈写成一行。箱子按行列排序，避免集合顺序抖动。
    static func encode(
        level: Int,
        player: GridPoint,
        boxes: Set<GridPoint>,
        steps: Int,
        facing: SokobanDirection,
        won: Bool,
        counts: Bool,
        undo: [SokobanFrame],
        redo: [SokobanFrame]
    ) -> String {
        [
            "\(level)",
            point(player),
            boxList(boxes),
            "\(steps)",
            facing.name,
            won ? "1" : "0",
            counts ? "1" : "0",
            undo.map(frame).joined(separator: ";"),
            redo.map(frame).joined(separator: ";")
        ].joined(separator: "|")
    }

    /// 拆开一行。关号不在 1 到 100，或朝向不是四个方向之一，就整行作废。
    static func parse(_ raw: String) -> Parsed? {
        let fields = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 9,
              let level = Int(fields[0]),
              (1...SokobanLevels.count).contains(level),
              let player = point(fields[1]),
              let boxes = boxes(fields[2]),
              let steps = Int(fields[3]),
              let facing = direction(fields[4]),
              let won = flag(fields[5]),
              let counts = flag(fields[6]),
              let undo = frames(fields[7]),
              let redo = frames(fields[8]) else { return nil }
        return Parsed(
            level: level,
            player: player,
            boxes: boxes,
            steps: steps,
            facing: facing,
            won: won,
            counts: counts,
            undo: undo,
            redo: redo
        )
    }

    private static func frame(_ frame: SokobanFrame) -> String {
        [
            point(frame.player),
            boxList(frame.boxes),
            "\(frame.steps)",
            frame.facing.name,
            frame.won ? "1" : "0",
            frame.counts ? "1" : "0"
        ].joined(separator: "*")
    }

    private static func frames(_ raw: String) -> [SokobanFrame]? {
        if raw.isEmpty { return [] }
        var decoded: [SokobanFrame] = []
        for piece in raw.split(separator: ";", omittingEmptySubsequences: false) {
            let fields = piece.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6,
                  let player = point(fields[0]),
                  let boxes = boxes(fields[1]),
                  let steps = Int(fields[2]),
                  let facing = direction(fields[3]),
                  let won = flag(fields[4]),
                  let counts = flag(fields[5]) else { return nil }
            decoded.append(SokobanFrame(
                player: player,
                boxes: boxes,
                steps: steps,
                facing: facing,
                won: won,
                counts: counts
            ))
        }
        return decoded
    }

    private static func boxList(_ boxes: Set<GridPoint>) -> String {
        boxes.sorted { lhs, rhs in
            lhs.row == rhs.row ? lhs.col < rhs.col : lhs.row < rhs.row
        }
        .map(point)
        .joined(separator: "+")
    }

    private static func boxes(_ raw: String) -> Set<GridPoint>? {
        if raw.isEmpty { return [] }
        var points: Set<GridPoint> = []
        for piece in raw.split(separator: "+", omittingEmptySubsequences: false) {
            guard let point = point(String(piece)) else { return nil }
            points.insert(point)
        }
        return points
    }

    private static func point(_ point: GridPoint) -> String {
        "\(point.row),\(point.col)"
    }

    private static func point(_ raw: String) -> GridPoint? {
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let row = Int(parts[0]), let col = Int(parts[1]) else { return nil }
        return GridPoint(row: row, col: col)
    }

    private static func direction(_ name: String) -> SokobanDirection? {
        switch name {
        case "up": .up
        case "down": .down
        case "left": .left
        case "right": .right
        default: nil
        }
    }

    private static func flag(_ raw: String) -> Bool? {
        switch raw {
        case "1": true
        case "0": false
        default: nil
        }
    }
}
