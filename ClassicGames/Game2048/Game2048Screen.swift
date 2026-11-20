import SwiftUI

/// 2048 这一局。格子用 SwiftUI 画，不使用 SpriteKit。
struct Game2048Screen: View {
    @State private var model = Game2048Model()

    var body: some View {
        GameFrame(
            id: .game2048,
            title: "2048",
            score: model.score,
            scorePrefix: "本局",
            isOver: model.isOver,
            banner: model.banner,
            rule: .higherAsScoreGrows,
            onRestart: model.restart
        ) {
            VStack(spacing: 16) {
                Game2048Board(model: model)
                // 没有字的小热区，给模拟器把这一局按规则走到结束。平时画面上看不见。
                Color.clear
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture { model.playUntilStuck() }
                    .accessibilityIdentifier("game2048.finish")
                    .accessibilityLabel("走到结束")
                    .accessibilityAddTraits(.isButton)
                Game2048Pad { direction in
                    model.move(direction)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

/// 4×4 棋盘。同一块数字移动时会滑过去。
struct Game2048Board: View {
    var model: Game2048Model

    var body: some View {
        GeometryReader { geo in
            let side = max(0, min(geo.size.width, geo.size.height))
            let gap: CGFloat = 8
            let cell = max(0, (side - gap * 5) / 4)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Game2048Palette.board)
                    .frame(width: side, height: side)
                ForEach(0..<16, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Game2048Palette.empty)
                        .frame(width: cell, height: cell)
                        .offset(x: gap + CGFloat(index % 4) * (cell + gap), y: gap + CGFloat(index / 4) * (cell + gap))
                }
                ForEach(model.tiles) { tile in
                    Text("\(tile.value)")
                        .font(.title.bold())
                        .foregroundStyle(Game2048Palette.ink(for: tile.value))
                        .frame(width: cell, height: cell)
                        .background(Game2048Palette.fill(for: tile.value), in: RoundedRectangle(cornerRadius: 8))
                        .offset(
                            x: gap + CGFloat(tile.col) * (cell + gap),
                            y: gap + CGFloat(tile.row) * (cell + gap)
                        )
                }
            }
            .frame(width: side, height: side)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .animation(.easeInOut(duration: 0.12), value: model.tiles)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("game2048.board")
        .accessibilityLabel(model.token)
        .gesture(swipe)
    }

    /// 在棋盘上滑动一步，和方向按钮走同一个方法。
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { value in
            let dx = value.translation.width
            let dy = value.translation.height
            if abs(dx) > abs(dy) {
                model.move(dx > 0 ? .right : .left)
            } else {
                model.move(dy > 0 ? .down : .up)
            }
        }
    }
}

/// 棋盘下面的方向按钮。结束后再点也不会改棋盘。
struct Game2048Pad: View {
    var onMove: (Direction2048) -> Void

    var body: some View {
        VStack(spacing: 8) {
            key("上", "pad.up", .up)
            HStack(spacing: 8) {
                key("左", "pad.left", .left)
                key("下", "pad.down", .down)
                key("右", "pad.right", .right)
            }
        }
    }

    /// 一颗方向键。
    private func key(_ title: String, _ identifier: String, _ direction: Direction2048) -> some View {
        Button {
            onMove(direction)
        } label: {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(ShellPalette.ink)
                .frame(width: 76, height: 56)
                .background(ShellPalette.card, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// 2048 自己的格子颜色。
enum Game2048Palette {
    static let board = Color(red: 0.73, green: 0.68, blue: 0.63)
    static let empty = Color(red: 0.80, green: 0.76, blue: 0.71)

    /// 数字越大颜色越深，方便看出合成结果。
    static func fill(for value: Int) -> Color {
        switch value {
        case 2: return Color(red: 0.93, green: 0.89, blue: 0.85)
        case 4: return Color(red: 0.93, green: 0.88, blue: 0.78)
        case 8: return Color(red: 0.95, green: 0.69, blue: 0.47)
        case 16: return Color(red: 0.96, green: 0.58, blue: 0.39)
        case 32: return Color(red: 0.96, green: 0.49, blue: 0.37)
        case 64: return Color(red: 0.95, green: 0.37, blue: 0.23)
        case 128, 256, 512: return Color(red: 0.93, green: 0.81, blue: 0.45)
        default: return Color(red: 0.93, green: 0.76, blue: 0.32)
        }
    }

    /// 浅色格子用深字，深色格子用白字。
    static func ink(for value: Int) -> Color {
        value <= 4 ? Color(red: 0.36, green: 0.31, blue: 0.27) : .white
    }
}
