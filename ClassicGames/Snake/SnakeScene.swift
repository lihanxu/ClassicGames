import SpriteKit
import UIKit

/// 贪吃蛇自己的场景。节拍、转向和碰撞都在这里，不引用别的游戏。
final class SnakeScene: SKScene {
    /// 和界面底部按钮位置对应的比例，模拟器检查按同一组数字点。
    static let stripRatio: CGFloat = 0.24
    static let upYInStrip: CGFloat = 0.70
    static let rowYInStrip: CGFloat = 0.28
    static let sideShiftRatio: CGFloat = 0.20

    private weak var model: SnakeModel?
    private var snake: [SnakeCell] = []
    private var food = SnakeCell(col: 0, row: 0)
    private var heading: SnakeHeading = .right
    private var pending: SnakeHeading?
    private var lastTick: TimeInterval = 0
    /// 平时每 0.15 秒走一格，不随长度加快。
    /// 模拟器检查的点按来得慢，带 `-ui-testing` 时放宽到 0.4 秒，避免还没点到就已经撞墙。
    private var tickInterval: TimeInterval {
        ProcessInfo.processInfo.arguments.contains("-ui-testing") ? 0.40 : 0.15
    }
    private var didBuild = false

    private let segmentLayer = SKNode()
    private let foodNode = SKShapeNode(circleOfRadius: 8)
    private var upButton = SKNode()
    private var downButton = SKNode()
    private var leftButton = SKNode()
    private var rightButton = SKNode()
    private var gridOrigin = CGPoint.zero
    private var cellSize: CGFloat = 10
    /// 滑动起点。结束时和落点比，避免只用最后一小段位移。
    private var touchOrigin: CGPoint?

    /// 挂上这一局的模型。节点等场景有尺寸后再摆。
    func start(model: SnakeModel) {
        self.model = model
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = UIColor(red: 0.11, green: 0.16, blue: 0.14, alpha: 1)
        foodNode.fillColor = UIColor(red: 0.90, green: 0.33, blue: 0.24, alpha: 1)
        foodNode.strokeColor = .clear
    }

    /// 拆掉当前蛇，回到长度 3、朝右、中部开局。
    func resetGame() {
        heading = .right
        pending = nil
        lastTick = 0
        snake = [
            SnakeCell(col: 8, row: 8),
            SnakeCell(col: 7, row: 8),
            SnakeCell(col: 6, row: 8)
        ]
        spawnFood()
        didBuild = true
        publish()
        redraw()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        MainActor.assumeIsolated {
            self.layoutBoard()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        MainActor.assumeIsolated {
            self.advance(currentTime)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: self) else { return }
        touchOrigin = location
        MainActor.assumeIsolated {
            self.press(at: location)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let end = touch.location(in: self)
        let start = touchOrigin ?? end
        touchOrigin = nil
        MainActor.assumeIsolated {
            self.swipe(from: start, to: end)
        }
    }

    /// 按场景宽度把棋盘放在按钮区上面。
    private func layoutBoard() {
        guard size.width > 20, size.height > 20 else { return }
        if !didBuild {
            resetGame()
        }
        let strip = size.height * Self.stripRatio
        let playHeight = size.height - strip
        let grid = min(size.width - 16, playHeight - 12)
        cellSize = grid / 16
        gridOrigin = CGPoint(
            x: (size.width - grid) / 2,
            y: strip + (playHeight - grid) / 2
        )
        if segmentLayer.parent == nil {
            addChild(segmentLayer)
            addChild(foodNode)
            upButton = makeButton("上")
            downButton = makeButton("下")
            leftButton = makeButton("左")
            rightButton = makeButton("右")
            addChild(upButton)
            addChild(downButton)
            addChild(leftButton)
            addChild(rightButton)
        }
        let midX = size.width / 2
        let shift = size.width * Self.sideShiftRatio
        upButton.position = CGPoint(x: midX, y: strip * Self.upYInStrip)
        downButton.position = CGPoint(x: midX, y: strip * Self.rowYInStrip)
        leftButton.position = CGPoint(x: midX - shift, y: strip * Self.rowYInStrip)
        rightButton.position = CGPoint(x: midX + shift, y: strip * Self.rowYInStrip)
        foodNode.path = CGPath(ellipseIn: CGRect(x: -cellSize * 0.28, y: -cellSize * 0.28, width: cellSize * 0.56, height: cellSize * 0.56), transform: nil)
        redraw()
    }

    /// 到点就走一格。节拍前的多次转向只留最后一次，且不能和当前方向相反。
    private func advance(_ time: TimeInterval) {
        guard didBuild, let model, !model.isOver, !snake.isEmpty else { return }
        if lastTick == 0 {
            lastTick = time
            return
        }
        guard time - lastTick >= tickInterval else { return }
        lastTick = time
        if let pending, pending != heading.opposite {
            heading = pending
        }
        pending = nil
        step()
    }

    /// 记住这一拍要转的方向。正相反的输入直接丢掉。
    private func queue(_ heading: SnakeHeading) {
        guard let model, !model.isOver else { return }
        guard heading != self.heading.opposite else { return }
        pending = heading
    }

    /// 向前一格。吃到就变长并再放一个食物，撞墙或撞身体就结束。
    private func step() {
        guard let model, let head = snake.first else { return }
        let next = head.moved(heading)
        let eats = next == food
        let hitsBody = snake.dropLast().contains(next) || (eats && next == snake.last)
        if !next.isInsideBoard || hitsBody {
            let reason = next.isInsideBoard ? "body" : "wall"
            model.didDie(note: "\(reason) \(next.col),\(next.row)")
            publish()
            return
        }
        snake.insert(next, at: 0)
        if eats {
            spawnFood()
            model.didEat(length: snake.count)
        } else {
            snake.removeLast()
        }
        publish()
        redraw()
    }

    /// 在蛇身以外随机放一块食物。场上始终只有这一块。
    private func spawnFood() {
        var empty: [SnakeCell] = []
        for row in 0..<16 {
            for col in 0..<16 {
                let cell = SnakeCell(col: col, row: row)
                if !snake.contains(cell) {
                    empty.append(cell)
                }
            }
        }
        food = empty.randomElement() ?? SnakeCell(col: 0, row: 0)
    }

    /// 点在哪个方向按钮上，就转向。
    private func press(at location: CGPoint) {
        let buttons: [(SKNode, SnakeHeading)] = [
            (upButton, .up),
            (downButton, .down),
            (leftButton, .left),
            (rightButton, .right)
        ]
        guard let nearest = buttons.min(by: { distance($0.0.position, location) < distance($1.0.position, location) }) else { return }
        guard distance(nearest.0.position, location) <= 46 else { return }
        queue(nearest.1)
    }

    /// 场景里滑动，和按钮进同一个转向方法。
    private func swipe(from start: CGPoint, to end: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard hypot(dx, dy) >= 28 else { return }
        if abs(dx) > abs(dy) {
            queue(dx > 0 ? .right : .left)
        } else {
            queue(dy > 0 ? .up : .down)
        }
    }

    private func publish() {
        guard let model, let head = snake.first else { return }
        model.publish(
            direction: heading.name,
            head: "\(head.col),\(head.row)",
            food: "\(food.col),\(food.row)",
            length: snake.count
        )
    }

    /// 按当前蛇和食物重画格子。按钮层不动。
    private func redraw() {
        guard cellSize > 1, let head = snake.first else { return }
        segmentLayer.removeAllChildren()
        for cell in snake {
            let node = SKShapeNode(rectOf: CGSize(width: cellSize * 0.82, height: cellSize * 0.82), cornerRadius: 3)
            node.fillColor = cell == head
                ? UIColor(red: 0.55, green: 0.86, blue: 0.46, alpha: 1)
                : UIColor(red: 0.32, green: 0.70, blue: 0.38, alpha: 1)
            node.strokeColor = .clear
            node.position = center(of: cell)
            segmentLayer.addChild(node)
        }
        foodNode.position = center(of: food)
    }

    private func center(of cell: SnakeCell) -> CGPoint {
        CGPoint(
            x: gridOrigin.x + (CGFloat(cell.col) + 0.5) * cellSize,
            y: gridOrigin.y + (CGFloat(15 - cell.row) + 0.5) * cellSize
        )
    }

    /// 一颗方向按钮。字是中文方向，点按区域比字大。
    private func makeButton(_ title: String) -> SKNode {
        let root = SKNode()
        let plate = SKShapeNode(rectOf: CGSize(width: 84, height: 52), cornerRadius: 12)
        plate.fillColor = UIColor(white: 0.96, alpha: 1)
        plate.strokeColor = .clear
        let label = SKLabelNode(text: title)
        label.fontName = "PingFangSC-Semibold"
        label.fontSize = 22
        label.fontColor = UIColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        root.addChild(plate)
        root.addChild(label)
        root.isAccessibilityElement = true
        root.accessibilityLabel = title
        root.accessibilityTraits = .button
        return root
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

/// 棋盘上的一格。只在贪吃蛇场景里使用。
struct SnakeCell: Hashable {
    var col: Int
    var row: Int

    var isInsideBoard: Bool {
        col >= 0 && row >= 0 && col < 16 && row < 16
    }

    /// 沿当前朝向走一格。不管会不会出界。
    func moved(_ heading: SnakeHeading) -> SnakeCell {
        switch heading {
        case .up:
            return SnakeCell(col: col, row: row - 1)
        case .down:
            return SnakeCell(col: col, row: row + 1)
        case .left:
            return SnakeCell(col: col - 1, row: row)
        case .right:
            return SnakeCell(col: col + 1, row: row)
        }
    }
}

/// 蛇的朝向。相反方向在排队时会被丢掉。
enum SnakeHeading {
    case up
    case down
    case left
    case right

    var opposite: SnakeHeading {
        switch self {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        }
    }

    var name: String {
        switch self {
        case .up: "up"
        case .down: "down"
        case .left: "left"
        case .right: "right"
        }
    }
}
