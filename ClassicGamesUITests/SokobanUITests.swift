import XCTest

/// 第 1 关的开局、最短走法和多走两步的走法。步数来自这一关的最短解。
enum SokobanMoves {
    static let start = "level:1;player:3,2;boxes:3,1|4,3;steps:0;won:false"
    static let win = "level:1;player:2,2;boxes:1,2|3,1;steps:33;won:true"
    static let longWin = "level:1;player:2,2;boxes:1,2|3,1;steps:35;won:true"
    static let level2 = "level:2;player:2,3;boxes:3,2|3,3|4,3;steps:0;won:false"
    static let level20 = "level:20;player:2,3;boxes:2,4|2,5;steps:0;won:false"
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
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        XCTAssertTrue(app.buttons["chrome.back"].isHittable)
    }

    /// 方向键按顺序点。每一步都进同一个移动方法。
    private func play(_ moves: [String]) {
        for move in moves {
            app.buttons[move].tap()
        }
    }
}
