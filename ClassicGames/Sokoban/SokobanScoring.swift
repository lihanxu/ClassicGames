import Foundation

/// v4.0 三星阈值与得分。核心进度与发奖以星档为准，得分只用于结算展示。
enum SokobanScoring {
    struct Thresholds: Equatable, Sendable {
        let par: Int
        /// 三星上限（含）：`max(ceil(par * 1.15), par + 2)`
        let t3: Int
        /// 二星上限（含）：`max(ceil(par * 1.50), t3 + 3)`
        let t2: Int
        /// 一星插值下限：与二星带宽相同，`t2 + (t2 - t3)`。超出后得分保底 50。
        /// PRD 对 1★ 只规定 50–69 且「超出越多越接近 50」，该跨度使规则稳定可测。
        let t1: Int
    }

    static func thresholds(parSteps: Int) -> Thresholds {
        let par = max(0, parSteps)
        let t3 = max(Int(ceil(Double(par) * 1.15)), par + 2)
        let t2 = max(Int(ceil(Double(par) * 1.50)), t3 + 3)
        let t1 = t2 + (t2 - t3)
        return Thresholds(par: par, t3: t3, t2: t2, t1: t1)
    }

    /// 1...3。`parSteps` 必须 > 0；若缺省，按 1 星处理以免误发三星奖。
    static func stars(steps: Int, parSteps: Int) -> Int {
        let t = thresholds(parSteps: parSteps)
        if steps <= t.t3 { return 3 }
        if steps <= t.t2 { return 2 }
        return 1
    }

    /// 50...100 整数。
    static func score(steps: Int, parSteps: Int) -> Int {
        let t = thresholds(parSteps: parSteps)
        if steps <= t.par { return 100 }
        if steps <= t.t3 {
            return interpolate(steps, from: t.par + 1, to: t.t3, start: 99, end: 90)
        }
        if steps <= t.t2 {
            return interpolate(steps, from: t.t3 + 1, to: t.t2, start: 89, end: 70)
        }
        if steps <= t.t1 {
            return interpolate(steps, from: t.t2 + 1, to: t.t1, start: 69, end: 50)
        }
        return 50
    }

    static func title(stars: Int) -> String {
        switch stars {
        case 3: return "完美通关"
        case 2: return "出色通关"
        default: return "顺利过关"
        }
    }

    private static func interpolate(_ value: Int, from: Int, to: Int, start: Int, end: Int) -> Int {
        if to <= from { return end }
        let t = Double(value - from) / Double(to - from)
        let clamped = min(max(t, 0), 1)
        return Int((Double(start) + (Double(end - start) * clamped)).rounded())
    }
}

enum SokobanShopItem: String, CaseIterable, Sendable {
    case undo1
    case undo5
    case hint1
    case hint3

    var coinCost: Int {
        switch self {
        case .undo1: return 15
        case .undo5: return 60
        case .hint1: return 50
        case .hint3: return 130
        }
    }

    var undoDelta: Int {
        switch self {
        case .undo1: return 1
        case .undo5: return 5
        default: return 0
        }
    }

    var hintDelta: Int {
        switch self {
        case .hint1: return 1
        case .hint3: return 3
        default: return 0
        }
    }

    var title: String {
        switch self {
        case .undo1: return "撤销券 ×1"
        case .undo5: return "撤销券 ×5"
        case .hint1: return "提示道具 ×1"
        case .hint3: return "提示道具 ×3"
        }
    }

    var isBundle: Bool {
        self == .undo5 || self == .hint3
    }
}

enum SokobanRewards {
    /// 该星档的累计应得总奖励。
    static func cumulative(stars: Int) -> (coins: Int, undo: Int, hint: Int) {
        switch stars {
        case 3: return (80, 2, 1)
        case 2: return (40, 2, 0)
        case 1: return (20, 1, 0)
        default: return (0, 0, 0)
        }
    }

    /// 本次星级相对已领星档的实发差额；不升星则固定 +5 金币。
    static func payout(thisStars: Int, claimedTier: Int) -> SokobanPayout {
        let earned = max(0, min(3, thisStars))
        let claimed = max(0, min(3, claimedTier))
        if earned <= claimed {
            return SokobanPayout(coins: 5, undo: 0, hint: 0, isRepeat: true, claimedBefore: claimed, claimedAfter: claimed, stars: earned)
        }
        let fresh = cumulative(stars: earned)
        let already = cumulative(stars: claimed)
        return SokobanPayout(
            coins: fresh.coins - already.coins,
            undo: fresh.undo - already.undo,
            hint: fresh.hint - already.hint,
            isRepeat: false,
            claimedBefore: claimed,
            claimedAfter: earned,
            stars: earned
        )
    }
}

struct SokobanPayout: Equatable, Sendable {
    var coins: Int
    var undo: Int
    var hint: Int
    var isRepeat: Bool
    var claimedBefore: Int
    var claimedAfter: Int
    var stars: Int
}

struct SokobanSettlement: Equatable, Sendable {
    var level: Int
    var steps: Int
    var parSteps: Int
    var stars: Int
    var score: Int
    var title: String
    var payout: SokobanPayout
    var counts: Bool
}

struct SokobanWallet: Codable, Equatable, Sendable {
    var formatVersion: Int
    var coins: Int
    var undoItemCount: Int
    var hintItemCount: Int
    /// 关卡号字符串 -> 已领星档（0–3）。bestStars 由 bestSteps + 新阈值推导，不单独存。
    var claimedStarTier: [String: Int]

    static let initialCoins = 50
    static let initialUndo = 5
    static let initialHint = 2
    static let format = 1

    static var fresh: SokobanWallet {
        SokobanWallet(
            formatVersion: format,
            coins: initialCoins,
            undoItemCount: initialUndo,
            hintItemCount: initialHint,
            claimedStarTier: [:]
        )
    }

    func claimed(level: Int) -> Int {
        claimedStarTier[String(level)] ?? 0
    }

    mutating func setClaimed(level: Int, tier: Int) {
        claimedStarTier[String(level)] = max(0, min(3, tier))
    }
}
