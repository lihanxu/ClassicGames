import SwiftUI
import UIKit

/// 应用入口。持有本机纪录，并把根导航交给 `RootView`。
@main
struct ClassicGamesApp: App {
    @State private var scores = ScoreStore()
    @State private var router = AppRouter()
    @State private var sokobanAudio = SokobanAudio()

    init() {
        // 模拟器检查关掉转场动画，避免进游戏前蛇已经撞墙。正式游玩没有这个参数。
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(scores)
                .environment(router)
                .environment(sokobanAudio)
        }
    }
}
