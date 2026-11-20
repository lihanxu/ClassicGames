import SwiftUI

/// 五子棋这一局。15×15 个交叉点，黑先，两名玩家同一台设备轮流点。
struct GomokuScreen: View {
    @State private var model = GomokuModel()

    var body: some View {
        GameFrame(
            id: .gomoku,
            title: "五子棋",
            score: 0,
            scorePrefix: "",
            isOver: model.locked,
            banner: model.banner,
            rule: .matchWins,
            statusText: model.statusText,
            outcome: model.outcome,
            onRestart: model.restart
        ) {
            VStack(spacing: 8) {
                GomokuBoard(model: model)
                Text(verbatim: model.token)
                    .font(.system(size: 1))
                    .foregroundStyle(ShellPalette.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
                    .accessibilityIdentifier("gomoku.state")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}

/// 棋盘线穿过每一颗可以落子的点。
struct GomokuBoard: View {
    var model: GomokuModel

    var body: some View {
        GeometryReader { geo in
            let side = max(0, min(geo.size.width, geo.size.height))
            let cell = side / CGFloat(GomokuModel.size)
            VStack(spacing: 0) {
                ForEach(0..<GomokuModel.size, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<GomokuModel.size, id: \.self) { column in
                            pointButton(row: row, column: column)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(GomokuPalette.board)
                    Canvas { context, size in
                        let step = size.width / CGFloat(GomokuModel.size)
                        for index in 0..<GomokuModel.size {
                            let offset = step * (CGFloat(index) + 0.5)
                            var row = Path()
                            row.move(to: CGPoint(x: step / 2, y: offset))
                            row.addLine(to: CGPoint(x: size.width - step / 2, y: offset))
                            context.stroke(row, with: .color(GomokuPalette.line), lineWidth: 1)
                            var column = Path()
                            column.move(to: CGPoint(x: offset, y: step / 2))
                            column.addLine(to: CGPoint(x: offset, y: size.height - step / 2))
                            context.stroke(column, with: .color(GomokuPalette.line), lineWidth: 1)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// 一个交叉点。空位点下去，已有子再点不会换手。
    private func pointButton(row: Int, column: Int) -> some View {
        let stone = model.stones[row * GomokuModel.size + column]
        return Button {
            model.tap(row: row, column: column)
        } label: {
            ZStack {
                Rectangle().fill(Color.white.opacity(0.001))
                if stone != .empty {
                    Circle()
                        .fill(stone == .black ? GomokuPalette.black : GomokuPalette.white)
                        .padding(3)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("point.\(row).\(column)")
    }
}

/// 五子棋自己的棋盘颜色。
enum GomokuPalette {
    static let board = Color(red: 0.86, green: 0.72, blue: 0.48)
    static let line = Color(red: 0.35, green: 0.24, blue: 0.12)
    static let black = Color(red: 0.12, green: 0.11, blue: 0.10)
    static let white = Color(red: 0.96, green: 0.95, blue: 0.92)
}
