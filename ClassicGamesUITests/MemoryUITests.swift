import XCTest

/// 翻牌记忆的模拟器检查：背面、配对、不配对翻回、第三张无效、结束，以及更差的次数不覆盖纪录。
final class MemoryUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-game", "memory"]
        app.launch()
    }

    func testMatchMismatchAndKeepFewerMoves() {
        openRow("memory")
        XCTAssertTrue(app.staticTexts["chrome.title"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.staticTexts["chrome.title"].label, "翻牌记忆", app.debugDescription)
        let state = app.descendants(matching: .any)["memory.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 5), app.debugDescription)
        let opening = waitState { $0.kinds.count == 16 && $0.up.isEmpty && $0.moves == 0 }
        XCTAssertEqual(opening.kinds.count, 16, opening.raw)
        XCTAssertEqual(Set(opening.kinds).count, 8, opening.raw)

        let different = unmatchedPair(in: opening.kinds)
        app.buttons["card.\(different.0)"].tap()
        app.buttons["card.\(different.1)"].tap()
        let pending = waitState { $0.moves == 1 && $0.resolving && $0.up.contains(different.0) && $0.up.contains(different.1) }
        XCTAssertEqual(pending.moves, 1, pending.raw)
        let third = opening.kinds.indices.first { $0 != different.0 && $0 != different.1 } ?? 0
        app.buttons["card.\(third)"].tap()
        let ignored = currentState()
        XCTAssertEqual(ignored.moves, 1, ignored.raw)
        XCTAssertFalse(ignored.up.contains(third), ignored.raw)

        let flipped = waitState(timeout: 3) { !$0.resolving && !$0.up.contains(different.0) && !$0.up.contains(different.1) }
        XCTAssertFalse(flipped.up.contains(different.0), flipped.raw)
        XCTAssertFalse(flipped.up.contains(different.1), flipped.raw)

        let matched = matchOnePair(in: flipped)
        XCTAssertEqual(matched.moves, 2, matched.raw)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let stayed = currentState()
        XCTAssertTrue(stayed.up.contains(matched.lastPair.0) && stayed.up.contains(matched.lastPair.1), stayed.raw)

        let finished = finishRemaining()
        XCTAssertTrue(finished.over, finished.raw)
        XCTAssertTrue(app.staticTexts["结束"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 \(finished.moves)")
        let best = finished.moves
        Screenshot.save("11-memory.png")

        app.buttons["chrome.restart"].tap()
        var second = waitState { $0.moves == 0 && !$0.over && $0.up.isEmpty && $0.kinds.count == 16 }
        second = mismatchOnce(from: second)
        second = mismatchOnce(from: second)
        let worse = finishRemaining()
        XCTAssertTrue(worse.over, worse.raw)
        XCTAssertGreaterThan(worse.moves, best, worse.raw)
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 \(best)")
    }

    /// 翻开一对相同图案，并确认它们保持打开。
    private func matchOnePair(in board: MemoryBoardState) -> (moves: Int, lastPair: (Int, Int), raw: String) {
        let pair = matchedPair(in: board.kinds, excluding: Set(board.up))
        app.buttons["card.\(pair.0)"].tap()
        app.buttons["card.\(pair.1)"].tap()
        let opened = waitState { $0.up.contains(pair.0) && $0.up.contains(pair.1) && $0.moves == board.moves + 1 }
        return (opened.moves, pair, opened.raw)
    }

    /// 把剩下的背面配完。
    private func finishRemaining() -> MemoryBoardState {
        var latest = currentState()
        var guardCount = 0
        while !latest.over, guardCount < 30 {
            if latest.resolving {
                latest = waitState(timeout: 2) { !$0.resolving }
                guardCount += 1
                continue
            }
            let faceDown = Set(latest.kinds.indices).subtracting(latest.up)
            let pair = matchedPair(in: latest.kinds, excluding: latest.up.reduce(into: Set()) { $0.insert($1) })
            XCTAssertTrue(faceDown.contains(pair.0) && faceDown.contains(pair.1), latest.raw)
            app.buttons["card.\(pair.0)"].tap()
            app.buttons["card.\(pair.1)"].tap()
            latest = waitState(timeout: 2) { $0.over || ($0.up.contains(pair.0) && $0.up.contains(pair.1)) }
            guardCount += 1
        }
        return latest
    }

    /// 翻开两张不同图案，等它们盖回去。
    private func mismatchOnce(from board: MemoryBoardState) -> MemoryBoardState {
        let faceDown = board.kinds.indices.filter { !board.up.contains($0) }
        var pair = (faceDown[0], faceDown[1])
        for left in faceDown {
            for right in faceDown where right > left && board.kinds[left] != board.kinds[right] {
                pair = (left, right)
            }
        }
        app.buttons["card.\(pair.0)"].tap()
        app.buttons["card.\(pair.1)"].tap()
        _ = waitState { $0.moves == board.moves + 1 }
        return waitState(timeout: 3) { !$0.resolving && !$0.up.contains(pair.0) && !$0.up.contains(pair.1) }
    }

    private func unmatchedPair(in kinds: [Int]) -> (Int, Int) {
        for left in kinds.indices {
            for right in kinds.indices where right > left && kinds[left] != kinds[right] {
                return (left, right)
            }
        }
        return (0, 1)
    }

    private func matchedPair(in kinds: [Int], excluding: Set<Int>) -> (Int, Int) {
        var seen: [Int: Int] = [:]
        for index in kinds.indices where !excluding.contains(index) {
            if let other = seen[kinds[index]] {
                return (other, index)
            }
            seen[kinds[index]] = index
        }
        return (0, 1)
    }

    private func openRow(_ id: String) {
        let button = app.buttons["home.row.\(id)"]
        let row = button.waitForExistence(timeout: 4) ? button : app.descendants(matching: .any)["home.row.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 8), id)
        row.tap()
    }

    private func currentState() -> MemoryBoardState {
        MemoryBoardState(app.descendants(matching: .any)["memory.state"].label)
    }

    private func waitState(timeout: TimeInterval = 3, where predicate: (MemoryBoardState) -> Bool) -> MemoryBoardState {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = currentState()
        while Date() < deadline {
            latest = currentState()
            if latest.raw.contains("kinds:"), predicate(latest) { return latest }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return latest
    }
}

/// 翻牌棋盘摘要。
struct MemoryBoardState {
    var raw: String
    var moves = 0
    var over = false
    var resolving = false
    var up: [Int] = []
    var kinds: [Int] = []

    init(_ raw: String) {
        self.raw = raw
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            switch pieces[0] {
            case "moves": moves = Int(pieces[1]) ?? 0
            case "over": over = pieces[1] == "true"
            case "resolving": resolving = pieces[1] == "true"
            case "up":
                up = pieces[1].isEmpty ? [] : pieces[1].split(separator: ",").map { Int($0) ?? 0 }
            case "kinds":
                kinds = pieces[1].split(separator: ",").map { Int($0) ?? 0 }
            default: break
            }
        }
    }
}
