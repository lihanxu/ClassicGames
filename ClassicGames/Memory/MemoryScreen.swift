import SwiftUI

/// 翻牌记忆这一局。4×4 的牌用纯色几何形，不使用 SpriteKit。
struct MemoryScreen: View {
    @State private var model = MemoryModel()

    var body: some View {
        GameFrame(
            id: .memory,
            title: "翻牌记忆",
            score: model.moves,
            scorePrefix: "次数",
            isOver: model.isOver,
            banner: model.banner,
            rule: .lowerOnClear,
            onRestart: model.restart
        ) {
            VStack(spacing: 8) {
                MemoryBoard(model: model)
                Text(verbatim: model.token)
                    .font(.system(size: 1))
                    .foregroundStyle(ShellPalette.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
                    .accessibilityIdentifier("memory.state")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

/// 十六张牌。背面朝上，点一下翻开。
struct MemoryBoard: View {
    var model: MemoryModel

    var body: some View {
        GeometryReader { geo in
            let side = max(0, min(geo.size.width, geo.size.height))
            let cell = side / 4
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { column in
                            let index = row * 4 + column
                            cardButton(model.cards[index])
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

    /// 一张牌。没配对时背面是纯色，翻开后画出对应图形。
    private func cardButton(_ card: MemoryCard) -> some View {
        Button {
            model.tap(card.id)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(card.faceUp ? MemoryPalette.face : MemoryPalette.back)
                    .padding(4)
                if card.faceUp {
                    MemoryGlyph(kind: card.kind)
                        .padding(16)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card.\(card.id)")
    }
}

/// 八种互不相同的纯色几何形。
struct MemoryGlyph: View {
    let kind: Int

    var body: some View {
        let color = MemoryPalette.color(for: kind)
        switch kind {
        case 0:
            Circle().fill(color)
        case 1:
            RoundedRectangle(cornerRadius: 8).fill(color)
        case 2:
            MemoryDiamond().fill(color)
        case 3:
            MemoryTriangle().fill(color)
        case 4:
            Capsule().fill(color)
        case 5:
            Ellipse().fill(color).padding(.horizontal, 2)
        case 6:
            MemoryPlus().fill(color)
        default:
            Circle().strokeBorder(color, lineWidth: 8)
        }
    }
}

/// 菱形。
struct MemoryDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// 三角形。
struct MemoryTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 十字。
struct MemoryPlus: Shape {
    func path(in rect: CGRect) -> Path {
        let thickness = min(rect.width, rect.height) * 0.34
        var path = Path()
        path.addRect(CGRect(x: rect.midX - thickness / 2, y: rect.minY, width: thickness, height: rect.height))
        path.addRect(CGRect(x: rect.minX, y: rect.midY - thickness / 2, width: rect.width, height: thickness))
        return path
    }
}

/// 翻牌记忆自己的颜色。
enum MemoryPalette {
    static let back = Color(red: 0.35, green: 0.48, blue: 0.62)
    static let face = Color(red: 0.98, green: 0.96, blue: 0.92)

    /// 每种图案一种颜色，避免只靠形状才能分辨。
    static func color(for kind: Int) -> Color {
        switch kind {
        case 0: return Color(red: 0.85, green: 0.28, blue: 0.24)
        case 1: return Color(red: 0.20, green: 0.45, blue: 0.78)
        case 2: return Color(red: 0.18, green: 0.58, blue: 0.36)
        case 3: return Color(red: 0.90, green: 0.58, blue: 0.16)
        case 4: return Color(red: 0.55, green: 0.28, blue: 0.68)
        case 5: return Color(red: 0.15, green: 0.55, blue: 0.58)
        case 6: return Color(red: 0.75, green: 0.32, blue: 0.48)
        default: return Color(red: 0.40, green: 0.36, blue: 0.28)
        }
    }
}
