import XCTest
@testable import SokobanLogic

@MainActor
final class EconomyTests: XCTestCase {
    final class MemoryStorage: SokobanSaveStorage {
        var values: [String: Data] = [:]
        func data(forKey key: String) throws -> Data? { values[key] }
        func write(_ data: Data, forKey key: String, ifAbsent: Bool) throws {
            if ifAbsent, let existing = values[key] {
                guard existing == data else { throw CocoaError(.fileWriteFileExists) }
                return
            }
            values[key] = data
        }
    }

    private func makeRepo(_ storage: MemoryStorage? = nil) -> (SokobanPersistence, MemoryStorage, UserDefaults) {
        let storage = storage ?? MemoryStorage()
        let defaults = UserDefaults(suiteName: "sokoban.economy." + UUID().uuidString)!
        return (SokobanPersistence(storage: storage, legacyDefaults: defaults), storage, defaults)
    }

    private func rawWin(level: Int = 1) -> String {
        let moves = SokobanSolutions.directions(level: level)!
        let board = SokobanLevel.parsed(level)
        var player = board.player, boxes = board.boxes
        var frames: [SokobanFrame] = []
        var facing = SokobanDirection.down
        for (index, move) in moves.enumerated() {
            frames.append(SokobanFrame(player: player, boxes: boxes, steps: index, facing: facing, won: false, counts: false))
            let next = player.moving(move)
            if boxes.remove(next) != nil { boxes.insert(next.moving(move)) }
            player = next
            facing = move
        }
        return SokobanResume.encode(level: level, player: player, boxes: boxes, steps: moves.count,
            facing: facing, won: boxes == board.targets, counts: true, undo: frames, redo: [])
    }

    func testPayoutFirstUpgradeAndRepeat() {
        XCTAssertEqual(SokobanRewards.payout(thisStars: 1, claimedTier: 0).coins, 20)
        XCTAssertEqual(SokobanRewards.payout(thisStars: 1, claimedTier: 0).undo, 1)
        XCTAssertEqual(SokobanRewards.payout(thisStars: 2, claimedTier: 0), SokobanPayout(coins: 40, undo: 2, hint: 0, isRepeat: false, claimedBefore: 0, claimedAfter: 2, stars: 2))
        XCTAssertEqual(SokobanRewards.payout(thisStars: 3, claimedTier: 0), SokobanPayout(coins: 80, undo: 2, hint: 1, isRepeat: false, claimedBefore: 0, claimedAfter: 3, stars: 3))
        XCTAssertEqual(SokobanRewards.payout(thisStars: 2, claimedTier: 1), SokobanPayout(coins: 20, undo: 1, hint: 0, isRepeat: false, claimedBefore: 1, claimedAfter: 2, stars: 2))
        XCTAssertEqual(SokobanRewards.payout(thisStars: 3, claimedTier: 2), SokobanPayout(coins: 40, undo: 0, hint: 1, isRepeat: false, claimedBefore: 2, claimedAfter: 3, stars: 3))
        XCTAssertEqual(SokobanRewards.payout(thisStars: 3, claimedTier: 1), SokobanPayout(coins: 60, undo: 1, hint: 1, isRepeat: false, claimedBefore: 1, claimedAfter: 3, stars: 3))
        let repeatPayout = SokobanRewards.payout(thisStars: 3, claimedTier: 3)
        XCTAssertTrue(repeatPayout.isRepeat)
        XCTAssertEqual(repeatPayout.coins, 5)
        XCTAssertEqual(repeatPayout.undo, 0)
        XCTAssertEqual(repeatPayout.hint, 0)
        XCTAssertEqual(SokobanRewards.payout(thisStars: 1, claimedTier: 3).coins, 5)
    }

    func testFreshWalletStartingGrant() {
        let (repo, store, _) = makeRepo()
        XCTAssertEqual(repo.wallet.coins, 50)
        XCTAssertEqual(repo.wallet.undoItemCount, 5)
        XCTAssertEqual(repo.wallet.hintItemCount, 2)
        XCTAssertNil(store.values[SokobanPersistence.walletKey], "cold start stays in memory until a mutation")
    }

    func testShopPurchaseAndInsufficientFunds() {
        let (repo, _, _) = makeRepo()
        XCTAssertTrue(repo.purchase(.hint1))
        XCTAssertEqual(repo.wallet.coins, 0)
        XCTAssertEqual(repo.wallet.hintItemCount, 3)
        XCTAssertFalse(repo.purchase(.undo1))
        XCTAssertFalse(repo.purchase(.undo5))
        XCTAssertFalse(repo.purchase(.hint3))
        XCTAssertEqual(repo.wallet.coins, 0)
        XCTAssertEqual(repo.wallet.undoItemCount, 5)
        // A later fresh wallet can buy undo packs while funds last.
        let (rich, _, _) = makeRepo()
        XCTAssertTrue(rich.purchase(.undo1))
        XCTAssertEqual(rich.wallet.coins, 35)
        XCTAssertEqual(rich.wallet.undoItemCount, 6)
        XCTAssertFalse(rich.purchase(.undo5))
        XCTAssertEqual(rich.wallet.coins, 35)
    }

    func testFirstClearUpgradeAndRepeatAwardsPersist() {
        let (repo, store, defaults) = makeRepo()
        let first = repo.applyClearReward(level: 1, steps: 33, counts: true)
        XCTAssertEqual(first.stars, 3)
        XCTAssertEqual(first.score, 100)
        XCTAssertEqual(first.title, "完美通关")
        XCTAssertEqual(first.payout.coins, 80)
        XCTAssertEqual(first.payout.undo, 2)
        XCTAssertEqual(first.payout.hint, 1)
        XCTAssertEqual(repo.wallet.coins, 130)
        XCTAssertEqual(repo.wallet.undoItemCount, 7)
        XCTAssertEqual(repo.wallet.hintItemCount, 3)
        XCTAssertEqual(repo.wallet.claimed(level: 1), 3)
        XCTAssertNotNil(store.values[SokobanPersistence.walletKey])
        let again = repo.applyClearReward(level: 1, steps: 40, counts: true)
        XCTAssertEqual(again.stars, 2)
        XCTAssertTrue(again.payout.isRepeat)
        XCTAssertEqual(again.payout.coins, 5)
        XCTAssertEqual(repo.wallet.coins, 135)
        XCTAssertEqual(repo.wallet.claimed(level: 1), 3)
        let reopened = SokobanPersistence(storage: store, legacyDefaults: defaults)
        XCTAssertEqual(reopened.wallet.coins, 135)
        XCTAssertEqual(reopened.wallet.claimed(level: 1), 3)
        XCTAssertEqual(reopened.wallet.undoItemCount, 7)
    }

    func testLegacySaveShowsNewStarsAndLeavesClaimedAtZero() {
        let (repo, store, defaults) = makeRepo()
        XCTAssertTrue(repo.save(level: 1, raw: rawWin(), eligible: true))
        XCTAssertEqual(repo.best(level: 1), 33)
        XCTAssertEqual(repo.bestStars(level: 1), 3)
        XCTAssertEqual(repo.wallet.claimed(level: 1), 0)
        let again = SokobanPersistence(storage: store, legacyDefaults: defaults)
        XCTAssertEqual(again.best(level: 1), 33)
        XCTAssertEqual(again.bestStars(level: 1), 3)
        XCTAssertEqual(again.wallet.claimed(level: 1), 0)
        let award = again.applyClearReward(level: 1, steps: 33, counts: true)
        XCTAssertFalse(award.payout.isRepeat)
        XCTAssertEqual(award.payout.coins, 80)
        XCTAssertEqual(again.wallet.claimed(level: 1), 3)
    }

    func testUndoAndHintConsumeAndZeroStock() {
        let (repo, _, _) = makeRepo()
        for _ in 1...5 { XCTAssertTrue(repo.consumeUndoTicket()) }
        XCTAssertEqual(repo.wallet.undoItemCount, 0)
        XCTAssertFalse(repo.consumeUndoTicket())
        XCTAssertTrue(repo.consumeHintItem())
        XCTAssertTrue(repo.consumeHintItem())
        XCTAssertFalse(repo.consumeHintItem())
        XCTAssertEqual(repo.wallet.hintItemCount, 0)
    }

    func testIneligibleClearDoesNotPay() {
        let (repo, _, _) = makeRepo()
        let settlement = repo.applyClearReward(level: 1, steps: 33, counts: false)
        XCTAssertEqual(settlement.stars, 3)
        XCTAssertEqual(settlement.payout.coins, 0)
        XCTAssertEqual(repo.wallet.coins, 50)
        XCTAssertEqual(repo.wallet.claimed(level: 1), 0)
    }

    func testModelRequestUndoChargesAndOpensShopWhenEmpty() {
        let (repo, _, _) = makeRepo()
        let model = SokobanModel(persistence: repo)
        XCTAssertEqual(model.requestUndo(), .empty)
        model.move(.down)
        XCTAssertEqual(model.steps, 1)
        XCTAssertEqual(model.requestUndo(), .undone)
        XCTAssertEqual(model.steps, 0)
        XCTAssertEqual(repo.wallet.undoItemCount, 4)
        model.move(.down)
        while repo.wallet.undoItemCount > 0 { _ = repo.consumeUndoTicket() }
        XCTAssertEqual(model.requestUndo(), .needsShop)
        XCTAssertEqual(model.steps, 1)
        XCTAssertEqual(repo.wallet.undoItemCount, 0)
    }

    func testOfficialWinPaysThreeStarRewardAndRecordsSettlement() {
        let (repo, _, _) = makeRepo()
        let model = SokobanModel(persistence: repo)
        for direction in SokobanSolutions.directions(level: 1)! { model.move(direction) }
        XCTAssertTrue(model.won)
        XCTAssertEqual(model.lastSettlement?.stars, 3)
        XCTAssertEqual(model.lastSettlement?.score, 100)
        XCTAssertEqual(model.lastSettlement?.payout.coins, 80)
        XCTAssertEqual(repo.wallet.coins, 130)
        XCTAssertEqual(repo.bestStars(level: 1), 3)
        XCTAssertEqual(repo.totalStars(), 3)
    }
}
