import XCTest

/// 第 1 关的开局、最短走法和多走两步的走法。步数来自这一关的最短解。
enum SokobanMoves {
    static let start = "level:1;player:3,2;boxes:3,1|4,3;steps:0;won:false;face:down"
    static let win = "level:1;player:2,2;boxes:1,2|3,1;steps:33;won:true;face:up"
    static let longWin = "level:1;player:2,2;boxes:1,2|3,1;steps:35;won:true;face:up"
    static let level2 = "level:2;player:2,3;boxes:3,2|3,3|4,3;steps:0;won:false;face:down"
    static let level20 = "level:20;player:2,3;boxes:2,4|2,5;steps:0;won:false;face:down"
    static let short = [
        "pad.down", "pad.left", "pad.up", "pad.right", "pad.right", "pad.right",
        "pad.down", "pad.left", "pad.up", "pad.left", "pad.left", "pad.down",
        "pad.down", "pad.right", "pad.up", "pad.left", "pad.up", "pad.right",
        "pad.up", "pad.up", "pad.left", "pad.down", "pad.right", "pad.down",
        "pad.down", "pad.right", "pad.right", "pad.up", "pad.left", "pad.down",
        "pad.left", "pad.up", "pad.up"
    ]
    /// 先向上走一格再走回来，然后沿最短解过关，比纪录多 2 步。
    static let long = ["pad.up", "pad.down"] + short
}

/// 推箱子的模拟器检查：过关、纪录、选关、重开、返回。
final class SokobanUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // 只清推箱子纪录，避免这一局沿用上次留下的步数。
        app.launchArguments = ["-ui-testing", "-reset-game", "sokoban"]
        app.launch()
    }

    /// 第 1 关能过关，重开回到这一关，返回后首页留着较少的步数。
    func testClearRestartAndReturn() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["sokoban.level"].label, "第 1 关 / 100")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")

        app.buttons["pad.left"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 33")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 33")

        let locked = board.value as? String
        play(["pad.up", "pad.left"])
        XCTAssertEqual(board.value as? String, locked)

        app.buttons["chrome.restart"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertFalse(app.staticTexts["过关"].exists)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")

        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.best.sokoban"].label, "最高 33")
    }

    /// 图标能分开，第 20 关能打开，较差步数不覆盖，关掉再打开纪录还在。
    func testIconsLevelsAndScores() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["sokoban.levels"].value as? String, "100")
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        Screenshot.save("18-sokoban-icons.png")

        app.buttons["pad.left"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 0")

        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 2))
        let locked = board.value as? String
        play(["pad.up", "pad.down", "pad.left", "pad.right"])
        board.swipeUp()
        XCTAssertEqual(board.value as? String, locked)

        app.buttons["chrome.restart"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")

        play(SokobanMoves.long)
        XCTAssertEqual(board.value as? String, SokobanMoves.longWin)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 35")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 33")

        app.buttons["sokoban.next"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        XCTAssertEqual(app.staticTexts["sokoban.level"].label, "第 2 关 / 100")
        XCTAssertFalse(app.staticTexts["过关"].exists)

        app.buttons["sokoban.levels"].tap()
        let level20 = app.buttons["sokoban.pick.20"]
        XCTAssertTrue(level20.waitForExistence(timeout: 5))
        level20.tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level20)
        XCTAssertEqual(app.staticTexts["sokoban.level"].label, "第 20 关 / 100")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 33")
        Screenshot.save("19-sokoban-levels.png")

        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.best.sokoban"].label, "最高 33")

        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["home.best.sokoban"].label, "最高 33")
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, SokobanMoves.level20)
        XCTAssertEqual(app.staticTexts["sokoban.level"].label, "第 20 关 / 100")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 33")
        app.buttons["sokoban.levels"].tap()
        XCTAssertTrue(app.staticTexts["sokoban.cleared.1"].waitForExistence(timeout: 5))
        app.buttons["sokoban.pick.1"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        XCTAssertTrue(app.buttons["chrome.back"].isHittable)
    }

    /// 成功的走或推才改朝向。顶墙、过关后的按键、重开和换关都回到或停在该有的方向。
    func testFacingFollowsSuccessfulMoves() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        app.buttons["pad.left"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        app.buttons["pad.down"].tap()
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")
        app.buttons["pad.right"].tap()
        XCTAssertEqual(board.value as? String, "level:1;player:4,3;boxes:3,1|4,4;steps:2;won:false;face:right")
        app.buttons["pad.up"].tap()
        XCTAssertEqual(board.value as? String, "level:1;player:3,3;boxes:3,1|4,4;steps:3;won:false;face:up")
        app.buttons["pad.left"].tap()
        XCTAssertEqual(board.value as? String, "level:1;player:3,2;boxes:3,1|4,4;steps:4;won:false;face:left")

        app.buttons["chrome.restart"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertFalse(app.buttons["sokoban.next"].exists)

        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        let locked = board.value as? String
        play(["pad.left", "pad.right", "pad.up", "pad.down"])
        XCTAssertEqual(board.value as? String, locked)

        app.buttons["sokoban.next"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        app.buttons["sokoban.levels"].tap()
        let level20 = app.buttons["sokoban.pick.20"]
        XCTAssertTrue(level20.waitForExistence(timeout: 5))
        level20.tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level20)
    }

    /// 单指滑动只走一格，短拖不动。大图停在 28pt，单指也不平移棋盘。
    func testSwipeMovesOneCellWithoutScrolling() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sokoban.pan"].label, "off")

        let player = cellCoordinate(board, row: 3, col: 2)
        player.press(forDuration: 0.05, thenDragTo: player.withOffset(CGVector(dx: 12, dy: 0)))
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["sokoban.pan"].label, "off")

        let center = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 0, dy: 80)))
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "walk:140")
        XCTAssertEqual(app.staticTexts["sokoban.pan"].label, "off")

        app.buttons["sokoban.levels"].tap()
        let level99 = app.buttons["sokoban.pick.99"]
        var swipes = 0
        while !level99.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(level99.isHittable)
        level99.tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue((board.value as? String)?.hasPrefix("level:99;") == true)
        XCTAssertEqual(app.staticTexts["sokoban.pan"].label, "on:0:0")

        let before = board.value as? String
        board.swipeLeft()
        let after = board.value as? String
        XCTAssertNotEqual(before, nil)
        XCTAssertTrue(after == before || stepsAdvanced(from: before, to: after))
        XCTAssertEqual(app.staticTexts["sokoban.pan"].label, "on:0:0")
    }

    /// 点空地走到那一格。点墙、点箱子不变。有不推箱子的路时不改去推，哪怕绕得更远。
    func testTapFloorWalksToThatCell() {
        XCTAssertTrue(app.staticTexts["方向键、滑动或点空地，把箱子全部推到目标。"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        tapCell(board, row: 0, col: 0)
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        tapCell(board, row: 3, col: 1)
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        tapCell(board, row: 3, col: 2)
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        tapCell(board, row: 4, col: 2)
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")

        app.buttons["chrome.restart"].tap()
        tapCell(board, row: 3, col: 4)
        XCTAssertEqual(board.value as? String, "level:1;player:3,4;boxes:3,1|4,3;steps:2;won:false;face:right")

        tapCell(board, row: 4, col: 4)
        XCTAssertEqual(board.value as? String, "level:1;player:4,4;boxes:3,1|4,3;steps:3;won:false;face:down")
        tapCell(board, row: 4, col: 2)
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:7;won:false;face:down")
    }

    /// 点地之后每一格都留下自己的走或推时长，中间不再加一段。模型已经停在终局。
    func testPathPlaysEachCell() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))

        tapCell(board, row: 4, col: 2)
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "path:walk:140")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")

        app.buttons["chrome.restart"].tap()
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "idle")
        tapCell(board, row: 3, col: 4)
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "path:walk:140+walk:140")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 2")

        tapCell(board, row: 4, col: 4)
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "path:walk:140")
        tapCell(board, row: 4, col: 2)
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "path:walk:140+walk:140+walk:140+walk:140")
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:7;won:false;face:down")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 7")
    }

    /// 撤销和重做各退回或前进一步。点地的每一格都能单独撤，过关后也能撤，纪录不改，换关撤不回去。
    func testUndoAndRedoStayOnThisLevel() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))

        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        app.buttons["pad.down"].tap()
        let oneStep = "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down"
        XCTAssertEqual(board.value as? String, oneStep)
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "idle")
        app.buttons["sokoban.redo"].tap()
        XCTAssertEqual(board.value as? String, oneStep)
        app.buttons["sokoban.undo"].tap()
        app.buttons["pad.right"].tap()
        let steppedAside = "level:1;player:3,3;boxes:3,1|4,3;steps:1;won:false;face:right"
        XCTAssertEqual(board.value as? String, steppedAside)
        app.buttons["sokoban.redo"].tap()
        XCTAssertEqual(board.value as? String, steppedAside)

        app.buttons["chrome.restart"].tap()
        tapCell(board, row: 3, col: 4)
        XCTAssertEqual(board.value as? String, "level:1;player:3,4;boxes:3,1|4,3;steps:2;won:false;face:right")
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, steppedAside)
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        app.buttons["sokoban.redo"].tap()
        XCTAssertEqual(board.value as? String, steppedAside)

        app.buttons["chrome.restart"].tap()
        app.buttons["pad.down"].tap()
        app.buttons["chrome.restart"].tap()
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 32")
        XCTAssertFalse(app.staticTexts["sokoban.win"].exists)
        XCTAssertFalse(app.buttons["sokoban.next"].exists)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        app.buttons["sokoban.redo"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        app.buttons["sokoban.next"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
    }

    /// 提示和看解只改当前关。没有解串时局面不变。看解的过关不写纪录。
    func testHintAndSolutionStayOnThisLevel() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sokoban.notice"].label, "")

        app.buttons["sokoban.hint"].tap()
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "walk:140")
        XCTAssertEqual(app.staticTexts["sokoban.notice"].label, "")

        app.buttons["pad.up"].tap()
        let diverged = board.value as? String
        app.buttons["sokoban.hint"].tap()
        XCTAssertEqual(board.value as? String, diverged)
        XCTAssertEqual(app.staticTexts["sokoban.notice"].label, "已偏离解法")
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(app.staticTexts["sokoban.notice"].label, "")

        app.buttons["sokoban.levels"].tap()
        let level2 = app.buttons["sokoban.pick.2"]
        XCTAssertTrue(level2.waitForExistence(timeout: 5))
        level2.tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        app.buttons["sokoban.hint"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        XCTAssertEqual(app.staticTexts["sokoban.notice"].label, "这一关没有解")
        app.buttons["sokoban.solution"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        XCTAssertEqual(app.staticTexts["sokoban.notice"].label, "这一关没有解")

        app.buttons["sokoban.levels"].tap()
        let level1 = app.buttons["sokoban.pick.1"]
        XCTAssertTrue(level1.waitForExistence(timeout: 5))
        level1.tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["sokoban.notice"].label, "")
        app.buttons["sokoban.solution"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 —")
        XCTAssertEqual(app.staticTexts["sokoban.notice"].label, "")
        let motion = app.staticTexts["sokoban.motion"].label
        XCTAssertTrue(motion.hasPrefix("path:"))
        XCTAssertEqual(motion.split(separator: "+").count, 33)
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 32")
        XCTAssertFalse(app.staticTexts["sokoban.win"].exists)
        XCTAssertTrue((board.value as? String)?.contains("level:1;") == true)
    }

    /// 返回首页或杀掉再打开，还停在这一关这一步，撤销栈也在。恢复不改纪录。
    func testResumeKeepsThisStep() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        app.buttons["pad.down"].tap()
        app.buttons["pad.right"].tap()
        app.buttons["sokoban.undo"].tap()
        let oneStep = "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down"
        XCTAssertEqual(board.value as? String, oneStep)

        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, oneStep)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        app.buttons["sokoban.redo"].tap()
        XCTAssertEqual(board.value as? String, "level:1;player:4,3;boxes:3,1|4,4;steps:2;won:false;face:right")
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, oneStep)

        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["home.best.sokoban"].label, "最高 —")
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, oneStep)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        app.buttons["sokoban.levels"].tap()
        let level2 = app.buttons["sokoban.pick.2"]
        XCTAssertTrue(level2.waitForExistence(timeout: 5))
        level2.tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
    }

    /// 关号、朝向或箱子数量不对时改回第 1 关开局。恢复一份过关局面也不重写纪录。
    func testBadResumeStartsLevelOne() {
        let won = "1|2,2|1,2+3,1|33|up|1|1||"
        launch(resume: won)
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 —")

        launch(resume: "1|4,2|3,1|1|down|0|0||")
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        launch(resume: "1|4,2|3,1+4,3|1|sideways|0|0||")
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
    }

    /// 顶墙、走出一格、推动一格各自留下时长。过关后的按键不再顶墙，重开清掉这段。
    func testWalkPushAndWallTransitions() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "idle")
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        app.buttons["pad.left"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 0")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "bump:120")

        app.buttons["pad.down"].tap()
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "walk:140")

        app.buttons["pad.right"].tap()
        XCTAssertEqual(board.value as? String, "level:1;player:4,3;boxes:3,1|4,4;steps:2;won:false;face:right")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 2")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "push:180")

        app.buttons["chrome.restart"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "idle")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 0")

        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 33")
        let settled = app.staticTexts["sokoban.motion"].label
        XCTAssertTrue(settled == "walk:140" || settled == "push:180")
        let locked = board.value as? String
        play(["pad.left", "pad.right", "pad.up", "pad.down"])
        XCTAssertEqual(board.value as? String, locked)
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, settled)
    }

    /// 选关能看出已过和五组难度。当前关描边还在，点编号仍进入该关开局。
    func testClearedMarksAndDifficultyGroups() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        app.buttons["pad.left"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 0")

        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 2))

        app.buttons["sokoban.levels"].tap()
        let intro = app.staticTexts["sokoban.group.入门"]
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        XCTAssertEqual(intro.label, "入门 1/20")
        XCTAssertFalse(app.buttons["sokoban.group.入门"].exists)
        let credit = app.staticTexts["sokoban.credit"]
        XCTAssertTrue(credit.exists)
        XCTAssertLessThan(credit.frame.maxY, intro.frame.minY)
        XCTAssertEqual(app.staticTexts["sokoban.group.初级"].label, "初级 0/20")
        XCTAssertTrue(app.staticTexts["sokoban.cleared.1"].exists)
        XCTAssertFalse(app.staticTexts["sokoban.cleared.2"].exists)
        XCTAssertTrue(app.buttons["sokoban.pick.1"].exists)
        let level20 = app.buttons["sokoban.pick.20"]
        XCTAssertTrue(level20.waitForExistence(timeout: 2))
        level20.tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level20)
        XCTAssertEqual(app.staticTexts["sokoban.level"].label, "第 20 关 / 100")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")

        app.buttons["chrome.restart"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level20)
        app.buttons["sokoban.levels"].tap()
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        XCTAssertEqual(intro.label, "入门 1/20")
        XCTAssertTrue(app.staticTexts["sokoban.cleared.1"].exists)
        app.buttons["sokoban.pick.1"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")

        app.buttons["sokoban.levels"].tap()
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        let level100 = app.buttons["sokoban.pick.100"]
        var swipes = 0
        while !level100.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(level100.isHittable)
        XCTAssertEqual(app.staticTexts["sokoban.group.挑战"].label, "挑战 0/20")
        level100.tap()
        XCTAssertEqual(app.staticTexts["sokoban.level"].label, "第 100 关 / 100")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        XCTAssertFalse(app.staticTexts["过关"].exists)

        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.best.sokoban"].label, "最高 33")
    }

    /// 进入推箱子后背景循环开始；走一步有声，顶墙和推动不加这次计数；回首页和其他七款都停。
    func testBackgroundStartsOnEnterAndStopsOnLeave() {
        launch(hearing: "audible")
        waitAudio(["bgm": "stopped", "engine": "0", "steps": "0", "wins": "0"])
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        waitAudio(["bgm": "playing", "engine": "1", "steps": "0", "wins": "0"])

        app.buttons["pad.left"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        waitAudio(["bgm": "playing", "engine": "1", "steps": "0"])

        app.buttons["pad.down"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        waitAudio(["steps": "1"])

        app.buttons["pad.right"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 2")
        waitAudio(["bgm": "playing", "engine": "1", "steps": "1", "wins": "0"])

        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        waitAudio(["bgm": "stopped", "engine": "0", "steps": "1"])

        for identifier in ["snake", "breakout", "game2048", "minesweeper", "memory", "gomoku", "platformer"] {
            openHomeRow(identifier)
            XCTAssertTrue(app.buttons["chrome.back"].waitForExistence(timeout: 5))
            waitAudio(["bgm": "stopped", "engine": "0"])
            app.buttons["chrome.back"].tap()
            XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
            waitAudio(["bgm": "stopped", "engine": "0"])
        }
    }

    /// 过关短乐在走完第 1 关后发出。这一关最短解有 25 声脚步，推动不加。
    func testClearPlaysShortTune() {
        launch(hearing: "audible")
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 2))
        waitAudio(["bgm": "playing", "engine": "1", "steps": "25", "wins": "1"], timeout: 2)
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        waitAudio(["bgm": "stopped", "engine": "0"])
    }

    /// 系统静音时背景循环不送出，走步和过关也不计数。
    func testSilentEmitsNothing() {
        launch(hearing: "silent")
        waitAudio(["bgm": "stopped", "engine": "0"])
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        waitAudio(["bgm": "silent", "engine": "0", "steps": "0", "wins": "0"])

        app.buttons["pad.left"].tap()
        app.buttons["pad.down"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        waitAudio(["bgm": "silent", "engine": "0", "steps": "0", "wins": "0"])

        app.buttons["chrome.restart"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        waitAudio(["bgm": "silent", "engine": "0", "steps": "0", "wins": "0"])

        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        waitAudio(["bgm": "stopped", "engine": "0", "steps": "0", "wins": "0"])
    }

    /// 上线完成度：从首页走到过关、下一关、纪录和静音，一次点完。
    func testReleaseChecklist() {
        launch(hearing: "audible")
        waitAudio(["bgm": "stopped", "engine": "0"])
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        waitAudio(["bgm": "playing", "engine": "1", "steps": "0", "wins": "0"])

        app.buttons["sokoban.levels"].tap()
        XCTAssertTrue(app.staticTexts["sokoban.credit"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sokoban.group.入门"].label, "入门 0/20")
        app.buttons["sokoban.pick.1"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        app.buttons["pad.left"].tap()
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "bump:120")
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        app.buttons["pad.down"].tap()
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "walk:140")
        waitAudio(["steps": "1", "wins": "0"])
        app.buttons["pad.right"].tap()
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "push:180")
        XCTAssertEqual(board.value as? String, "level:1;player:4,3;boxes:3,1|4,4;steps:2;won:false;face:right")
        app.buttons["sokoban.undo"].tap()
        app.buttons["sokoban.redo"].tap()
        XCTAssertEqual(board.value as? String, "level:1;player:4,3;boxes:3,1|4,4;steps:2;won:false;face:right")

        app.buttons["chrome.restart"].tap()
        tapCell(board, row: 3, col: 4)
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "path:walk:140+walk:140")
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        app.buttons["sokoban.redo"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 2")

        app.buttons["chrome.restart"].tap()
        app.buttons["sokoban.hint"].tap()
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "walk:140")

        app.buttons["sokoban.levels"].tap()
        let level2 = app.buttons["sokoban.pick.2"]
        XCTAssertTrue(level2.waitForExistence(timeout: 5))
        level2.tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        app.buttons["sokoban.hint"].tap()
        app.buttons["sokoban.solution"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        XCTAssertEqual(app.staticTexts["sokoban.notice"].label, "这一关没有解")

        app.buttons["sokoban.levels"].tap()
        let level1 = app.buttons["sokoban.pick.1"]
        XCTAssertTrue(level1.waitForExistence(timeout: 5))
        level1.tap()
        app.buttons["pad.down"].tap()
        let parked = "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down"
        XCTAssertEqual(board.value as? String, parked)
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        app.buttons["home.row.sokoban"].tap()
        XCTAssertEqual(board.value as? String, parked)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, parked)
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 33")
        let locked = board.value as? String
        app.buttons["pad.up"].tap()
        XCTAssertEqual(board.value as? String, locked)

        app.buttons["chrome.restart"].tap()
        play(SokobanMoves.long)
        XCTAssertEqual(board.value as? String, SokobanMoves.longWin)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        app.buttons["sokoban.next"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        app.buttons["chrome.restart"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.best.sokoban"].label, "最高 33")

        launch(hearing: "silent")
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        app.buttons["pad.down"].tap()
        waitAudio(["bgm": "silent", "engine": "0", "steps": "0", "wins": "0"])
    }

    /// 用固定的听感重新打开。正式游玩不带这个参数。
    private func launch(hearing: String) {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-game", "sokoban", "-sokoban-hearing", hearing]
        app.launch()
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
    }

    /// 用一份写好的中途局面重新打开。坏局面由模型改回第 1 关。
    private func launch(resume: String) {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-game", "sokoban", "-sokoban-resume", resume]
        app.launch()
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
    }

    /// 首页某一行。列表比屏幕高时先滚到能点。
    private func openHomeRow(_ identifier: String) {
        let row = app.buttons["home.row.\(identifier)"]
        if !(row.exists && row.isHittable) {
            app.swipeDown()
            app.swipeDown()
        }
        if !(row.exists && row.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
    }

    /// 等到 `sokoban.audio` 里的字段和期望一致。
    private func waitAudio(_ expected: [String: String], timeout: TimeInterval = 3) {
        XCTAssertTrue(app.staticTexts["sokoban.audio"].waitForExistence(timeout: 5), "找不到推箱子声音状态")
        let deadline = Date().addingTimeInterval(timeout)
        var last = ""
        while Date() < deadline {
            last = app.staticTexts["sokoban.audio"].label
            let fields = audioFields(last)
            if expected.allSatisfy({ fields[$0.key] == $0.value }) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("音频状态是 \(last)，期望 \(expected)")
    }

    /// `bgm:playing;engine:1;steps:0;wins:0` 拆成字段。
    private func audioFields(_ token: String) -> [String: String] {
        var fields: [String: String] = [:]
        for part in token.split(separator: ";") {
            let pair = part.split(separator: ":", maxSplits: 1)
            if pair.count == 2 {
                fields[String(pair[0])] = String(pair[1])
            }
        }
        return fields
    }

    /// 点到棋盘上的一格。缝和格子尺寸从 `sokoban.layout` 读。
    private func tapCell(_ board: XCUIElement, row: Int, col: Int) {
        cellCoordinate(board, row: row, col: col).tap()
    }

    /// 某一格的中心。布局没出来时会点在棋盘左上角。
    private func cellCoordinate(_ board: XCUIElement, row: Int, col: Int) -> XCUICoordinate {
        let fields = audioFields(app.staticTexts["sokoban.layout"].label)
        let cell = Double(fields["cell"] ?? "") ?? 0
        let originX = Double(fields["ox"] ?? "") ?? 0
        let originY = Double(fields["oy"] ?? "") ?? 0
        let gutter = Double(fields["gutter"] ?? "") ?? 0
        let x = originX + (cell + gutter) * Double(col) + cell / 2
        let y = originY + (cell + gutter) * Double(row) + cell / 2
        let topLeft = board.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        return topLeft.withOffset(CGVector(dx: x, dy: y))
    }

    /// 大图上单指滑动最多让步数加 1，不能连走，也不能换关。
    private func stepsAdvanced(from before: String?, to after: String?) -> Bool {
        guard let before, let after else { return false }
        let oldFields = audioFields(before)
        let newFields = audioFields(after)
        guard oldFields["level"] == newFields["level"],
              let oldSteps = oldFields["steps"].flatMap(Int.init),
              let newSteps = newFields["steps"].flatMap(Int.init) else { return false }
        return newSteps == oldSteps + 1
    }

    /// 方向键按顺序点。每一步都进同一个移动方法。
    private func play(_ moves: [String]) {
        for move in moves {
            app.buttons[move].tap()
        }
    }
}
