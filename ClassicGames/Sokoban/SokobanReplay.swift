import Foundation

/// 纯函数回放与提示规划，不碰存档，也不依赖 MainActor 上的对局模型。
enum SokobanMoveLetter {
    static func direction(from character: Character) -> SokobanDirection? {
        switch character {
        case "U", "u", "上": return .up
        case "D", "d", "下": return .down
        case "L", "l", "左": return .left
        case "R", "r", "右": return .right
        default: return nil
        }
    }

    static func letter(_ direction: SokobanDirection) -> Character {
        switch direction {
        case .up: return "U"
        case .down: return "D"
        case .left: return "L"
        case .right: return "R"
        }
    }

    static func parse(_ text: String) -> [SokobanDirection]? {
        var directions: [SokobanDirection] = []
        directions.reserveCapacity(text.count)
        for character in text {
            guard let direction = direction(from: character) else { return nil }
            directions.append(direction)
        }
        return directions
    }
}

struct SokobanBoardState: Hashable, Sendable {
    var player: GridPoint
    var boxes: Set<GridPoint>
}

enum SokobanReplay {
    struct Outcome: Equatable {
        var ok: Bool
        var reason: String
        var steps: Int
        var pushes: Int
        var player: GridPoint
        var boxes: Set<GridPoint>
        var won: Bool
        var boxesOnTargets: Int
    }

    static func board(level number: Int) -> (rows: Int, cols: Int, walls: Set<GridPoint>, targets: Set<GridPoint>, boxes: Set<GridPoint>, player: GridPoint) {
        SokobanLevel.parsed(number)
    }

    static func boxesOnTargets(_ boxes: Set<GridPoint>, _ targets: Set<GridPoint>) -> Int {
        boxes.intersection(targets).count
    }

    /// 从指定局面走一步。撞墙、顶死双箱时返回 nil，局面不变。
    static func stepped(
        player: GridPoint,
        boxes: Set<GridPoint>,
        walls: Set<GridPoint>,
        rows: Int,
        cols: Int,
        direction: SokobanDirection
    ) -> (player: GridPoint, boxes: Set<GridPoint>, pushed: Bool)? {
        let next = player.moving(direction)
        guard next.row >= 0, next.col >= 0, next.row < rows, next.col < cols, !walls.contains(next) else { return nil }
        var nextBoxes = boxes
        var pushed = false
        if nextBoxes.contains(next) {
            let beyond = next.moving(direction)
            guard beyond.row >= 0, beyond.col >= 0, beyond.row < rows, beyond.col < cols,
                  !walls.contains(beyond), !nextBoxes.contains(beyond) else { return nil }
            nextBoxes.remove(next)
            nextBoxes.insert(beyond)
            pushed = true
        }
        return (next, nextBoxes, pushed)
    }

    static func play(level number: Int, moves: String, starting: SokobanBoardState? = nil) -> Outcome {
        let parsed = SokobanLevel.parsed(number)
        var player = starting?.player ?? parsed.player
        var boxes = starting?.boxes ?? parsed.boxes
        guard let directions = SokobanMoveLetter.parse(moves), !directions.isEmpty else {
            return Outcome(ok: false, reason: "empty_or_invalid_chars", steps: 0, pushes: 0,
                           player: player, boxes: boxes, won: boxes == parsed.targets,
                           boxesOnTargets: boxesOnTargets(boxes, parsed.targets))
        }
        var pushes = 0
        for (index, direction) in directions.enumerated() {
            guard let result = stepped(player: player, boxes: boxes, walls: parsed.walls,
                                       rows: parsed.rows, cols: parsed.cols, direction: direction) else {
                let wall = player.moving(direction)
                let reason = (parsed.walls.contains(wall) || wall.row < 0 || wall.col < 0 || wall.row >= parsed.rows || wall.col >= parsed.cols)
                    ? "illegal_wall_at_step_\(index + 1)" : "illegal_push_at_step_\(index + 1)"
                return Outcome(ok: false, reason: reason, steps: index, pushes: pushes,
                               player: player, boxes: boxes, won: false,
                               boxesOnTargets: boxesOnTargets(boxes, parsed.targets))
            }
            player = result.player
            boxes = result.boxes
            if result.pushed { pushes += 1 }
        }
        let won = boxes == parsed.targets
        return Outcome(ok: won, reason: won ? "ok" : "unsolved", steps: directions.count, pushes: pushes,
                       player: player, boxes: boxes, won: won,
                       boxesOnTargets: boxesOnTargets(boxes, parsed.targets))
    }

    /// 不推箱子的最短走位。走不到返回空。
    static func shortestWalk(
        from player: GridPoint,
        to target: GridPoint,
        boxes: Set<GridPoint>,
        walls: Set<GridPoint>,
        rows: Int,
        cols: Int
    ) -> [SokobanDirection]? {
        if player == target { return [] }
        var best: [GridPoint: [SokobanDirection]] = [player: []]
        var queue: [GridPoint] = [player]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            let path = best[current] ?? []
            for direction in SokobanDirection.walkOrder {
                let next = current.moving(direction)
                guard next.row >= 0, next.col >= 0, next.row < rows, next.col < cols,
                      !walls.contains(next), !boxes.contains(next), best[next] == nil else { continue }
                best[next] = path + [direction]
                queue.append(next)
            }
        }
        return best[target]
    }
}

enum SokobanHintOutcome: Equatable, Sendable {
    case sequence([SokobanDirection], fromReference: Bool)
    case deadlock
    case timeout
}

enum SokobanHintPlanner {
    static let budget: TimeInterval = 1.5

    /// 开局或参考解沿线盘面：O(开局回放) 命中后截取到首次净增 +1（或直接通关）。
    static func referenceLine(level number: Int, player: GridPoint, boxes: Set<GridPoint>) -> [SokobanDirection]? {
        guard let entry = SokobanReferenceSolutions.entry(levelId: number),
              let solution = SokobanMoveLetter.parse(entry.moves), !solution.isEmpty else { return nil }
        let parsed = SokobanLevel.parsed(number)
        var simPlayer = parsed.player
        var simBoxes = parsed.boxes
        // 沿线每个精确局面，以及「箱子相同、人可无推走位到参考格」的局面。
        if let suffix = suffixIfOnLine(player: player, boxes: boxes, simPlayer: simPlayer, simBoxes: simBoxes,
                                       parsed: parsed, remaining: solution) {
            return suffix
        }
        for (index, direction) in solution.enumerated() {
            guard let step = SokobanReplay.stepped(player: simPlayer, boxes: simBoxes, walls: parsed.walls,
                                                   rows: parsed.rows, cols: parsed.cols, direction: direction) else {
                return nil
            }
            simPlayer = step.player
            simBoxes = step.boxes
            let remaining = Array(solution[(index + 1)...])
            if let suffix = suffixIfOnLine(player: player, boxes: boxes, simPlayer: simPlayer, simBoxes: simBoxes,
                                           parsed: parsed, remaining: remaining) {
                return suffix
            }
        }
        return nil
    }

    private static func suffixIfOnLine(
        player: GridPoint,
        boxes: Set<GridPoint>,
        simPlayer: GridPoint,
        simBoxes: Set<GridPoint>,
        parsed: (rows: Int, cols: Int, walls: Set<GridPoint>, targets: Set<GridPoint>, boxes: Set<GridPoint>, player: GridPoint),
        remaining: [SokobanDirection]
    ) -> [SokobanDirection]? {
        guard boxes == simBoxes else { return nil }
        let walk: [SokobanDirection]
        if player == simPlayer {
            walk = []
        } else if let path = SokobanReplay.shortestWalk(from: player, to: simPlayer, boxes: boxes,
                                                        walls: parsed.walls, rows: parsed.rows, cols: parsed.cols) {
            walk = path
        } else {
            return nil
        }
        let startOn = SokobanReplay.boxesOnTargets(boxes, parsed.targets)
        var prefix = walk
        var curPlayer = simPlayer
        var curBoxes = boxes
        if remaining.isEmpty {
            return (curBoxes == parsed.targets) ? prefix : nil
        }
        for direction in remaining {
            guard let step = SokobanReplay.stepped(player: curPlayer, boxes: curBoxes, walls: parsed.walls,
                                                   rows: parsed.rows, cols: parsed.cols, direction: direction) else {
                return nil
            }
            prefix.append(direction)
            curPlayer = step.player
            curBoxes = step.boxes
            let on = SokobanReplay.boxesOnTargets(curBoxes, parsed.targets)
            if on >= startOn + 1 || curBoxes == parsed.targets {
                return prefix
            }
        }
        return nil
    }

    /// 先走参考解 O(1) 命中，否则在 `budget` 内做推箱 A*（目标：箱子就位数净增 +1 或通关）。
    static func plan(level number: Int, player: GridPoint, boxes: Set<GridPoint>, budget: TimeInterval = budget) -> SokobanHintOutcome {
        if let line = referenceLine(level: number, player: player, boxes: boxes), !line.isEmpty {
            return .sequence(line, fromReference: true)
        }
        return search(level: number, player: player, boxes: boxes, budget: budget)
    }

    static func search(level number: Int, player: GridPoint, boxes: Set<GridPoint>, budget: TimeInterval) -> SokobanHintOutcome {
        SokobanHintSearch.run(level: number, player: player, boxes: boxes, budget: budget)
    }
}
