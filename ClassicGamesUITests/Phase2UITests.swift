import XCTest

/// 阶段 2 总检查：新三款都能结束并重开，关掉 App 后纪录还在，阶段 1 的纪录不被清掉。
final class Phase2UITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testThreeNewGamesPersist() {
        for name in ["推箱子", "贪吃蛇", "打砖块", "2048", "扫雷", "翻牌记忆", "五子棋"] {
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 8), name)
        }
        let phase1 = [
            "home.best.sokoban",
            "home.best.snake",
            "home.best.breakout",
            "home.best.game2048"
        ].map { app.staticTexts[$0].label }

        finishMinesweeper()
        finishMemory()
        finishGomoku()

        scrollToTop()
        Screenshot.save("13-home-phase2.png")
        let minesweeper = reveal("home.best.minesweeper").label
        let memory = reveal("home.best.memory").label
        let gomoku = reveal("home.best.gomoku").label
        XCTAssertNotEqual(minesweeper, "最高 —", minesweeper)
        XCTAssertNotEqual(memory, "最高 —", memory)
        XCTAssertNotEqual(gomoku, "—", gomoku)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["经典小游戏"].waitForExistence(timeout: 8))
        let again = [
            "home.best.sokoban",
            "home.best.snake",
            "home.best.breakout",
            "home.best.game2048"
        ].map { app.staticTexts[$0].label }
        XCTAssertEqual(again, phase1)
        XCTAssertEqual(reveal("home.best.minesweeper").label, minesweeper)
        XCTAssertEqual(reveal("home.best.memory").label, memory)
        XCTAssertEqual(reveal("home.best.gomoku").label, gomoku)
    }

    /// 翻开全部安全格后重开再返回。
    private func finishMinesweeper() {
        openRow("minesweeper")
        app.buttons["mine.4.4"].tap()
        var board = waitMine { $0.status == "play" && $0.cells.contains { $0 != "#" } }
        var steps = 0
        while board.status != "won", steps < 90 {
            guard let next = board.cells.firstIndex(of: "#") else { break }
            app.buttons["mine.\(next / 9).\(next % 9)"].tap()
            board = waitMine(timeout: 2) { $0.status == "won" || $0.cells[next] != "#" }
            steps += 1
        }
        XCTAssertEqual(board.status, "won", board.raw)
        app.buttons["chrome.restart"].tap()
        _ = waitMine { $0.seconds == 0 && $0.cells.allSatisfy { $0 == "#" } }
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.minesweeper"].waitForExistence(timeout: 5))
    }

    /// 把八对配完后重开再返回。
    private func finishMemory() {
        openRow("memory")
        var board = waitMemory { $0.kinds.count == 16 }
        var steps = 0
        while !board.over, steps < 24 {
            if board.resolving {
                board = waitMemory(timeout: 2) { !$0.resolving }
                continue
            }
            let pair = pairMatch(in: board.kinds, excluding: Set(board.up))
            app.buttons["card.\(pair.0)"].tap()
            app.buttons["card.\(pair.1)"].tap()
            board = waitMemory(timeout: 2) { $0.over || ($0.up.contains(pair.0) && $0.up.contains(pair.1)) }
            steps += 1
        }
        XCTAssertTrue(board.over, board.raw)
        app.buttons["chrome.restart"].tap()
        _ = waitMemory { $0.moves == 0 && !$0.over && $0.up.isEmpty }
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.memory"].waitForExistence(timeout: 5))
    }

    /// 黑棋连成五子后重开再返回。
    private func finishGomoku() {
        openRow("gomoku")
        _ = waitGomoku { $0.cells.count == 225 }
        let black = [(7, 7), (7, 8), (7, 9), (7, 10), (7, 11)]
        let white = [(0, 0), (0, 1), (0, 2), (0, 3)]
        for index in 0..<5 {
            app.buttons["point.\(black[index].0).\(black[index].1)"].tap()
            if index < 4 {
                _ = waitGomoku { $0.turn == "white" }
                app.buttons["point.\(white[index].0).\(white[index].1)"].tap()
                _ = waitGomoku { $0.turn == "black" }
            }
        }
        let won = waitGomoku { $0.winner == "black" }
        XCTAssertEqual(won.winner, "black", won.raw)
        app.buttons["chrome.restart"].tap()
        _ = waitGomoku { $0.turn == "black" && $0.winner == "none" }
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.gomoku"].waitForExistence(timeout: 5))
    }

    private func pairMatch(in kinds: [Int], excluding: Set<Int>) -> (Int, Int) {
        var seen: [Int: Int] = [:]
        for index in kinds.indices where !excluding.contains(index) {
            if let other = seen[kinds[index]] { return (other, index) }
            seen[kinds[index]] = index
        }
        return (0, 1)
    }

    private func openRow(_ id: String) {
        let row = reveal("home.row.\(id)", kind: .button)
        if row.frame.maxY > app.frame.height - 8 {
            app.swipeUp()
        }
        row.tap()
    }

    /// 列表滑回顶部，方便截完整首页。
    private func scrollToTop() {
        for _ in 0..<4 {
            let title = app.staticTexts["home.title"]
            if title.exists, title.frame.minY > 0, title.frame.minY < 200 { return }
            app.swipeDown()
        }
    }

    /// 把还没出现在列表里的行滑进屏幕。
    private func reveal(_ identifier: String, kind: XCUIElement.ElementType = .staticText) -> XCUIElement {
        let query = kind == .button ? app.buttons[identifier] : app.staticTexts[identifier]
        var swipes = 0
        while !query.exists, swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(query.waitForExistence(timeout: 2), identifier)
        return query
    }

    private func waitMine(timeout: TimeInterval = 3, where predicate: (MineBoard) -> Bool) -> MineBoard {
        wait(timeout: timeout, read: { MineBoard(app.descendants(matching: .any)["minesweeper.state"].label) }, ready: { $0.raw.contains("cells:") }, predicate: predicate)
    }

    private func waitMemory(timeout: TimeInterval = 3, where predicate: (MemoryBoardState) -> Bool) -> MemoryBoardState {
        wait(timeout: timeout, read: { MemoryBoardState(app.descendants(matching: .any)["memory.state"].label) }, ready: { $0.raw.contains("kinds:") }, predicate: predicate)
    }

    private func waitGomoku(timeout: TimeInterval = 3, where predicate: (GomokuBoardState) -> Bool) -> GomokuBoardState {
        wait(timeout: timeout, read: { GomokuBoardState(app.descendants(matching: .any)["gomoku.state"].label) }, ready: { $0.raw.contains("cells:") }, predicate: predicate)
    }

    private func wait<State>(
        timeout: TimeInterval,
        read: () -> State,
        ready: (State) -> Bool,
        predicate: (State) -> Bool
    ) -> State {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = read()
        while Date() < deadline {
            latest = read()
            if ready(latest), predicate(latest) { return latest }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return latest
    }
}
