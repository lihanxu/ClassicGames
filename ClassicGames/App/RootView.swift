import SwiftUI

/// 根导航。路径里只放游戏标识，返回时弹出，重新开始不改路径。
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SokobanAudio.self) private var audio

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: GameID.self) { id in
                    GameDestination(id: id)
                }
        }
        .background(alignment: .top) {
            Text(verbatim: audio.token)
                .font(.system(size: 1))
                .foregroundStyle(ShellPalette.ink.opacity(0.02))
                .accessibilityIdentifier("sokoban.audio")
                .accessibilityLabel(audio.token)
                .accessibilityValue(audio.token)
                .allowsHitTesting(false)
        }
        .onChange(of: router.path) { _, path in
            // 只有路径停在推箱子才循环。回首页或其他游戏都停。
            if path.last == .sokoban {
                audio.enter()
            } else {
                audio.leave()
            }
        }
    }
}

/// 按标识挂上对应的一局。登记为空时不会从首页进来。
struct GameDestination: View {
    let id: GameID

    var body: some View {
        if id == .sokoban {
            SokobanScreen()
        } else if id == .snake {
            SnakeScreen()
        } else if id == .breakout {
            BreakoutScreen()
        } else if id == .game2048 {
            Game2048Screen()
        } else if id == .minesweeper {
            MinesweeperScreen()
        } else if id == .memory {
            MemoryScreen()
        } else if id == .gomoku {
            GomokuScreen()
        } else if id == .platformer {
            PlatformerScreen()
        } else {
            EmptyView()
        }
    }
}
