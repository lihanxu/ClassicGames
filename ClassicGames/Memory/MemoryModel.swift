import Foundation
import Observation

/// 翻牌记忆的一张牌。同一种图案有两张。
struct MemoryCard: Identifiable, Equatable {
    let id: Int
    let kind: Int
    var faceUp = false
    var matched = false
}

/// 翻牌记忆这一局。配对和次数都在这里，不写最少次数。
@MainActor
@Observable
final class MemoryModel {
    private(set) var cards: [MemoryCard] = []
    private(set) var moves = 0
    private(set) var isOver = false
    /// 两张不同图案还没翻回去时，不再接受新的点击。
    private(set) var resolving = false
    private var firstIndex: Int?
    private var flipTask: Task<Void, Never>?
    private var generation = 0

    init() {
        deal()
    }

    /// 八对都打开后显示「结束」。
    var banner: String? {
        isOver ? "结束" : nil
    }

    /// 给模拟器读的牌面。图案编号一直公开，画面上没翻开的仍是背面。
    var token: String {
        let kinds = cards.map { String($0.kind) }.joined(separator: ",")
        let up = cards.indices.filter { cards[$0].faceUp }.map(String.init).joined(separator: ",")
        return "moves:\(moves);over:\(isOver);resolving:\(resolving);up:\(up);kinds:\(kinds)"
    }

    /// 翻开一张。第二张计一次；图案不同则大约 0.6 秒后翻回。
    func tap(_ index: Int) {
        guard !isOver, !resolving else { return }
        guard cards.indices.contains(index), !cards[index].faceUp else { return }
        cards[index].faceUp = true
        guard let first = firstIndex else {
            firstIndex = index
            return
        }
        firstIndex = nil
        moves += 1
        if cards[first].kind == cards[index].kind {
            cards[first].matched = true
            cards[index].matched = true
            if cards.allSatisfy(\.matched) {
                isOver = true
            }
            return
        }
        resolving = true
        let ticket = generation
        flipTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, ticket == generation else { return }
            cards[first].faceUp = false
            cards[index].faceUp = false
            resolving = false
        }
    }

    /// 重新洗牌并盖上。最少次数留在外框。
    func restart() {
        generation += 1
        flipTask?.cancel()
        flipTask = nil
        resolving = false
        firstIndex = nil
        moves = 0
        isOver = false
        deal()
    }

    /// 八种图案各两张，打乱后背面朝上。
    private func deal() {
        var kinds = Array(0..<8) + Array(0..<8)
        kinds.shuffle()
        cards = kinds.enumerated().map { MemoryCard(id: $0.offset, kind: $0.element) }
    }
}

extension GameID {
    /// 翻牌记忆的登记标识。
    static let memory = GameID(rawValue: "memory")
}
