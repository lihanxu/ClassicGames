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

    /// 用固定的听感重新打开。正式游玩不带这个参数。
    private func launch(hearing: String) {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-game", "sokoban", "-sokoban-hearing", hearing]
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

    /// 方向键按顺序点。每一步都进同一个移动方法。
    private func play(_ moves: [String]) {
        for move in moves {
            app.buttons[move].tap()
        }
    }
}
