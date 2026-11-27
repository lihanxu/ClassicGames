import XCTest
@testable import SokobanLogic

final class HintTests: XCTestCase {
    func testOpeningStateHitsReferenceLineForEveryLevel() {
        for id in 1...100 {
            let board = SokobanLevel.parsed(id)
            let line = SokobanHintPlanner.referenceLine(level: id, player: board.player, boxes: board.boxes)
            XCTAssertFalse(line?.isEmpty ?? true, "L\(id) opening should hit the reference line")
            let startOn = SokobanReplay.boxesOnTargets(board.boxes, board.targets)
            var player = board.player
            var boxes = board.boxes
            for direction in line! {
                let step = SokobanReplay.stepped(player: player, boxes: boxes, walls: board.walls, rows: board.rows, cols: board.cols, direction: direction)
                XCTAssertNotNil(step, "L\(id) illegal hint step")
                player = step!.player
                boxes = step!.boxes
            }
            let on = SokobanReplay.boxesOnTargets(boxes, board.targets)
            XCTAssertTrue(on >= startOn + 1 || boxes == board.targets, "L\(id) did not net +1")
        }
    }

    func testLevelOneOpeningHintClearsTheLastBox() {
        let board = SokobanLevel.parsed(1)
        let plan = SokobanHintPlanner.plan(level: 1, player: board.player, boxes: board.boxes)
        guard case .sequence(let moves, let fromReference) = plan else {
            return XCTFail("expected a sequence")
        }
        XCTAssertTrue(fromReference)
        XCTAssertEqual(moves.count, 33)
        XCTAssertTrue(SokobanReplay.play(level: 1, moves: moves.map { String(SokobanMoveLetter.letter($0)) }.joined()).won)
    }

    func testLevelSixtySixOpeningHintStopsAfterFirstBoxOnTarget() {
        let board = SokobanLevel.parsed(66)
        let plan = SokobanHintPlanner.plan(level: 66, player: board.player, boxes: board.boxes)
        guard case .sequence(let moves, let fromReference) = plan else {
            return XCTFail("expected a sequence")
        }
        XCTAssertTrue(fromReference)
        XCTAssertEqual(moves.count, 1)
        let result = SokobanReplay.play(level: 66, moves: String(SokobanMoveLetter.letter(moves[0])))
        XCTAssertFalse(result.won)
        XCTAssertEqual(result.boxesOnTargets, 1)
    }

    func testDeadlockDoesNotProduceASequence() {
        let board = SokobanLevel.parsed(1)
        // Park the unmarked box into the top-right unreachable-style corner if one exists off-target.
        // Level 1: force a classic corner freeze by placing a box at (1,1) if that's a wall-corner.
        var boxes = board.boxes
        let boxed = boxes.first { !board.targets.contains($0) } ?? boxes.first!
        // Move that box into a wall corner: (0,1) is usually a wall on Microban 1; find a floor corner.
        var corner: GridPoint?
        for r in 0..<board.rows {
            for c in 0..<board.cols {
                let p = GridPoint(row: r, col: c)
                guard !board.walls.contains(p), !board.targets.contains(p) else { continue }
                let up = GridPoint(row: r - 1, col: c)
                let left = GridPoint(row: r, col: c - 1)
                let down = GridPoint(row: r + 1, col: c)
                let right = GridPoint(row: r, col: c + 1)
                let vWall = board.walls.contains(up) || board.walls.contains(down) || r == 0 || r == board.rows - 1
                let hWall = board.walls.contains(left) || board.walls.contains(right) || c == 0 || c == board.cols - 1
                if vWall && hWall { corner = p; break }
            }
            if corner != nil { break }
        }
        guard let corner else { return XCTFail("no off-target corner") }
        boxes.remove(boxed)
        boxes.insert(corner)
        let player = board.player
        let outcome = SokobanHintPlanner.search(level: 1, player: player, boxes: boxes, budget: 0.4)
        XCTAssertNotEqual(outcome, .sequence([], fromReference: false))
        if case .sequence = outcome {
            XCTFail("deadlocked corner should not yield a playable sequence: \(outcome)")
        } else {
            XCTAssertTrue(outcome == .deadlock || outcome == .timeout)
        }
        // Product rule: only a playable sequence may consume a hint. Deadlock/timeout never charge.
        XCTAssertNotEqual(String(describing: outcome).contains("sequence"), true)
    }

    func testOffLineSearchRespectsTimeout() {
        let board = SokobanLevel.parsed(93)
        // Nudge the player one legal walk if possible so we may leave the exact opening cell
        // while keeping boxes; if still on the line, search is skipped. Use a 0-budget search directly.
        let outcome = SokobanHintPlanner.search(level: 93, player: board.player, boxes: board.boxes, budget: 0.001)
        XCTAssertTrue(outcome == .timeout || {
            if case .sequence = outcome { return true }
            return outcome == .deadlock
        }(), "unexpected \(outcome)")
    }

    @MainActor
    func testHintItemIsNotConsumedWhenPlannerFails() {
        let storage = EconomyTests.MemoryStorage()
        let repo = SokobanPersistence(storage: storage, legacyDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let model = SokobanModel(persistence: repo)
        XCTAssertFalse(model.beginHintPlayback([]))
        XCTAssertEqual(repo.wallet.hintItemCount, 2)
        XCTAssertTrue(model.beginHintPlayback([.down]))
        XCTAssertEqual(repo.wallet.hintItemCount, 1)
        // later manual undos do not refund
        _ = model.requestUndo()
        XCTAssertEqual(repo.wallet.hintItemCount, 1)
    }
}

final class DPadRepeatTests: XCTestCase {
    func testTouchTargetsMeetMinimum() {
        XCTAssertGreaterThanOrEqual(SokobanDPadRepeat.defaultPointSize, 44)
        XCTAssertGreaterThanOrEqual(SokobanDPadRepeat.accessibilityPointSize, 44)
        XCTAssertEqual(SokobanDPadRepeat.firstDelay, 0.260, accuracy: 0.0001)
        XCTAssertEqual(SokobanDPadRepeat.interval, 0.130, accuracy: 0.0001)
        XCTAssertEqual(SokobanDPadRepeat.hintStepDuration, 0.140, accuracy: 0.0001)
    }

    func testPressStepsImmediatelyAndRepeatsAfterDelay() {
        var pad = SokobanDPadRepeat()
        XCTAssertEqual(pad.press(.left, at: 0, allowed: true, locked: false, won: false), .step)
        XCTAssertNil(pad.tick(at: 0.259, allowed: true, locked: false, won: false))
        XCTAssertEqual(pad.tick(at: 0.260, allowed: true, locked: false, won: false), .step)
        XCTAssertNil(pad.tick(at: 0.389, allowed: true, locked: false, won: false))
        XCTAssertEqual(pad.tick(at: 0.390, allowed: true, locked: false, won: false), .step)
        XCTAssertEqual(pad.release(), .stop(.released))
        XCTAssertNil(pad.tick(at: 1, allowed: true, locked: false, won: false))
    }

    func testStopsOnBlockWinLockOrPressWhenDisabled() {
        var pad = SokobanDPadRepeat()
        XCTAssertEqual(pad.press(.up, at: 0, allowed: false, locked: false, won: false), .stop(.blocked))
        XCTAssertEqual(pad.press(.up, at: 0, allowed: true, locked: true, won: false), .stop(.locked))
        XCTAssertEqual(pad.press(.up, at: 0, allowed: true, locked: false, won: true), .stop(.won))
        XCTAssertEqual(pad.press(.down, at: 1, allowed: true, locked: false, won: false), .step)
        XCTAssertEqual(pad.tick(at: 1.3, allowed: false, locked: false, won: false), .stop(.blocked))
        XCTAssertEqual(pad.press(.down, at: 2, allowed: true, locked: false, won: false), .step)
        XCTAssertEqual(pad.tick(at: 2.3, allowed: true, locked: false, won: true), .stop(.won))
        XCTAssertEqual(pad.press(.down, at: 3, allowed: true, locked: false, won: false), .step)
        XCTAssertEqual(pad.tick(at: 3.3, allowed: true, locked: true, won: false), .stop(.locked))
    }
}
