import Foundation
import Observation

/// 跑跳这一局给外框看的状态。场景负责跑、跳和碰撞，这里不读 UserDefaults。
@MainActor
@Observable
final class PlatformerModel {
    private(set) var score = 0
    private(set) var bonus = 0
    private(set) var isOver = false
    private(set) var failed = false
    private(set) var banner: String?

    let scene: PlatformerScene

    init() {
        let scene = PlatformerScene()
        self.scene = scene
        scene.start(model: self)
    }

    /// 失败或过关后不再接受操作。失败不把 isOver 设上，避免外框写成最高纪录。
    var locked: Bool { failed || isOver }

    /// 从下方顶掉一块砖，本局加 1。
    func brokeBrick() {
        guard !locked else { return }
        score += 1
    }

    /// 从上方踩掉敌人，本局加 1。
    func stompedEnemy() {
        guard !locked else { return }
        score += 1
    }

    /// 侧面碰到敌人或掉进坑。只结束这一局，不写最高纪录。
    func didFail() {
        guard !locked else { return }
        failed = true
        banner = "失败"
    }

    /// 走到终点。先加上额外的 5 分，再标记过关，外框这时才比较最高纪录。
    func didReachGoal() {
        guard !locked else { return }
        score += 5
        bonus = 5
        isOver = true
        banner = "过关"
    }

    /// 拆掉这一局的进度。最高纪录留在外框。
    func restart() {
        score = 0
        bonus = 0
        isOver = false
        failed = false
        banner = nil
        scene.resetGame()
    }
}

extension GameID {
    /// 跑跳的登记标识。
    static let platformer = GameID(rawValue: "platformer")
}
