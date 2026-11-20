import XCTest

/// 阶段 3 的模拟器检查：跑、跳、顶砖、踩敌人、失败不写纪录、到终点才记分。
final class PlatformerUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-game", "platformer"]
        app.launch()
    }

    func testRunJumpBrickStompAndGoal() {
        let play = PlatformerDriver(app: app)
        play.open()
        for word in ["马里奥", "马力欧", "Mario", "Goomba", "Koopa", "任天堂", "库巴"] {
            XCTAssertFalse(app.staticTexts[word].exists, word)
            XCTAssertFalse(app.buttons[word].exists, word)
        }

        let opening = play.wait { $0.status == "play" && $0.ground && $0.bricks == 2 && $0.enemy }
        XCTAssertEqual(opening.score, 0, opening.raw)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "本局 0")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 —")

        let movedRight = play.hold("向右", 0.40)
        XCTAssertGreaterThan(movedRight.x, opening.x + 24, movedRight.raw)
        let movedLeft = play.hold("向左", 0.40)
        XCTAssertLessThan(movedLeft.x, movedRight.x - 18, movedLeft.raw)
        let settled = play.settle()
        let still = play.settle()
        XCTAssertLessThanOrEqual(abs(settled.x - still.x), 8, "\(settled.raw) \(still.raw)")

        let beforeJump = play.wait { $0.ground && $0.status == "play" }
        play.tap("跳跃")
        let airborne = play.wait(timeout: 2.5) { !$0.ground && $0.y > beforeJump.y + 16 }
        XCTAssertFalse(airborne.ground, airborne.raw)
        XCTAssertEqual(airborne.jumps, beforeJump.jumps + 1, airborne.raw)
        play.tap("跳跃")
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        let second = play.read()
        XCTAssertEqual(second.jumps, airborne.jumps, second.raw)
        XCTAssertLessThan(second.vy, 400, second.raw)
        let landed = play.wait(timeout: 2) { $0.ground && $0.status == "play" }
        XCTAssertEqual(landed.jumps, beforeJump.jumps + 1, landed.raw)
        XCTAssertLessThanOrEqual(abs(landed.y - beforeJump.y), 4, landed.raw)

        let stomped = play.stomp()
        XCTAssertFalse(stomped.enemy, stomped.raw)
        XCTAssertEqual(stomped.score, opening.score + 1, stomped.raw)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "本局 \(stomped.score)")

        let broke = play.breakBrick()
        XCTAssertLessThan(broke.bricks, 2, broke.raw)
        XCTAssertEqual(broke.score, stomped.score + (2 - broke.bricks), broke.raw)

        let bestBeforeFail = app.staticTexts["chrome.best"].label
        app.buttons["chrome.restart"].tap()
        let restarted = play.wait(timeout: 3) { $0.score == 0 && $0.enemy && $0.bricks == 2 && $0.status == "play" && $0.x < 80 }
        XCTAssertEqual(restarted.score, 0, restarted.raw)
        XCTAssertEqual(app.staticTexts["chrome.best"].label, bestBeforeFail)

        play.hold("向右", 2.2)
        let failed = play.wait(timeout: 3) { $0.status == "fail" }
        XCTAssertEqual(failed.status, "fail", failed.raw)
        XCTAssertTrue(app.staticTexts["失败"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 —")
        let frozen = failed.x
        play.hold("向右", 0.25)
        let afterFailInput = play.read()
        XCTAssertLessThanOrEqual(abs(afterFailInput.x - frozen), 4, afterFailInput.raw)

        app.buttons["chrome.restart"].tap()
        _ = play.wait(timeout: 3) { $0.status == "play" && $0.score == 0 && $0.enemy && $0.x < 80 }
        let won = play.reachGoal()
        XCTAssertEqual(won.status, "win", won.raw)
        XCTAssertEqual(won.bonus, 5, won.raw)
        XCTAssertGreaterThanOrEqual(won.score, 5, won.raw)
        XCTAssertTrue(app.staticTexts["过关"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "本局 \(won.score)")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 \(won.score)")
        Screenshot.save("14-platformer.png")

        let locked = won.x
        play.hold("向右", 0.25)
        let afterWinInput = play.read()
        XCTAssertEqual(afterWinInput.status, "win", afterWinInput.raw)
        XCTAssertLessThanOrEqual(abs(afterWinInput.x - locked), 4, afterWinInput.raw)
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.platformer"].waitForExistence(timeout: 5))
    }
}

/// 阶段 3 总检查：首页有八款，跑跳能结束并重开，前面两阶段的纪录还在。
final class Phase3UITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testEightGamesKeepEarlierScores() {
        for name in ["推箱子", "贪吃蛇", "打砖块", "2048", "扫雷", "翻牌记忆", "五子棋", "跑跳"] {
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 8), name)
        }
        let before = captureBests()
        let phase12 = [
            "home.best.sokoban", "home.best.snake", "home.best.breakout", "home.best.game2048",
            "home.best.minesweeper", "home.best.memory", "home.best.gomoku"
        ]

        let play = PlatformerDriver(app: app)
        play.open()
        _ = play.wait { $0.status == "play" && $0.x < 80 }
        let won = play.reachGoal()
        XCTAssertEqual(won.status, "win", won.raw)
        XCTAssertEqual(won.bonus, 5, won.raw)
        let shown = app.staticTexts["chrome.best"].label
        app.buttons["chrome.restart"].tap()
        let restarted = play.wait(timeout: 3) { $0.status == "play" && $0.score == 0 && $0.x < 90 }
        XCTAssertEqual(restarted.status, "play", restarted.raw)
        XCTAssertEqual(app.staticTexts["chrome.best"].label, shown)
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.staticTexts["跑跳"].waitForExistence(timeout: 5))

        scrollToTop()
        Screenshot.save("15-home-phase3.png")
        let after = captureBests()
        for id in phase12 {
            XCTAssertEqual(after[id], before[id], id)
        }
        XCTAssertNotEqual(after["home.best.platformer"], "最高 —")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["经典小游戏"].waitForExistence(timeout: 8))
        let again = captureBests()
        for id in phase12 {
            XCTAssertEqual(again[id], before[id], id)
        }
        XCTAssertEqual(again["home.best.platformer"], after["home.best.platformer"])
    }

    /// 先读画面上方的纪录，再往下把后面几款滑出来。
    private func captureBests() -> [String: String] {
        scrollToTop()
        var labels: [String: String] = [:]
        let upper = ["home.best.sokoban", "home.best.snake", "home.best.breakout", "home.best.game2048"]
        for id in upper {
            let text = app.staticTexts[id]
            XCTAssertTrue(text.waitForExistence(timeout: 3), id)
            labels[id] = text.label
        }
        let lower = ["home.best.minesweeper", "home.best.memory", "home.best.gomoku", "home.best.platformer"]
        for id in lower {
            labels[id] = reveal(id).label
        }
        return labels
    }

    /// 列表滑回顶部。
    private func scrollToTop() {
        for _ in 0..<5 {
            let title = app.staticTexts["home.title"]
            if title.exists, title.frame.minY > 0, title.frame.minY < 220 { return }
            app.swipeDown()
        }
    }

    /// 把还没出现的行滑进列表。
    private func reveal(_ identifier: String) -> XCUIElement {
        let query = app.staticTexts[identifier]
        var swipes = 0
        while !query.exists, swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(query.waitForExistence(timeout: 2), identifier)
        return query
    }
}

/// 跑跳场景的操作。检查和总验收共用，避免两套点法。
struct PlatformerDriver {
    let app: XCUIApplication

    /// 从首页进入跑跳。最后一行贴着底边时，先往上滑再点中间。
    func open() {
        let button = app.buttons["home.row.platformer"]
        var swipes = 0
        while swipes < 6 {
            let visible = button.exists && button.frame.minY > 90 && button.frame.maxY < app.frame.height - 70
            if visible { break }
            if button.exists, button.frame.minY < 90 {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            swipes += 1
        }
        XCTAssertTrue(button.waitForExistence(timeout: 4))
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        _ = wait { $0.raw.contains("status:") }
    }

    /// 按住场景里的按钮一会儿。用画面比例点，不依赖按钮节点的空框。
    @discardableResult
    func hold(_ identifier: String, _ seconds: TimeInterval) -> PlatformerState {
        point(identifier).press(forDuration: seconds)
        return read()
    }

    /// 点一下跳跃或方向。用短按，和按住走同一条触摸。
    func tap(_ identifier: String) {
        point(identifier).press(forDuration: 0.06)
    }

    /// 按钮中心在场景里的坐标。
    func point(_ identifier: String) -> XCUICoordinate {
        let state = read()
        let scene = app.descendants(matching: .any)["platformer.scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 3))
        let dx: CGFloat
        switch identifier {
        case "向左": dx = CGFloat(state.padLeft)
        case "跳跃": dx = CGFloat(state.padJump)
        default: dx = CGFloat(state.padRight)
        }
        return scene.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: CGFloat(state.padY)))
    }

    /// 松手之后站着不动，确认速度已经停下来。
    func settle() -> PlatformerState {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        return read()
    }

    /// 站在敌人区间左边，等它走过来时跳起来踩住。
    func stomp() -> PlatformerState {
        let stand = read().patrolMin - 36
        run(to: stand, tolerance: 14)
        let started = Date()
        while Date().timeIntervalSince(started) < 22 {
            let state = read()
            if !state.enemy { return state }
            if state.status != "play" { return state }
            let distance = abs(state.enemyX - state.x)
            let toward = (state.x - state.enemyX) * state.dir > 0
            let standing = state.y < 110
            if standing, toward, distance >= 40, distance <= 68 {
                tap("跳跃")
                let landed = wait(timeout: 4.5) { !$0.enemy || ($0.y < 110 && $0.jumps > state.jumps) || $0.status != "play" }
                if !landed.enemy || landed.status != "play" { return landed }
            } else {
                RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            }
        }
        return read()
    }

    /// 跑到第一块砖下面，跳起来把它顶掉。
    func breakBrick() -> PlatformerState {
        let brick = read().brick
        run(to: brick, tolerance: 12)
        let before = read().bricks
        tap("跳跃")
        return wait(timeout: 4.5) { $0.bricks < before && $0.ground }
    }

    /// 从左侧起跳并按住向右，飞过坑，落到对面后跑进终点。
    func reachGoal() -> PlatformerState {
        let right = point("向右")
        let jump = point("跳跃")
        right.press(forDuration: 0.08, thenDragTo: jump, withVelocity: .fast, thenHoldForDuration: 4.4)
        return wait(timeout: 2) { $0.status != "play" }
    }

    /// 短按左右，走到目标横坐标附近，避免一下跑进坑里。
    func run(to target: Int, tolerance: Int) {
        for _ in 0..<24 {
            let state = read()
            if state.status != "play" { return }
            if abs(state.x - target) <= tolerance { return }
            let gap = abs(state.x - target)
            let seconds = min(0.32, max(0.08, Double(gap) / 220))
            hold(state.x < target ? "向右" : "向左", seconds)
        }
    }

    /// 读当前摘要。
    func read() -> PlatformerState {
        let element = app.descendants(matching: .any)["platformer.state"]
        return PlatformerState(element.label)
    }

    /// 等到条件成立，超时就返回最后一次读到的状态。
    func wait(timeout: TimeInterval = 3, where predicate: (PlatformerState) -> Bool) -> PlatformerState {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = read()
        while Date() < deadline {
            latest = read()
            if latest.raw.contains("status:"), predicate(latest) { return latest }
            RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        }
        return latest
    }
}

/// 跑跳场景公布的一行摘要。
struct PlatformerState {
    var raw: String
    var x = 0
    var y = 0
    var vy = 0
    var ground = false
    var jumps = 0
    var score = 0
    var bricks = 0
    var enemy = false
    var enemyX = 0
    var dir = 0
    var patrolMin = 0
    var patrolMax = 0
    var brick = 0
    var edge = 0
    var padLeft = 0.20
    var padRight = 0.48
    var padJump = 0.80
    var padY = 0.90
    var status = ""
    var bonus = 0

    init(_ raw: String) {
        self.raw = raw
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            switch pieces[0] {
            case "x": x = Int(pieces[1]) ?? 0
            case "y": y = Int(pieces[1]) ?? 0
            case "vy": vy = Int(pieces[1]) ?? 0
            case "ground": ground = pieces[1] == "true"
            case "jumps": jumps = Int(pieces[1]) ?? 0
            case "score": score = Int(pieces[1]) ?? 0
            case "bricks": bricks = Int(pieces[1]) ?? 0
            case "enemy": enemy = pieces[1] == "true"
            case "enemyX": enemyX = Int(pieces[1]) ?? 0
            case "dir": dir = Int(pieces[1]) ?? 0
            case "patrol":
                let ends = pieces[1].split(separator: ",").map { Int($0) ?? 0 }
                patrolMin = ends.first ?? 0
                patrolMax = ends.dropFirst().first ?? 0
            case "brick": brick = Int(pieces[1]) ?? 0
            case "edge": edge = Int(pieces[1]) ?? 0
            case "pad":
                let values = pieces[1].split(separator: ",").map { Double($0) ?? 0 }
                if values.count == 4 {
                    padLeft = values[0]
                    padRight = values[1]
                    padJump = values[2]
                    padY = values[3]
                }
            case "status": status = pieces[1]
            case "bonus": bonus = Int(pieces[1]) ?? 0
            default: break
            }
        }
    }
}
