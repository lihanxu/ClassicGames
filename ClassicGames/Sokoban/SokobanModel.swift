import Foundation
import Observation

/// Picker compatibility facade. New records are versioned; old defaults are read
/// separately as historical data and are never promoted to these fair records.
@MainActor
enum SokobanRecords {
    static func best(level: Int) -> Int? { SokobanPersistence.shared.best(level: level) }
    static func clearedCount(from start: Int, through end: Int) -> Int {
        (start...end).filter { best(level: $0) != nil }.count
    }
    static func inProgressSummary() -> (level: Int, steps: Int)? {
        let persistence = SokobanPersistence.shared
        guard let level = persistence.recentLevel(),
              let game = try? persistence.game(level: level),
              let parsed = SokobanResume.parse(game.raw), parsed.won == false else { return nil }
        return (level, parsed.steps)
    }
    static func inProgressSteps(level: Int) -> Int? {
        guard let game = try? SokobanPersistence.shared.game(level: level),
              let parsed = SokobanResume.parse(game.raw), parsed.won == false, parsed.steps > 0 else { return nil }
        return parsed.steps
    }
    static func historicalBest(level: Int) -> Int? {
        SokobanPersistence.shared.historicalBest(level: level)
    }
}

enum SokobanVisitKind: String { case playing, completedNow, completedRevisit, scoreOnly, recovery }
enum SokobanCompletionKind: String { case first, newRecord, tie, normal, lastNotAll, campaign }
enum SokobanLaunchIntent {
    static var openPickerOnAppear = false
}

/// 推箱子这一局的状态。管当前关的走动、过关和换关，不改别的关的纪录。
@MainActor
@Observable
final class SokobanModel {
    private(set) var visitKind: SokobanVisitKind = .playing
    private(set) var completionEvents = 0
    private(set) var lastCompletionKind: SokobanCompletionKind?
    var hasBoard: Bool { visitKind != .scoreOnly && loadIssue.isEmpty }
    var isReadOnlyCompletion: Bool { visitKind == .completedRevisit || visitKind == .scoreOnly }
    var isCampaignComplete: Bool { persistence.isCampaignComplete() }
    var completionTitle: String {
        Self.completionTitle(isReadOnly: isReadOnlyCompletion, won: won, isCampaignComplete: isCampaignComplete)
    }
    static func completionTitle(isReadOnly: Bool, won: Bool, isCampaignComplete: Bool) -> String {
        if isReadOnly { return "已通关" }
        if !won { return "推箱子" }
        return isCampaignComplete ? "全部完成" : "过关"
    }
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
    /// 提示行。没有提示时是空字符串。
    private(set) var notice = ""
    /// 最近一次结算（含不发奖的看解通关）。开局、重开、换关时清空。
    private(set) var lastSettlement: SokobanSettlement?
    var coins: Int { persistence.wallet.coins }
    var undoItemCount: Int { persistence.wallet.undoItemCount }
    var hintItemCount: Int { persistence.wallet.hintItemCount }
    var parSteps: Int { SokobanReferenceSolutions.parSteps(levelId: levelNumber) }
    var bestStars: Int { persistence.bestStars(level: levelNumber) }
    var totalStars: Int { persistence.totalStars() }
    var claimedStarTier: Int { persistence.wallet.claimed(level: levelNumber) }
    var persistenceWallet: SokobanWallet { persistence.wallet }
    func persistenceBestStars(level: Int) -> Int { persistence.bestStars(level: level) }
    @discardableResult
    func purchase(_ item: SokobanShopItem) -> Bool { persistence.purchase(item) }
    func noticeHintFail(_ message: String) { notice = message }

    private var initialBoxes: Set<GridPoint> = []
    private var initialPlayer = GridPoint(row: 0, col: 0)
    private var undoStack: [SokobanFrame] = []
    private var redoStack: [SokobanFrame] = []
    private let persistence: SokobanPersistence
    private var recordEligible = true
    private(set) var loadIssue = ""
    var hasUnverifiedPredecessor: Bool { persistence.hasUnverifiedPredecessor(level: levelNumber) }
    private var unverifiedRecordNotice: String { "原存档已隔离保留，原纪录暂无法核实。" }
    var saveState: SokobanSaveState? { persistence.states[levelNumber] }
    var legacyMigration: SokobanMigrationResult { persistence.migrationResult }
    var historicalBest: Int? { persistence.historicalBest(level: levelNumber) }

    init(persistence: SokobanPersistence? = nil) {
        self.persistence = persistence ?? .shared
        self.persistence.migrateLegacy()
        load(self.persistence.recentLevel() ?? 1, persist: false)
    }

    @discardableResult
    func retrySave() -> Bool {
        let saved = persistence.retry(level: levelNumber)
        levelBest = persistence.best(level: levelNumber)
        if hasUnverifiedPredecessor { notice = unverifiedRecordNotice }
        return saved
    }

    /// 走一步。顶墙、顶箱子但箱子前方走不通，都不算步。过关后不再移动。成功才记入撤销。
    func move(_ direction: SokobanDirection) {
        _ = step(direction, countsOnWin: true)
    }

    /// 这一格能不能走（与 `move` 同一套规则，不改局面）。方向键连发撞墙/顶死时立刻停。
    func canMove(_ direction: SokobanDirection) -> Bool {
        guard !isReadOnlyCompletion, loadIssue.isEmpty, !won else { return false }
        let next = player.moving(direction)
        guard contains(next), !walls.contains(next) else { return false }
        if boxes.contains(next) {
            let beyond = next.moving(direction)
            guard contains(beyond), !walls.contains(beyond), !boxes.contains(beyond) else { return false }
        }
        return true
    }

    enum UndoRequest: Equatable { case undone, empty, needsShop, blocked }

    /// 产品撤销：有步才扣 1 张撤销券；0 步不扣；有步但券为 0 时交给兑换弹层。
    @discardableResult
    func requestUndo() -> UndoRequest {
        guard !isReadOnlyCompletion, loadIssue.isEmpty else { return .blocked }
        guard !undoStack.isEmpty, steps > 0 else { return .empty }
        guard persistence.wallet.undoItemCount > 0 else { return .needsShop }
        guard persistence.consumeUndoTicket() else { return .needsShop }
        return undo() ? .undone : .blocked
    }

    /// 确认已有可执行提示序列后扣 1 个提示道具。后续手动撤销不退。
    @discardableResult
    func beginHintPlayback(_ moves: [SokobanDirection]) -> Bool {
        guard !moves.isEmpty, !isReadOnlyCompletion, loadIssue.isEmpty, !won else { return false }
        return persistence.consumeHintItem()
    }

    /// 退回上一格。栈空或已经是开局则不变。不改纪录，也不换关。
    @discardableResult
    func undo() -> Bool {
        guard !isReadOnlyCompletion, loadIssue.isEmpty, let previous = undoStack.popLast() else { return false }
        redoStack.append(currentFrame)
        restore(previous)
        persist()
        notice = ""
        return true
    }

    /// 把刚撤销的那一格放回来。没有可重做的步则不变。
    @discardableResult
    func redo() -> Bool {
        guard !isReadOnlyCompletion, loadIssue.isEmpty, let next = redoStack.popLast() else { return false }
        undoStack.append(currentFrame)
        restore(next)
        persist()
        notice = ""
        return true
    }

    /// 成功的一格。先记下走之前的局面，再改人和箱子。过关且参加比较时才写本关纪录。
    @discardableResult
    private func step(_ direction: SokobanDirection, countsOnWin: Bool) -> Bool {
        guard !isReadOnlyCompletion, loadIssue.isEmpty, !won else { return false }
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
            let priorBest = levelBest
            won = true
            visitKind = .completedNow
            completionEvents += 1
            winCounts = countsOnWin && recordEligible
            persist()
            if isCampaignComplete { lastCompletionKind = .campaign }
            else if levelNumber == SokobanLevels.count { lastCompletionKind = .lastNotAll }
            else if priorBest == nil { lastCompletionKind = .first }
            else if steps < priorBest! { lastCompletionKind = .newRecord }
            else if steps == priorBest! { lastCompletionKind = .tie }
            else { lastCompletionKind = .normal }
            lastSettlement = persistence.applyClearReward(level: levelNumber, steps: steps, counts: winCounts)
        } else {
            persist()
        }
        notice = ""
        return true
    }

    #if SWIFT_PACKAGE
    /// 按官方解走出下一步。没有解、已经偏离或这一步走不通时，局面不变。
    func hint() -> SokobanStep? {
        guard !isReadOnlyCompletion, loadIssue.isEmpty else { return nil }
        guard let solution = SokobanSolutions.directions(level: levelNumber) else {
            notice = "这一关没有解"
            return nil
        }
        guard !won else { return nil }
        guard let taken = historyDirections(), solution.starts(with: taken), taken.count < solution.count else {
            notice = takenCountIsPrefix(of: solution) ? "这一步没有提示" : "已偏离解法"
            return nil
        }
        let direction = solution[taken.count]
        let boxesBefore = boxes
        recordEligible = false
        guard step(direction, countsOnWin: true) else {
            notice = "这一步没有提示"
            return nil
        }
        return SokobanStep(direction: direction, pushed: boxes != boxesBefore)
    }

    /// 回到这一关开局再逐格走出官方解。没有解串时局面不变。看解的过关不写纪录。
    func showSolution() -> SokobanPlayback {
        guard !isReadOnlyCompletion, loadIssue.isEmpty else {
            return SokobanPlayback(steps: [], player: player, boxes: boxes, stepsAtStart: steps)
        }
        guard let solution = SokobanSolutions.directions(level: levelNumber) else {
            notice = "这一关没有解"
            return SokobanPlayback(steps: [], player: player, boxes: boxes, stepsAtStart: steps)
        }
        restart()
        recordEligible = false
        let originPlayer = player
        let originBoxes = boxes
        var taken: [SokobanStep] = []
        for direction in solution {
            if won { break }
            let boxesBefore = boxes
            guard step(direction, countsOnWin: false) else {
                notice = "解法走不通"
                return SokobanPlayback(steps: taken, player: originPlayer, boxes: originBoxes, stepsAtStart: 0)
            }
            taken.append(SokobanStep(direction: direction, pushed: boxes != boxesBefore))
        }
        if !won {
            notice = "解法没有过关"
        }
        return SokobanPlayback(steps: taken, player: originPlayer, boxes: originBoxes, stepsAtStart: 0)
    }

    /// 已经走出的方向。有一格对不上相邻方向，就当作偏离。
    private func historyDirections() -> [SokobanDirection]? {
        let players = undoStack.map(\.player) + [player]
        guard players.count >= 2 else { return [] }
        var directions: [SokobanDirection] = []
        for pair in zip(players, players.dropFirst()) {
            guard let direction = SokobanDirection.between(pair.0, pair.1) else { return nil }
            directions.append(direction)
        }
        return directions
    }

    /// 当前步数还落在解的前缀上，只是没有下一步可走。
    private func takenCountIsPrefix(of solution: [SokobanDirection]) -> Bool {
        guard let taken = historyDirections() else { return false }
        return solution.starts(with: taken)
    }

    #endif

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
        visitKind = frame.won ? .completedNow : .playing
    }

    /// 点到一格。先走不推箱子的最短路；没有这种路才沿直线推开挡路的箱子。走不到就完全不变。
    #if SWIFT_PACKAGE
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

    #endif

    /// 人和箱子回到这一关的原位，步数归零。不改已经写下的纪录，也不换关。这一关的撤销和重做都空。
    func restart() {
        do { try persistence.prepareRestart(level: levelNumber) }
        catch { notice = "重开失败，当前局面已保留"; return }
        loadIssue = ""
        visitKind = .playing
        recordEligible = true
        boxes = initialBoxes
        player = initialPlayer
        steps = 0
        won = false
        facing = .down
        winCounts = false
        lastCompletionKind = nil
        lastSettlement = nil
        undoStack.removeAll()
        redoStack.removeAll()
        notice = ""
        persist()
    }

    /// 打开该关的独立存档；失败写入的最新局面仍由持久化层保留。
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
        notice = ""
        loadIssue = ""
        recordEligible = true
        visitKind = .playing
        lastCompletionKind = nil
        lastSettlement = nil
        levelBest = persistence.best(level: clamped)
        do {
            if let saved = try persistence.game(level: clamped) {
                if saved.recordOnly == true {
                    visitKind = .scoreOnly
                } else {
                    guard applyResume(saved.raw) else { throw SokobanSaveError.corrupt }
                    if won { visitKind = .completedRevisit }
                }
                recordEligible = saved.eligible
                if saved.recordRecoveryPending == true { notice = unverifiedRecordNotice }
            }
            // Reopening terminal/score-only data is a read, not another win or save.
            if shouldPersist && !isReadOnlyCompletion { persist() }
        } catch { loadIssue = String(describing: error); visitKind = .recovery }
    }

    /// 过关后进入下一关。还没过关，或已经是最后一关，就停在原地。
    func advance() {
        guard won, visitKind == .completedNow, levelNumber < SokobanLevels.count else { return }
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

    /// 将完整历史交给分关版本文件存档；合法且公平的通关同时更新该版本最少步数。
    /// 不改旧版 UserDefaults 原档、历史纪录或其他游戏纪录。
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
        persistence.save(level: levelNumber, raw: text, eligible: recordEligible)
        levelBest = persistence.best(level: levelNumber)
        if hasUnverifiedPredecessor { notice = unverifiedRecordNotice }
    }

    /// 只恢复身份与完整历史均已验证的新槽；拒绝时阻止输入，不静默覆盖。
    private func applyResume(_ raw: String) -> Bool {
        guard let parsed = SokobanPersistence.validated(raw, level: levelNumber) else { return false }
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
        levelBest = persistence.best(level: parsed.level)
        return true
    }

    private func contains(_ point: GridPoint) -> Bool {
        point.row >= 0 && point.col >= 0 && point.row < rows && point.col < cols
    }
}

/// 走之前的局面。过关标记只说明这一帧是否已经过关，以及这次过关要不要参加纪录比较。
struct SokobanFrame {
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

/// 已经写入模型的一串步骤，以及播放前的起点。看解从这一关开局播。
struct SokobanPlayback {
    var steps: [SokobanStep]
    var player: GridPoint
    var boxes: Set<GridPoint>
    var stepsAtStart: Int
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
enum SokobanResume {
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
            guard points.insert(point).inserted else { return nil }
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
