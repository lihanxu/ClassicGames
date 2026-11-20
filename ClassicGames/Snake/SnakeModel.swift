import Foundation
import Observation
import SpriteKit

/// 贪吃蛇这一局给外框看的状态。场景负责走动，这里不读 UserDefaults。
@MainActor
@Observable
final class SnakeModel {
    private(set) var score = 0
    private(set) var length = 3
    private(set) var isOver = false
    private(set) var banner: String?
    /// 当前朝向，给界面和模拟器检查看。
    private(set) var directionName = "right"
    private(set) var headText = "8,8"
    private(set) var foodText = ""
    private(set) var note = ""

    let scene: SnakeScene

    init() {
        let scene = SnakeScene()
        self.scene = scene
        scene.start(model: self)
    }

    /// 场景吃到食物时加一分，并同步长度。
    func didEat(length: Int) {
        guard !isOver else { return }
        score += 1
        self.length = length
    }

    /// 撞墙或撞到自己。外框看到结束后才写最高纪录。
    func didDie(note: String) {
        guard !isOver else { return }
        isOver = true
        banner = "死亡"
        self.note = note
    }

    /// 场景每个节拍刷新朝向、蛇头、食物和长度。
    func publish(direction: String, head: String, food: String, length: Int) {
        directionName = direction
        headText = head
        foodText = food
        self.length = length
    }

    /// 长度回到 3，本局回到 0。最高纪录留在外框。
    func restart() {
        score = 0
        length = 3
        isOver = false
        banner = nil
        directionName = "right"
        headText = "8,8"
        foodText = ""
        note = ""
        scene.resetGame()
    }

    /// 模拟器检查用来读蛇头、食物和朝向。
    var token: String {
        "score:\(score);len:\(length);over:\(isOver);dir:\(directionName);head:\(headText);food:\(foodText);note:\(note)"
    }
}

extension GameID {
    /// 贪吃蛇的登记标识。
    static let snake = GameID(rawValue: "snake")
}
