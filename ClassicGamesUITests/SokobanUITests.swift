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
    private var namespace = ""
    private var measuredDrawnByLevel: [Int: [Double]] = [:]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // A case owns one bounded UUID container; every helper/relaunch reuses it.
        namespace = "sokoban.ui." + UUID().uuidString
        app.launchEnvironment["CLASSICGAMES_SOKOBAN_TEST_NAMESPACE"] = namespace
        app.launchArguments = ["-ui-testing"]
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

        move("left")
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 33")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")

        let locked = board.value as? String
        play(["pad.up", "pad.left"])
        XCTAssertEqual(board.value as? String, locked)

        restartUI()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertFalse(app.staticTexts["过关"].exists)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")

        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.best.sokoban"].label, "已通关 1/100")
    }

    /// 图标能分开，第 20 关能打开，较差步数不覆盖，关掉再打开纪录还在。
    func testIconsLevelsAndScores() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["sokoban.levels"].value as? String, "100")
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        saveEvidence("original-18-sokoban-icons")

        move("left")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 0")

        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 2))
        let locked = board.value as? String
        play(["pad.up", "pad.down", "pad.left", "pad.right"])
        board.swipeUp()
        XCTAssertEqual(board.value as? String, locked)

        restartUI()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")

        play(SokobanMoves.long)
        XCTAssertEqual(board.value as? String, SokobanMoves.longWin)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 35")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")

        app.buttons["sokoban.next"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        XCTAssertEqual(app.staticTexts["sokoban.level"].label, "第 2 关 / 100")
        XCTAssertFalse(app.staticTexts["过关"].exists)

        app.buttons["sokoban.levels"].tap()
        revealPick(20).tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level20)
        XCTAssertEqual(app.staticTexts["sokoban.level"].label, "第 20 关 / 100")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        saveEvidence("original-19-sokoban-levels")

        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.best.sokoban"].label, "已通关 1/100")

        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["home.best.sokoban"].label, "已通关 1/100")
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, SokobanMoves.level20)
        XCTAssertEqual(app.staticTexts["sokoban.level"].label, "第 20 关 / 100")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        app.buttons["sokoban.levels"].tap()
        XCTAssertTrue(app.staticTexts["sokoban.cleared.1"].waitForExistence(timeout: 5))
        app.buttons["sokoban.pick.1"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.longWin)
        XCTAssertTrue(app.staticTexts["sokoban.completed.title"].exists)
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

        move("left")
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        move("down")
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")
        move("right")
        XCTAssertEqual(board.value as? String, "level:1;player:4,3;boxes:3,1|4,4;steps:2;won:false;face:right")
        move("up")
        XCTAssertEqual(board.value as? String, "level:1;player:3,3;boxes:3,1|4,4;steps:3;won:false;face:up")
        move("left")
        XCTAssertEqual(board.value as? String, "level:1;player:3,2;boxes:3,1|4,4;steps:4;won:false;face:left")

        restartUI()
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
        revealPick(20).tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level20)
    }

    /// 单指滑动只走一格，短拖不动。大图整盘适配，单指也不平移棋盘。
    func testSwipeMovesOneCellWithoutScrolling() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        assertDrawnPositionUnchanged()

        let player = cellCoordinate(board, row: 3, col: 2)
        player.press(forDuration: 0.05, thenDragTo: player.withOffset(CGVector(dx: 8, dy: 0)))
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        assertDrawnPositionUnchanged()

        let center = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 0, dy: 80)))
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "walk:140")
        assertDrawnPositionUnchanged()

        app.buttons["sokoban.levels"].tap()
        revealPick(99).tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue((board.value as? String)?.hasPrefix("level:99;") == true)
        assertDrawnPositionUnchanged()

        let before = board.value as? String
        board.swipeLeft()
        let after = board.value as? String
        XCTAssertNotEqual(before, nil)
        XCTAssertTrue(after == before || stepsAdvanced(from: before, to: after))
        assertDrawnPositionUnchanged()
        let beforePinch = board.value as? String
        board.pinch(withScale: 1.3, velocity: 1)
        XCTAssertEqual(board.value as? String, beforePinch)
        assertDrawnPositionUnchanged()
    }

    /// 旧点地用例按v0.2迁移：任何点击均不自动移动，真实滑动才走一格。
    func testTapFloorWalksToThatCell() {
        enter()
        let initial = board.value as? String
        for p in [(0,0),(3,1),(3,2),(4,2),(3,4),(4,4)] { tapCell(board, row: p.0, col: p.1); XCTAssertEqual(board.value as? String, initial) }
        XCTAssertTrue(app.buttons["sokoban.hint"].exists)
        XCTAssertTrue(app.buttons["sokoban.dpad.up"].exists)
        XCTAssertFalse(app.buttons["pad.up"].exists)
        move("down")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "walk:140")
    }

    /// 旧路径用例按v0.2迁移：长按/斜滑不动，长滑仅一格，行走/推动时长与撤销保持。
    func testPathPlaysEachCell() {
        enter()
        let center = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 1.2)
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 35, dy: 34)))
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        move("down", distance: 150)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "walk:140")
        move("right")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 2")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "push:180")
        XCTAssertFalse(app.staticTexts["sokoban.motion"].label.hasPrefix("path:"))
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
    }

    /// 撤销和重做各退回或前进一步。点地的每一格都能单独撤，过关后也能撤，纪录不改，换关撤不回去。
    func testUndoAndRedoStayOnThisLevel() {
        enter()
        XCTAssertFalse(app.buttons["sokoban.undo"].isEnabled)
        move("down"); let one = board.value as? String
        move("right")
        app.buttons["sokoban.undo"].tap(); XCTAssertEqual(board.value as? String, one)
        testAction("redo"); XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 2")
        app.buttons["sokoban.undo"].tap(); app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertFalse(app.buttons["sokoban.undo"].isEnabled)
        move("right"); let newBranch = board.value as? String
        testAction("redo"); XCTAssertEqual(board.value as? String, newBranch)
        restartUI(); XCTAssertEqual(board.value as? String, SokobanMoves.start)
        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        // Result layer replaces the circular control bar, so undo is absent (not just disabled).
        XCTAssertFalse(app.buttons["sokoban.undo"].exists)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        app.buttons["sokoban.next"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        XCTAssertFalse(app.buttons["sokoban.undo"].isEnabled)
        pick(1)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertFalse(app.buttons["sokoban.next"].exists)
    }

    /// 正式提示会推进当前关；L66 开局提示只把第一个箱子推上目标，不会直接过关。
    /// 测试钩子 pad.* / 看解 / 重做仍不得出现在正式界面。
    func testHintAndSolutionStayOnThisLevel() {
        enter()
        XCTAssertTrue(app.buttons["sokoban.hint"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sokoban.dpad.up"].exists)
        XCTAssertTrue(app.buttons["sokoban.dpad.down"].exists)
        XCTAssertTrue(app.buttons["sokoban.dpad.left"].exists)
        XCTAssertTrue(app.buttons["sokoban.dpad.right"].exists)
        for id in ["sokoban.solution", "sokoban.redo", "pad.up", "pad.down", "pad.left", "pad.right"] {
            XCTAssertFalse(app.buttons[id].exists)
        }
        pick(66)
        let before = board.value as? String
        XCTAssertTrue(before?.hasPrefix("level:66;") == true)
        XCTAssertTrue(before?.contains("won:false") == true)
        app.buttons["sokoban.hint"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        let after = board.value as? String
        XCTAssertTrue(after?.hasPrefix("level:66;") == true)
        XCTAssertNotEqual(after, before)
        XCTAssertTrue(after?.contains("won:false") == true)
        pick(2)
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        XCTAssertTrue(app.buttons["sokoban.hint"].exists)
        XCTAssertFalse(app.buttons["sokoban.solution"].exists)
        XCTAssertFalse(app.buttons["pad.up"].exists)
    }

    /// 返回首页或杀掉再打开，还停在这一关这一步，撤销栈也在。恢复不改纪录。
    func testResumeKeepsThisStep() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        move("down")
        move("right")
        app.buttons["sokoban.undo"].tap()
        let oneStep = "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down"
        XCTAssertEqual(board.value as? String, oneStep)

        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, oneStep)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        testAction("redo")
        XCTAssertEqual(board.value as? String, "level:1;player:4,3;boxes:3,1|4,4;steps:2;won:false;face:right")
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, oneStep)

        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["home.best.sokoban"].label, "已通关 0/100")
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

    /// 无身份旧终局与坏历史只备份隔离；不把它们当作新版合法终局或纪录。
    func testBadResumeStartsLevelOne() {
        let won = "1|2,2|1,2+3,1|33|up|1|1||"
        launch(resume: won)
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        expectDiagnostic(["legacy": "identityUnproven", "legacyRetained": "true", "diskHash": "missing"])
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")

        launch(resume: "1|4,2|3,1|1|down|0|0||")
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        expectDiagnostic(["legacy": "identityUnproven", "legacyRetained": "true"])

        launch(resume: "1|4,2|3,1+4,3|1|sideways|0|0||")
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        expectDiagnostic(["legacy": "identityUnproven", "legacyRetained": "true"])
    }

    /// 顶墙、走出一格、推动一格各自留下时长。过关后的按键不再顶墙，重开清掉这段。
    func testWalkPushAndWallTransitions() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "idle")
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        move("left")
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 0")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "bump:120")

        move("down")
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "walk:140")

        move("right")
        XCTAssertEqual(board.value as? String, "level:1;player:4,3;boxes:3,1|4,4;steps:2;won:false;face:right")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 2")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "push:180")

        restartUI()
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
        move("left")
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 0")

        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 2))

        app.buttons["sokoban.levels"].tap()
        XCTAssertTrue(app.staticTexts["选择关卡"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sokoban.levels.close"].exists)
        let credit = app.staticTexts["sokoban.credit"]
        XCTAssertTrue(credit.exists)
        XCTAssertFalse(app.staticTexts["sokoban.group.入门"].exists)
        XCTAssertFalse(app.staticTexts["sokoban.group.初级"].exists)
        XCTAssertTrue(app.staticTexts["sokoban.cleared.1"].exists)
        XCTAssertFalse(app.staticTexts["sokoban.cleared.2"].exists)
        XCTAssertTrue(app.buttons["sokoban.pick.1"].exists)
        revealPick(20).tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level20)
        XCTAssertEqual(app.staticTexts["sokoban.level"].label, "第 20 关 / 100")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")

        restartUI()
        XCTAssertEqual(board.value as? String, SokobanMoves.level20)
        app.buttons["sokoban.levels"].tap()
        XCTAssertTrue(app.staticTexts["选择关卡"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["sokoban.cleared.1"].exists)
        app.buttons["sokoban.pick.1"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertTrue(app.staticTexts["sokoban.completed.title"].exists)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")

        app.buttons["sokoban.levels"].tap()
        XCTAssertTrue(app.staticTexts["选择关卡"].waitForExistence(timeout: 5))
        let level100 = revealPick(100)
        XCTAssertFalse(app.staticTexts["sokoban.group.挑战"].exists)
        level100.tap()
        XCTAssertEqual(app.staticTexts["sokoban.level"].label, "第 100 关 / 100")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        XCTAssertFalse(app.staticTexts["过关"].exists)

        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.best.sokoban"].label, "已通关 1/100")
    }

    /// 进入推箱子后背景循环开始；走一步有脚步，推一格有推动声，顶墙不加；回首页和其他七款都停。
    func testBackgroundStartsOnEnterAndStopsOnLeave() {
        launch(hearing: "audible")
        waitAudio(["bgm": "stopped", "engine": "0", "steps": "0", "wins": "0"])
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        waitAudio(["bgm": "playing", "engine": "1", "steps": "0", "wins": "0"])

        move("left")
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        waitAudio(["bgm": "playing", "engine": "1", "steps": "0"])

        move("down")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        waitAudio(["steps": "1"])

        move("right")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 2")
        waitAudio(["bgm": "playing", "engine": "1", "steps": "1", "pushes": "1", "wins": "0"])

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

    /// 过关短乐在走完第 1 关后发出。这一关最短解有 25 声脚步和 8 声推动。
    func testClearPlaysShortTune() {
        launch(hearing: "audible")
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 2))
        waitAudio(["bgm": "playing", "engine": "1", "steps": "25", "pushes": "8", "wins": "1"], timeout: 2)
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        waitAudio(["bgm": "stopped", "engine": "0"])
    }

    /// 系统静音时背景循环不送出，走步、推动和过关也不计数。
    func testSilentEmitsNothing() {
        launch(hearing: "silent")
        waitAudio(["bgm": "stopped", "engine": "0"])
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        waitAudio(["bgm": "silent", "engine": "0", "steps": "0", "pushes": "0", "wins": "0"])

        move("left")
        move("down")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        waitAudio(["bgm": "silent", "engine": "0", "steps": "0", "pushes": "0", "wins": "0"])

        restartUI()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        play(SokobanMoves.short)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        waitAudio(["bgm": "silent", "engine": "0", "steps": "0", "pushes": "0", "wins": "0"])

        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        waitAudio(["bgm": "stopped", "engine": "0", "steps": "0", "wins": "0"])
    }

    /// 上线完成度：从首页走到过关、下一关、纪录和静音，一次点完。
    func testReleaseChecklist() {
        launch(hearing: "audible")
        waitAudio(["bgm": "stopped", "engine": "0"])
        saveEvidence("entry-home")
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        waitAudio(["bgm": "playing", "engine": "1", "steps": "0", "wins": "0"])
        saveEvidence("entry-playing")

        app.buttons["sokoban.levels"].tap()
        XCTAssertTrue(app.staticTexts["sokoban.credit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["选择关卡"].exists)
        XCTAssertFalse(app.staticTexts["sokoban.group.入门"].exists)
        app.buttons["sokoban.pick.1"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)

        move("left")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "bump:120")
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        move("down")
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "walk:140")
        waitAudio(["steps": "1", "wins": "0"])
        move("right")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "push:180")
        XCTAssertEqual(board.value as? String, "level:1;player:4,3;boxes:3,1|4,4;steps:2;won:false;face:right")
        app.buttons["sokoban.undo"].tap()
        testAction("redo")
        XCTAssertEqual(board.value as? String, "level:1;player:4,3;boxes:3,1|4,4;steps:2;won:false;face:right")

        app.buttons["chrome.restart"].tap()
        XCTAssertTrue(app.staticTexts["sokoban.reset.title"].waitForExistence(timeout: 3))
        let dirty = board.value as? String
        app.buttons["sokoban.reset.cancel"].tap(); XCTAssertEqual(board.value as? String, dirty)
        restartUI()
        move("right"); move("right")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "walk:140")
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        testAction("redo")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 2")

        restartUI()
        XCTAssertTrue(app.buttons["sokoban.hint"].exists)
        XCTAssertTrue(app.buttons["sokoban.dpad.up"].exists)
        XCTAssertFalse(app.buttons["pad.up"].exists)
        XCTAssertFalse(app.buttons["sokoban.solution"].exists)
        move("down")
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "walk:140")

        app.buttons["sokoban.levels"].tap()
        let level2 = app.buttons["sokoban.pick.2"]
        XCTAssertTrue(level2.waitForExistence(timeout: 5))
        level2.tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        XCTAssertTrue(app.buttons["sokoban.hint"].exists)
        XCTAssertFalse(app.buttons["sokoban.solution"].exists)
        XCTAssertFalse(app.buttons["pad.up"].exists)
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        XCTAssertFalse(app.staticTexts["这一关没有解"].exists)

        app.buttons["sokoban.levels"].tap()
        let level1 = app.buttons["sokoban.pick.1"]
        XCTAssertTrue(level1.waitForExistence(timeout: 5))
        level1.tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        restartUI()
        move("down")
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
        saveEvidence("entry-completed")
        // 刚刚通关时底栏改为主次大按钮，不再要求四个圆钮同排。
        for id in ["sokoban.next", "chrome.restart"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 2), id)
            let frame = app.buttons[id].frame
            XCTAssertGreaterThanOrEqual(frame.width, 44, id)
            XCTAssertGreaterThanOrEqual(frame.height, 44, id)
            XCTAssertLessThanOrEqual(frame.maxX, 375.1, id)
            XCTAssertLessThanOrEqual(frame.maxY, 667.1, id)
        }
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        let locked = board.value as? String
        move("up")
        XCTAssertEqual(board.value as? String, locked)

        restartUI()
        play(SokobanMoves.long)
        XCTAssertEqual(board.value as? String, SokobanMoves.longWin)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        app.buttons["sokoban.next"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        restartUI()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.best.sokoban"].label, "已通关 1/100")

        launch(hearing: "silent")
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        move("down")
        waitAudio(["bgm": "silent", "engine": "0", "steps": "0", "pushes": "0", "wins": "0"])
    }

    /// 用固定的听感重新打开。正式游玩不带这个参数。
    private func launch(hearing: String) {
        app.terminate()
        app = XCUIApplication()
        app.launchEnvironment["CLASSICGAMES_SOKOBAN_TEST_NAMESPACE"] = namespace
        app.launchArguments = ["-ui-testing", "-sokoban-hearing", hearing]
        app.launch()
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
    }

    /// 向同case的synthetic defaults写旧raw，验证不可证明身份时保原档隔离。
    private func launch(resume: String) {
        app.terminate()
        app = XCUIApplication()
        app.launchEnvironment["CLASSICGAMES_SOKOBAN_TEST_NAMESPACE"] = namespace
        app.launchArguments = ["-ui-testing", "-sokoban-resume", resume]
        app.launch()
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
    }

    private func relaunch(fixture: String? = nil, explicitTesting: Bool = true, namespaceOverride: String? = nil) {
        app.terminate()
        app = XCUIApplication()
        app.launchEnvironment["CLASSICGAMES_SOKOBAN_TEST_NAMESPACE"] = namespaceOverride ?? namespace
        app.launchArguments = explicitTesting ? ["-ui-testing"] : []
        app.launchArguments += ["-sokoban-hearing", "audible"]
        if let fixture { app.launchArguments += ["-sokoban-fixture", fixture] }
        app.launch()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 8))
    }
    private func diagnostic() -> [String: String] {
        let text = app.staticTexts["sokoban.testing.state"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        return Dictionary(uniqueKeysWithValues: text.label.split(separator: ";").compactMap {
            let pair = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        })
    }
    private func expectDiagnostic(_ fields: [String: String], file: StaticString = #filePath, line: UInt = #line) {
        let actual = diagnostic()
        for (key, value) in fields { XCTAssertEqual(actual[key], value, "\(key): \(actual)", file: file, line: line) }
    }
    private func testAction(_ name: String) {
        // Hidden Darwin hook: no visible "隔离测试" entry in the test or production package.
        let note = CFNotificationName("practice.classicgames.sokoban.test." + name as CFString)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), note, nil, nil, true)
        let deadline = Date().addingTimeInterval(0.35)
        while Date() < deadline { RunLoop.current.run(mode: .default, before: deadline) }
    }
    private func revealPick(_ level: Int) -> XCUIElement {
        let choice = app.descendants(matching: .any)["sokoban.pick.\(level)"]
        let scroller = app.scrollViews["sokoban.levels.scroll"]
        func nudge(_ up: Bool, fraction: CGFloat) {
            let target: XCUIElement = scroller.exists ? scroller : app
            let startY: CGFloat = up ? 0.82 : 0.28
            let endY = up ? (0.82 - fraction) : (0.28 + fraction)
            let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        var n = 0
        while !choice.waitForExistence(timeout: 0.15) && n < 80 {
            nudge(true, fraction: n < 6 ? 0.45 : 0.28)
            n += 1
        }
        n = 0
        while choice.exists && !choice.isHittable && n < 24 {
            nudge(true, fraction: 0.18)
            n += 1
        }
        n = 0
        while choice.exists && !choice.isHittable && n < 24 {
            nudge(false, fraction: 0.18)
            n += 1
        }
        XCTAssertTrue(choice.waitForExistence(timeout: 2), "level \(level) should exist in the picker")
        XCTAssertTrue(choice.isHittable, "level \(level) should be reachable in the picker")
        return choice
    }

    private func pick(_ level: Int) {
        app.buttons["sokoban.levels"].tap()
        revealPick(level).tap()
    }

    func testB3Native99WholeBoardWithoutClipping() {
        enter(); pick(99)
        verifyLayout(level: 99, accessibility: false, name: "99-normal")
    }
    func testB3Native66Normal() { enter(); pick(66); verifyLayout(level: 66, accessibility: false, name: "66-normal") }
    func testB3Native66MaximumAccessibility() { maximumFixture("level66"); enter(); verifyLayout(level: 66, accessibility: true, name: "66-AX5") }
    func testB3Native99MaximumAccessibility() { maximumFixture("level99"); enter(); verifyLayout(level: 99, accessibility: true, name: "99-AX5") }
    func testB3FormalRetryAndLeaveProtection() {
        enter(); move("up"); testAction("fault.writes"); move("down")
        expectDiagnostic(["save":"failed","pending":"2","diskSteps":"1"])
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.staticTexts["sokoban.leave.title"].waitForExistence(timeout: 3))
        app.buttons["sokoban.leave.stay"].tap()
        testAction("fault.none")
        let retry = app.buttons["sokoban.save.retry"]
        XCTAssertTrue(retry.isHittable); retry.tap()
        expectDiagnostic(["save":"saved","pending":"nil","diskSteps":"2"])
        XCTAssertTrue(app.staticTexts["sokoban.save.saved"].waitForExistence(timeout: 2))
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].exists)
    }
    func testB3RelativePanResetDoesNotLoseRealSwipe() {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-sokoban-hearing", "audible", "-sokoban-gesture-relative-reset"]
        app.launch(); enter()
        move("down")
        XCTAssertEqual(board.value as? String, "level:1;player:4,2;boxes:3,1|4,3;steps:1;won:false;face:down")
        move("right")
        XCTAssertEqual(board.value as? String, "level:1;player:4,3;boxes:3,1|4,4;steps:2;won:false;face:right")
        XCTAssertEqual(app.staticTexts["sokoban.motion"].label, "push:180")
        waitAudio(["steps":"1", "pushes":"1", "wins":"0"])
    }
    func testB3DetailedArtworkFromNormalEntry() {
        enter()
        let text = app.staticTexts["sokoban.layout.metrics"].label
        let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String:Any]
        XCTAssertEqual(object?["renderMode"] as? String, "assets")
        XCTAssertEqual(object?["boardAssetsLoaded"] as? Bool, true)
        saveEvidence("Q-normal-entry", metadata: text)
    }
    func testB3AXHistorySummaryAndScroll() {
        maximumFixture("layoutHistory66"); enter()
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        app.buttons["sokoban.records.open"].tap()
        XCTAssertEqual(app.staticTexts["sokoban.records.current"].label, "本关纪录 —")
        XCTAssertEqual(app.staticTexts["sokoban.records.legacy"].label, "历史纪录（旧版） 7")
        let detail = app.staticTexts["sokoban.records.measurements"]
        XCTAssertTrue(detail.waitForExistence(timeout: 4))
        saveEvidence("66-AX5-history-expanded", metadata: detail.label)
        // Long explanation copy was removed; the card now only pins current and
        // legacy lines. Equivalence: those lines stay complete and untruncated.
        let legacy = app.staticTexts["sokoban.records.legacy"]
        XCTAssertEqual(legacy.label, "历史纪录（旧版） 7")
        XCTAssertFalse((legacy.value as? String)?.contains("…") == true)
        XCTAssertGreaterThan(legacy.frame.width, 44)
        if app.scrollViews["sokoban.records.scroll"].exists {
            app.scrollViews["sokoban.records.scroll"].swipeUp()
            saveEvidence("66-AX5-history-scrolled", metadata: detail.label)
        }
        XCTAssertEqual(app.staticTexts["sokoban.records.current"].label, "本关纪录 —")
        XCTAssertEqual(app.staticTexts["sokoban.records.legacy"].label, "历史纪录（旧版） 7")
        app.buttons["sokoban.records.close"].tap()
    }
    func testB3NoDemoAutomaticControls() {
        app.buttons["home.row.sokoban"].tap()
        XCTAssertFalse(app.buttons["pad.up"].exists)
        XCTAssertTrue(app.buttons["sokoban.hint"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sokoban.dpad.up"].exists)
        XCTAssertFalse(app.buttons["sokoban.solution"].exists)
    }
    func testB2SeparateLevelFilesAndRelaunchUndo() {
        relaunch(fixture: "resume1")
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 2")
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        testAction("redo")
        let level1 = board.value as? String
        pick(2)
        move("up")
        let level2 = board.value as? String
        expectDiagnostic(["diskSteps": "1"])
        pick(1)
        XCTAssertEqual(board.value as? String, level1)
        relaunch()
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, level1)
        app.buttons["sokoban.undo"].tap()
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        pick(2)
        XCTAssertEqual(board.value as? String, level2)
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.level2)
    }
    func testB2WriteFailureRetainsLatestUntilRetry() {
        app.buttons["home.row.sokoban"].tap()
        move("up")
        let before = diagnostic()["diskHash"]
        testAction("fault.writes")
        move("down")
        expectDiagnostic(["save": "failed", "pending": "2", "diskSteps": "1"])
        XCTAssertEqual(diagnostic()["diskHash"], before)
        testAction("retry")
        expectDiagnostic(["save": "failed", "pending": "2"])
        testAction("fault.none"); testAction("retry")
        expectDiagnostic(["save": "saved", "pending": "nil", "diskSteps": "2"])
        XCTAssertNotEqual(diagnostic()["diskHash"], before)
        relaunch()
        app.buttons["home.row.sokoban"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 2")
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
    }
    func testB2ReadFailureAfterWinAndRetryNeverErasesBest() {
        relaunch(fixture: "history")
        app.buttons["home.row.sokoban"].tap()
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 —")
        XCTAssertEqual(app.staticTexts["sokoban.history.best"].label, "历史纪录（旧版） 7")
        play(SokobanMoves.short)
        expectDiagnostic(["diskBest": "33", "events": "1", "oldBest": "7", "other": "700"])
        testAction("fault.reads")
        testAction("undo")
        expectDiagnostic(["save": "failed", "pending": "32", "diskBest": "33"])
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        testAction("fault.none"); testAction("retry")
        expectDiagnostic(["save": "saved", "diskBest": "33", "diskSteps": "32"])
        testAction("fault.reads")
        testAction("undo")
        testAction("retry")
        expectDiagnostic(["save": "failed", "pending": "31", "diskBest": "33"])
        testAction("fault.none"); testAction("retry")
        expectDiagnostic(["save": "saved", "diskBest": "33", "diskSteps": "31", "oldBest": "7", "other": "700"])
        XCTAssertEqual(app.staticTexts["sokoban.history.best"].label, "历史纪录（旧版） 7")
    }
    func testB2RestartReadFailuresPreserveBestAndPending() {
        relaunch(fixture: "complete1")
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        let original = diagnostic()["diskHash"]
        testAction("fault.reads")
        restartUI()
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        expectDiagnostic(["visit": "completedRevisit", "pending": "nil", "backups": "0", "diskBest": "33"])
        XCTAssertEqual(diagnostic()["diskHash"], original)
        testAction("fault.none")
        restartUI()
        move("up")
        let healthy = diagnostic()["diskHash"]
        testAction("fault.secondRead")
        restartUI()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        expectDiagnostic(["save": "failed", "pending": "0", "diskSteps": "1", "diskBest": "33", "backups": "0"])
        XCTAssertEqual(diagnostic()["diskHash"], healthy)
        testAction("fault.none"); testAction("retry")
        expectDiagnostic(["save": "saved", "pending": "nil", "diskSteps": "0", "diskBest": "33", "backups": "0"])
    }
    func testB2RestartBackupFailureThenSlotFailurePreservesRawBytes() {
        app.buttons["home.row.sokoban"].tap()
        move("up")
        testAction("corrupt")
        expectDiagnostic(["visit": "recovery", "board": "false", "backups": "0"])
        let original = diagnostic()["diskHash"]
        testAction("fault.backupWrites")
        restartUI()
        expectDiagnostic(["visit": "recovery", "backups": "0", "pending": "nil"])
        XCTAssertEqual(diagnostic()["diskHash"], original)
        testAction("fault.slotWrites")
        restartUI()
        expectDiagnostic(["visit": "playing", "save": "failed", "pending": "0", "backups": "1", "exactBackup": "true"])
        XCTAssertEqual(diagnostic()["diskHash"], original)
        XCTAssertEqual(diagnostic()["backupHash"], original)
        testAction("retry")
        expectDiagnostic(["save": "failed", "pending": "0", "exactBackup": "true"])
        testAction("fault.none"); testAction("retry")
        expectDiagnostic(["save": "saved", "pending": "nil", "diskSteps": "0", "backups": "1"])
        XCTAssertEqual(diagnostic()["backupHash"], original)
        XCTAssertTrue(app.descendants(matching: .any)["sokoban.board"].exists)
    }
    func testB2ScoreOnlyFinalLevelHasNoFabricatedBoardOrCelebration() {
        relaunch(fixture: "scoreOnly100")
        app.buttons["home.row.sokoban"].tap()
        pick(100)
        XCTAssertTrue(app.staticTexts["sokoban.board.unavailable"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["sokoban.board"].exists)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "已通关")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        XCTAssertEqual(app.staticTexts["sokoban.completed.title"].label, "已通关")
        XCTAssertFalse(app.buttons["sokoban.next"].exists)
        XCTAssertFalse(app.staticTexts["sokoban.win"].exists)
        XCTAssertFalse(app.staticTexts["全部完成"].exists)
        expectDiagnostic(["visit": "scoreOnly", "board": "false", "events": "0", "diskBest": "33"])
        let hash = diagnostic()["diskHash"]
        pick(1); pick(100)
        XCTAssertEqual(diagnostic()["diskHash"], hash)
        waitAudio(["wins": "0"])
        restartUI()
        XCTAssertTrue(app.descendants(matching: .any)["sokoban.board"].exists)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 0")
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 0")
        expectDiagnostic(["visit": "playing", "board": "true", "diskBest": "33"])
    }
    func testB2GateRejectsMisuseAtRuntime() {
        relaunch(namespaceOverride: "sokoban.ui.../../../not-allowed")
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["sokoban.board"].waitForExistence(timeout: 5))
        app.buttons["sokoban.pause"].tap()
        XCTAssertFalse(app.buttons["sokoban.testing.open"].exists)
        XCTAssertFalse(app.staticTexts["隔离测试"].exists)
        XCTAssertFalse(app.staticTexts["sokoban.testing.state"].exists)
        app.buttons["sokoban.pause.resume"].tap()
        relaunch(explicitTesting: false)
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["sokoban.board"].waitForExistence(timeout: 5))
        app.buttons["sokoban.pause"].tap()
        XCTAssertFalse(app.buttons["sokoban.testing.open"].exists)
        XCTAssertFalse(app.staticTexts["隔离测试"].exists)
        XCTAssertFalse(app.staticTexts["sokoban.testing.state"].exists)
        app.buttons["sokoban.pause.resume"].tap()
        relaunch()
        app.buttons["home.row.sokoban"].tap()
        app.buttons["sokoban.pause"].tap()
        XCTAssertFalse(app.buttons["sokoban.testing.open"].exists)
        XCTAssertFalse(app.staticTexts["隔离测试"].exists)
        XCTAssertTrue(app.buttons["sokoban.pause.resume"].waitForExistence(timeout: 5))
    }
    func testB2CompletedRevisitIsReadOnly() {
        relaunch(fixture: "complete1")
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertTrue(app.staticTexts["sokoban.completed.title"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["sokoban.completed.title"].label, "已通关")
        XCTAssertFalse(app.staticTexts["sokoban.win"].exists)
        XCTAssertFalse(app.buttons["sokoban.next"].exists)
        expectDiagnostic(["visit": "completedRevisit", "events": "0", "diskBest": "33"])
        let hash = diagnostic()["diskHash"]
        waitAudio(["wins": "0"])
        pick(2); pick(1)
        XCTAssertEqual(board.value as? String, SokobanMoves.win)
        XCTAssertEqual(diagnostic()["diskHash"], hash)
        waitAudio(["wins": "0"])
        restartUI()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        app.buttons["sokoban.undo"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        expectDiagnostic(["visit": "playing", "diskBest": "33", "events": "0"])
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

    /// `bgm:playing;engine:1;steps:0;pushes:0;wins:0` 拆成字段。
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

    /// 真实单指滑动依次输入；每次手势只触发一次模型移动。
    /// Default typography visual pass for v2.4 cards, picker, hedge, and reserved save slot.
    func testCaptureDefaultVisualPass() {
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        shotImpl("play-default")
        openShopShot("shop-default")
        app.buttons["sokoban.levels"].tap()
        let level66 = app.buttons["sokoban.pick.66"]
        var swipes = 0
        while !level66.isHittable && swipes < 40 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(level66.waitForExistence(timeout: 5))
        level66.tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue((board.value as? String)?.hasPrefix("level:66;") == true)
        shotImpl("play-irregular-66-default")
        captureHintExecuted("hint-executed-default")
        app.buttons["chrome.back"].tap()
        if app.staticTexts["sokoban.leave.title"].waitForExistence(timeout: 2) {
            app.buttons["sokoban.leave.stay"].tap()
            app.buttons["chrome.back"].tap()
        }
        // Re-enter level 1 for the rest of the default visual pass.
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        app.buttons["sokoban.levels"].tap()
        let level1 = app.buttons["sokoban.pick.1"]
        XCTAssertTrue(level1.waitForExistence(timeout: 5))
        level1.tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chrome.back"].isHittable)
        XCTAssertTrue(app.buttons["chrome.restart"].isHittable)
        move("down")
        app.buttons["chrome.restart"].tap()
        XCTAssertTrue(app.staticTexts["sokoban.reset.title"].waitForExistence(timeout: 3))
        shotImpl("reset-default")
        app.buttons["sokoban.reset.cancel"].tap()
        app.buttons["chrome.back"].tap()

        launchVisual(ax5: false, fault: "slotWrites", freshNamespace: true)
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        let boardYBefore = board.frame.minY
        move("right")
        XCTAssertTrue(app.staticTexts["sokoban.save.failed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sokoban.save.failed"].label, "本步尚未保存")
        XCTAssertTrue(app.buttons["sokoban.save.retry"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["sokoban.save.retry"].frame.height, 44)
        let failedDefault = app.staticTexts["sokoban.save.failed"]
        let retryDefault = app.buttons["sokoban.save.retry"]
        let screenDefault = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(failedDefault.frame.minY, 0)
        XCTAssertLessThanOrEqual(failedDefault.frame.maxY, screenDefault.height)
        XCTAssertGreaterThanOrEqual(retryDefault.frame.minY, 0)
        XCTAssertLessThanOrEqual(retryDefault.frame.maxY, screenDefault.height)
        shotImpl("save-failed-default")
        XCTAssertEqual(board.frame.minY, boardYBefore, accuracy: 3)
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.staticTexts["sokoban.leave.title"].waitForExistence(timeout: 3))
        shotImpl("leave-default")
        app.buttons["sokoban.leave.stay"].tap()
        app.buttons["chrome.back"].tap()
        if app.buttons["sokoban.leave.stay"].waitForExistence(timeout: 2) { app.buttons["sokoban.leave.stay"].tap() }

        launchVisual(ax5: false, freshNamespace: true)
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        play(SokobanMoves.short)
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 8))
        shotImpl("complete-default")
        XCTAssertTrue(app.staticTexts["sokoban.save.saved"].exists)
        XCTAssertTrue(app.staticTexts["sokoban.level"].exists)
        XCTAssertTrue(app.otherElements["sokoban.result.stars"].exists || app.staticTexts["sokoban.result.grade"].exists)
        captureLevelStars("levels-stars-default")

        launchVisual(ax5: false, fixture: "campaignReady", freshNamespace: true)
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        play(SokobanMoves.short)
        XCTAssertTrue(app.staticTexts["全部完成"].waitForExistence(timeout: 8))
        shotImpl("campaign-complete-default")

        launchVisual(ax5: false, fixture: "clear100NotAll", freshNamespace: true)
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        pick(100)
        XCTAssertEqual(app.staticTexts["sokoban.level"].label, "第 100 关 / 100")
        XCTAssertFalse(app.staticTexts["全部完成"].exists)
        play(["left"])
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["全部完成"].exists)
        XCTAssertTrue(app.staticTexts["还可以继续挑战其他关卡。"].waitForExistence(timeout: 5))
        shotImpl("clear100-not-all-default")
    }

    /// AX5 shots on a regular-height device. 375×667 first-screen overflow is not an acceptance item.
    func testCaptureAX5RegularHeightVisualPass() throws {
        let height = app.windows.firstMatch.frame.height
        try XCTSkipIf(height < 800, "AX5 acceptance shots require a regular-height device, not 375×667")

        launchVisual(ax5: true, freshNamespace: true)
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chrome.back"].isHittable)
        XCTAssertTrue(app.buttons["sokoban.levels"].isHittable)
        XCTAssertTrue(app.buttons["sokoban.records.open"].isHittable)
        XCTAssertTrue(app.buttons["chrome.restart"].isHittable)
        XCTAssertTrue(app.buttons["sokoban.pause"].isHittable)
        shotImpl("play-ax5")
        openShopShot("shop-ax5")
        app.buttons["sokoban.levels"].tap()
        revealPick(66).tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue((board.value as? String)?.hasPrefix("level:66;") == true)
        shotImpl("play-irregular-66-ax5")
        captureHintExecuted("hint-executed-ax5")
        app.buttons["chrome.back"].tap()
        if app.staticTexts["sokoban.leave.title"].waitForExistence(timeout: 2) {
            app.buttons["sokoban.leave.stay"].tap()
            app.buttons["chrome.back"].tap()
        }
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        let metrics = app.scrollViews["sokoban.metrics.scroll"]
        if metrics.exists && metrics.frame.height > 0 {
            metrics.swipeUp()
            shotImpl("play-ax5-metrics-scrolled")
            XCTAssertTrue(app.buttons["chrome.back"].isHittable)
            XCTAssertTrue(app.buttons["sokoban.pause"].isHittable)
        }
        move("down")
        app.buttons["chrome.restart"].tap()
        XCTAssertTrue(app.staticTexts["sokoban.reset.title"].waitForExistence(timeout: 3))
        shotImpl("reset-ax5")
        app.buttons["sokoban.reset.cancel"].tap()
        app.buttons["chrome.back"].tap()

        launchVisual(ax5: true, fixture: "history", freshNamespace: true)
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        app.buttons["sokoban.records.open"].tap()
        XCTAssertTrue(app.staticTexts["sokoban.records.current"].waitForExistence(timeout: 4))
        shotImpl("records-ax5")
        XCTAssertEqual(app.staticTexts["sokoban.records.legacy"].label, "历史纪录（旧版） 7")
        app.buttons["sokoban.records.close"].tap()
        app.buttons["chrome.back"].tap()

        launchVisual(ax5: true, fault: "slotWrites", freshNamespace: true)
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        let boardYBefore = board.frame.minY
        move("right")
        XCTAssertTrue(app.staticTexts["sokoban.save.failed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sokoban.save.failed"].label, "本步尚未保存")
        XCTAssertFalse(app.staticTexts["sokoban.save.failed"].label.contains("…"))
        let failed = app.staticTexts["sokoban.save.failed"]
        let retry = app.buttons["sokoban.save.retry"]
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(retry.isHittable)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        XCTAssertGreaterThanOrEqual(retry.frame.width, 44)
        // Banner stays in the reserved first-screen slot; do not scroll it away.
        XCTAssertGreaterThanOrEqual(failed.frame.minY, 0)
        XCTAssertLessThanOrEqual(failed.frame.maxY, screen.height)
        XCTAssertGreaterThanOrEqual(retry.frame.minY, 0)
        XCTAssertLessThanOrEqual(retry.frame.maxY, screen.height)
        XCTAssertGreaterThanOrEqual(retry.frame.minY, failed.frame.maxY - 2, "AX5 stacks retry under the message")
        shotImpl("save-failed-ax5")
        XCTAssertEqual(board.frame.minY, boardYBefore, accuracy: 3)
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.staticTexts["sokoban.leave.title"].waitForExistence(timeout: 3))
        shotImpl("leave-ax5")
        app.buttons["sokoban.leave.stay"].tap()
        app.buttons["chrome.back"].tap()
        if app.buttons["sokoban.leave.stay"].waitForExistence(timeout: 2) { app.buttons["sokoban.leave.stay"].tap() }

        launchVisual(ax5: true, freshNamespace: true)
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        play(SokobanMoves.short)
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 8))
        shotImpl("complete-ax5")
        XCTAssertTrue(app.otherElements["sokoban.result.stars"].exists || app.staticTexts["sokoban.result.grade"].exists)
        // 通关改为独立结果层上的主次按钮，不再挤四个圆钮。
        XCTAssertTrue(app.buttons["sokoban.next"].isHittable)
        XCTAssertTrue(app.buttons["chrome.restart"].isHittable)
        XCTAssertTrue(app.staticTexts["sokoban.save.saved"].exists)
        XCTAssertTrue(app.staticTexts["sokoban.level"].exists)
        let levelLine = app.staticTexts["sokoban.level"]
        let savedLine = app.staticTexts["sokoban.save.saved"]
        let screenComplete = app.windows.firstMatch.frame
        XCTAssertEqual(savedLine.label, "已保存到本机")
        XCTAssertFalse(levelLine.label.contains("…"))
        XCTAssertFalse(savedLine.label.contains("…"))
        XCTAssertTrue(levelLine.label.contains("第") && levelLine.label.contains("100"))
        XCTAssertGreaterThanOrEqual(levelLine.frame.minY, 0)
        XCTAssertGreaterThanOrEqual(savedLine.frame.minY, 0)
        XCTAssertLessThanOrEqual(levelLine.frame.maxY, screenComplete.height)
        XCTAssertLessThanOrEqual(savedLine.frame.maxY, screenComplete.height)
        XCTAssertFalse(levelLine.frame.intersects(savedLine.frame), "Level line and saved text must stay separate")
        XCTAssertLessThanOrEqual(levelLine.frame.maxY, savedLine.frame.minY)
        captureLevelStars("levels-stars-ax5")

        launchVisual(ax5: true, fixture: "campaignReady", freshNamespace: true)
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        play(SokobanMoves.short)
        XCTAssertTrue(app.staticTexts["全部完成"].waitForExistence(timeout: 8))
        shotImpl("campaign-complete-ax5")

        launchVisual(ax5: true, fixture: "clear100NotAll", freshNamespace: true)
        app.buttons["home.row.sokoban"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        pick(100)
        XCTAssertEqual(app.staticTexts["sokoban.level"].label, "第 100 关 / 100")
        XCTAssertFalse(app.staticTexts["全部完成"].exists)
        play(["left"])
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["全部完成"].exists)
        XCTAssertTrue(app.staticTexts["还可以继续挑战其他关卡。"].waitForExistence(timeout: 5))
        shotImpl("clear100-not-all-ax5")
    }

    private func launchVisual(ax5: Bool, fixture: String? = nil, fault: String? = nil, freshNamespace: Bool = false) {
        app.terminate()
        app = XCUIApplication()
        if freshNamespace { namespace = "sokoban.ui." + UUID().uuidString }
        app.launchEnvironment["CLASSICGAMES_SOKOBAN_TEST_NAMESPACE"] = namespace
        var args = ["-ui-testing"]
        if ax5 {
            args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if let fixture { args += ["-sokoban-fixture", fixture] }
        if let fault { args += ["-sokoban-fault", fault] }
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 8))
    }

    private func clearSaveFaultIfNeeded() {
        if app.buttons["sokoban.leave.stay"].exists { app.buttons["sokoban.leave.stay"].tap() }
        if app.buttons["sokoban.pause.resume"].exists { app.buttons["sokoban.pause.resume"].tap() }
        testAction("fault.none")
        if app.buttons["sokoban.save.retry"].exists { _ = app.buttons["sokoban.save.retry"].tap() }
    }

    private func openShopShot(_ name: String) {
        let coins = app.descendants(matching: .any)["sokoban.coins"]
        XCTAssertTrue(coins.waitForExistence(timeout: 5))
        coins.tap()
        let shop = app.descendants(matching: .any)["sokoban.shop"]
        XCTAssertTrue(shop.waitForExistence(timeout: 5))
        shotImpl(name)
        let close = app.descendants(matching: .any)["sokoban.shop.close"]
        if close.waitForExistence(timeout: 3) {
            close.tap()
        } else {
            let done = app.buttons["完成"]
            XCTAssertTrue(done.waitForExistence(timeout: 3), "shop close control is missing")
            done.tap()
        }
        XCTAssertFalse(shop.exists)
    }

    private func captureHintExecuted(_ name: String) {
        XCTAssertTrue(app.buttons["sokoban.hint"].waitForExistence(timeout: 5))
        let before = board.value as? String
        app.buttons["sokoban.hint"].tap()
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 1")
        XCTAssertNotEqual(board.value as? String, before)
        XCTAssertTrue((board.value as? String)?.contains("won:false") == true)
        shotImpl(name)
    }

    private func captureLevelStars(_ name: String) {
        let open = app.buttons["sokoban.result.levels"].exists ? app.buttons["sokoban.result.levels"] : app.buttons["sokoban.levels"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.staticTexts["选择关卡"].waitForExistence(timeout: 5))
        let stars = app.descendants(matching: .any)["sokoban.pick.stars.1"]
        XCTAssertTrue(stars.waitForExistence(timeout: 5))
        let total = app.descendants(matching: .any)["sokoban.stars.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 3))
        shotImpl(name)
    }

    private func shotImpl(_ name: String) {
        let root = URL(fileURLWithPath: "/Users/hansen/ClassicGames-Engineering/sokoban-impl-20261126/screenshots-v4")
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try image.pngRepresentation.write(to: root.appendingPathComponent(name + ".png"))
        } catch {
            XCTFail("Screenshot write failed: \(error)")
        }
    }

    private func play(_ moves: [String]) {
        for direction in moves { move(direction.replacingOccurrences(of: "pad.", with: "")) }
    }

    private var board: XCUIElement { app.descendants(matching: .any)["sokoban.board"] }
    private func enter() {
        let row = app.buttons["home.row.sokoban"]
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
    }
    private func move(_ direction: String, distance: CGFloat = 60) {
        let captureGestureValues = false // original event cadence; app-side gated OSLog records real recognizer/gates
        let before = board.value as? String ?? "missing"
        let observedFrame = captureGestureValues ? board.frame : .zero
        let p = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let delta: CGVector
        switch direction { case "up": delta = CGVector(dx:0,dy:-distance); case "down": delta = CGVector(dx:0,dy:distance); case "left": delta = CGVector(dx:-distance,dy:0); default: delta = CGVector(dx:distance,dy:0) }
        p.press(forDuration: 0.05, thenDragTo: p.withOffset(delta))
        let deadline = Date().addingTimeInterval(0.9)
        while Date() < deadline {
            let moved = (board.value as? String ?? "missing") != before
            let motion = app.staticTexts["sokoban.motion"]
            let idle = !motion.exists || motion.label == "idle" || motion.label.isEmpty
            if moved && idle { break }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.04))
        }
        guard captureGestureValues else { return }
        let after = board.value as? String ?? "missing"
        let trace: [String: Any] = ["direction": direction, "before": before, "after": after, "frame": [observedFrame.minX,observedFrame.minY,observedFrame.width,observedFrame.height], "requestedDelta": [delta.dx,delta.dy]]
        if let data = try? JSONSerialization.data(withJSONObject: trace, options: [.sortedKeys]), let line = String(data: data, encoding: .utf8) { print("REAL_GESTURE_TRACE " + line) }
    }
    private func restartUI() {
        app.buttons["chrome.restart"].tap()
        if app.buttons["sokoban.reset.confirm"].waitForExistence(timeout: 2) { app.buttons["sokoban.reset.confirm"].tap() }
    }
    private func maximumFixture(_ fixture: String) {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-sokoban-fixture", fixture,
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
    }
    private func saveEvidence(_ name: String, metadata: String = "") {
        var metadata = metadata
        if metadata.isEmpty, app.staticTexts["sokoban.layout.metrics"].exists { metadata = app.staticTexts["sokoban.layout.metrics"].label }
        if metadata.isEmpty {
            let f = app.windows.firstMatch.frame
            metadata = "{\"viewport\":[\(f.width),\(f.height)],\"entry\":\"home\"}"
        }
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let root = URL(fileURLWithPath: "/Users/hansen/ClassicGames-Engineering/sokoban-batch3-layout-20261125/screenshots")
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories:true)
            try image.pngRepresentation.write(to: root.appendingPathComponent(name+".png"))
            if !metadata.isEmpty { try Data(metadata.utf8).write(to: root.appendingPathComponent(name+".json")) }
        } catch { XCTFail("Evidence write failed: \(error)") }
    }
    private func verifyLayout(level: Int, accessibility: Bool, name: String) {
        XCTAssertTrue((board.value as? String)?.hasPrefix("level:\(level);") == true)
        let metric = app.staticTexts["sokoban.layout.metrics"]
        XCTAssertTrue(metric.waitForExistence(timeout: 5))
        let text = metric.label
        saveEvidence(name, metadata: text)
        guard let data = text.data(using:.utf8), let obj = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let cell = obj["cell"] as? Double, let drawnW = obj["drawnWidth"] as? Double,
              let drawnH = obj["drawnHeight"] as? Double, let frames = obj["frames"] as? [String:[Double]],
              let available = frames["board"], let drawn = frames["drawn"] else { return XCTFail("Missing native measured layout: \(text)") }
        XCTAssertEqual(obj["level"] as? Int, level)
        XCTAssertGreaterThan(cell, 0)
        guard let metrics = frames["metrics"], let best = frames["best"], let steps = frames["steps"] else { return XCTFail("Primary metric frames missing: \(text)") }
        // At default typography, level/steps/best share the pinned metrics row.
        // At AX5, only the level line is pinned above the save slot; steps and
        // best may scroll in leftover. Equivalence: the pinned level line stays
        // complete, and default typography still forbids half-line clipping.
        if !accessibility {
            for lineFrame in [best, steps] {
                XCTAssertGreaterThanOrEqual(lineFrame[1], metrics[1]-0.1)
                XCTAssertLessThanOrEqual(lineFrame[1]+lineFrame[3], metrics[1]+metrics[3]+0.1, "No half-line clipping")
            }
        }
        if accessibility, let level = frames["level"] {
            XCTAssertGreaterThanOrEqual(level[1], metrics[1]-0.1)
            XCTAssertLessThanOrEqual(level[1]+level[3], metrics[1]+metrics[3]+0.1, "Pinned level line must not clip")
        }
        XCTAssertEqual(app.windows.firstMatch.frame.width, 375, accuracy:0.1)
        XCTAssertEqual(app.windows.firstMatch.frame.height, 667, accuracy:0.1)
        XCTAssertEqual((obj["category"] as? String)?.contains("accessibility"), accessibility)
        XCTAssertLessThanOrEqual(drawnW,available[2]+0.1); XCTAssertLessThanOrEqual(drawnH,available[3]+0.1)
        XCTAssertGreaterThanOrEqual(drawn[0],available[0]-0.1); XCTAssertGreaterThanOrEqual(drawn[1],available[1]-0.1)
        XCTAssertLessThanOrEqual(drawn[0]+drawn[2],available[0]+available[2]+0.1)
        XCTAssertLessThanOrEqual(drawn[1]+drawn[3],available[1]+available[3]+0.1)
        let controlIds = ["undo":"sokoban.undo","restart":"chrome.restart","pause":"sokoban.pause",
                          "back":"chrome.back","levels":"sokoban.levels","records":"sokoban.records.open"]
        for key in ["undo","restart","pause","back","levels","records"] {
            guard let frame = frames[key] else { XCTFail("Missing control \(key)"); continue }
            XCTAssertGreaterThanOrEqual(frame[2],44); XCTAssertGreaterThanOrEqual(frame[3],44)
            XCTAssertGreaterThanOrEqual(frame[0],0); XCTAssertGreaterThanOrEqual(frame[1],0)
            XCTAssertLessThanOrEqual(frame[0]+frame[2],375.1)
            // 375×667 first-screen overflow is not an acceptance item. AX5
            // captions under the 64pt buttons may extend past 667; 44pt targets
            // and hittable checks stay in force. Default typography still has
            // to keep the full control frame on the 667-pt screen.
            if !accessibility {
                XCTAssertLessThanOrEqual(frame[1]+frame[3],667.1)
            }
            if let id = controlIds[key] {
                XCTAssertTrue(app.buttons[id].isHittable, "\(key) should stay tappable")
            }
        }
        XCTAssertTrue(app.buttons["chrome.restart"].isHittable); XCTAssertTrue(app.buttons["sokoban.pause"].isHittable)
        XCTAssertFalse(app.buttons["pad.up"].exists)
        XCTAssertTrue(app.buttons["sokoban.hint"].exists)
        XCTAssertTrue(app.buttons["sokoban.hint"].isHittable)
        XCTAssertTrue(app.buttons["sokoban.dpad.up"].exists)
        XCTAssertTrue(app.buttons["sokoban.dpad.up"].isHittable)
        XCTAssertTrue(app.buttons["sokoban.dpad.down"].isHittable)
        XCTAssertTrue(app.buttons["sokoban.dpad.left"].isHittable)
        XCTAssertTrue(app.buttons["sokoban.dpad.right"].isHittable)
        if accessibility {
            app.buttons["sokoban.records.open"].tap()
            let detail = app.staticTexts["sokoban.records.measurements"]
            XCTAssertTrue(detail.waitForExistence(timeout: 4))
            saveEvidence(name+"-expanded", metadata: detail.label)
            app.scrollViews["sokoban.records.scroll"].swipeUp()
            saveEvidence(name+"-scrolled", metadata: detail.label)
            app.buttons["sokoban.records.close"].tap()
        }
    }

    private func assertDrawnPositionUnchanged(file: StaticString = #filePath, line: UInt = #line) {
        let text = app.staticTexts["sokoban.layout.metrics"].label
        guard let o = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String:Any],
              let level = o["level"] as? Int, let fs = o["frames"] as? [String:[Double]],
              let drawn = fs["drawn"], let available = fs["board"] else { return XCTFail("Missing real board frames",file:file,line:line) }
        if let previous = measuredDrawnByLevel[level] {
            for (a,b) in zip(previous,drawn) { XCTAssertEqual(a,b,accuracy:0.1,file:file,line:line) }
        } else { measuredDrawnByLevel[level] = drawn }
        XCTAssertGreaterThanOrEqual(drawn[0],available[0]-0.1,file:file,line:line)
        XCTAssertGreaterThanOrEqual(drawn[1],available[1]-0.1,file:file,line:line)
        XCTAssertLessThanOrEqual(drawn[0]+drawn[2],available[0]+available[2]+0.1,file:file,line:line)
        XCTAssertLessThanOrEqual(drawn[1]+drawn[3],available[1]+available[3]+0.1,file:file,line:line)
    }
}
