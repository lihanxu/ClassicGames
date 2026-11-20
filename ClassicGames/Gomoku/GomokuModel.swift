import Foundation
import Observation

/// 五子棋的一颗子。空位还能再下。
enum GomokuStone: Equatable {
    case empty
    case black
    case white
}

/// 五子棋这一局。落子和五连判断都在这里，不写胜场。
@MainActor
@Observable
final class GomokuModel {
    static let size = 15

    private(set) var stones: [GomokuStone]
    private(set) var blackTurn = true
    private(set) var winner: GomokuStone = .empty
    private(set) var draw = false

    init() {
        stones = Array(repeating: .empty, count: Self.size * Self.size)
    }

    /// 棋盘已经锁住：有人连成五子，或格子下满。
    var locked: Bool {
        winner != .empty || draw
    }

    /// 顶栏显示进行中、黑胜、白胜或平局。
    var statusText: String {
        if winner == .black { return "黑胜" }
        if winner == .white { return "白胜" }
        if draw { return "平局" }
        return "进行中"
    }

    /// 结束时的横幅。平局不加胜场，横幅仍然出现。
    var banner: String? {
        locked ? statusText : nil
    }

    /// 外框用来加胜场。平局和进行中都不加。
    var outcome: MatchOutcome {
        switch winner {
        case .black: return .black
        case .white: return .white
        case .empty: return draw ? .draw : .none
        }
    }

    /// 给模拟器读的棋盘。点是空位，B 是黑，W 是白。
    var token: String {
        let turn = blackTurn ? "black" : "white"
        let result = winner == .black ? "black" : (winner == .white ? "white" : (draw ? "draw" : "none"))
        let body = stones.map { stone in
            switch stone {
            case .empty: return "."
            case .black: return "B"
            case .white: return "W"
            }
        }.joined()
        return "turn:\(turn);winner:\(result);cells:\(body)"
    }

    /// 在空位落一子。已有子的位置再点无效，仍轮到当前一方。
    func tap(row: Int, column: Int) {
        guard !locked else { return }
        guard let index = index(row: row, column: column), stones[index] == .empty else { return }
        let stone: GomokuStone = blackTurn ? .black : .white
        stones[index] = stone
        if hasFive(row: row, column: column, stone: stone) {
            winner = stone
            return
        }
        if stones.allSatisfy({ $0 != .empty }) {
            draw = true
            return
        }
        blackTurn.toggle()
    }

    /// 清空棋盘，仍由黑先。胜场留在外框。
    func restart() {
        stones = Array(repeating: .empty, count: Self.size * Self.size)
        blackTurn = true
        winner = .empty
        draw = false
    }

    /// 从刚落下的子向四个方向数，连成五子或更长即胜。
    private func hasFive(row: Int, column: Int, stone: GomokuStone) -> Bool {
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for (rowStep, columnStep) in directions {
            let count = 1
                + run(row, column, rowStep, columnStep, stone)
                + run(row, column, -rowStep, -columnStep, stone)
            if count >= 5 { return true }
        }
        return false
    }

    /// 沿一个方向数连续的同色子，不含起点。
    private func run(_ row: Int, _ column: Int, _ rowStep: Int, _ columnStep: Int, _ stone: GomokuStone) -> Int {
        var count = 0
        var nextRow = row + rowStep
        var nextColumn = column + columnStep
        while let index = index(row: nextRow, column: nextColumn), stones[index] == stone {
            count += 1
            nextRow += rowStep
            nextColumn += columnStep
        }
        return count
    }

    private func index(row: Int, column: Int) -> Int? {
        guard (0..<Self.size).contains(row), (0..<Self.size).contains(column) else { return nil }
        return row * Self.size + column
    }
}

extension GameID {
    /// 五子棋的登记标识。
    static let gomoku = GameID(rawValue: "gomoku")
}
