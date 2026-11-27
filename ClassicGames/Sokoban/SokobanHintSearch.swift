import Foundation

/// 后台可用的推箱 A*：走位 BFS + 反向拉箱死格 + 2×2 冻结剪枝。
/// 目标不是通关，而是相对起点首次让「在目标上的箱子数」净增 +1，或直接通关。
enum SokobanHintSearch {
    static func run(level number: Int, player: GridPoint, boxes: Set<GridPoint>, budget: TimeInterval) -> SokobanHintOutcome {
        let parsed = SokobanLevel.parsed(number)
        let startOn = SokobanReplay.boxesOnTargets(boxes, parsed.targets)
        if boxes == parsed.targets { return .deadlock }
        let graph = Graph(parsed: parsed)
        if graph.isDead(boxes) { return .deadlock }
        let deadline = Date().addingTimeInterval(max(0.05, budget))
        let startKey = Key(boxes: boxes, player: player)
        var parent: [Key: (Key, SokobanDirection)] = [:]
        var seen: Set<Key> = [startKey]
        var queue: [Key] = [startKey]
        var head = 0
        var expanded = 0
        while head < queue.count {
            if Date() > deadline { return .timeout }
            let current = queue[head]
            head += 1
            expanded += 1
            let reach = graph.reachable(from: current.player, boxes: current.boxes)
            for box in current.boxes {
                for direction in SokobanDirection.all {
                    let stand = GridPoint(row: box.row - direction.rowDelta, col: box.col - direction.colDelta)
                    let dest = GridPoint(row: box.row + direction.rowDelta, col: box.col + direction.colDelta)
                    guard reach.contains(stand), graph.isFloor(dest), !current.boxes.contains(dest), !graph.deadSquares.contains(dest) else { continue }
                    var nextBoxes = current.boxes
                    nextBoxes.remove(box)
                    nextBoxes.insert(dest)
                    if graph.freeze2x2(nextBoxes, moved: dest) { continue }
                    let next = Key(boxes: nextBoxes, player: box)
                    if seen.contains(next) { continue }
                    seen.insert(next)
                    parent[next] = (current, direction)
                    let on = SokobanReplay.boxesOnTargets(nextBoxes, parsed.targets)
                    if on >= startOn + 1 || nextBoxes == parsed.targets {
                        return .sequence(reconstruct(parent: parent, from: startKey, to: next, startPlayer: player, graph: graph), fromReference: false)
                    }
                    queue.append(next)
                }
            }
        }
        return expanded == 0 ? .deadlock : .deadlock
    }

    private static func reconstruct(parent: [Key: (Key, SokobanDirection)], from start: Key, to goal: Key, startPlayer: GridPoint, graph: Graph) -> [SokobanDirection] {
        var pushes: [(Key, SokobanDirection)] = []
        var cursor = goal
        while cursor != start, let step = parent[cursor] {
            pushes.append(step)
            cursor = step.0
        }
        pushes.reverse()
        var player = startPlayer
        var boxes = start.boxes
        var moves: [SokobanDirection] = []
        for (before, direction) in pushes {
            // `before` is the parent key; the box being pushed is the cell the player walks to, then one more.
            // Recover the box cell: after the push, player stands on the vacated box cell, which is `parent.player` of the child... 
            // We stored parent[next] = (current, direction) and next.player = vacated box cell = `box`.
            // So the box starts at the child's player after... wait child.player is the vacated cell, which is the box origin.
            // We don't have the child in this pair. `before` is parent. After applying direction we get child.
            var applied = false
            for box in before.boxes {
                let stand = GridPoint(row: box.row - direction.rowDelta, col: box.col - direction.colDelta)
                let dest = GridPoint(row: box.row + direction.rowDelta, col: box.col + direction.colDelta)
                if before.boxes.contains(dest) { continue }
                if !graph.isFloor(dest) || !graph.isFloor(stand) { continue }
                guard let walk = SokobanReplay.shortestWalk(from: player, to: stand, boxes: boxes, walls: graph.walls, rows: graph.rows, cols: graph.cols) else { continue }
                moves.append(contentsOf: walk)
                moves.append(direction)
                boxes.remove(box)
                boxes.insert(dest)
                player = box
                applied = true
                break
            }
            if !applied { break }
        }
        return moves
    }

    private struct Key: Hashable {
        var boxes: Set<GridPoint>
        var player: GridPoint
    }

    private struct Graph {
        let rows: Int
        let cols: Int
        let walls: Set<GridPoint>
        let targets: Set<GridPoint>
        let deadSquares: Set<GridPoint>

        init(parsed: (rows: Int, cols: Int, walls: Set<GridPoint>, targets: Set<GridPoint>, boxes: Set<GridPoint>, player: GridPoint)) {
            rows = parsed.rows
            cols = parsed.cols
            walls = parsed.walls
            targets = parsed.targets
            deadSquares = Graph.computeDead(rows: parsed.rows, cols: parsed.cols, walls: parsed.walls, targets: parsed.targets)
        }

        func isFloor(_ p: GridPoint) -> Bool {
            p.row >= 0 && p.col >= 0 && p.row < rows && p.col < cols && !walls.contains(p)
        }

        func isDead(_ boxes: Set<GridPoint>) -> Bool {
            boxes.contains { !targets.contains($0) && deadSquares.contains($0) }
        }

        func reachable(from player: GridPoint, boxes: Set<GridPoint>) -> Set<GridPoint> {
            var seen: Set<GridPoint> = [player]
            var queue = [player]
            var head = 0
            while head < queue.count {
                let cur = queue[head]
                head += 1
                for direction in SokobanDirection.all {
                    let next = cur.moving(direction)
                    guard isFloor(next), !boxes.contains(next), !seen.contains(next) else { continue }
                    seen.insert(next)
                    queue.append(next)
                }
            }
            return seen
        }

        func freeze2x2(_ boxes: Set<GridPoint>, moved: GridPoint) -> Bool {
            func occupied(_ r: Int, _ c: Int) -> Bool {
                let p = GridPoint(row: r, col: c)
                if r < 0 || c < 0 || r >= rows || c >= cols || walls.contains(p) { return true }
                return boxes.contains(p)
            }
            func isBox(_ r: Int, _ c: Int) -> Bool {
                let p = GridPoint(row: r, col: c)
                guard r >= 0, c >= 0, r < rows, c < cols, !walls.contains(p) else { return false }
                return boxes.contains(p)
            }
            func offTarget(_ r: Int, _ c: Int) -> Bool {
                let p = GridPoint(row: r, col: c)
                return boxes.contains(p) && !targets.contains(p)
            }
            for dr in -1...0 {
                for dc in -1...0 {
                    let r0 = moved.row + dr, c0 = moved.col + dc
                    var solids = 0, boxCount = 0, off = false
                    for a in 0..<2 {
                        for b in 0..<2 {
                            if occupied(r0 + a, c0 + b) { solids += 1 }
                            if isBox(r0 + a, c0 + b) {
                                boxCount += 1
                                if offTarget(r0 + a, c0 + b) { off = true }
                            }
                        }
                    }
                    if boxCount >= 1 && solids == 4 && off { return true }
                }
            }
            return false
        }

        static func computeDead(rows: Int, cols: Int, walls: Set<GridPoint>, targets: Set<GridPoint>) -> Set<GridPoint> {
            func floor(_ p: GridPoint) -> Bool {
                p.row >= 0 && p.col >= 0 && p.row < rows && p.col < cols && !walls.contains(p)
            }
            var floors: [GridPoint] = []
            for r in 0..<rows {
                for c in 0..<cols {
                    let p = GridPoint(row: r, col: c)
                    if floor(p) { floors.append(p) }
                }
            }
            var live = Set<GridPoint>(targets)
            var seen = Set<String>()
            var queue: [(GridPoint, GridPoint)] = []
            for t in targets {
                for d in SokobanDirection.all {
                    let n = t.moving(d)
                    if floor(n) {
                        let key = "\(t.row),\(t.col)|\(n.row),\(n.col)"
                        if seen.insert(key).inserted {
                            queue.append((t, n))
                        }
                    }
                }
            }
            var head = 0
            while head < queue.count {
                let (box, player) = queue[head]
                head += 1
                live.insert(box)
                // flood player around box
                var reach: Set<GridPoint> = [player]
                var rq = [player]
                var rh = 0
                while rh < rq.count {
                    let u = rq[rh]
                    rh += 1
                    for d in SokobanDirection.all {
                        let v = u.moving(d)
                        if floor(v), v != box, reach.insert(v).inserted { rq.append(v) }
                    }
                }
                for d in SokobanDirection.all {
                    let from = GridPoint(row: box.row - d.rowDelta, col: box.col - d.colDelta)
                    let stand = GridPoint(row: from.row - d.rowDelta, col: from.col - d.colDelta)
                    guard floor(from), floor(stand), reach.contains(from) else { continue }
                    let key = "\(from.row),\(from.col)|\(stand.row),\(stand.col)"
                    if seen.insert(key).inserted {
                        queue.append((from, stand))
                    }
                }
            }
            var dead: Set<GridPoint> = []
            for f in floors where !live.contains(f) { dead.insert(f) }
            return dead
        }
    }
}

extension SokobanDirection {
    static let all: [SokobanDirection] = [.up, .down, .left, .right]
}
