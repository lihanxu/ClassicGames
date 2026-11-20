import SwiftUI
import SpriteKit

/// 把贪吃蛇场景嵌进外框。转向按钮在场景里面，不在这层处理。
struct SnakeScreen: View {
    @State private var model = SnakeModel()

    var body: some View {
        GameFrame(
            id: .snake,
            title: "贪吃蛇",
            score: model.score,
            scorePrefix: "本局",
            isOver: model.isOver,
            banner: model.banner,
            rule: .higherOnEnd,
            onRestart: model.restart
        ) {
            VStack(spacing: 8) {
                Text("长度 \(model.length)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(ShellPalette.ink)
                    .accessibilityIdentifier("snake.state")
                    .accessibilityLabel(model.token)
                SpriteView(scene: model.scene, preferredFramesPerSecond: 60)
                    .accessibilityIdentifier("snake.scene")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}
