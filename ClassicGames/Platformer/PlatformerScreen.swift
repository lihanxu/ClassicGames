import SwiftUI
import SpriteKit
import UIKit

/// 把跑跳场景嵌进外框。左、右、跳都在场景里，这层只提供给模拟器读的状态。
struct PlatformerScreen: View {
    @State private var model = PlatformerModel()

    var body: some View {
        GameFrame(
            id: .platformer,
            title: "跑跳",
            score: model.score,
            scorePrefix: "本局",
            isOver: model.isOver,
            banner: model.banner,
            rule: .higherOnEnd,
            onRestart: model.restart
        ) {
            VStack(spacing: 0) {
                PlatformerProbe()
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(false)
                SpriteView(scene: model.scene, preferredFramesPerSecond: 60)
                    .accessibilityIdentifier("platformer.scene")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// 场景每帧写入的可读摘要。不进观测，避免角色一动界面就没空闲。
final class PlatformerProbeView: UIView {
    static weak var current: PlatformerProbeView?
    static var latest = "status:play"

    /// 换成最新摘要，模拟器下一拍就能读到。
    func show(_ token: String) {
        Self.latest = token
        accessibilityLabel = token
    }
}

/// 挂上探针视图，让场景有地方写摘要。
struct PlatformerProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> PlatformerProbeView {
        let view = PlatformerProbeView()
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "platformer.state"
        view.accessibilityLabel = PlatformerProbeView.latest
        view.backgroundColor = .clear
        PlatformerProbeView.current = view
        return view
    }

    func updateUIView(_ uiView: PlatformerProbeView, context: Context) {
        uiView.accessibilityIdentifier = "platformer.state"
        uiView.accessibilityLabel = PlatformerProbeView.latest
        PlatformerProbeView.current = uiView
    }
}
