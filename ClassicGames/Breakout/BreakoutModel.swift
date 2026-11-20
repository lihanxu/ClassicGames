import Foundation
import Observation

/// 打砖块这一局给外框看的状态。场景负责球和挡板，这里不读 UserDefaults。
@MainActor
@Observable
final class BreakoutModel {
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var isOver = false
    private(set) var banner: String?
    private(set) var launched = false
    private(set) var ballX = 0.5
    private(set) var ballY = 0.12
    private(set) var paddleX = 0.5
    private(set) var paddleY = 0.12
    private(set) var bricks = 32

    let scene: BreakoutScene

    init() {
        let scene = BreakoutScene()
        self.scene = scene
        scene.start(model: self)
    }

    /// 打掉一块砖，本局加 1。
    func brickDestroyed() {
        guard !isOver else { return }
        score += 1
    }

    /// 球落到挡板下。还有命就减一条，没命就结束。
    func lifeLost() {
        guard !isOver else { return }
        lives = max(lives - 1, 0)
        if lives == 0 {
            isOver = true
            banner = "结束"
        }
    }

    /// 砖全部打完。这条和命用完都会结束一局。
    func cleared() {
        guard !isOver else { return }
        isOver = true
        banner = "清台"
    }

    /// 场景同步球、挡板和还剩多少砖，供界面和模拟器检查读取。
    func publish(launched: Bool, ballX: Double, ballY: Double, paddleX: Double, paddleY: Double, bricks: Int) {
        self.launched = launched
        self.ballX = ballX
        self.ballY = ballY
        self.paddleX = paddleX
        self.paddleY = paddleY
        self.bricks = bricks
    }

    /// 砖和 3 条命都回来，本局分数归零。最高纪录留在外框。
    func restart() {
        score = 0
        lives = 3
        isOver = false
        banner = nil
        launched = false
        bricks = 32
        scene.resetGame()
    }

    /// 模拟器检查用来读命、球和砖。
    var token: String {
        let launchedText = launched ? "true" : "false"
        let overText = isOver ? "true" : "false"
        return "score:\(score);lives:\(lives);launched:\(launchedText);bricks:\(bricks);ball:\(ballX),\(ballY);paddle:\(paddleX),\(paddleY);over:\(overText)"
    }
}

extension GameID {
    /// 打砖块的登记标识。
    static let breakout = GameID(rawValue: "breakout")
}
