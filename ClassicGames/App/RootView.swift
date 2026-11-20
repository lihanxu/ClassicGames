import SwiftUI

/// 根导航。路径里只放游戏标识，返回时弹出，重新开始不改路径。
struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: GameID.self) { id in
                    GameDestination(id: id)
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
