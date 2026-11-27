import Foundation
import Observation
import CryptoKit

@MainActor
protocol SokobanSaveStorage: AnyObject {
    func data(forKey key: String) throws -> Data?
    func write(_ data: Data, forKey key: String, ifAbsent: Bool) throws
}

enum SokobanSaveState: Equatable { case saved, failed, retrying }
enum SokobanMigrationResult: String, Codable {
    case none, identityUnproven, invalid, migrated, legacyCompleted, existingSlotPreserved, failed
}
struct SokobanLegacyProof {
    let rawDigest: String
    let identity: String
}
struct SokobanSavedGame: Codable {
    let formatVersion: Int
    let identity: String
    let level: Int
    let sequence: UInt64
    let raw: String
    let eligible: Bool
    let best: Int?
    let legacyDigest: String?
    /// Explicit same-version record without a recoverable board; never inferred from corrupt raw data.
    var recordOnly: Bool? = nil
    /// A corrupt predecessor was retained, but its prior record could not be proved.
    /// Optional for backwards compatibility; never imports the predecessor's best.
    var recordRecoveryPending: Bool? = nil
}

/// Single-process, MainActor-only file boundary. Atomic replacement reports actual
/// write errors, not UserDefaults' asynchronous in-memory acceptance. It is not an
/// fsync/power-loss guarantee and does not coordinate multiple app processes.
@MainActor
final class SokobanFileStorage: SokobanSaveStorage {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    func data(forKey key: String) throws -> Data? {
        let url = directory.appendingPathComponent(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    func write(_ data: Data, forKey key: String, ifAbsent: Bool) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if ifAbsent, let existing = try self.data(forKey: key) {
            guard existing == data else { throw CocoaError(.fileWriteFileExists) }
            return
        }
        try data.write(to: directory.appendingPathComponent(key), options: .atomic)
    }
}

enum SokobanSaveError: Error {
    case corrupt, incompatible, stale, sequenceExhausted
    case readFailed(Error)
}

@MainActor
@Observable
final class SokobanPersistence {
    static let shared: SokobanPersistence = {
        #if DEBUG
        if let session = SokobanTestSession.active { return session.persistence }
        #endif
        return SokobanPersistence(storage: SokobanFileStorage(directory: FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask)[0].appendingPathComponent("SokobanSaves-v1", isDirectory: true)),
        legacyDefaults: .standard)
    }()
    private let storage: SokobanSaveStorage
    private let legacyDefaults: UserDefaults
    private var pending: [Int: SokobanSavedGame] = [:]
    // IO bookkeeping is not view state: a rendering read must not invalidate itself.
    @ObservationIgnored private var known: [Int: SokobanSavedGame] = [:]
    @ObservationIgnored private var sequence: UInt64 = 0
    @ObservationIgnored private var completedLevels: Set<Int> = []
    @ObservationIgnored private var completionsIndexed = false
    private(set) var revision: UInt64 = 0
    private(set) var states: [Int: SokobanSaveState] = [:]
    private(set) var issues: [Int: String] = [:]
    private(set) var migrationResult: SokobanMigrationResult = .none

    init(storage: SokobanSaveStorage, legacyDefaults: UserDefaults) {
        self.storage = storage; self.legacyDefaults = legacyDefaults
        for level in 1...SokobanLevels.count {
            if let game = try? load(level: level) { sequence = max(sequence, game.sequence) }
        }
    }
    static func digest(_ raw: String) -> String { digest(Data(raw.utf8)) }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    /// Stable exact asset content, independent of Swift's randomized hashValue.
    #if DEBUG || SWIFT_PACKAGE
    /// Test-only: simulate a canonical resource edition change without editing fixtures.
    static var testIdentityOverride: ((Int) -> String)?
    #endif
    static func identity(level: Int) -> String {
        #if DEBUG || SWIFT_PACKAGE
        if let testIdentityOverride { return testIdentityOverride(level) }
        #endif
        return digest(SokobanLevels.pictures[level - 1])
    }
    static func slotKey(level: Int) -> String { "slot.\(level)" }
    static let walletKey = "profile.economy.v1"

    private var walletStore = SokobanWallet.fresh
    private var walletDidLoad = false

    /// 纯离线钱包。冷启动为 50 金币 + 撤销券 ×5 + 提示 ×2；没有档案时不立刻落盘。
    var wallet: SokobanWallet {
        ensureWallet()
        return walletStore
    }

    private func ensureWallet() {
        guard !walletDidLoad else { return }
        walletDidLoad = true
        if let data = try? storage.data(forKey: Self.walletKey),
           let decoded = try? JSONDecoder().decode(SokobanWallet.self, from: data),
           decoded.formatVersion == SokobanWallet.format,
           decoded.coins >= 0, decoded.undoItemCount >= 0, decoded.hintItemCount >= 0 {
            walletStore = decoded
        } else {
            walletStore = .fresh
        }
    }

    private func persistWallet() {
        ensureWallet()
        guard let data = try? JSONEncoder().encode(walletStore) else { return }
        try? storage.write(data, forKey: Self.walletKey, ifAbsent: false)
        revision &+= 1
    }

    func bestStars(level: Int) -> Int {
        guard let best = best(level: level) else { return 0 }
        let par = SokobanReferenceSolutions.parSteps(levelId: level)
        guard par > 0 else { return 0 }
        return SokobanScoring.stars(steps: best, parSteps: par)
    }

    func totalStars() -> Int {
        (1...SokobanLevels.count).reduce(0) { $0 + bestStars(level: $1) }
    }

    @discardableResult
    func applyClearReward(level: Int, steps: Int, counts: Bool) -> SokobanSettlement {
        ensureWallet()
        let par = SokobanReferenceSolutions.parSteps(levelId: level)
        let stars = SokobanScoring.stars(steps: steps, parSteps: max(par, 1))
        let score = SokobanScoring.score(steps: steps, parSteps: max(par, 1))
        let title = SokobanScoring.title(stars: stars)
        if !counts {
            let claimed = walletStore.claimed(level: level)
            return SokobanSettlement(level: level, steps: steps, parSteps: par, stars: stars, score: score, title: title,
                payout: SokobanPayout(coins: 0, undo: 0, hint: 0, isRepeat: false, claimedBefore: claimed, claimedAfter: claimed, stars: stars),
                counts: false)
        }
        let payout = SokobanRewards.payout(thisStars: stars, claimedTier: walletStore.claimed(level: level))
        walletStore.coins += payout.coins
        walletStore.undoItemCount += payout.undo
        walletStore.hintItemCount += payout.hint
        walletStore.setClaimed(level: level, tier: payout.claimedAfter)
        persistWallet()
        return SokobanSettlement(level: level, steps: steps, parSteps: par, stars: stars, score: score, title: title, payout: payout, counts: true)
    }

    @discardableResult
    func purchase(_ item: SokobanShopItem) -> Bool {
        ensureWallet()
        guard walletStore.coins >= item.coinCost else { return false }
        walletStore.coins -= item.coinCost
        walletStore.undoItemCount += item.undoDelta
        walletStore.hintItemCount += item.hintDelta
        persistWallet()
        return true
    }

    @discardableResult
    func consumeUndoTicket() -> Bool {
        ensureWallet()
        guard walletStore.undoItemCount > 0 else { return false }
        walletStore.undoItemCount -= 1
        persistWallet()
        return true
    }

    @discardableResult
    func consumeHintItem() -> Bool {
        ensureWallet()
        guard walletStore.hintItemCount > 0 else { return false }
        walletStore.hintItemCount -= 1
        persistWallet()
        return true
    }


    func load(level: Int) throws -> SokobanSavedGame? {
        do {
            let data: Data?
            do { data = try storage.data(forKey: Self.slotKey(level: level)) }
            catch { throw SokobanSaveError.readFailed(error) }
            guard let data else { return nil }
            let game = try decoded(data, level: level)
            if issues[level] != nil { issues[level] = nil }
            known[level] = game
            sequence = max(sequence, game.sequence)
            rememberCompletion(game)
            return game
        } catch {
            let message = String(describing: error)
            if issues[level] != message { issues[level] = message }
            throw error
        }
    }
    /// Pure content validation: never reads storage. A read error must not be
    /// mistaken for malformed bytes when deciding whether replacement is allowed.
    private func decoded(_ data: Data, level: Int) throws -> SokobanSavedGame {
        let game = try JSONDecoder().decode(SokobanSavedGame.self, from: data)
        guard game.formatVersion == 1, (1...SokobanLevels.count).contains(level),
              game.identity == Self.identity(level: level) else { throw SokobanSaveError.incompatible }
        guard game.level == level, game.sequence > 0, game.best.map({ $0 >= 0 }) ?? true,
              (game.recordOnly == true ? (game.raw.isEmpty && game.best != nil)
                                       : Self.validated(game.raw, level: level) != nil) else { throw SokobanSaveError.corrupt }
        return game
    }
    /// Failed writes remain addressable across level switches within this process.
    func game(level: Int) throws -> SokobanSavedGame? {
        if let latest = pending[level] { return latest }
        do { return try load(level: level) }
        catch SokobanSaveError.readFailed(let underlying) {
            // Only an IO failure can fall back to a verified current-identity
            // snapshot. Missing or malformed/incompatible data is not a cache hit.
            guard let last = known[level], last.formatVersion == 1,
                  last.identity == Self.identity(level: level) else { throw SokobanSaveError.readFailed(underlying) }
            return last
        }
    }
    func recentLevel() -> Int? {
        (1...SokobanLevels.count).compactMap { level -> SokobanSavedGame? in
            guard let game = try? game(level: level),
                  SokobanResume.parse(game.raw)?.won == false else { return nil }
            return game
        }.max(by: { $0.sequence < $1.sequence })?.level
    }
    func best(level: Int) -> Int? {
        _ = revision // Observe successful writes without treating a disk read as a write.
        return (try? game(level: level))?.best
    }
    func historicalBest(level: Int) -> Int? {
        let key = "classicgames.best.sokoban.\(level)"
        guard legacyDefaults.object(forKey: key) != nil else { return nil }
        let score = legacyDefaults.integer(forKey: key)
        return score >= 0 ? score : nil
    }
    /// Current-identity verified completion only. Foreign, corrupt, or legacy defaults do not count.
    /// The title line reads this during layout, so it must not scan slots on every
    /// frame — that would consume injected read faults and stall the UI.
    func hasCurrentIdentityCompletion(level: Int) -> Bool {
        _ = revision
        indexCompletionsIfNeeded()
        return completedLevels.contains(level)
    }
    func isCampaignComplete() -> Bool {
        _ = revision
        indexCompletionsIfNeeded()
        return completedLevels.count == SokobanLevels.count
    }
    private func rememberCompletion(_ game: SokobanSavedGame) {
        if game.best != nil { completedLevels.insert(game.level) }
    }
    private func indexCompletionsIfNeeded() {
        guard !completionsIndexed else { return }
        completionsIndexed = true
        for level in 1...SokobanLevels.count {
            let game = pending[level] ?? known[level] ?? (try? load(level: level))
            if let game { rememberCompletion(game) }
        }
    }

    @discardableResult
    func save(level: Int, raw: String, eligible: Bool) -> Bool {
        guard let parsed = Self.validated(raw, level: level) else { states[level] = .failed; return false }
        do {
            let replacing = replacementRecords[level] != nil
            var previous = replacing ? nil : pending[level]
            var disk: SokobanSavedGame?
            var readFailure: Error?
            if !replacing {
                do { disk = try load(level: level) }
                catch {
                    readFailure = error
                    if case SokobanSaveError.readFailed = error,
                       previous == nil, let last = known[level],
                       last.formatVersion == 1, last.identity == Self.identity(level: level) {
                        previous = last
                    }
                }
            }
            sequence = max(sequence, max(previous?.sequence ?? 0, disk?.sequence ?? 0))
            guard sequence < UInt64.max else { throw SokobanSaveError.sequenceExhausted }
            sequence += 1
            var best = [previous?.best, disk?.best, replacementRecords[level]?.best].compactMap { $0 }.min()
            if eligible && parsed.won && parsed.counts { best = min(best ?? parsed.steps, parsed.steps) }
            let latest = SokobanSavedGame(formatVersion: 1, identity: Self.identity(level: level), level: level,
                sequence: sequence, raw: raw, eligible: eligible, best: best, legacyDigest: nil,
                recordRecoveryPending: (previous?.recordRecoveryPending == true || disk?.recordRecoveryPending == true || replacementRecords[level]?.unverified == true) ? true : nil)
            pending[level] = latest
            // Preserve the latest intent, but do not swallow an observed read
            // error and then report a later write as if that error never occurred.
            if let readFailure { throw readFailure }
            try commit(latest)
            pending[level] = nil; replacementRecords.removeValue(forKey: level); states[level] = .saved
            return true
        } catch { states[level] = .failed; return false }
    }
    @discardableResult
    func retry(level: Int) -> Bool {
        guard states[level] != .retrying, let latest = pending[level] else { return states[level] == .saved }
        states[level] = .retrying
        do {
            try commit(latest)
            pending[level] = nil; replacementRecords.removeValue(forKey: level); states[level] = .saved
            return true
        } catch { states[level] = .failed; return false }
    }
    /// Synchronous MainActor writes cannot finish out of order. The extra sequence
    /// check also rejects replayed snapshots and another coordinator's stale write.
    func commit(_ game: SokobanSavedGame) throws {
        guard game.formatVersion == 1, (1...SokobanLevels.count).contains(game.level),
              game.identity == Self.identity(level: game.level),
              Self.validated(game.raw, level: game.level) != nil else { throw SokobanSaveError.corrupt }
        let old = replacementRecords[game.level] != nil ? nil : try load(level: game.level)
        if let old, old.sequence >= game.sequence {
            // Idempotent success also refreshes the actual committed snapshot.
            guard old.sequence == game.sequence,
                  old.raw == game.raw, old.identity == game.identity, old.eligible == game.eligible,
                  old.best == game.best, old.legacyDigest == game.legacyDigest,
                  old.recordRecoveryPending == game.recordRecoveryPending else { throw SokobanSaveError.stale }
            known[game.level] = old
            sequence = max(sequence, old.sequence)
            rememberCompletion(old)
            return
        }
        // A retry may encounter a better, verified same-version disk record.
        // Sequence protects the board; best must independently remain monotonic.
        let best = [old?.best, game.best].compactMap { $0 }.min()
        let committed = SokobanSavedGame(formatVersion: game.formatVersion, identity: game.identity,
            level: game.level, sequence: game.sequence, raw: game.raw, eligible: game.eligible,
            best: best, legacyDigest: game.legacyDigest,
            recordRecoveryPending: (old?.recordRecoveryPending == true || game.recordRecoveryPending == true) ? true : nil)
        try storage.write(try JSONEncoder().encode(committed), forKey: Self.slotKey(level: game.level), ifAbsent: false)
        // Do not require a second read after successful storage acceptance.
        known[game.level] = committed
        rememberCompletion(committed)
        revision &+= 1
        sequence = max(sequence, committed.sequence)
        issues[game.level] = nil
    }
    /// Explicit restart only: retain incompatible/corrupt bytes before replacing.
    /// It never clears the legacy defaults or any other level's slot.
    func prepareRestart(level: Int) throws {
        let data: Data?
        do { data = try storage.data(forKey: Self.slotKey(level: level)) }
        catch { throw SokobanSaveError.readFailed(error) }
        guard let data else { return } // Truly missing, not a read error.
        do {
            let current = try decoded(data, level: level)
            known[level] = current
            sequence = max(sequence, current.sequence)
        } catch {
            // Only the SAME already-read bytes failed pure content validation.
            // Backup failure propagates before granting permission or clearing pending.
            try storage.write(data, forKey: "quarantine.slot.\(level)." + Self.digest(data), ifAbsent: true)
            // These are previously verified snapshots, NOT fields scavenged
            // from the bytes that just failed validation. Capture before clearing.
            let trusted = [known[level], pending[level]].compactMap { $0 }.filter { game in
                guard let encoded = try? JSONEncoder().encode(game) else { return false }
                return (try? decoded(encoded, level: level)) != nil
            }
            replacementRecords[level] = RestartRecord(
                best: (trusted.compactMap(\.best) + [replacementRecords[level]?.best].compactMap { $0 }).min(),
                unverified: trusted.isEmpty || trusted.contains { $0.recordRecoveryPending == true } || replacementRecords[level]?.unverified == true)
            pending[level] = nil
        }
    }
    private struct RestartRecord { let best: Int?; let unverified: Bool }
    @ObservationIgnored private var replacementRecords: [Int: RestartRecord] = [:]
    func hasUnverifiedPredecessor(level: Int) -> Bool {
        _ = revision
        return (pending[level] ?? known[level])?.recordRecoveryPending == true
    }
    #if DEBUG
    func testPending(level: Int) -> SokobanSavedGame? { pending[level] }
    #endif

    /// No shipped historical asset/source witness is bundled. Production calls
    /// without proof, preserving the entire nine-field archive pending recovery.
    /// A proof binds the EXACT archive digest to an externally established asset
    /// identity; synthetic tests supply one, geometry alone never creates one.
    @discardableResult
    func migrateLegacy(proof: SokobanLegacyProof? = nil) -> SokobanMigrationResult {
        guard let raw = legacyDefaults.string(forKey: "classicgames.sokoban.resume") else {
            migrationResult = .none; return .none
        }
        let hash = Self.digest(raw)
        do {
            try storage.write(Data(raw.utf8), forKey: "legacy.original." + hash, ifAbsent: true)
            let outcome: SokobanMigrationResult
            if let parsed = SokobanResume.parse(raw), let proof,
               proof.rawDigest == hash, proof.identity == Self.identity(level: parsed.level) {
                if Self.validated(raw, level: parsed.level) == nil { outcome = .invalid }
                else if parsed.won {
                    try storage.write(Data(raw.utf8), forKey: "legacy.completed." + hash, ifAbsent: true)
                    outcome = .legacyCompleted
                } else if let existing = try load(level: parsed.level) {
                    outcome = existing.legacyDigest == hash && existing.raw == raw ? .migrated : .existingSlotPreserved
                } else {
                    guard sequence < UInt64.max else { throw SokobanSaveError.sequenceExhausted }
                    sequence += 1
                    let game = SokobanSavedGame(formatVersion: 1, identity: proof.identity, level: parsed.level,
                        sequence: sequence, raw: raw, eligible: false, best: nil, legacyDigest: hash)
                    try commit(game)
                    outcome = .migrated
                }
            } else { outcome = .identityUnproven }
            try storage.write(try JSONEncoder().encode(outcome), forKey: "legacy.result." + hash, ifAbsent: false)
            migrationResult = outcome; return outcome
        } catch { migrationResult = .failed; return .failed }
    }
    func legacyCompletedRaw(digest: String) -> String? {
        guard let data = try? storage.data(forKey: "legacy.completed." + digest) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replay ALL undo/current/redo frames from the asset's initial state. Bounds,
    /// walls, duplicate boxes, overlap, steps, won flags and adjacent pushes must
    /// all agree. A single bad frame rejects the whole archive.
    static func validated(_ raw: String, level: Int) -> SokobanResume.Parsed? {
        guard (1...SokobanLevels.count).contains(level), let parsed = SokobanResume.parse(raw),
              parsed.level == level else { return nil }
        let board = SokobanLevel.parsed(level)
        let current = SokobanFrame(player: parsed.player, boxes: parsed.boxes, steps: parsed.steps,
            facing: parsed.facing, won: parsed.won, counts: parsed.counts)
        let all = parsed.undo + [current] + parsed.redo.reversed()
        func floor(_ point: GridPoint) -> Bool {
            point.row >= 0 && point.col >= 0 && point.row < board.rows && point.col < board.cols && !board.walls.contains(point)
        }
        guard parsed.steps == parsed.undo.count else { return nil }
        for (index, frame) in all.enumerated() {
            guard frame.steps == index, floor(frame.player), frame.boxes.count == board.boxes.count,
                  frame.boxes.allSatisfy(floor), !frame.boxes.contains(frame.player),
                  frame.won == (frame.boxes == board.targets), !frame.counts || frame.won else { return nil }
            if index == 0 {
                guard frame.player == board.player, frame.boxes == board.boxes,
                      frame.facing == .down, !frame.counts else { return nil }
            } else {
                let before = all[index - 1]
                guard !before.won, let direction = SokobanDirection.between(before.player, frame.player),
                      frame.facing == direction else { return nil }
                var expected = before.boxes
                if expected.contains(frame.player) {
                    let beyond = frame.player.moving(direction)
                    guard floor(beyond), !expected.contains(beyond) else { return nil }
                    expected.remove(frame.player); expected.insert(beyond)
                }
                guard frame.boxes == expected else { return nil }
            }
        }
        return parsed
    }
}

/// Production has no runtime override for the compile-time gate.
enum SokobanTestGate {
    static let environmentKey = "CLASSICGAMES_SOKOBAN_TEST_NAMESPACE"
    static func namespace(arguments: [String], environment: [String: String]) -> String? {
        #if DEBUG
        guard arguments.contains("-ui-testing"), let input = environment[environmentKey],
              input.hasPrefix("sokoban.ui."), input.count == 47,
              let id = UUID(uuidString: String(input.dropFirst(11))) else { return nil }
        return "sokoban.ui." + id.uuidString.lowercased()
        #else
        return nil
        #endif
    }
}

#if DEBUG
/// Test-only boundary around actual atomic files; no synthetic success or fake model.
@MainActor
final class SokobanFaultStorage: SokobanSaveStorage {
    enum Mode: String {
        case none, writes, reads, secondRead, backupWrites, slotWrites
        static let allCasesForUI: [Mode] = [.none, .writes, .reads, .secondRead, .backupWrites, .slotWrites]
    }
    let base: SokobanFileStorage
    var mode: Mode = .none { didSet { reads = 0 } }
    private var reads = 0
    init(base: SokobanFileStorage) { self.base = base }
    func data(forKey key: String) throws -> Data? {
        reads += 1
        if mode == .reads { throw CocoaError(.fileReadNoPermission) }
        if mode == .secondRead && reads == 2 {
            mode = .none
            throw CocoaError(.fileReadNoPermission)
        }
        return try base.data(forKey: key)
    }
    func write(_ data: Data, forKey key: String, ifAbsent: Bool) throws {
        if mode == .writes || (mode == .slotWrites && key.hasPrefix("slot.")) ||
            (mode == .backupWrites && (key.hasPrefix("quarantine.") || key.hasPrefix("legacy.original."))) {
            throw CocoaError(.fileWriteNoPermission)
        }
        try base.write(data, forKey: key, ifAbsent: ifAbsent)
    }
}

/// Created only after all three gates pass. Runtime input never supplies a path.
@MainActor
final class SokobanTestSession {
    static let active: SokobanTestSession? = {
        let process = ProcessInfo.processInfo
        guard let name = SokobanTestGate.namespace(arguments: process.arguments, environment: process.environment) else { return nil }
        return SokobanTestSession(namespace: name, arguments: process.arguments)
    }()
    let storage: SokobanFaultStorage
    // Bounded fault reproduces the observed UIKit relative-delta=1 boundary.
    let forceRelativeGestureReset: Bool
    let persistence: SokobanPersistence
    let defaults: UserDefaults
    private init(namespace: String, arguments: [String]) {
        forceRelativeGestureReset = arguments.contains("-sokoban-gesture-relative-reset")
        // `namespace` is a canonical fixed-length UUID value, never an arbitrary path.
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UITestSokoban", isDirectory: true).appendingPathComponent(namespace, isDirectory: true)
        storage = SokobanFaultStorage(base: SokobanFileStorage(directory: directory))
        defaults = UserDefaults(suiteName: "sokoban.synthetic.ui." + namespace)!
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        if let raw = value("-sokoban-resume"), raw.utf8.count <= 32768 {
            defaults.set(raw, forKey: "classicgames.sokoban.resume")
        }
        if value("-sokoban-fixture") == "layoutHistory66" {
            defaults.set(7, forKey: "classicgames.best.sokoban.66")
        }
        if value("-sokoban-fixture") == "history" {
            defaults.set(7, forKey: "classicgames.best.sokoban.1")
            defaults.set(700, forKey: "classicgames.best.snake")
        }
        persistence = SokobanPersistence(storage: storage, legacyDefaults: defaults)
        // Fixtures are explicit, gate-confined, and are ordinary validated envelopes.
        // Do not seed over an existing slot, including on same-case relaunch.
        if let fixture = value("-sokoban-fixture") {
            let level = fixture == "scoreOnly100" ? 100 : ((fixture == "level66" || fixture == "layoutHistory66") ? 66 : (fixture == "level99" ? 99 : 1))
            let key = SokobanPersistence.slotKey(level: level)
            if (try? storage.base.data(forKey: key)) == nil {
                if fixture == "level66" || fixture == "level99" || fixture == "layoutHistory66" {
                    if let raw = Self.fixtureRaw([], level: level) { persistence.save(level: level, raw: raw, eligible: true) }
                } else if fixture == "complete1" || fixture == "resume1" {
                    let steps = fixture == "complete1" ? SokobanSolutions.directions(level: 1)! : [.down, .right]
                    if let raw = Self.fixtureRaw(steps, level: 1) {
                        persistence.save(level: 1, raw: raw, eligible: true)
                    }
                } else if fixture == "scoreOnly1" || fixture == "scoreOnly100" {
                    let game = SokobanSavedGame(formatVersion: 1, identity: SokobanPersistence.identity(level: level),
                        level: level, sequence: 1, raw: "", eligible: false, best: 33, legacyDigest: nil, recordOnly: true)
                    if let data = try? JSONEncoder().encode(game) { try? storage.base.write(data, forKey: key, ifAbsent: true) }
                }
            }
        }
        if value("-sokoban-fixture") == "campaignReady" {
            try? writeScoreOnlyFixtures(levels: 2...SokobanLevels.count)
        }
        if value("-sokoban-fixture") == "clear100NotAll" {
            try? writeScoreOnlyFixtures(levels: 2...50)
            // Almost-won official path for level 100 (all but the last move).
            // The UI test plays that last step so the shot is the live 过关
            // celebration with other levels still unfinished, not a score-only revisit.
            if let steps = Self.directions(from: "左下下右下上左上上右下右右右下左下下下右右上上左右下下左左上上右右下左上上上左左左左下下右上下左下下右上上左上上右右右上右下下下左上下右右下下左左上上右右下左上上上左左左上左下下下右上左上右右右上右下下下左上右上左左左上左下下上右右右下下右右下下左左上上上右上左左左上左下右右右下下右右下左下左上上上右上左左"),
               let raw = Self.fixtureRaw(steps, level: 100) {
                persistence.save(level: 100, raw: raw, eligible: true)
            }
        }
        if let raw = value("-sokoban-fault"), let mode = SokobanFaultStorage.Mode(rawValue: raw) {
            storage.mode = mode
        }
    }

    private func writeScoreOnlyFixtures(levels: ClosedRange<Int>, best: Int = 20) throws {
        for level in levels {
            let key = SokobanPersistence.slotKey(level: level)
            if (try? storage.base.data(forKey: key)) != nil { continue }
            let game = SokobanSavedGame(formatVersion: 1, identity: SokobanPersistence.identity(level: level),
                level: level, sequence: UInt64(level), raw: "", eligible: true, best: best, legacyDigest: nil, recordOnly: true)
            if let data = try? JSONEncoder().encode(game) {
                try storage.base.write(data, forKey: key, ifAbsent: true)
            }
        }
    }

        private static func directions(from text: String) -> [SokobanDirection]? {
            var directions: [SokobanDirection] = []
            for character in text {
                switch character {
                case "上": directions.append(.up)
                case "下": directions.append(.down)
                case "左": directions.append(.left)
                case "右": directions.append(.right)
                default: return nil
                }
            }
            return directions
        }
        private static func fixtureRaw(_ directions: [SokobanDirection], level: Int) -> String? {
        let board = SokobanLevel.parsed(level)
        var player = board.player, boxes = board.boxes, facing = SokobanDirection.down
        var history: [SokobanFrame] = []
        for (i, direction) in directions.enumerated() {
            history.append(SokobanFrame(player: player, boxes: boxes, steps: i, facing: facing, won: false, counts: false))
            let next = player.moving(direction)
            if boxes.remove(next) != nil { boxes.insert(next.moving(direction)) }
            player = next; facing = direction
        }
        let raw = SokobanResume.encode(level: level, player: player, boxes: boxes, steps: directions.count,
            facing: facing, won: boxes == board.targets, counts: boxes == board.targets, undo: history, redo: [])
        return SokobanPersistence.validated(raw, level: level) == nil ? nil : raw
    }
    func corruptCurrentSlot(model: SokobanModel) {
        try? storage.base.write(Data("synthetic-corrupt-slot".utf8), forKey: SokobanPersistence.slotKey(level: model.levelNumber), ifAbsent: false)
        model.load(model.levelNumber)
    }
    static func diagnosticDigest(_ bytes: Data) -> String { SokobanPersistence.digest(bytes) }
    func diagnostic(model: SokobanModel) -> String {
        let level = model.levelNumber
        // Observe real files directly: diagnostics must not consume injected read faults.
        let bytes = try? storage.base.data(forKey: SokobanPersistence.slotKey(level: level))
        let disk = bytes.flatMap { try? JSONDecoder().decode(SokobanSavedGame.self, from: $0) }
        let diskFrame = disk.flatMap { SokobanResume.parse($0.raw) }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: storage.base.directory.path)) ?? []
        let backups = names.filter { $0.hasPrefix("quarantine.slot.\(level).") }
        let backupHash = backups.sorted().first.flatMap { try? storage.base.data(forKey: $0) }
            .map { Self.diagnosticDigest($0) } ?? "missing"
        let exactBackup = bytes.map { data in backups.contains { name in (try? storage.base.data(forKey: name)) == data } } ?? false
        let legacyRaw = defaults.string(forKey: "classicgames.sokoban.resume")
        let legacyRetained = legacyRaw.map { raw in (try? storage.base.data(forKey: "legacy.original." + SokobanPersistence.digest(raw))) == Data(raw.utf8) } ?? false
        let hash = bytes.map { Self.diagnosticDigest($0) } ?? "missing"
        let pending = persistence.testPending(level: level).flatMap { SokobanResume.parse($0.raw)?.steps }
        return "visit=\(model.visitKind.rawValue);events=\(model.completionEvents);save=\(model.saveState.map { String(describing: $0) } ?? "none");pending=\(pending.map(String.init) ?? "nil");diskSteps=\(diskFrame.map { String($0.steps) } ?? "nil");diskBest=\(disk?.best.map(String.init) ?? "nil");diskHash=\(hash);backups=\(backups.count);exactBackup=\(exactBackup);backupHash=\(backupHash);legacy=\(model.legacyMigration.rawValue);legacyRetained=\(legacyRetained);oldBest=\(model.historicalBest.map(String.init) ?? "nil");other=\(defaults.object(forKey: "classicgames.best.snake").map { String(describing: $0) } ?? "nil");board=\(model.hasBoard)"
    }
}
#endif
