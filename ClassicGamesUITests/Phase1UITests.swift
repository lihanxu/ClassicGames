import XCTest

/// 阶段 1 总检查：四款都能结束并重开，较差的推箱子成绩不覆盖纪录，关掉 App 后纪录还在。
final class Phase1UITests: XCTestCase {
    private var app = XCUIApplication()
    private let sokobanNamespace = "sokoban.ui." + UUID().uuidString.lowercased()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["CLASSICGAMES_SOKOBAN_TEST_NAMESPACE"] = sokobanNamespace
        app.launchArguments = ["-ui-testing", "-reset-scores"]
        app.launch()
    }

    func testAllFourPersistAcrossRelaunch() {
        for name in ["推箱子", "贪吃蛇", "打砖块", "2048"] {
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 8), name)
        }
        Screenshot.save("08-home-four.png")

        clearSokobanTwice()
        let snakeBest = finishSnake()
        let breakoutBest = finishBreakout()
        let game2048Best = finish2048()

        app.terminate()
        app.launchEnvironment["CLASSICGAMES_SOKOBAN_TEST_NAMESPACE"] = sokobanNamespace
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["推箱子"].waitForExistence(timeout: 8))
        // 首页推箱子主卡展示已通关关数；33 步纪录仍由局内「最高纪录」断言覆盖。
        XCTAssertEqual(app.staticTexts["home.best.sokoban"].label, "已通关 1/100")
        XCTAssertEqual(app.staticTexts["home.best.snake"].label, "最高 \(snakeBest)")
        XCTAssertEqual(app.staticTexts["home.best.breakout"].label, "最高 \(breakoutBest)")
        XCTAssertEqual(app.staticTexts["home.best.game2048"].label, "最高 \(game2048Best)")
        Screenshot.save("09-home-after-relaunch.png")
    }

    /// 先用 33 步过关，再用 35 步过关。纪录应留在较少的 33。
    private func clearSokobanTwice() -> Int {
        app.buttons["home.row.sokoban"].tap()
        let board = app.descendants(matching: .any)["sokoban.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        playSokoban(SokobanMoves.short)
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 5))
        // 推箱子局内纪录在 sokoban.best，文案为「本关纪录」，与原先 chrome.best「最高纪录」同等约束。
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")

        app.buttons["chrome.restart"].tap()
        XCTAssertEqual(board.value as? String, SokobanMoves.start)
        playSokoban(SokobanMoves.long)
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "步数 35")
        XCTAssertEqual(app.staticTexts["sokoban.best"].label, "本关纪录 33")
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.sokoban"].waitForExistence(timeout: 5))
        return 33
    }

    /// 不转向，等蛇自己撞上右墙。
    private func finishSnake() -> Int {
        app.buttons["home.row.snake"].tap()
        let state = wait(id: "snake.state", timeout: 8) { raw in
            raw.contains("over:true")
        }
        XCTAssertTrue(app.staticTexts["死亡"].waitForExistence(timeout: 2))
        let score = value(in: state, key: "score")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 \(score)")
        app.buttons["chrome.restart"].tap()
        let restarted = wait(id: "snake.state", timeout: 3) { raw in
            raw.contains("score:0") && raw.contains("len:3") && raw.contains("over:false")
        }
        XCTAssertTrue(restarted.contains("len:3"), restarted)
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.snake"].waitForExistence(timeout: 5))
        return score
    }

    /// 发球后把挡板躲开，直到 3 条命用完。
    private func finishBreakout() -> Int {
        app.buttons["home.row.breakout"].tap()
        let scene = app.descendants(matching: .any)["breakout.scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 5))
        _ = wait(id: "breakout.state", timeout: 4) { $0.contains("bricks:32") }
        dragBreakout(in: scene, toX: 0.7)
        var latest = wait(id: "breakout.state", timeout: 8) { $0.contains("score:") && !scoreIsZero($0) || $0.contains("launched:true") }
        while !latest.contains("over:true") {
            if latest.contains("launched:true") {
                let ballX = fraction(in: latest, key: "ball")
                dragBreakout(in: scene, toX: ballX < 0.5 ? 0.9 : 0.1)
            } else {
                dragBreakout(in: scene, toX: 0.62)
            }
            latest = wait(id: "breakout.state", timeout: 12) { raw in
                raw.contains("over:true") || raw.contains("launched:false")
            }
            if latest.contains("over:true") { break }
        }
        XCTAssertTrue(app.staticTexts["结束"].waitForExistence(timeout: 2))
        let score = value(in: latest, key: "score")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 \(score)")
        app.buttons["chrome.restart"].tap()
        let restarted = wait(id: "breakout.state", timeout: 4) { raw in
            raw.contains("lives:3") && raw.contains("bricks:32") && raw.contains("score:0")
        }
        XCTAssertTrue(restarted.contains("lives:3"), restarted)
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.breakout"].waitForExistence(timeout: 5))
        return score
    }

    /// 点一次能走的方向，再让这一局按规则走到结束。
    private func finish2048() -> Int {
        app.buttons["home.row.game2048"].tap()
        let opening = wait(id: "game2048.board", timeout: 4) { $0.contains("cells:") }
        app.buttons["pad.left"].tap()
        app.descendants(matching: .any)["game2048.finish"].tap()
        let ended = wait(id: "game2048.board", timeout: 8) { raw in
            guard raw.contains("over:true") else { return false }
            let score = value(in: raw, key: "score")
            return app.staticTexts["chrome.score"].label == "本局 \(score)"
                && app.staticTexts["chrome.best"].label == "最高纪录 \(score)"
        }
        XCTAssertTrue(app.staticTexts["结束"].waitForExistence(timeout: 2), ended)
        let score = value(in: ended, key: "score")
        XCTAssertGreaterThan(score, 0, ended)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "本局 \(score)", ended)
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 \(score)", ended)
        let locked = ended
        app.buttons["pad.up"].tap()
        let after = app.descendants(matching: .any)["game2048.board"].label
        XCTAssertEqual(after, locked)
        app.buttons["chrome.restart"].tap()
        let restarted = wait(id: "game2048.board", timeout: 4) { raw in
            raw.contains("score:0") && raw.contains("over:false")
        }
        XCTAssertTrue(restarted.contains("score:0"), restarted)
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.game2048"].waitForExistence(timeout: 5))
        _ = opening
        return score
    }

    /// 推箱子已改为滑动移一格，不再提供方向键。这里用与 SokobanUITests 同等的滑动输入走完同一条官方解。
    private func playSokoban(_ moves: [String]) {
        let board = app.descendants(matching: .any)["sokoban.board"]
        for move in moves {
            let direction = move.replacingOccurrences(of: "pad.", with: "")
            let before = board.value as? String ?? "missing"
            let point = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let distance: CGFloat = 60
            let delta: CGVector
            switch direction {
            case "up": delta = CGVector(dx: 0, dy: -distance)
            case "down": delta = CGVector(dx: 0, dy: distance)
            case "left": delta = CGVector(dx: -distance, dy: 0)
            default: delta = CGVector(dx: distance, dy: 0)
            }
            var changed = false
            for _ in 0..<3 {
                point.press(forDuration: 0.05, thenDragTo: point.withOffset(delta))
                let deadline = Date().addingTimeInterval(0.9)
                while Date() < deadline {
                    if (board.value as? String ?? "missing") != before {
                        changed = true
                        break
                    }
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.04))
                }
                if changed { break }
            }
            // 等步进动画结束，再滑下一步，避免把未完成的滑动吃掉。
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.25))
        }
    }

    private func dragBreakout(in scene: XCUIElement, toX: CGFloat) {
        let raw = app.descendants(matching: .any)["breakout.state"].label
        let paddleY = fraction(in: raw, key: "paddle", component: 1)
        let paddleX = fraction(in: raw, key: "paddle", component: 0)
        let dy = 1 - max(0.05, min(paddleY, 0.4))
        let start = scene.coordinate(withNormalizedOffset: CGVector(dx: max(0.08, min(paddleX, 0.92)), dy: dy))
        let end = scene.coordinate(withNormalizedOffset: CGVector(dx: max(0.08, min(toX, 0.92)), dy: dy))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func wait(id: String, timeout: TimeInterval, where predicate: (String) -> Bool) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = ""
        while Date() < deadline {
            latest = app.descendants(matching: .any)[id].label
            if predicate(latest) { return latest }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return latest
    }

    private func value(in raw: String, key: String) -> Int {
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            if pieces.first == key { return Int(pieces.last ?? "") ?? 0 }
        }
        return 0
    }

    private func fraction(in raw: String, key: String, component: Int = 0) -> Double {
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.first == key else { continue }
            let numbers = pieces.last?.split(separator: ",").map { Double($0) ?? 0 } ?? []
            return numbers.indices.contains(component) ? numbers[component] : 0
        }
        return 0
    }

    private func scoreIsZero(_ raw: String) -> Bool {
        raw.contains("score:0")
    }
}
