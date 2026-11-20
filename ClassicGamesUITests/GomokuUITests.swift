import XCTest

/// 五子棋的模拟器检查：黑先、占位无效、五连锁盘、重开保留胜场、首页显示黑白胜场。
final class GomokuUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-game", "gomoku"]
        app.launch()
    }

    func testFiveInARowKeepsWins() {
        openRow("gomoku")
        XCTAssertTrue(app.descendants(matching: .any)["gomoku.state"].waitForExistence(timeout: 5))
        let opening = waitState { $0.cells.count == 225 && $0.turn == "black" && $0.winner == "none" }
        XCTAssertEqual(opening.turn, "black", opening.raw)
        XCTAssertTrue(opening.cells.allSatisfy { $0 == "." }, opening.raw)

        play("point.7.7")
        let afterBlack = waitState { $0.turn == "white" && $0.cell(7, 7) == "B" }
        play("point.7.7")
        let ignored = currentState()
        XCTAssertEqual(ignored.turn, "white", ignored.raw)
        XCTAssertEqual(ignored.cell(7, 7), "B", ignored.raw)
        XCTAssertEqual(ignored.cells, afterBlack.cells, ignored.raw)

        let blackMoves = [(7, 8), (7, 9), (7, 10), (7, 11)]
        let whiteMoves = [(0, 0), (0, 1), (0, 2), (0, 3)]
        for index in blackMoves.indices {
            play("point.\(whiteMoves[index].0).\(whiteMoves[index].1)")
            _ = waitState { $0.turn == "black" }
            play("point.\(blackMoves[index].0).\(blackMoves[index].1)")
            if index < blackMoves.count - 1 {
                _ = waitState { $0.turn == "white" }
            }
        }
        let won = waitState { $0.winner == "black" }
        XCTAssertEqual(won.winner, "black", won.raw)
        XCTAssertTrue(app.staticTexts["黑胜"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "黑胜")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "黑 1 · 白 0")
        let locked = won.cells
        play("point.7.12")
        let still = currentState()
        XCTAssertEqual(still.cells, locked, still.raw)
        Screenshot.save("12-gomoku.png")

        app.buttons["chrome.restart"].tap()
        let restarted = waitState { $0.turn == "black" && $0.winner == "none" && $0.cells.allSatisfy { $0 == "." } }
        XCTAssertEqual(restarted.turn, "black", restarted.raw)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "进行中")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "黑 1 · 白 0")

        app.buttons["chrome.back"].tap()
        let home = app.staticTexts["home.best.gomoku"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertEqual(home.label, "黑 1 · 白 0")
    }

    private func play(_ identifier: String) {
        let point = app.buttons[identifier]
        if !point.isHittable {
            app.swipeUp()
        }
        point.tap()
    }

    private func openRow(_ id: String) {
        let button = app.buttons["home.row.\(id)"]
        let row = button.waitForExistence(timeout: 4) ? button : app.descendants(matching: .any)["home.row.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 8), id)
        if row.frame.maxY > app.frame.height - 40 {
            app.swipeUp()
        }
        row.tap()
    }

    private func currentState() -> GomokuBoardState {
        GomokuBoardState(app.descendants(matching: .any)["gomoku.state"].label)
    }

    private func waitState(timeout: TimeInterval = 3, where predicate: (GomokuBoardState) -> Bool) -> GomokuBoardState {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = currentState()
        while Date() < deadline {
            latest = currentState()
            if latest.raw.contains("cells:"), predicate(latest) { return latest }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return latest
    }
}

/// 五子棋棋盘摘要。
struct GomokuBoardState {
    var raw: String
    var turn = ""
    var winner = ""
    var cells: [Character] = []

    init(_ raw: String) {
        self.raw = raw
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            switch pieces[0] {
            case "turn": turn = pieces[1]
            case "winner": winner = pieces[1]
            case "cells": cells = Array(pieces[1])
            default: break
            }
        }
    }

    /// 读一格。行和列都从 0 开始。
    func cell(_ row: Int, _ column: Int) -> Character {
        let index = row * 15 + column
        guard cells.indices.contains(index) else { return "?" }
        return cells[index]
    }
}
