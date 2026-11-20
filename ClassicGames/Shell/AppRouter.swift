import Foundation
import Observation

/// 根导航路径。首页推进游戏标识，返回弹出；重新开始不动路径。
@MainActor
@Observable
final class AppRouter {
    var path: [GameID] = []

    /// 回到首页。没有上一层时不做任何事。
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
}
