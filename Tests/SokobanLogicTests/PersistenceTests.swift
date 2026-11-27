import XCTest
import Observation
@testable import SokobanLogic

@MainActor
final class PersistenceTests: XCTestCase {
    final class MemoryStorage: SokobanSaveStorage {
        var values: [String: Data] = [:]
        var fail = false
        var failReads = false
        var readCount = 0
        var failReadAt: Int?
        var afterWrite: ((String) -> Void)?
        var failPrefix: String?
        var onWrite: (() -> Void)?
        func data(forKey key: String) throws -> Data? {
            readCount += 1
            if failReads || readCount == failReadAt { throw CocoaError(.fileReadNoPermission) }; return values[key]
        }
        func write(_ data: Data, forKey key: String, ifAbsent: Bool) throws {
            onWrite?()
            if fail || failPrefix.map({ key.hasPrefix($0) }) == true { throw CocoaError(.fileWriteNoPermission) }
            if ifAbsent, let existing = values[key] {
                guard existing == data else { throw CocoaError(.fileWriteFileExists) }
                return
            }
            values[key] = data
            afterWrite?(key)
        }
    }
    private func fixture() -> (SokobanPersistence, MemoryStorage, UserDefaults) {
        let store = MemoryStorage()
        // Every test has a fresh named suite. Never remove a persistent domain.
        let defaults = UserDefaults(suiteName: "sokoban.synthetic." + UUID().uuidString)!
        return (SokobanPersistence(storage: store, legacyDefaults: defaults), store, defaults)
    }
    private func raw(_ moves: [SokobanDirection] = [], level: Int = 1) -> String {
        let board = SokobanLevel.parsed(level)
        var p = board.player, boxes = board.boxes
        var frames: [SokobanFrame] = []
        var facing: SokobanDirection = .down
        for (i, move) in moves.enumerated() {
            frames.append(SokobanFrame(player: p, boxes: boxes, steps: i, facing: facing, won: false, counts: false))
            let next = p.moving(move)
            if boxes.remove(next) != nil { boxes.insert(next.moving(move)) }
            p = next; facing = move
        }
        let won = boxes == board.targets
        return SokobanResume.encode(level: level, player: p, boxes: boxes, steps: moves.count,
            facing: facing, won: won, counts: won, undo: frames, redo: [])
    }
    private func writeScoreOnly(_ store: MemoryStorage, levels: ClosedRange<Int>, best: Int = 20, identity: ((Int) -> String)? = nil) throws {
        for level in levels {
            let game = SokobanSavedGame(
                formatVersion: 1,
                identity: identity?(level) ?? SokobanPersistence.identity(level: level),
                level: level,
                sequence: UInt64(level),
                raw: "",
                eligible: true,
                best: best,
                legacyDigest: nil,
                recordOnly: true)
            store.values[SokobanPersistence.slotKey(level: level)] = try JSONEncoder().encode(game)
        }
    }
    func testB3ArtworkUsesSmallReadableCellsOnly() {
        XCTAssertTrue(SokobanBoardFit.usesDetailedArtwork(rows: 7, cols: 6, cell: 59))
        XCTAssertFalse(SokobanBoardFit.usesDetailedArtwork(rows: 14, cols: 9, cell: 30))
        XCTAssertFalse(SokobanBoardFit.usesDetailedArtwork(rows: 10, cols: 22, cell: 15.84))
        XCTAssertFalse(SokobanBoardFit.usesDetailedArtwork(rows: 7, cols: 6, cell: 20))
    }

    func testB3WholeBoardFitHasNoClippingOrMinimum28() async {
        for (rows, cols) in [(14,9),(10,22)] {
            for height in [220.0, 300.0, 440.0] {
                let fit = SokobanBoardFit.calculate(width: 359, height: height, rows: rows, cols: cols)
                XCTAssertLessThanOrEqual(fit.width, 359)
                XCTAssertLessThanOrEqual(fit.height, height)
                XCTAssertGreaterThan(fit.cell, 0)
                XCTAssertEqual(fit.width, Double(cols)*fit.cell + Double(cols-1)*fit.gap, accuracy: 0.01)
            }
        }
        XCTAssertLessThan(SokobanBoardFit.calculate(width: 359, height: 300, rows: 10, cols: 22).cell, 20)
    }
    func testB3SwipeRejectsTapShortAndAmbiguousDirections() async {
        XCTAssertNil(SokobanSwipe.direction(dx: 0, dy: 0))
        XCTAssertNil(SokobanSwipe.direction(dx: 8, dy: 0))
        XCTAssertNil(SokobanSwipe.direction(dx: 30, dy: 29))
        XCTAssertNil(SokobanSwipe.direction(dx: .nan, dy: 20))
        XCTAssertEqual(SokobanSwipe.direction(dx: 70, dy: 3), .right)
        XCTAssertEqual(SokobanSwipe.direction(dx: -70, dy: 3), .left)
        XCTAssertEqual(SokobanSwipe.direction(dx: 3, dy: 70), .down)
        XCTAssertEqual(SokobanSwipe.direction(dx: 3, dy: -70), .up)
    }
    func testB3ExteriorBlankIsNotPaintedAsPlayableFloor() async {
        let walls = Set((1...3).flatMap { row in (1...3).compactMap { col in
            (row == 1 || row == 3 || col == 1 || col == 3) ? GridPoint(row: row, col: col) : nil
        } })
        let outside = SokobanBoardFit.exterior(rows: 5, cols: 5, walls: walls)
        XCTAssertEqual(outside.count, 16)
        XCTAssertTrue(outside.contains(GridPoint(row: 0,col: 0)))
        XCTAssertFalse(outside.contains(GridPoint(row: 2,col: 2)))
        XCTAssertTrue(outside.isDisjoint(with: walls))
    }

    func testV3AllLevelsActiveCellsAndExteriorBlockedFloors() {
        for number in 1...SokobanLevels.count {
            let board = SokobanLevel.parsed(number)
            let exterior = SokobanBoardFit.exterior(rows: board.rows, cols: board.cols, walls: board.walls)
            let grid = SokobanVisualGrid.make(rows: board.rows, cols: board.cols)
            func paint(_ point: GridPoint) -> SokobanFloorPaint {
                SokobanFloorPaint.paint(
                    point,
                    rows: board.rows,
                    cols: board.cols,
                    walls: board.walls,
                    targets: board.targets,
                    exterior: exterior
                )
            }
            XCTAssertTrue(paint(board.player).isActive, "level \(number) player must sit on an active floor")
            XCTAssertFalse(board.walls.contains(board.player))
            XCTAssertFalse(exterior.contains(board.player))
            for box in board.boxes {
                XCTAssertTrue(paint(box).isActive, "level \(number) box \(box) must sit on an active floor")
                XCTAssertFalse(board.walls.contains(box))
                XCTAssertFalse(exterior.contains(box))
            }
            for target in board.targets {
                XCTAssertEqual(paint(target), .target, "level \(number) target \(target) must use the target tile")
                XCTAssertFalse(board.walls.contains(target))
                XCTAssertFalse(exterior.contains(target))
            }
            // N×N padding cells (no original level point) are blocked floors, not cream walkable tiles.
            for row in 1..<(grid.side - 1) {
                for col in 1..<(grid.side - 1) {
                    let kind = SokobanFloorPaint.paint(
                        visualRow: row,
                        visualCol: col,
                        grid: grid,
                        rows: board.rows,
                        cols: board.cols,
                        walls: board.walls,
                        targets: board.targets,
                        exterior: exterior
                    )
                    if grid.levelPoint(visualRow: row, visualCol: col, rows: board.rows, cols: board.cols) == nil {
                        XCTAssertEqual(kind, .blocked, "level \(number) padding (\(row),\(col)) must be blocked")
                    }
                }
            }
        }

        let level1 = SokobanLevel.parsed(1)
        XCTAssertEqual(level1.rows, 7)
        XCTAssertEqual(level1.cols, 6)
        let exterior1 = SokobanBoardFit.exterior(rows: level1.rows, cols: level1.cols, walls: level1.walls)
        // 右上 / 右下 pockets sit outside the wall ring but inside the 7×6 bbox.
        for point in [GridPoint(row: 0, col: 4), GridPoint(row: 0, col: 5), GridPoint(row: 6, col: 4), GridPoint(row: 6, col: 5)] {
            XCTAssertTrue(exterior1.contains(point), "level 1 \(point) should be an exterior blank")
            XCTAssertEqual(
                SokobanFloorPaint.paint(point, rows: level1.rows, cols: level1.cols, walls: level1.walls, targets: level1.targets, exterior: exterior1),
                .blocked
            )
        }

        let level66 = SokobanLevel.parsed(66)
        XCTAssertEqual(level66.rows, 14)
        XCTAssertEqual(level66.cols, 9)
        let exterior66 = SokobanBoardFit.exterior(rows: level66.rows, cols: level66.cols, walls: level66.walls)
        let corners = [
            GridPoint(row: 0, col: 0),
            GridPoint(row: 0, col: level66.cols - 1),
            GridPoint(row: level66.rows - 1, col: 0),
            GridPoint(row: level66.rows - 1, col: level66.cols - 1)
        ]
        for point in corners {
            XCTAssertTrue(exterior66.contains(point), "level 66 corner \(point) should be an exterior blank")
            XCTAssertEqual(
                SokobanFloorPaint.paint(point, rows: level66.rows, cols: level66.cols, walls: level66.walls, targets: level66.targets, exterior: exterior66),
                .blocked
            )
        }
    }

    #if DEBUG
    func testB3BinaryCorruptBytesAndDiagnosticAreLossless() async throws {
        let (repo, store, _) = fixture()
        let a = Data([0xff]), b = Data([0xfe])
        store.values["slot.1"] = a
        XCTAssertThrowsError(try repo.load(level: 1))
        try repo.prepareRestart(level: 1)
        XCTAssertEqual(store.values["slot.1"], a)
        XCTAssertTrue(store.values.contains { $0.key.hasPrefix("quarantine.slot.1.") && $0.value == a })
        store.values["slot.1"] = b
        try repo.prepareRestart(level: 1)
        XCTAssertEqual(store.values["slot.1"], b)
        XCTAssertEqual(store.values.keys.filter { $0.hasPrefix("quarantine.slot.1.") }.count, 2)
        XCTAssertNotEqual(SokobanTestSession.diagnosticDigest(a), SokobanTestSession.diagnosticDigest(b))
    }
    #endif
    func testB2BestQueriesDoNotInvalidateTheirOwnObservation() async throws {
        let (repo, _, _) = fixture()
        XCTAssertTrue(repo.save(level: 1, raw: raw(SokobanSolutions.directions(level: 1)!), eligible: true))
        final class Changes: @unchecked Sendable { var count = 0 }
        let changes = Changes()
        withObservationTracking {
            XCTAssertEqual(repo.best(level: 1), 33)
        } onChange: { changes.count += 1 }
        XCTAssertEqual(changes.count, 0, "A rendering query must not invalidate itself")
        XCTAssertEqual(repo.best(level: 1), 33)
        XCTAssertEqual(changes.count, 0, "Repeated rendering query must remain read-only to observation")
        XCTAssertTrue(repo.save(level: 1, raw: raw(), eligible: true))
        XCTAssertEqual(changes.count, 1, "Real writes must still invalidate observers")
    }
    #if DEBUG
    func testB2RealFileFaultRetainsLatestThenRetries() async throws {
        let base = SokobanFileStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent("sokoban.synthetic." + UUID().uuidString))
        let fault = SokobanFaultStorage(base: base)
        let repo = SokobanPersistence(storage: fault, legacyDefaults: UserDefaults(suiteName: "sokoban.synthetic." + UUID().uuidString)!)
        let model = SokobanModel(persistence: repo)
        model.move(.up)
        let original = try base.data(forKey: "slot.1")
        fault.mode = .writes
        model.move(.down)
        XCTAssertEqual(model.saveState, .failed)
        XCTAssertEqual(model.steps, 2)
        XCTAssertEqual(try base.data(forKey: "slot.1"), original)
        fault.mode = .none
        XCTAssertTrue(model.retrySave())
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertEqual(SokobanResume.parse(try XCTUnwrap(repo.load(level: 1)).raw)?.steps, 2)
    }
    #endif
    func testB2GateRequiresBuildArgumentAndBoundedNamespace() async {
        let valid = "sokoban.ui." + UUID().uuidString
        let env = [SokobanTestGate.environmentKey: valid]
        #if DEBUG
        XCTAssertNotNil(SokobanTestGate.namespace(arguments: ["-ui-testing"], environment: env))
        #else
        XCTAssertNil(SokobanTestGate.namespace(arguments: ["-ui-testing"], environment: env))
        #endif
        XCTAssertNil(SokobanTestGate.namespace(arguments: [], environment: env))
        XCTAssertNil(SokobanTestGate.namespace(arguments: ["-ui-testing"], environment: [:]))
        for bad in ["", "/tmp/escape", "sokoban.ui.../../escape", "sokoban.ui.not-a-uuid", valid + "/escape", "production." + UUID().uuidString] {
            XCTAssertNil(SokobanTestGate.namespace(arguments: ["-ui-testing"], environment: [SokobanTestGate.environmentKey: bad]))
        }
    }
    func testB2CompletedRevisitDoesNotRewriteOrUndo() async throws {
        let (repo, store, defaults) = fixture()
        XCTAssertTrue(repo.save(level: 1, raw: raw(SokobanSolutions.directions(level: 1)!), eligible: true))
        defaults.set(4, forKey: "classicgames.best.sokoban.1")
        let terminalBytes = store.values["slot.1"]
        let model = SokobanModel(persistence: repo)
        model.load(2)
        model.load(1)
        XCTAssertTrue(model.won)
        XCTAssertEqual(model.visitKind, .completedRevisit)
        XCTAssertTrue(model.hasBoard)
        XCTAssertEqual(model.completionEvents, 0)
        XCTAssertEqual(model.steps, 33)
        XCTAssertEqual(model.levelBest, 33)
        XCTAssertEqual(store.values["slot.1"], terminalBytes, "Revisit is not another settlement/save")
        XCTAssertFalse(model.undo(), "Historical terminal is read-only until explicit replay")
        XCTAssertEqual(model.steps, 33)
        model.restart()
        XCTAssertEqual(model.steps, 0)
        XCTAssertFalse(model.won)
        XCTAssertFalse(model.undo())
        XCTAssertEqual(model.levelBest, 33)
        XCTAssertEqual(defaults.integer(forKey: "classicgames.best.sokoban.1"), 4)
    }
    func testB2ScoreOnlyIsNotCorruptAndReplayPreservesBest() async throws {
        let (repo, store, _) = fixture()
        XCTAssertTrue(repo.save(level: 1, raw: raw(SokobanSolutions.directions(level: 1)!), eligible: true))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(store.values["slot.1"])) as? [String: Any])
        json["raw"] = ""; json["recordOnly"] = true
        store.values["slot.1"] = try JSONSerialization.data(withJSONObject: json)
        let before = store.values["slot.1"]
        let model = SokobanModel(persistence: repo)
        model.load(1)
        XCTAssertTrue(model.loadIssue.isEmpty, "An explicit same-identity score-only record is not a corrupt board")
        XCTAssertFalse(model.hasBoard)
        XCTAssertEqual(model.visitKind, .scoreOnly)
        XCTAssertEqual(model.completionEvents, 0)
        XCTAssertEqual(model.levelBest, 33)
        XCTAssertEqual(store.values["slot.1"], before)
        model.move(.up)
        XCTAssertEqual(model.steps, 0, "No fabricated playable board for score-only data")
        model.restart()
        XCTAssertEqual(model.levelBest, 33)
        XCTAssertEqual(model.steps, 0)
        model.move(.up)
        XCTAssertEqual(model.steps, 1)
    }
    func testSeparateSlotsAndRestoredUndo() async throws {
        let (repo, store, defaults) = fixture()
        XCTAssertTrue(repo.save(level: 1, raw: raw([.up]), eligible: true))
        XCTAssertTrue(repo.save(level: 2, raw: raw([], level: 2), eligible: true))
        let reopened = SokobanPersistence(storage: store, legacyDefaults: defaults)
        XCTAssertEqual(try reopened.load(level: 1)?.raw, raw([.up]))
        XCTAssertEqual(try reopened.load(level: 2)?.raw, raw([], level: 2))
        let game = try XCTUnwrap(reopened.load(level: 1))
        XCTAssertEqual(game.formatVersion, 1)
        XCTAssertEqual(game.identity, SokobanPersistence.identity(level: 1))
        XCTAssertEqual(SokobanResume.parse(game.raw)?.undo.count, 1)
    }
    func testFailedWriteKeepsLatestAndRetryStates() async throws {
        let (repo, store, _) = fixture()
        XCTAssertTrue(repo.save(level: 1, raw: raw(), eligible: true))
        store.fail = true
        XCTAssertFalse(repo.save(level: 1, raw: raw([.up]), eligible: true))
        XCTAssertEqual(repo.states[1], .failed)
        XCTAssertFalse(repo.save(level: 1, raw: raw([.up, .down]), eligible: true))
        XCTAssertEqual(try repo.game(level: 1)?.raw, raw([.up, .down]))
        XCTAssertEqual(try repo.load(level: 1)?.raw, raw())
        store.fail = false
        var sawRetry = false
        store.onWrite = { sawRetry = repo.states[1] == .retrying }
        XCTAssertTrue(repo.retry(level: 1))
        XCTAssertTrue(sawRetry)
        XCTAssertEqual(repo.states[1], .saved)
        XCTAssertEqual(try repo.load(level: 1)?.raw, raw([.up, .down]))
    }
    func testOldSnapshotCannotOverwriteNew() async throws {
        let (repo, _, _) = fixture()
        XCTAssertTrue(repo.save(level: 1, raw: raw(), eligible: true))
        let old = try XCTUnwrap(repo.load(level: 1))
        XCTAssertTrue(repo.save(level: 1, raw: raw([.up]), eligible: true))
        XCTAssertThrowsError(try repo.commit(old))
        XCTAssertEqual(try repo.load(level: 1)?.raw, raw([.up]))
    }
    func testUnknownIdentityIsBackedUpAndQuarantinedIdempotently() async throws {
        let (repo, store, defaults) = fixture()
        let old = raw([.up])
        defaults.set(old, forKey: "classicgames.sokoban.resume")
        XCTAssertEqual(repo.migrateLegacy(), .identityUnproven)
        let backup = "legacy.original." + SokobanPersistence.digest(old)
        XCTAssertEqual(store.values[backup], Data(old.utf8))
        XCTAssertEqual(repo.migrateLegacy(), .identityUnproven)
        XCTAssertNil(try repo.load(level: 1))
        XCTAssertEqual(defaults.string(forKey: "classicgames.sokoban.resume"), old)
    }
    func testBackupFailureStopsMigrationAndCanRetry() async throws {
        let (repo, store, defaults) = fixture()
        defaults.set(raw(), forKey: "classicgames.sokoban.resume")
        store.failPrefix = "legacy.original."
        XCTAssertEqual(repo.migrateLegacy(), .failed)
        XCTAssertNil(try repo.load(level: 1))
        store.failPrefix = nil
        XCTAssertEqual(repo.migrateLegacy(), .identityUnproven)
    }
    func testInvalidUndoQuarantinesWholeArchiveEvenWithSyntheticProof() async throws {
        let (repo, _, defaults) = fixture()
        let old = raw([.up]).replacingOccurrences(of: "3,2*", with: "0,0*")
        defaults.set(old, forKey: "classicgames.sokoban.resume")
        let proof = SokobanLegacyProof(rawDigest: SokobanPersistence.digest(old), identity: SokobanPersistence.identity(level: 1))
        XCTAssertEqual(repo.migrateLegacy(proof: proof), .invalid)
        XCTAssertNil(try repo.load(level: 1))
    }
    func testRejectsNegativeStepsTeleportOverlapAndInvalidWin() async throws {
        let (repo, _, _) = fixture()
        let start = raw()
        var parts = start.components(separatedBy: "|")
        parts[3] = "-1"
        XCTAssertFalse(repo.save(level: 1, raw: parts.joined(separator: "|"), eligible: true))
        parts = start.components(separatedBy: "|"); parts[1] = "0,0"
        XCTAssertFalse(repo.save(level: 1, raw: parts.joined(separator: "|"), eligible: true))
        parts = start.components(separatedBy: "|"); parts[1] = "3,1"
        XCTAssertFalse(repo.save(level: 1, raw: parts.joined(separator: "|"), eligible: true))
        parts = start.components(separatedBy: "|"); parts[5] = "1"
        XCTAssertFalse(repo.save(level: 1, raw: parts.joined(separator: "|"), eligible: true))
        let teleport = raw([.up]).replacingOccurrences(of: "1|2,2|", with: "1|2,3|")
        XCTAssertFalse(repo.save(level: 1, raw: teleport, eligible: true))
    }
    func testLegacyCompletedIsViewableOnlyAndNeverNewRecord() async throws {
        let (repo, store, defaults) = fixture()
        let old = raw(SokobanSolutions.directions(level: 1)!)
        defaults.set(old, forKey: "classicgames.sokoban.resume")
        defaults.set(10, forKey: "classicgames.best.sokoban.1")
        let proof = SokobanLegacyProof(rawDigest: SokobanPersistence.digest(old), identity: SokobanPersistence.identity(level: 1))
        XCTAssertEqual(repo.migrateLegacy(proof: proof), .legacyCompleted)
        XCTAssertEqual(repo.legacyCompletedRaw(digest: SokobanPersistence.digest(old)), old)
        XCTAssertNil(try repo.load(level: 1))
        XCTAssertNil(repo.best(level: 1))
        XCTAssertEqual(repo.historicalBest(level: 1), 10)
        XCTAssertFalse(store.values.isEmpty)
    }
    func testInterruptedMigrationNeverOverwritesNewerPlay() async throws {
        let (repo, store, defaults) = fixture()
        let old = raw([.up])
        defaults.set(old, forKey: "classicgames.sokoban.resume")
        let proof = SokobanLegacyProof(rawDigest: SokobanPersistence.digest(old), identity: SokobanPersistence.identity(level: 1))
        store.failPrefix = "legacy.result."
        XCTAssertEqual(repo.migrateLegacy(proof: proof), .failed)
        XCTAssertEqual(try repo.load(level: 1)?.raw, old)
        XCTAssertTrue(repo.save(level: 1, raw: raw([.up, .down]), eligible: true))
        store.failPrefix = nil
        XCTAssertEqual(repo.migrateLegacy(proof: proof), .existingSlotPreserved)
        XCTAssertEqual(try repo.load(level: 1)?.raw, raw([.up, .down]))
        XCTAssertEqual(defaults.string(forKey: "classicgames.sokoban.resume"), old)
    }
    func testFairBestIsVersionedAndLegacyKeysUnchanged() async throws {
        let (repo, _, defaults) = fixture()
        defaults.set(1, forKey: "classicgames.best.sokoban.1")
        defaults.set(700, forKey: "classicgames.best.snake")
        XCTAssertNil(repo.best(level: 1))
        let win = raw(SokobanSolutions.directions(level: 1)!)
        XCTAssertTrue(repo.save(level: 1, raw: win, eligible: false))
        XCTAssertNil(repo.best(level: 1))
        XCTAssertTrue(repo.save(level: 1, raw: win, eligible: true))
        XCTAssertEqual(repo.best(level: 1), 33)
        XCTAssertTrue(repo.save(level: 1, raw: raw(), eligible: true))
        XCTAssertEqual(repo.best(level: 1), 33)
        XCTAssertEqual(defaults.integer(forKey: "classicgames.best.sokoban.1"), 1)
        XCTAssertEqual(defaults.integer(forKey: "classicgames.best.snake"), 700)
    }
    func testMalformedOrDifferentSchemaNeverSilentlyLoads() async throws {
        let (repo, store, _) = fixture()
        XCTAssertTrue(repo.save(level: 1, raw: raw(), eligible: true))
        let key = SokobanPersistence.slotKey(level: 1)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(store.values[key])) as? [String: Any])
        json["formatVersion"] = 99
        store.values[key] = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try repo.load(level: 1))
        store.values[key] = Data("broken".utf8)
        XCTAssertThrowsError(try repo.load(level: 1))
    }

    func testReadFailureStillRetainsNewestPendingSnapshot() async throws {
        let (repo, store, _) = fixture()
        XCTAssertTrue(repo.save(level: 1, raw: raw(), eligible: true))
        store.failReads = true
        XCTAssertFalse(repo.save(level: 1, raw: raw([.up]), eligible: true))
        XCTAssertEqual(try repo.game(level: 1)?.raw, raw([.up]))
        store.failReads = false
        XCTAssertTrue(repo.retry(level: 1))
        XCTAssertEqual(try repo.load(level: 1)?.raw, raw([.up]))
    }
    func testModelSwitchResumeAndUndoUseIndependentSlots() async throws {
        let (repo, store, defaults) = fixture()
        let model = SokobanModel(persistence: repo)
        model.move(.up)
        model.load(2)
        model.move(.up)
        model.load(1)
        XCTAssertEqual(model.steps, 1)
        XCTAssertEqual(model.player, GridPoint(row: 2, col: 2))
        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.steps, 0)
        let reopened = SokobanModel(persistence: SokobanPersistence(storage: store, legacyDefaults: defaults))
        XCTAssertEqual(reopened.levelNumber, 1)
        XCTAssertEqual(reopened.steps, 0)
        reopened.load(2)
        XCTAssertEqual(reopened.steps, 1)
        XCTAssertTrue(reopened.undo())
    }
    func testModelQuarantinesUnknownLegacyWithoutChangingOriginal() async throws {
        let (repo, store, defaults) = fixture()
        defaults.set(raw([.up]), forKey: "classicgames.sokoban.resume")
        let model = SokobanModel(persistence: repo)
        XCTAssertEqual(model.steps, 0)
        XCTAssertEqual(model.legacyMigration, .identityUnproven)
        XCTAssertEqual(defaults.string(forKey: "classicgames.sokoban.resume"), raw([.up]))
        XCTAssertNotNil(store.values["legacy.original." + SokobanPersistence.digest(raw([.up]))])
    }
    func testCorruptSlotBlocksPlayUntilExplicitRestartPreservesBytes() async throws {
        let (repo, store, _) = fixture()
        let key = SokobanPersistence.slotKey(level: 1)
        let broken = Data("not-json".utf8)
        store.values[key] = broken
        let model = SokobanModel(persistence: repo)
        XCTAssertFalse(model.loadIssue.isEmpty)
        model.move(.up)
        XCTAssertEqual(model.steps, 0)
        XCTAssertEqual(store.values[key], broken)
        model.restart()
        XCTAssertTrue(model.loadIssue.isEmpty)
        XCTAssertTrue(store.values.keys.contains(where: { $0.hasPrefix("quarantine.slot.1.") }))
        model.move(.up)
        XCTAssertEqual(model.steps, 1)
        XCTAssertNotEqual(store.values[key], broken)
    }
    func testModelFailuresRetryAndNoOpDoNotClaimSuccess() async throws {
        let (repo, store, _) = fixture()
        let model = SokobanModel(persistence: repo)
        model.move(.left) // wall; no snapshot write.
        XCTAssertTrue(store.values.isEmpty)
        store.fail = true
        model.move(.up)
        XCTAssertEqual(model.saveState, .failed)
        model.move(.down)
        XCTAssertEqual(model.steps, 2)
        store.fail = false
        XCTAssertTrue(model.retrySave())
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertEqual(SokobanResume.parse(try XCTUnwrap(repo.load(level: 1)).raw)?.steps, 2)
    }
    func testHintTaintsEntireRunAndNewFairWinLeavesLegacyKeysUnchanged() async throws {
        let (repo, _, defaults) = fixture()
        defaults.set(2, forKey: "classicgames.best.sokoban.1")
        let model = SokobanModel(persistence: repo)
        _ = model.hint()
        for direction in SokobanSolutions.directions(level: 1)!.dropFirst() { model.move(direction) }
        XCTAssertTrue(model.won)
        XCTAssertNil(model.levelBest)
        model.restart()
        for direction in SokobanSolutions.directions(level: 1)! { model.move(direction) }
        XCTAssertTrue(model.won)
        XCTAssertEqual(model.levelBest, 33)
        XCTAssertEqual(defaults.integer(forKey: "classicgames.best.sokoban.1"), 2)
        XCTAssertEqual(model.historicalBest, 2)
    }

    func testRestartRetainsPendingFairBestAfterFailedWinSave() async throws {
        let (repo, store, _) = fixture()
        let model = SokobanModel(persistence: repo)
        let solution = SokobanSolutions.directions(level: 1)!
        for direction in solution.dropLast() { model.move(direction) }
        store.fail = true
        model.move(solution.last!)
        XCTAssertEqual(model.levelBest, 33)
        store.fail = false
        model.restart()
        XCTAssertEqual(model.levelBest, 33)
        XCTAssertEqual(model.steps, 0)
    }
    func testRealFileBoundaryReportsFailureAndNeverOverwritesBackup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sokoban-synthetic-" + UUID().uuidString)
        let fileStore = SokobanFileStorage(directory: directory)
        try fileStore.write(Data("original".utf8), forKey: "backup", ifAbsent: true)
        XCTAssertThrowsError(try fileStore.write(Data("changed".utf8), forKey: "backup", ifAbsent: true))
        XCTAssertEqual(try fileStore.data(forKey: "backup"), Data("original".utf8))
        let blocked = SokobanFileStorage(directory: directory.appendingPathComponent("backup"))
        let defaults = UserDefaults(suiteName: "sokoban.synthetic." + UUID().uuidString)!
        let repo = SokobanPersistence(storage: blocked, legacyDefaults: defaults)
        XCTAssertFalse(repo.save(level: 1, raw: raw([.up]), eligible: true))
        XCTAssertEqual(repo.states[1], .failed)
        XCTAssertEqual(try repo.game(level: 1)?.raw, raw([.up]))
    }

    func testRestartReadFailureDoesNotLockHealthyCurrentPlay() async throws {
        let (repo, store, _) = fixture()
        let model = SokobanModel(persistence: repo)
        model.move(.up)
        store.failReads = true
        model.restart()
        XCTAssertEqual(model.steps, 1)
        XCTAssertTrue(model.loadIssue.isEmpty)
        model.move(.down)
        XCTAssertEqual(model.steps, 2)
    }
    func testInvalidRedoDuplicateBoxesAndBoundsRejectWholeSnapshot() async throws {
        let (repo, _, _) = fixture()
        var parts = raw().components(separatedBy: "|")
        parts[8] = "2,3*3,1+4,3*1*up*0*0"
        XCTAssertFalse(repo.save(level: 1, raw: parts.joined(separator: "|"), eligible: true))
        parts = raw().components(separatedBy: "|"); parts[2] = "3,1+3,1+4,3"
        XCTAssertNil(SokobanResume.parse(parts.joined(separator: "|")))
        parts = raw().components(separatedBy: "|"); parts[1] = "9223372036854775807,2"
        XCTAssertFalse(repo.save(level: 1, raw: parts.joined(separator: "|"), eligible: true))
    }
    func testRetryRejectsReentrantDuplicateRequest() async throws {
        let (repo, store, _) = fixture()
        store.fail = true
        XCTAssertFalse(repo.save(level: 1, raw: raw([.up]), eligible: true))
        store.fail = false
        var observed = false
        store.onWrite = {
            observed = true
            XCTAssertEqual(repo.states[1], .retrying)
            XCTAssertFalse(repo.retry(level: 1))
        }
        XCTAssertTrue(repo.retry(level: 1))
        XCTAssertTrue(observed)
    }

    // I1: no repository reads between the successful last write and the injected
    // read outage: inspecting bytes directly must not accidentally refresh known.
    func testI1SuccessfulWinThenReadFailureUndoRetryKeepsBest() async throws {
        let (repo, store, _) = fixture()
        let model = SokobanModel(persistence: repo)
        let solution = SokobanSolutions.directions(level: 1)!
        for d in solution.dropLast() { model.move(d) }
        store.afterWrite = { key in if key == "slot.1" { store.failReads = true } }
        model.move(solution.last!)
        store.afterWrite = nil
        let written = try JSONDecoder().decode(SokobanSavedGame.self, from: XCTUnwrap(store.values["slot.1"]))
        XCTAssertEqual(written.best, 33)
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertEqual(model.levelBest, 33)
        XCTAssertEqual(repo.best(level: 1), 33)
        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.saveState, .failed)
        XCTAssertEqual(try repo.game(level: 1)?.best, 33)
        store.failReads = false
        XCTAssertTrue(model.retrySave())
        XCTAssertEqual(try repo.load(level: 1)?.best, 33)
    }
    func testI1SuccessfulRetryThenReadFailureUndoRetryKeepsBest() async throws {
        let (repo, store, _) = fixture()
        let model = SokobanModel(persistence: repo)
        let solution = SokobanSolutions.directions(level: 1)!
        for d in solution.dropLast() { model.move(d) }
        store.fail = true
        model.move(solution.last!)
        XCTAssertEqual(model.saveState, .failed)
        XCTAssertEqual(model.levelBest, 33)
        store.fail = false
        store.afterWrite = { key in if key == "slot.1" { store.failReads = true } }
        XCTAssertTrue(model.retrySave())
        store.afterWrite = nil
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertEqual(repo.best(level: 1), 33)
        XCTAssertTrue(model.undo())
        XCTAssertEqual(try repo.game(level: 1)?.best, 33)
        store.failReads = false
        XCTAssertTrue(model.retrySave())
        XCTAssertEqual(try repo.load(level: 1)?.best, 33)
    }
    func testI1RetryPreservesVerifiedSameIdentityDiskBest() async throws {
        let (repo, store, _) = fixture()
        let model = SokobanModel(persistence: repo)
        model.move(.up)
        let before = try XCTUnwrap(repo.load(level: 1))
        store.fail = true
        model.move(.down)
        store.fail = false
        // Disk has a better same-version record by the time retry reads it.
        let recorded = SokobanSavedGame(formatVersion: before.formatVersion, identity: before.identity,
            level: before.level, sequence: before.sequence, raw: before.raw, eligible: before.eligible,
            best: 33, legacyDigest: before.legacyDigest)
        store.values["slot.1"] = try JSONEncoder().encode(recorded)
        XCTAssertTrue(model.retrySave())
        XCTAssertEqual(try repo.load(level: 1)?.best, 33)
        XCTAssertEqual(model.levelBest, 33)
    }

    func testI1NoCacheReadFailureIsNotMissingOrBadContent() async throws {
        let (repo, store, defaults) = fixture()
        defaults.set(1, forKey: "classicgames.best.sokoban.1")
        store.failReads = true
        XCTAssertThrowsError(try repo.game(level: 1)) { error in
            guard case SokobanSaveError.readFailed = error else { return XCTFail("IO failure misclassified: \(error)") }
        }
        XCTAssertNil(repo.best(level: 1)) // never import the old historical 1.
        store.failReads = false
        XCTAssertNil(try repo.game(level: 1))
    }
    func testI1CacheDoesNotMaskMissingMalformedOrOtherIdentitySlot() async throws {
        let (repo, store, _) = fixture()
        XCTAssertTrue(repo.save(level: 1, raw: raw(), eligible: true))
        let original = try XCTUnwrap(store.values["slot.1"])
        store.values["slot.1"] = nil
        XCTAssertNil(try repo.game(level: 1))
        store.values["slot.1"] = Data("broken".utf8)
        XCTAssertThrowsError(try repo.game(level: 1))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        json["identity"] = "old-different-asset"; json["best"] = 1
        store.values["slot.1"] = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try repo.game(level: 1))
        XCTAssertNil(repo.best(level: 1))
    }

    func testI2FirstRestartReadFailureLeavesPendingAndBoardUntouched() async throws {
        let (repo, store, _) = fixture()
        let model = SokobanModel(persistence: repo)
        for d in SokobanSolutions.directions(level: 1)! { model.move(d) }
        store.fail = true
        XCTAssertTrue(model.undo())
        let pending = try XCTUnwrap(repo.game(level: 1))
        let bytes = store.values["slot.1"]
        store.fail = false; store.readCount = 0; store.failReadAt = 1
        model.restart()
        XCTAssertEqual(model.steps, 32)
        XCTAssertEqual(try repo.game(level: 1)?.raw, pending.raw)
        XCTAssertEqual(store.values["slot.1"], bytes)
        XCTAssertEqual(model.levelBest, 33)
        XCTAssertFalse(model.notice.isEmpty)
        XCTAssertFalse(store.values.keys.contains { $0.hasPrefix("quarantine.") })
    }
    func testI2SecondReadFaultNeverQuarantinesHealthyWinOrDropsBest() async throws {
        let (repo, store, _) = fixture()
        let model = SokobanModel(persistence: repo)
        for d in SokobanSolutions.directions(level: 1)! { model.move(d) }
        let bytes = try XCTUnwrap(store.values["slot.1"])
        store.readCount = 0; store.failReadAt = 2
        model.restart()
        XCTAssertEqual(store.values["slot.1"], bytes)
        XCTAssertEqual(model.levelBest, 33)
        XCTAssertFalse(store.values.keys.contains { $0.hasPrefix("quarantine.") })
        // With duplicate prepare reads removed, the second read belongs to saving
        // the reset snapshot: that IO failure must retain it, never grant replacement.
        XCTAssertEqual(model.saveState, .failed)
        XCTAssertEqual(try repo.game(level: 1)?.best, 33)
        store.failReadAt = nil
        XCTAssertTrue(model.retrySave())
        XCTAssertEqual(try repo.load(level: 1)?.best, 33)
        XCTAssertEqual(SokobanResume.parse(try XCTUnwrap(repo.load(level: 1)).raw)?.steps, 0)
    }
    func testI2BackupFailurePreservesOriginalBytesAndExistingPending() async throws {
        let (repo, store, _) = fixture()
        let model = SokobanModel(persistence: repo)
        for d in SokobanSolutions.directions(level: 1)! { model.move(d) }
        store.fail = true
        XCTAssertTrue(model.undo())
        let pending = try XCTUnwrap(repo.game(level: 1))
        store.fail = false
        let bad = Data("bad-slot-needing-backup".utf8)
        store.values["slot.1"] = bad
        store.failPrefix = "quarantine.slot.1."
        model.restart()
        XCTAssertEqual(model.steps, 32)
        XCTAssertEqual(try repo.game(level: 1)?.raw, pending.raw)
        XCTAssertEqual(try repo.game(level: 1)?.best, 33)
        XCTAssertEqual(store.values["slot.1"], bad)
        XCTAssertFalse(store.values.keys.contains { $0.hasPrefix("quarantine.") })
    }
    func testI2BackupSucceedsReplacementWriteFailsThenRetryPreservesBackup() async throws {
        let (repo, store, defaults) = fixture()
        let bad = Data("original-corrupt-bytes".utf8)
        store.values["slot.1"] = bad
        defaults.set("legacy-must-stay", forKey: "classicgames.sokoban.resume")
        let model = SokobanModel(persistence: repo)
        store.failPrefix = "slot."
        model.restart()
        XCTAssertEqual(model.saveState, .failed)
        XCTAssertEqual(store.values["slot.1"], bad)
        let backups = store.values.filter { $0.key.hasPrefix("quarantine.slot.1.") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups.values.first, bad)
        XCTAssertEqual(SokobanResume.parse(try XCTUnwrap(repo.game(level: 1)).raw)?.steps, 0)
        store.failPrefix = nil
        XCTAssertTrue(model.retrySave())
        XCTAssertEqual(SokobanResume.parse(try XCTUnwrap(repo.load(level: 1)).raw)?.steps, 0)
        XCTAssertEqual(store.values.filter { $0.key.hasPrefix("quarantine.slot.1.") }, backups)
        XCTAssertEqual(defaults.string(forKey: "classicgames.sokoban.resume"), "legacy-must-stay")
    }
    func testI2HealthyRestartWriteFailureKeepsSuccessfulBestAndPendingReset() async throws {
        let (repo, store, _) = fixture()
        let model = SokobanModel(persistence: repo)
        for d in SokobanSolutions.directions(level: 1)! { model.move(d) }
        let bytes = store.values["slot.1"]
        store.failPrefix = "slot."
        model.restart()
        XCTAssertEqual(model.steps, 0)
        XCTAssertEqual(model.saveState, .failed)
        XCTAssertEqual(model.levelBest, 33)
        XCTAssertEqual(store.values["slot.1"], bytes)
        store.failPrefix = nil
        XCTAssertTrue(model.retrySave())
        XCTAssertEqual(try repo.load(level: 1)?.best, 33)
        XCTAssertFalse(store.values.keys.contains { $0.hasPrefix("quarantine.") })
    }
    func testI2RestartOtherIdentityDoesNotImportCachedOrHistoricalBest() async throws {
        let (repo, store, defaults) = fixture()
        let model = SokobanModel(persistence: repo)
        for d in SokobanSolutions.directions(level: 1)! { model.move(d) }
        defaults.set(1, forKey: "classicgames.best.sokoban.1")
        var other = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(store.values["slot.1"])) as? [String: Any])
        other["identity"] = "another-asset"; other["best"] = 2
        let original = try JSONSerialization.data(withJSONObject: other)
        store.values["slot.1"] = original
        model.restart()
        // The foreign 2 and legacy 1 remain forbidden. The already verified
        // CURRENT-identity 33 must now survive explicit replacement (B3-I1).
        XCTAssertEqual(model.levelBest, 33)
        XCTAssertEqual(try repo.load(level: 1)?.best, 33)
        XCTAssertEqual(store.values.filter { $0.key.hasPrefix("quarantine.slot.1.") }.values.first, original)
        XCTAssertEqual(model.historicalBest, 1)
    }
    func testB3I1Verified33SurvivesBinaryRecoveryRestartAndColdFileLoad() async throws {
        let directory = URL(fileURLWithPath: "/Users/hansen/ClassicGames-Engineering/sokoban-batch3-review-fixes-20261125/SyntheticTests").appendingPathComponent(UUID().uuidString)
        let store = SokobanFileStorage(directory: directory)
        let defaults = UserDefaults(suiteName: "sokoban.synthetic.b3fix." + UUID().uuidString)!
        defaults.set(7, forKey: "classicgames.best.sokoban.1")
        defaults.set(91, forKey: "classicgames.best.snake")
        let repo = SokobanPersistence(storage: store, legacyDefaults: defaults)
        let model = SokobanModel(persistence: repo)
        for direction in SokobanSolutions.directions(level: 1)! { model.move(direction) }
        XCTAssertEqual(model.levelBest, 33)
        let bad = Data([0xff, 0x00, 0xfe, 0x81])
        try store.write(bad, forKey: "slot.1", ifAbsent: false)
        model.load(1); XCTAssertEqual(model.visitKind, .recovery)
        model.restart()
        XCTAssertEqual(model.steps, 0); XCTAssertFalse(model.undo())
        XCTAssertEqual(model.levelBest, 33)
        XCTAssertEqual(try store.data(forKey: "quarantine.slot.1." + SokobanPersistence.digest(bad)), bad)
        let cold = SokobanModel(persistence: SokobanPersistence(storage: SokobanFileStorage(directory: directory), legacyDefaults: defaults))
        XCTAssertEqual(cold.steps, 0); XCTAssertFalse(cold.undo()); XCTAssertEqual(cold.levelBest, 33)
        XCTAssertEqual(defaults.integer(forKey: "classicgames.best.sokoban.1"), 7)
        XCTAssertEqual(defaults.integer(forKey: "classicgames.best.snake"), 91)
    }
    func testB3I1PendingBetterBestSurvivesBackupAndRepeatedRetryFailures() async throws {
        let (repo, store, defaults) = fixture(); defaults.set(7, forKey: "classicgames.best.sokoban.1")
        let model = SokobanModel(persistence: repo)
        model.move(.up); model.move(.down)
        for direction in SokobanSolutions.directions(level: 1)! { model.move(direction) }
        XCTAssertEqual(model.levelBest, 35)
        model.restart(); store.fail = true
        for direction in SokobanSolutions.directions(level: 1)! { model.move(direction) }
        let priorPending = try XCTUnwrap(repo.game(level: 1))
        XCTAssertEqual(priorPending.best, 33)
        let bad = Data([0xfe, 0xff, 0x81]); store.values["slot.1"] = bad
        store.fail = false; store.failPrefix = "quarantine."
        model.restart()
        XCTAssertEqual(model.steps, 33); XCTAssertEqual(try repo.game(level: 1)?.raw, priorPending.raw)
        XCTAssertEqual(try repo.game(level: 1)?.best, priorPending.best)
        XCTAssertEqual(try repo.game(level: 1)?.sequence, priorPending.sequence)
        XCTAssertEqual(store.values["slot.1"], bad)
        store.failPrefix = "slot."
        model.restart()
        XCTAssertEqual(model.steps, 0); XCTAssertFalse(model.undo())
        XCTAssertEqual(model.levelBest, 33); XCTAssertEqual(try repo.game(level: 1)?.best, 33)
        for _ in 0..<3 {
            XCTAssertFalse(model.retrySave()); XCTAssertEqual(model.levelBest, 33)
            XCTAssertEqual(try repo.game(level: 1)?.best, 33); XCTAssertEqual(store.values["slot.1"], bad)
        }
        store.failPrefix = nil; XCTAssertTrue(model.retrySave())
        let cold = SokobanModel(persistence: SokobanPersistence(storage: store, legacyDefaults: defaults))
        XCTAssertEqual(cold.levelBest, 33); XCTAssertEqual(cold.steps, 0); XCTAssertFalse(cold.undo())
        XCTAssertEqual(store.values["quarantine.slot.1." + SokobanPersistence.digest(bad)], bad)
        XCTAssertEqual(model.historicalBest, 7)
    }
    func testB3I1CurrentKnownIsNotReplacedByForeignOrInvalidJSONBest() async throws {
        for foreign in [true, false] {
            let (repo, store, defaults) = fixture(); defaults.set(7, forKey: "classicgames.best.sokoban.1")
            let model = SokobanModel(persistence: repo)
            for d in SokobanSolutions.directions(level: 1)! { model.move(d) }
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(store.values["slot.1"])) as? [String:Any])
            object["best"] = 1
            if foreign { object["identity"] = "not-current-identity" } else { object["raw"] = "not-a-legal-history" }
            let bad = try JSONSerialization.data(withJSONObject: object); store.values["slot.1"] = bad
            model.load(1); XCTAssertEqual(model.visitKind, .recovery)
            model.restart(); XCTAssertEqual(model.levelBest, 33)
            XCTAssertEqual(try repo.load(level: 1)?.best, 33)
            XCTAssertEqual(store.values["quarantine.slot.1." + SokobanPersistence.digest(bad)], bad)
            XCTAssertEqual(model.historicalBest, 7)
        }
    }
    func testB3I1NoTrustedRecordStaysQuarantinedAndExplicitlyUnverified() async throws {
        let (repo, store, defaults) = fixture(); defaults.set(7, forKey: "classicgames.best.sokoban.1")
        let bad = Data("{\"best\":1,\"identity\":\"foreign\",\"raw\":\"invalid\"}".utf8)
        store.values["slot.1"] = bad
        let model = SokobanModel(persistence: repo)
        XCTAssertEqual(model.visitKind, .recovery); XCTAssertFalse(model.hasBoard)
        model.restart(); XCTAssertEqual(model.steps, 0); XCTAssertNil(model.levelBest)
        XCTAssertFalse(model.notice.isEmpty, "No verifiable prior record must not silently look like a proven empty history")
        let cold = SokobanModel(persistence: SokobanPersistence(storage: store, legacyDefaults: defaults))
        XCTAssertNil(cold.levelBest); XCTAssertFalse(cold.notice.isEmpty)
        XCTAssertEqual(store.values["quarantine.slot.1." + SokobanPersistence.digest(bad)], bad)
        XCTAssertEqual(cold.historicalBest, 7)
    }

    func testB3I1OnlyForeignOrIllegalHistoryCannotSupplyNewBest() async throws {
        for foreign in [true, false] {
            let (repo, store, defaults) = fixture(); defaults.set(7, forKey: "classicgames.best.sokoban.1")
            let forged = SokobanSavedGame(formatVersion: 1,
                identity: foreign ? "another-identity" : SokobanPersistence.identity(level: 1),
                level: 1, sequence: 17, raw: foreign ? raw() : "illegal-full-history", eligible: true, best: 1, legacyDigest: nil)
            let bad = try JSONEncoder().encode(forged); store.values["slot.1"] = bad
            let model = SokobanModel(persistence: repo)
            XCTAssertEqual(model.visitKind, .recovery); XCTAssertFalse(model.hasBoard)
            model.restart(); XCTAssertNil(model.levelBest); XCTAssertFalse(model.undo())
            XCTAssertFalse(model.notice.isEmpty); XCTAssertEqual(model.historicalBest, 7)
            let cold = SokobanModel(persistence: SokobanPersistence(storage: store, legacyDefaults: defaults))
            XCTAssertNil(cold.levelBest); XCTAssertEqual(cold.steps, 0); XCTAssertFalse(cold.notice.isEmpty)
            XCTAssertEqual(store.values["quarantine.slot.1." + SokobanPersistence.digest(bad)], bad)
        }
    }

    func testB3I1ResourceIdentityChangeDoesNotCarryForwardOldBest() async throws {
        let (repo, store, defaults) = fixture()
        defaults.set(7, forKey: "classicgames.best.sokoban.1")
        let model = SokobanModel(persistence: repo)
        for direction in SokobanSolutions.directions(level: 1)! { model.move(direction) }
        XCTAssertEqual(model.levelBest, 33)
        let original = try XCTUnwrap(store.values["slot.1"])
        SokobanPersistence.testIdentityOverride = { _ in "resource-identity-after-edition-change" }
        defer { SokobanPersistence.testIdentityOverride = nil }
        model.load(1)
        XCTAssertEqual(model.visitKind, .recovery)
        model.restart()
        XCTAssertNil(model.levelBest)
        XCTAssertFalse(model.notice.isEmpty)
        XCTAssertEqual(model.steps, 0)
        XCTAssertFalse(model.undo())
        let cold = SokobanModel(persistence: SokobanPersistence(storage: store, legacyDefaults: defaults))
        XCTAssertNil(cold.levelBest)
        XCTAssertEqual(cold.steps, 0)
        XCTAssertFalse(cold.notice.isEmpty)
        XCTAssertEqual(store.values["quarantine.slot.1." + SokobanPersistence.digest(original)], original)
        XCTAssertEqual(cold.historicalBest, 7)
    }

    func testB3I2OnlyLevel100RecordIsNotCampaignComplete() async throws {
        let store = MemoryStorage()
        let defaults = UserDefaults(suiteName: "sokoban.synthetic.b3i2.only100." + UUID().uuidString)!
        defaults.set(7, forKey: "classicgames.best.sokoban.100")
        try writeScoreOnly(store, levels: 100...100)
        let repo = SokobanPersistence(storage: store, legacyDefaults: defaults)
        let model = SokobanModel(persistence: repo)
        model.load(100)
        XCTAssertEqual(model.levelNumber, SokobanLevels.count)
        XCTAssertEqual(model.visitKind, .scoreOnly)
        XCTAssertFalse(model.isCampaignComplete)
        XCTAssertEqual(model.completionTitle, "已通关")
        XCTAssertEqual(model.completionEvents, 0)
        XCTAssertEqual(model.historicalBest, 7)
    }

    func testB3I2FreshLastMissingLevelWinIsCampaignComplete() async throws {
        let store = MemoryStorage()
        let defaults = UserDefaults(suiteName: "sokoban.synthetic.b3i2.lastfill." + UUID().uuidString)!
        try writeScoreOnly(store, levels: 2...SokobanLevels.count)
        let repo = SokobanPersistence(storage: store, legacyDefaults: defaults)
        let model = SokobanModel(persistence: repo)
        model.load(1)
        XCTAssertFalse(model.isCampaignComplete)
        XCTAssertEqual(model.completionTitle, "推箱子")
        for direction in SokobanSolutions.directions(level: 1)! { model.move(direction) }
        XCTAssertTrue(model.won)
        XCTAssertEqual(model.visitKind, .completedNow)
        XCTAssertEqual(model.completionEvents, 1)
        XCTAssertTrue(model.isCampaignComplete)
        XCTAssertEqual(model.completionTitle, "全部完成")
        XCTAssertEqual(model.levelNumber, 1)
        XCTAssertNotEqual(model.levelNumber, SokobanLevels.count)
        let disk = try XCTUnwrap(store.values["slot.1"])
        let cold = SokobanModel(persistence: SokobanPersistence(storage: store, legacyDefaults: defaults))
        cold.load(1)
        XCTAssertEqual(cold.visitKind, .completedRevisit)
        XCTAssertEqual(cold.completionEvents, 0)
        XCTAssertEqual(cold.completionTitle, "已通关")
        XCTAssertTrue(cold.isCampaignComplete)
        XCTAssertEqual(store.values["slot.1"], disk)
        XCTAssertFalse(cold.undo())
    }

    func testB3I2ForeignOrLegacyRecordsDoNotCountTowardCampaignComplete() async throws {
        let store = MemoryStorage()
        let defaults = UserDefaults(suiteName: "sokoban.synthetic.b3i2.foreign." + UUID().uuidString)!
        defaults.set(9, forKey: "classicgames.best.sokoban.100")
        try writeScoreOnly(store, levels: 1...99)
        try writeScoreOnly(store, levels: 100...100, identity: { _ in "another-asset" })
        let repo = SokobanPersistence(storage: store, legacyDefaults: defaults)
        let model = SokobanModel(persistence: repo)
        XCTAssertFalse(model.isCampaignComplete)
        model.load(100)
        XCTAssertEqual(model.visitKind, .recovery)
        XCTAssertFalse(model.isCampaignComplete)
        XCTAssertNotEqual(model.completionTitle, "全部完成")
        XCTAssertEqual(model.historicalBest, 9)
    }

    func testB3I2HeadlineDoesNotTreatLastLevelNumberAsCampaignComplete() {
        XCTAssertEqual(SokobanModel.completionTitle(isReadOnly: false, won: true, isCampaignComplete: false), "过关")
        XCTAssertEqual(SokobanModel.completionTitle(isReadOnly: false, won: true, isCampaignComplete: true), "全部完成")
        XCTAssertEqual(SokobanModel.completionTitle(isReadOnly: true, won: true, isCampaignComplete: true), "已通关")
        XCTAssertEqual(SokobanModel.completionTitle(isReadOnly: false, won: false, isCampaignComplete: false), "推箱子")
    }

}
