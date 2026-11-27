import XCTest
@testable import SokobanLogic

final class ReferenceSolutionTests: XCTestCase {
    func testTableCoversEveryLevelWithPositivePar() {
        XCTAssertEqual(SokobanReferenceSolutions.count, 100)
        XCTAssertEqual(SokobanReferenceSolutions.table.count, 100)
        XCTAssertEqual(SokobanReferenceSolutions.sourceLevelsSHA256, "e2d11158bbb1a31883c399b1ecf0c054d32e4cdf3c62c2b6a1d8d8514c3798f0")
        for id in 1...100 {
            let entry = SokobanReferenceSolutions.entry(levelId: id)
            XCTAssertEqual(entry?.id, id, "id \(id)")
            XCTAssertGreaterThan(entry?.parSteps ?? 0, 0, "id \(id)")
            XCTAssertEqual(entry?.parSteps, entry?.moves.count, "id \(id)")
            XCTAssertEqual(SokobanSolutions.directions(level: id)?.count, entry?.parSteps, "id \(id)")
        }
    }

    func testOfficialLevelOneMatchesKnownBest() {
        XCTAssertEqual(SokobanReferenceSolutions.parSteps(levelId: 1), 33)
        XCTAssertEqual(SokobanReferenceSolutions.moves(levelId: 1), "DLURRRDLULLDDRULURUULDRDDRRULDLUU")
        let directions = SokobanSolutions.directions(level: 1)
        XCTAssertEqual(directions?.count, 33)
        XCTAssertEqual(directions?.first, .down)
    }

    func testEveryReferenceSolutionReplaysToAWin() {
        var pars: [Int] = []
        for id in 1...100 {
            let moves = SokobanReferenceSolutions.moves(levelId: id)
            let result = SokobanReplay.play(level: id, moves: moves)
            XCTAssertTrue(result.ok, "L\(id) \(result.reason)")
            XCTAssertTrue(result.won, "L\(id)")
            XCTAssertEqual(result.steps, moves.count, "L\(id)")
            XCTAssertEqual(result.pushes, SokobanReferenceSolutions.entry(levelId: id)?.pushes, "L\(id)")
            pars.append(result.steps)
        }
        let sorted = pars.sorted()
        XCTAssertEqual(sorted.first, 1)
        XCTAssertEqual(sorted.last, 349)
        XCTAssertEqual(sorted[49] + sorted[50], 128) // median 64
        XCTAssertEqual(pars.reduce(0, +), 8155)
    }
}
