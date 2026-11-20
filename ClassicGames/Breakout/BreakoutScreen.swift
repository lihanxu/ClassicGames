import SwiftUI
import SpriteKit

/// 把打砖块场景嵌进外框。拖动留在场景里。
struct BreakoutScreen: View {
    @State private var model = BreakoutModel()

    var body: some View {
        GameFrame(
            id: .breakout,
            title: "打砖块",
            score: model.score,
            scorePrefix: "本局",
            isOver: model.isOver,
            banner: model.banner,
            rule: .higherOnEnd,
            onRestart: model.restart
        ) {
            VStack(spacing: 8) {
                Text("命 \(model.lives)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(ShellPalette.ink)
                    .accessibilityIdentifier("breakout.state")
                    .accessibilityLabel(model.token)
                SpriteView(scene: model.scene, preferredFramesPerSecond: 60)
                    .accessibilityIdentifier("breakout.scene")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}
