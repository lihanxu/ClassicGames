import XCTest
@testable import SokobanLogic

final class ScoringTests: XCTestCase {
    func testThresholdsRespectBothFloors() {
        // par=33 (L1): ceil(33*1.15)=38, par+2=35 → t3=38; ceil(33*1.50)=50, t3+3=41 → t2=50
        let t = SokobanScoring.thresholds(parSteps: 33)
        XCTAssertEqual(t.par, 33)
        XCTAssertEqual(t.t3, 38)
        XCTAssertEqual(t.t2, 50)
        XCTAssertEqual(t.t1, 50 + (50 - 38)) // 62
        // tiny par uses +2 / +3 floors: par=1 → t3=max(ceil(1.15),3)=3, t2=max(2,6)=6
        let tiny = SokobanScoring.thresholds(parSteps: 1)
        XCTAssertEqual(tiny.t3, 3)
        XCTAssertEqual(tiny.t2, 6)
        XCTAssertEqual(tiny.t1, 9)
    }

    func testThreeStarScoreBand() {
        let par = 33
        XCTAssertEqual(SokobanScoring.stars(steps: 1, parSteps: par), 3)
        XCTAssertEqual(SokobanScoring.stars(steps: 33, parSteps: par), 3)
        XCTAssertEqual(SokobanScoring.stars(steps: 38, parSteps: par), 3)
        XCTAssertEqual(SokobanScoring.score(steps: 20, parSteps: par), 100)
        XCTAssertEqual(SokobanScoring.score(steps: 33, parSteps: par), 100)
        XCTAssertEqual(SokobanScoring.score(steps: 34, parSteps: par), 99)
        XCTAssertEqual(SokobanScoring.score(steps: 38, parSteps: par), 90)
        XCTAssertEqual(SokobanScoring.title(stars: 3), "完美通关")
    }

    func testTwoStarScoreBand() {
        let par = 33
        XCTAssertEqual(SokobanScoring.stars(steps: 39, parSteps: par), 2)
        XCTAssertEqual(SokobanScoring.stars(steps: 50, parSteps: par), 2)
        XCTAssertEqual(SokobanScoring.score(steps: 39, parSteps: par), 89)
        XCTAssertEqual(SokobanScoring.score(steps: 50, parSteps: par), 70)
        XCTAssertEqual(SokobanScoring.title(stars: 2), "出色通关")
    }

    func testOneStarScoreBandAndFloor() {
        let par = 33
        XCTAssertEqual(SokobanScoring.stars(steps: 51, parSteps: par), 1)
        XCTAssertEqual(SokobanScoring.stars(steps: 10_000, parSteps: par), 1)
        XCTAssertEqual(SokobanScoring.score(steps: 51, parSteps: par), 69)
        XCTAssertEqual(SokobanScoring.score(steps: 62, parSteps: par), 50)
        XCTAssertEqual(SokobanScoring.score(steps: 63, parSteps: par), 50)
        XCTAssertEqual(SokobanScoring.score(steps: 9_999, parSteps: par), 50)
        XCTAssertEqual(SokobanScoring.title(stars: 1), "顺利过关")
    }
}
