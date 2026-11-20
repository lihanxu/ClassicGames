import XCTest

/// 打砖块的模拟器检查：发球、打掉砖、丢命、命尽、重开、返回。
final class BreakoutUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testLoseLivesRestartAndReturn() {
        XCTAssertTrue(app.buttons["home.row.breakout"].waitForExistence(timeout: 8))
        app.buttons["home.row.breakout"].tap()

        let scene = app.descendants(matching: .any)["breakout.scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 5))
        let opening = waitForState { $0.bricks == 32 && $0.lives == 3 }
        XCTAssertFalse(opening.launched, opening.raw)
        XCTAssertEqual(opening.score, 0)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "本局 0")

        dragPaddle(in: scene, toX: min(opening.paddleX + 0.18, 0.85))
        let flying = waitForState(timeout: 3) { $0.launched }
        XCTAssertTrue(flying.launched, flying.raw)
        XCTAssertNotEqual(flying.paddleX, opening.paddleX, "挡板没有跟着移动 \(flying.raw)")

        let hit = waitForState(timeout: 8) { $0.score >= 1 }
        XCTAssertGreaterThanOrEqual(hit.score, 1, hit.raw)
        XCTAssertLessThan(hit.bricks, 32, hit.raw)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "本局 \(hit.score)")

        let afterDrop = loseOneLife(in: scene, from: hit.lives)
        XCTAssertEqual(afterDrop.lives, hit.lives - 1, afterDrop.raw)
        XCTAssertFalse(afterDrop.launched, "丢命后球应该回到挡板上 \(afterDrop.raw)")
        XCTAssertFalse(afterDrop.over)

        var latest = afterDrop
        while !latest.over {
            dragPaddle(in: scene, toX: 0.62)
            latest = loseOneLife(in: scene, from: latest.lives)
        }
        XCTAssertTrue(latest.over, latest.raw)
        XCTAssertEqual(latest.lives, 0)
        XCTAssertTrue(app.staticTexts["结束"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 \(latest.score)")
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "本局 \(latest.score)")
        Screenshot.save("06-breakout-end.png")

        let best = app.staticTexts["chrome.best"].label
        app.buttons["chrome.restart"].tap()
        let restarted = waitForState(timeout: 4) { $0.lives == 3 && $0.score == 0 && $0.bricks == 32 && !$0.launched && !$0.over }
        XCTAssertEqual(restarted.lives, 3, restarted.raw)
        XCTAssertEqual(restarted.bricks, 32, restarted.raw)
        XCTAssertEqual(restarted.score, 0)
        XCTAssertFalse(app.staticTexts["结束"].exists)
        XCTAssertEqual(app.staticTexts["chrome.best"].label, best)

        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.row.breakout"].waitForExistence(timeout: 5))
    }

    /// 把挡板拖到横向比例位置。球还粘着时，这一下会把球发出去。
    private func dragPaddle(in scene: XCUIElement, toX: CGFloat) {
        let state = currentState()
        let dy = 1 - max(0.05, min(state.paddleY, 0.4))
        let startX = max(0.08, min(state.paddleX, 0.92))
        let endX = max(0.08, min(toX, 0.92))
        let start = scene.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: dy))
        let end = scene.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: dy))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// 挡板躲开球，直到少一条命。
    private func loseOneLife(in scene: XCUIElement, from lives: Int) -> BreakoutState {
        waitForState(timeout: 20) { state in
            if state.launched && !state.over && state.lives == lives {
                let away: CGFloat = state.ballX < 0.5 ? 0.9 : 0.1
                if abs(state.paddleX - away) > 0.12 {
                    self.dragPaddle(in: scene, toX: away)
                }
            }
            return state.lives < lives || state.over
        }
    }

    private func currentState() -> BreakoutState {
        let element = app.descendants(matching: .any)["breakout.state"]
        let raw = (element.value as? String).flatMap { $0.contains("score:") ? $0 : nil } ?? element.label
        return BreakoutState(raw)
    }

    private func waitForState(timeout: TimeInterval = 5, where predicate: (BreakoutState) -> Bool) -> BreakoutState {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = currentState()
        while Date() < deadline {
            latest = currentState()
            if latest.raw.contains("score:"), predicate(latest) {
                return latest
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return latest
    }
}

/// 从场景公布的摘要里拆出命、球和砖。
struct BreakoutState {
    var raw: String
    var score = 0
    var lives = 0
    var launched = false
    var bricks = 0
    var ballX = 0.0
    var ballY = 0.0
    var paddleX = 0.0
    var paddleY = 0.0
    var over = false

    init(_ raw: String) {
        self.raw = raw
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            switch pieces[0] {
            case "score": score = Int(pieces[1]) ?? 0
            case "lives": lives = Int(pieces[1]) ?? 0
            case "launched": launched = pieces[1] == "true"
            case "bricks": bricks = Int(pieces[1]) ?? 0
            case "over": over = pieces[1] == "true"
            case "ball":
                let pair = pieces[1].split(separator: ",").map { Double($0) ?? 0 }
                ballX = pair.first ?? 0
                ballY = pair.dropFirst().first ?? 0
            case "paddle":
                let pair = pieces[1].split(separator: ",").map { Double($0) ?? 0 }
                paddleX = pair.first ?? 0
                paddleY = pair.dropFirst().first ?? 0
            default:
                break
            }
        }
    }
}
