import XCTest

/// 2048 的模拟器检查：开局两块、有效移动、无效移动、合成、走死、重开。
final class Game2048UITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testMergeStuckAndRestart() {
        XCTAssertTrue(app.buttons["home.row.game2048"].waitForExistence(timeout: 8))
        app.buttons["home.row.game2048"].tap()

        let opening = waitForState { $0.filledCount == 2 }
        XCTAssertEqual(opening.filledCount, 2, opening.raw)
        XCTAssertEqual(opening.score, 0)
        XCTAssertTrue(opening.values.allSatisfy { $0 == 2 || $0 == 4 })

        guard let valid = direction(on: opening.cells, wantMove: true) else {
            return XCTFail("开局没有任何方向可走 \(opening.raw)")
        }
        app.buttons[pad(valid)].tap()
        let moved = waitForState { $0.cells != opening.cells }
        XCTAssertNotEqual(moved.cells, opening.cells, moved.raw)
        XCTAssertTrue(moved.values.allSatisfy { $0 == 2 || $0 == 4 || $0 == 8 }, moved.raw)
        if moved.score == opening.score {
            XCTAssertEqual(moved.filledCount, opening.filledCount + 1, moved.raw)
            XCTAssertTrue(moved.values.allSatisfy { $0 == 2 || $0 == 4 })
        }

        var stable = moved
        var invalid = direction(on: stable.cells, wantMove: false)
        var packs = 0
        while invalid == nil, packs < 6 {
            guard let any = direction(on: stable.cells, wantMove: true) else { break }
            app.buttons[pad(any)].tap()
            stable = currentState()
            invalid = direction(on: stable.cells, wantMove: false)
            packs += 1
        }
        guard let invalid else {
            return XCTFail("找不到不能移动的方向 \(stable.raw)")
        }
        let beforeInvalid = stable
        app.buttons[pad(invalid)].tap()
        let unchanged = currentState()
        XCTAssertEqual(unchanged.cells, beforeInvalid.cells, unchanged.raw)
        XCTAssertEqual(unchanged.score, beforeInvalid.score)

        var latest = unchanged
        var guardCount = 0
        while latest.score == 0 && guardCount < 80 {
            if let merging = direction(on: latest.cells, wantScore: true) {
                app.buttons[pad(merging)].tap()
            } else if let any = direction(on: latest.cells, wantMove: true) {
                app.buttons[pad(any)].tap()
            } else {
                break
            }
            latest = currentState()
            guardCount += 1
        }
        XCTAssertGreaterThan(latest.score, 0, latest.raw)
        XCTAssertEqual(app.staticTexts["chrome.score"].label, "本局 \(latest.score)")
        XCTAssertEqual(app.staticTexts["chrome.best"].label, "最高纪录 \(latest.score)")

        app.descendants(matching: .any)["game2048.finish"].tap()
        latest = waitForState(timeout: 8) { $0.over }
        XCTAssertTrue(latest.over, latest.raw)
        XCTAssertTrue(app.staticTexts["结束"].waitForExistence(timeout: 2))
        let locked = currentState().cells
        for name in ["up", "down", "left", "right"] {
            app.buttons[pad(name)].tap()
        }
        XCTAssertEqual(currentState().cells, locked)
        Screenshot.save("07-game2048-end.png")

        let best = app.staticTexts["chrome.best"].label
        app.buttons["chrome.restart"].tap()
        let restarted = waitForState { $0.filledCount == 2 && $0.score == 0 && !$0.over }
        XCTAssertEqual(restarted.score, 0, restarted.raw)
        XCTAssertEqual(restarted.filledCount, 2, restarted.raw)
        XCTAssertFalse(app.staticTexts["结束"].exists)
        XCTAssertEqual(app.staticTexts["chrome.best"].label, best)
    }

    private func pad(_ direction: String) -> String {
        switch direction {
        case "up": "pad.up"
        case "down": "pad.down"
        case "left": "pad.left"
        default: "pad.right"
        }
    }

    /// 用和游戏相同的滑动规则，挑一个会动、不会动、或会加分的方向。
    private func direction(on cells: [Int], wantMove: Bool = false, wantScore: Bool = false) -> String? {
        for name in ["left", "right", "up", "down"] {
            let result = shifted(cells, name)
            if wantScore {
                if result.score > 0 { return name }
            } else if result.moved == wantMove {
                return name
            }
        }
        return nil
    }

    private func shifted(_ cells: [Int], _ direction: String) -> (cells: [Int], score: Int, moved: Bool) {
        var grid = cells
        var gained = 0
        let vertical = direction == "up" || direction == "down"
        let forward = direction == "left" || direction == "up"
        for index in 0..<4 {
            var line: [Int] = []
            for offset in 0..<4 {
                let row = vertical ? offset : index
                let col = vertical ? index : offset
                let value = grid[row * 4 + col]
                if value > 0 { line.append(value) }
            }
            if !forward { line.reverse() }
            var merged: [Int] = []
            var cursor = 0
            while cursor < line.count {
                if cursor + 1 < line.count, line[cursor] == line[cursor + 1] {
                    let sum = line[cursor] * 2
                    merged.append(sum)
                    gained += sum
                    cursor += 2
                } else {
                    merged.append(line[cursor])
                    cursor += 1
                }
            }
            var placed = merged
            if !forward { placed.reverse() }
            while placed.count < 4 {
                if forward { placed.append(0) } else { placed.insert(0, at: 0) }
            }
            for offset in 0..<4 {
                let row = vertical ? offset : index
                let col = vertical ? index : offset
                grid[row * 4 + col] = placed[offset]
            }
        }
        return (grid, gained, grid != cells)
    }

    private func currentState() -> Board2048State {
        let element = app.descendants(matching: .any)["game2048.board"]
        let raw = (element.value as? String).flatMap { $0.contains("cells:") ? $0 : nil } ?? element.label
        return Board2048State(raw)
    }

    private func waitForState(timeout: TimeInterval = 3, where predicate: (Board2048State) -> Bool) -> Board2048State {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = currentState()
        while Date() < deadline {
            latest = currentState()
            if latest.raw.contains("cells:"), predicate(latest) {
                return latest
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return latest
    }
}

/// 2048 棋盘摘要。
struct Board2048State {
    var raw: String
    var score = 0
    var over = false
    var cells: [Int] = []

    var filledCount: Int { cells.filter { $0 > 0 }.count }
    var values: [Int] { cells.filter { $0 > 0 } }

    init(_ raw: String) {
        self.raw = raw
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            switch pieces[0] {
            case "score": score = Int(pieces[1]) ?? 0
            case "over": over = pieces[1] == "true"
            case "cells": cells = pieces[1].split(separator: ",").map { Int($0) ?? 0 }
            default: break
            }
        }
    }
}
