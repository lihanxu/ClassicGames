import Foundation
import Observation

/// 扫雷的一格。雷的位置在第一次翻开之后才定。
struct MineCell: Equatable {
    var mine = false
    var open = false
    var flagged = false
    /// 周围八格的雷数。翻开后才显示。
    var adjacent = 0
}

/// 扫雷这一局。插旗、翻开和计时都在这里，不写最快纪录。
@MainActor
@Observable
final class MinesweeperModel {
    static let rows = 9
    static let columns = 9
    static let mineCount = 10

    private(set) var cells: [MineCell]
    private(set) var seconds = 0
    private(set) var flagging = false
    private(set) var won = false
    private(set) var lost = false
    /// 第一次翻开之后才开始计时，胜负后不再加。
    private var timing = false
    private var placed = false

    init() {
        cells = Array(repeating: MineCell(), count: Self.rows * Self.columns)
    }

    /// 失败或胜利时给出横幅。失败不把这一局标成可写入纪录的结束。
    var banner: String? {
        if won { return "胜利" }
        if lost { return "失败" }
        return nil
    }

    /// 给模拟器读的棋盘。未翻开的雷用 m，这样检查能避开或点中它；画面上仍是盖住的。
    var token: String {
        let status = won ? "won" : (lost ? "lost" : "play")
        let body = cells.map { cell in
            if cell.open {
                return cell.mine ? "*" : String(cell.adjacent)
            }
            if cell.flagged { return "F" }
            return cell.mine ? "m" : "#"
        }.joined(separator: ",")
        return "seconds:\(seconds);flagging:\(flagging);status:\(status);cells:\(body)"
    }

    /// 插旗开关。打开时点格子只插旗或取消旗，不翻开。
    func setFlagging(_ on: Bool) {
        guard !won, !lost else { return }
        flagging = on
    }

    /// 点一格。还没布雷时，这一格保证不是雷，然后再翻开。
    func tap(row: Int, column: Int) {
        guard !won, !lost else { return }
        guard let index = index(row: row, column: column) else { return }
        if flagging {
            guard !cells[index].open else { return }
            cells[index].flagged.toggle()
            return
        }
        guard !cells[index].flagged, !cells[index].open else { return }
        if !placed {
            placeMines(avoiding: index)
            placed = true
            timing = true
        }
        reveal(index)
    }

    /// 每秒调用一次。没翻开过，或已经胜负，都不加秒。
    func tick() {
        guard timing, !won, !lost else { return }
        seconds += 1
    }

    /// 棋盘重新盖上，秒数归零。最快纪录留在外框。
    func restart() {
        cells = Array(repeating: MineCell(), count: Self.rows * Self.columns)
        seconds = 0
        flagging = false
        won = false
        lost = false
        timing = false
        placed = false
    }

    /// 在点击格以外放 10 颗雷，并算好每格的数字。
    private func placeMines(avoiding safe: Int) {
        var spots = Array(cells.indices).filter { $0 != safe }
        spots.shuffle()
        for spot in spots.prefix(Self.mineCount) {
            cells[spot].mine = true
        }
        for index in cells.indices {
            cells[index].adjacent = neighbors(of: index).filter { cells[$0].mine }.count
        }
    }

    /// 翻开一格。点到雷就失败并亮出全部雷；翻开 0 时把相连的空地和外侧数字一起打开。
    private func reveal(_ start: Int) {
        if cells[start].mine {
            for index in cells.indices where cells[index].mine {
                cells[index].open = true
            }
            lost = true
            return
        }
        var pending = [start]
        while let current = pending.popLast() {
            if cells[current].open || cells[current].flagged || cells[current].mine { continue }
            cells[current].open = true
            if cells[current].adjacent == 0 {
                pending.append(contentsOf: neighbors(of: current))
            }
        }
        if cells.allSatisfy({ $0.mine || $0.open }) {
            won = true
        }
    }

    private func index(row: Int, column: Int) -> Int? {
        guard (0..<Self.rows).contains(row), (0..<Self.columns).contains(column) else { return nil }
        return row * Self.columns + column
    }

    private func neighbors(of index: Int) -> [Int] {
        let row = index / Self.columns
        let column = index % Self.columns
        var result: [Int] = []
        for rowOffset in -1...1 {
            for columnOffset in -1...1 where rowOffset != 0 || columnOffset != 0 {
                let nextRow = row + rowOffset
                let nextColumn = column + columnOffset
                if let next = self.index(row: nextRow, column: nextColumn) {
                    result.append(next)
                }
            }
        }
        return result
    }
}

extension GameID {
    /// 扫雷的登记标识。
    static let minesweeper = GameID(rawValue: "minesweeper")
}
