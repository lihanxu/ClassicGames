import SwiftUI

/// 扫雷这一局。格子和插旗开关都在外框下面，秒数每秒加一。
struct MinesweeperScreen: View {
    @State private var model = MinesweeperModel()

    var body: some View {
        GameFrame(
            id: .minesweeper,
            title: "扫雷",
            score: model.seconds,
            scorePrefix: "秒数",
            isOver: model.won,
            banner: model.banner,
            rule: .lowerOnClear,
            onRestart: model.restart
        ) {
            VStack(spacing: 12) {
                MinesweeperBoard(model: model)
                Button {
                    model.setFlagging(!model.flagging)
                } label: {
                    HStack {
                        Text(model.flagging ? "插旗开" : "插旗关")
                            .foregroundStyle(ShellPalette.ink)
                        Spacer()
                        Circle()
                            .fill(model.flagging ? ShellPalette.accent : ShellPalette.ink.opacity(0.25))
                            .frame(width: 22, height: 22)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(ShellPalette.card, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("minesweeper.flag")
                Color.clear
                    .frame(width: 4, height: 4)
                    .accessibilityIdentifier("minesweeper.state")
                    .accessibilityLabel(model.token)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .task {
            // 胜负后 tick 自己会停。这里只负责每秒叫一次。
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                model.tick()
            }
        }
    }
}

/// 9×9 棋盘。每一格都能点，盖住、数字、旗和雷分开画。
struct MinesweeperBoard: View {
    var model: MinesweeperModel

    var body: some View {
        GeometryReader { geo in
            let side = max(0, min(geo.size.width, geo.size.height))
            let cell = side / CGFloat(MinesweeperModel.columns)
            VStack(spacing: 0) {
                ForEach(0..<MinesweeperModel.rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<MinesweeperModel.columns, id: \.self) { column in
                            cellButton(row: row, column: column)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// 一格按钮。插旗或翻开都进模型的同一次点击。
    private func cellButton(row: Int, column: Int) -> some View {
        let cell = model.cells[row * MinesweeperModel.columns + column]
        return Button {
            model.tap(row: row, column: column)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(fill(for: cell))
                    .padding(1)
                if cell.open, cell.mine {
                    Circle()
                        .fill(MinesweeperPalette.mine)
                        .padding(cell.flagged ? 10 : 8)
                } else if cell.flagged {
                    MineFlag()
                        .fill(MinesweeperPalette.flag)
                        .padding(7)
                } else if cell.open, cell.adjacent > 0 {
                    Text("\(cell.adjacent)")
                        .font(.caption.bold())
                        .foregroundStyle(MinesweeperPalette.number(cell.adjacent))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mine.\(row).\(column)")
    }

    /// 盖住的格子浅一点，翻开的格子沉下去。
    private func fill(for cell: MineCell) -> Color {
        if cell.open, cell.mine { return MinesweeperPalette.exploded }
        return cell.open ? MinesweeperPalette.open : MinesweeperPalette.covered
    }
}

/// 小三角旗，用来标出插上的旗。
struct MineFlag: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 扫雷自己的格子颜色。
enum MinesweeperPalette {
    static let covered = Color(red: 0.55, green: 0.70, blue: 0.55)
    static let open = Color(red: 0.86, green: 0.84, blue: 0.76)
    static let exploded = Color(red: 0.86, green: 0.35, blue: 0.28)
    static let mine = Color(red: 0.15, green: 0.14, blue: 0.13)
    static let flag = Color(red: 0.78, green: 0.22, blue: 0.18)

    /// 数字颜色按周围雷数区分，方便一眼看出。
    static func number(_ value: Int) -> Color {
        switch value {
        case 1: return Color(red: 0.20, green: 0.40, blue: 0.75)
        case 2: return Color(red: 0.22, green: 0.50, blue: 0.28)
        case 3: return Color(red: 0.75, green: 0.22, blue: 0.20)
        default: return Color(red: 0.40, green: 0.22, blue: 0.55)
        }
    }
}
