import XCTest

/// 贪吃蛇的模拟器检查：自己往前走、转向、吃食物、撞墙、重开、再进入。
final class SnakeUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testEatDieRestartAndReturn() {
        XCTAssertTrue(app.buttons["home.row.snake"].waitForExistence(timeout: 8))
        app.buttons["home.row.snake"].tap()

        let scene = app.descendants(matching: .any)["snake.scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(scene.frame.height, 200)

        let seen = waitForState { $0.food.col >= 0 && $0.head.col >= 0 }
        XCTAssertFalse(seen.over, seen.raw)
        let started = seen.head
        let moved = waitForState(timeout: 3) { state in
            state.head != started
        }
        XCTAssertNotEqual(moved.head, started, "蛇没有自己往前走 \(moved.raw)")

        let turn = sideTurn(from: moved)
        tapDirection(turn, in: scene)
        let turned = waitForState(timeout: 2) { $0.dir == turn }
        XCTAssertEqual(turned.dir, turn, "点方向没有转向 \(turned.raw)")

        let opposite = oppositeDirection(turn)
        let rowBefore = turned.head.row
        let colBefore = turned.head.col
        tapDirection(opposite, in: scene)
        Thread.sleep(forTimeInterval: 1.1)
        let ignored = currentState()
        XCTAssertEqual(ignored.dir, turn, "相反方向不该生效 \(ignored.raw)")
        if turn == "up" {
            XCTAssertLessThan(ignored.head.row, rowBefore)
        } else if turn == "down" {
            XCTAssertGreaterThan(ignored.head.row, rowBefore)
        } else if turn == "left" {
            XCTAssertLessThan(ignored.head.col, colBefore)
        } else {
            XCTAssertGreaterThan(ignored.head.col, colBefore)
        }

        let eaten = waitForState(timeout: 25) { state in
            if state.score < 1, !state.over {
                tapDirection(self.directionTowardFood(state), in: scene)
            }
            return state.score >= 1 || state.over
        }
        XCTAssertFalse(eaten.over, "还没吃到就结束了 \(eaten.raw)")
        XCTAssertEqual(eaten.score, 1, eaten.raw)
        XCTAssertEqual(eaten.len, 4, eaten.raw)
        XCTAssertNotEqual(eaten.food, eaten.head)

        let dead = waitForState(timeout: 20) { state in
            if !state.over {
                tapDirection(self.directionTowardWall(state), in: scene)
            }
            return state.over
        }
        XCTAssertTrue(dead.over, dead.raw)
        XCTAssertTrue(app.staticTexts["死亡"].waitForExistence(timeout: 2))
        Thread.sleep(forTimeInterval: 0.55)
        let stopped = currentState()
        XCTAssertEqual(stopped.head, dead.head, "死亡后还在移动 \(stopped.raw)")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "本局 \(stopped.score)")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 \(stopped.score)")
        Screenshot.save("05-snake-death.png")

        let best = app.staticTexts["chrome.best"].label
        app.buttons["chrome.restart"].tap()
        let restarted = waitForState(timeout: 3) { $0.len == 3 && $0.score == 0 && !$0.over }
        XCTAssertEqual(restarted.len, 3)
        XCTAssertEqual(restarted.score, 0)
        XCTAssertFalse(app.staticTexts["死亡"].exists)
        XCTAssertEqual(app.staticTexts["chrome.best"].label, best)

        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.snake"].waitForExistence(timeout: 5))
        app.buttons["home.row.snake"].tap()
        let fresh = waitForState(timeout: 3) { $0.food.col >= 0 }
        XCTAssertFalse(fresh.over)
        XCTAssertEqual(fresh.score, 0)
        XCTAssertEqual(fresh.len, 3)
        XCTAssertFalse(app.staticTexts["死亡"].exists)
    }

    /// 读场景公布的蛇状态。长度文字仍显示「长度 n」。
    private func currentState() -> SnakeState {
        let element = app.descendants(matching: .any)["snake.state"]
        let raw = (element.value as? String).flatMap { $0.contains("score:") ? $0 : nil }
            ?? element.label
        return SnakeState(raw)
    }

    /// 等到条件成立。等待时反复读取，方便蛇自己往前走。
    private func waitForState(timeout: TimeInterval = 5, where predicate: (SnakeState) -> Bool) -> SnakeState {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = currentState()
        while Date() < deadline {
            latest = currentState()
            if predicate(latest), latest.raw.contains("score:") {
                return latest
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return latest
    }

    /// 点场景底部的方向按钮。优先点到暴露出来的按钮，否则按布局比例点。
    private func tapDirection(_ direction: String, in scene: XCUIElement) {
        let title = ["up": "上", "down": "下", "left": "左", "right": "右"][direction] ?? direction
        let button = app.buttons[title]
        if button.exists, button.isHittable {
            button.tap()
            return
        }
        let text = app.staticTexts[title]
        if text.exists, text.isHittable {
            text.tap()
            return
        }
        let strip = 0.24
        let dx: CGFloat
        let dy: CGFloat
        switch direction {
        case "up":
            dx = 0.50
            dy = 1 - strip * 0.70
        case "down":
            dx = 0.50
            dy = 1 - strip * 0.28
        case "left":
            dx = 0.50 - 0.20
            dy = 1 - strip * 0.28
        default:
            dx = 0.50 + 0.20
            dy = 1 - strip * 0.28
        }
        scene.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
    }

    private func oppositeDirection(_ direction: String) -> String {
        switch direction {
        case "up": "down"
        case "down": "up"
        case "left": "right"
        default: "left"
        }
    }

    /// 选一个和当前方向垂直、短时间内不会吃到食物或撞墙的方向。
    private func sideTurn(from state: SnakeState) -> String {
        let options = ["up", "down", "left", "right"].filter { $0 != state.dir && $0 != oppositeDirection(state.dir) }
        for option in options where clearSteps(state, direction: option) >= 4 && !rayHitsFood(state, direction: option, limit: 4) {
            return option
        }
        return options.first ?? "up"
    }

    /// 朝食物走。当前方向的反方向不会被选中。
    private func directionTowardFood(_ state: SnakeState) -> String {
        var prefs: [String] = []
        if state.food.col > state.head.col { prefs.append("right") }
        if state.food.col < state.head.col { prefs.append("left") }
        if state.food.row > state.head.row { prefs.append("down") }
        if state.food.row < state.head.row { prefs.append("up") }
        for pref in prefs where pref != oppositeDirection(state.dir) && nextIsInside(state, direction: pref) {
            return pref
        }
        for fallback in ["up", "down", "left", "right"] where fallback != oppositeDirection(state.dir) && nextIsInside(state, direction: fallback) {
            return fallback
        }
        return state.dir
    }

    /// 朝一面墙直走，路上不要先吃到食物。
    private func directionTowardWall(_ state: SnakeState) -> String {
        for direction in ["right", "left", "up", "down"] where direction != oppositeDirection(state.dir) && rayHitsWallBeforeFood(state, direction: direction) {
            return direction
        }
        for direction in ["right", "left", "up", "down"] where direction != oppositeDirection(state.dir) && nextIsInside(state, direction: direction) {
            return direction
        }
        return state.dir
    }

    private func nextIsInside(_ state: SnakeState, direction: String) -> Bool {
        let next = stepped(state.head, direction)
        return next.col >= 0 && next.row >= 0 && next.col < 16 && next.row < 16
    }

    private func clearSteps(_ state: SnakeState, direction: String) -> Int {
        var cell = state.head
        var steps = 0
        while steps < 16 {
            cell = stepped(cell, direction)
            if cell.col < 0 || cell.row < 0 || cell.col > 15 || cell.row > 15 { break }
            steps += 1
        }
        return steps
    }

    private func rayHitsFood(_ state: SnakeState, direction: String, limit: Int) -> Bool {
        var cell = state.head
        for _ in 0..<limit {
            cell = stepped(cell, direction)
            if cell == state.food { return true }
        }
        return false
    }

    private func rayHitsWallBeforeFood(_ state: SnakeState, direction: String) -> Bool {
        var cell = state.head
        for _ in 0..<16 {
            cell = stepped(cell, direction)
            if cell == state.food { return false }
            if cell.col < 0 || cell.row < 0 || cell.col > 15 || cell.row > 15 { return true }
        }
        return false
    }

    private func stepped(_ cell: SnakeCellPoint, _ direction: String) -> SnakeCellPoint {
        switch direction {
        case "up": SnakeCellPoint(col: cell.col, row: cell.row - 1)
        case "down": SnakeCellPoint(col: cell.col, row: cell.row + 1)
        case "left": SnakeCellPoint(col: cell.col - 1, row: cell.row)
        default: SnakeCellPoint(col: cell.col + 1, row: cell.row)
        }
    }
}

/// 从场景公布的摘要里拆出蛇头、食物和分数。
struct SnakeState {
    var raw: String
    var score = 0
    var len = 0
    var over = false
    var dir = ""
    var head = SnakeCellPoint(col: -1, row: -1)
    var food = SnakeCellPoint(col: -1, row: -1)

    init(_ raw: String) {
        self.raw = raw
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            switch pieces[0] {
            case "score": score = Int(pieces[1]) ?? 0
            case "len": len = Int(pieces[1]) ?? 0
            case "over": over = pieces[1] == "true"
            case "dir": dir = pieces[1]
            case "head": head = SnakeCellPoint(pieces[1])
            case "food": food = SnakeCellPoint(pieces[1])
            default: break
            }
        }
    }
}

/// 测试里用的格子坐标。
struct SnakeCellPoint: Equatable {
    var col: Int
    var row: Int

    init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }

    init(_ text: String) {
        let parts = text.split(separator: ",").map { Int($0) ?? -1 }
        col = parts.first ?? -1
        row = parts.dropFirst().first ?? -1
    }
}
