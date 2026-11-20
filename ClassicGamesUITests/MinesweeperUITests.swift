import XCTest

/// 扫雷的模拟器检查：首开不是雷、插旗、踩雷不计纪录、重开、胜局写入最快时间。
final class MinesweeperUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-game", "minesweeper"]
        app.launch()
    }

    func testRevealFlagLoseRestartAndWin() {
        openMinesweeper()
        let state = app.descendants(matching: .any)["minesweeper.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 5))

        app.buttons["mine.0.0"].tap()
        var board = waitState { $0.status == "play" && $0.cells[0] != "#" && $0.cells[0] != "m" }
        XCTAssertNotEqual(board.cells[0], "*", board.raw)
        XCTAssertTrue(board.cells[0].allSatisfy(\.isNumber), board.raw)
        board = openAZeroIfNeeded(board)
        assertZerosOpenedNeighbors(board)
        let ticking = waitState(timeout: 3) { $0.seconds >= 1 }
        XCTAssertGreaterThanOrEqual(ticking.seconds, 1, ticking.raw)

        let flagIndex = ticking.cells.firstIndex { $0 == "#" || $0 == "m" } ?? 1
        app.buttons["minesweeper.flag"].tap()
        let armed = waitState { $0.flagging }
        XCTAssertTrue(armed.flagging, armed.raw)
        let row = flagIndex / 9
        let column = flagIndex % 9
        app.buttons["mine.\(row).\(column)"].tap()
        let flagged = waitState { $0.cells[flagIndex] == "F" }
        XCTAssertEqual(flagged.cells[flagIndex], "F", flagged.raw)
        XCTAssertEqual(flagged.status, "play", flagged.raw)

        app.buttons["minesweeper.flag"].tap()
        guard let mineIndex = flagged.cells.firstIndex(of: "m") else {
            return XCTFail("找不到未插旗的雷 \(flagged.raw)")
        }
        app.buttons["mine.\(mineIndex / 9).\(mineIndex % 9)"].tap()
        let lost = waitState { $0.status == "lost" }
        XCTAssertTrue(app.staticTexts["失败"].waitForExistence(timeout: 2), lost.raw)
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 —", lost.raw)
        let frozen = lost.seconds
        RunLoop.current.run(until: Date().addingTimeInterval(1.3))
        let still = currentState()
        XCTAssertEqual(still.seconds, frozen, still.raw)
        XCTAssertEqual(still.status, "lost")

        app.buttons["chrome.restart"].tap()
        let restarted = waitState { $0.seconds == 0 && $0.status == "play" && $0.cells.allSatisfy { $0 == "#" } }
        XCTAssertEqual(restarted.seconds, 0, restarted.raw)
        XCTAssertTrue(restarted.cells.allSatisfy { $0 == "#" }, restarted.raw)

        app.buttons["mine.4.4"].tap()
        var playing = waitState { $0.status == "play" && $0.cells.contains { $0 != "#" } }
        var guardCount = 0
        while playing.status != "won", guardCount < 90 {
            guard let next = playing.cells.firstIndex(where: { $0 == "#" }) else { break }
            app.buttons["mine.\(next / 9).\(next % 9)"].tap()
            playing = waitState(timeout: 2) { state in
                state.status == "won" || state.cells[next] != "#"
            }
            guardCount += 1
        }
        XCTAssertEqual(playing.status, "won", playing.raw)
        XCTAssertTrue(app.staticTexts["胜利"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "秒数 \(playing.seconds)")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 \(playing.seconds)")
        Screenshot.save("10-minesweeper.png")
    }

    /// 如果首开没有带出 0，就再点一个周围没有雷的盖住格子。
    private func openAZeroIfNeeded(_ board: MineBoard) -> MineBoard {
        if board.cells.contains("0") { return board }
        guard let zero = hiddenZero(in: board.cells) else { return board }
        app.buttons["mine.\(zero / 9).\(zero % 9)"].tap()
        return waitState { $0.cells[zero] == "0" }
    }

    /// 每个已经翻开的 0，周围八格也必须翻开。
    private func assertZerosOpenedNeighbors(_ board: MineBoard) {
        var sawZero = false
        for index in board.cells.indices where board.cells[index] == "0" {
            sawZero = true
            for neighbor in neighbors(of: index) {
                let symbol = board.cells[neighbor]
                XCTAssertTrue(symbol.allSatisfy(\.isNumber), "0 旁边仍盖着 \(symbol) \(board.raw)")
            }
        }
        XCTAssertTrue(sawZero, "没有翻开任何 0 \(board.raw)")
    }

    private func hiddenZero(in cells: [String]) -> Int? {
        cells.indices.first { index in
            cells[index] == "#" && neighbors(of: index).allSatisfy { cells[$0] != "m" && cells[$0] != "*" }
        }
    }

    private func neighbors(of index: Int) -> [Int] {
        let row = index / 9
        let column = index % 9
        var result: [Int] = []
        for rowOffset in -1...1 {
            for columnOffset in -1...1 where rowOffset != 0 || columnOffset != 0 {
                let nextRow = row + rowOffset
                let nextColumn = column + columnOffset
                if (0..<9).contains(nextRow), (0..<9).contains(nextColumn) {
                    result.append(nextRow * 9 + nextColumn)
                }
            }
        }
        return result
    }

    private func openMinesweeper() {
        let row = app.buttons["home.row.minesweeper"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        if !row.isHittable {
            app.swipeUp()
        }
        row.tap()
    }

    private func currentState() -> MineBoard {
        let element = app.descendants(matching: .any)["minesweeper.state"]
        return MineBoard(element.label)
    }

    private func waitState(timeout: TimeInterval = 3, where predicate: (MineBoard) -> Bool) -> MineBoard {
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

/// 扫雷棋盘摘要。
struct MineBoard {
    var raw: String
    var seconds = 0
    var flagging = false
    var status = ""
    var cells: [String] = []

    init(_ raw: String) {
        self.raw = raw
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            switch pieces[0] {
            case "seconds": seconds = Int(pieces[1]) ?? 0
            case "flagging": flagging = pieces[1] == "true"
            case "status": status = pieces[1]
            case "cells": cells = pieces[1].split(separator: ",").map(String.init)
            default: break
            }
        }
    }
}
