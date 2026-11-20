import SpriteKit
import UIKit

/// 打砖块自己的场景。挡板、发球和反弹都在 `update` 里，不引用别的游戏。
final class BreakoutScene: SKScene {
    private weak var model: BreakoutModel?
    private var bricks: [SKShapeNode] = []
    private let ball = SKShapeNode(circleOfRadius: 8)
    private let paddle = SKShapeNode(rectOf: CGSize(width: 86, height: 14), cornerRadius: 6)
    private var velocity = CGVector.zero
    private var stuck = true
    private var built = false
    private var lastTime: TimeInterval = 0
    private var lastPublish: TimeInterval = 0
    private let ballRadius: CGFloat = 8
    private let paddleWidth: CGFloat = 86

    /// 挂上这一局的模型。棋盘等场景有尺寸后再摆。
    func start(model: BreakoutModel) {
        self.model = model
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = UIColor(red: 0.10, green: 0.13, blue: 0.20, alpha: 1)
        ball.fillColor = .white
        ball.strokeColor = .clear
        paddle.fillColor = UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1)
        paddle.strokeColor = .clear
    }

    /// 拆掉砖和球，回到开局：球粘在挡板上，3 条命由模型重置。
    func resetGame() {
        built = false
        stuck = true
        velocity = .zero
        lastTime = 0
        layout(force: true)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        MainActor.assumeIsolated {
            self.layout(force: false)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        MainActor.assumeIsolated {
            self.advance(currentTime)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let x = touches.first?.location(in: self).x else { return }
        MainActor.assumeIsolated { self.drag(to: x, canLaunch: true) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let x = touches.first?.location(in: self).x else { return }
        // 球刚粘回挡板时，这一下还是原来的拖动，只跟着走，不重新发球。
        MainActor.assumeIsolated { self.drag(to: x, canLaunch: false) }
    }

    /// 上方 8 列 4 行砖，挡板靠近底部。开局还没拖动时不重复拆掉正在进行的一局。
    private func layout(force: Bool) {
        guard size.width > 20, size.height > 20 else { return }
        if built && !force { return }
        removeAllChildren()
        bricks.removeAll()
        let columns = 8
        let rows = 4
        let margin: CGFloat = 10
        let gap: CGFloat = 4
        let brickWidth = (size.width - margin * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let brickHeight: CGFloat = 18
        let colors: [UIColor] = [
            UIColor(red: 0.86, green: 0.32, blue: 0.28, alpha: 1),
            UIColor(red: 0.92, green: 0.55, blue: 0.22, alpha: 1),
            UIColor(red: 0.93, green: 0.78, blue: 0.28, alpha: 1),
            UIColor(red: 0.36, green: 0.70, blue: 0.46, alpha: 1)
        ]
        for row in 0..<rows {
            for column in 0..<columns {
                let node = SKShapeNode(rectOf: CGSize(width: brickWidth, height: brickHeight), cornerRadius: 3)
                node.fillColor = colors[row % colors.count]
                node.strokeColor = .clear
                let x = margin + brickWidth / 2 + CGFloat(column) * (brickWidth + gap)
                let y = size.height - 28 - brickHeight / 2 - CGFloat(row) * (brickHeight + gap)
                node.position = CGPoint(x: x, y: y)
                addChild(node)
                bricks.append(node)
            }
        }
        addChild(paddle)
        addChild(ball)
        paddle.position = CGPoint(x: size.width / 2, y: size.height * 0.14)
        stickBall()
        built = true
        publish()
    }

    /// 跟着手指的横坐标移动挡板。新的一次按下才把粘着的球发出去。
    private func drag(to x: CGFloat, canLaunch: Bool) {
        guard built, let model, !model.isOver else { return }
        let half = paddleWidth / 2
        let clamped = min(max(x, half), size.width - half)
        paddle.position.x = clamped
        if stuck {
            stickBall()
            if canLaunch {
                launch()
            }
        }
        publish()
    }

    /// 球粘回挡板正中上方，等下一次拖动。
    private func stickBall() {
        stuck = true
        velocity = .zero
        ball.position = CGPoint(x: paddle.position.x, y: paddle.frame.maxY + ballRadius + 1)
    }

    /// 向右上飞出。竖直速度不为 0。
    private func launch() {
        stuck = false
        let speed: CGFloat = 460
        let raw = CGVector(dx: 120, dy: 430)
        let magnitude = hypot(raw.dx, raw.dy)
        velocity = CGVector(dx: raw.dx / magnitude * speed, dy: raw.dy / magnitude * speed)
    }

    /// 粘着的时候不走，飞出以后按时间推进一步。
    private func advance(_ time: TimeInterval) {
        guard built, let model, !model.isOver else { return }
        if lastTime == 0 {
            lastTime = time
            return
        }
        let dt = min(time - lastTime, 1.0 / 20)
        lastTime = time
        // 球粘着时不再刷新界面，否则模拟器会一直等不到界面空闲。
        guard !stuck else { return }
        var remaining = CGFloat(dt)
        while remaining > 0 {
            let slice = min(remaining, 1.0 / 120)
            ball.position.x += velocity.dx * slice
            ball.position.y += velocity.dy * slice
            if resolve() { break }
            remaining -= slice
        }
        keepVerticalSpeed()
        if time - lastPublish >= 0.2 {
            publish()
        }
    }

    /// 处理墙、砖和挡板。球落到挡板下方时返回 true，这一帧不再继续推。
    private func resolve() -> Bool {
        guard let model else { return true }
        if ball.position.x < ballRadius {
            ball.position.x = ballRadius
            velocity.dx = abs(velocity.dx)
        } else if ball.position.x > size.width - ballRadius {
            ball.position.x = size.width - ballRadius
            velocity.dx = -abs(velocity.dx)
        }
        if ball.position.y > size.height - ballRadius {
            ball.position.y = size.height - ballRadius
            velocity.dy = -abs(velocity.dy)
        }

        if velocity.dy < 0, ball.frame.intersects(paddle.frame), ball.position.y >= paddle.position.y {
            bounceFromPaddle()
        }

        for brick in bricks where brick.parent != nil && ball.frame.intersects(brick.frame) {
            brick.removeFromParent()
            if ball.position.y < brick.frame.midY {
                ball.position.y = brick.frame.minY - ballRadius - 1
                velocity.dy = -abs(velocity.dy)
            } else {
                ball.position.y = brick.frame.maxY + ballRadius + 1
                velocity.dy = abs(velocity.dy)
            }
            model.brickDestroyed()
            publish()
            if bricks.allSatisfy({ $0.parent == nil }) {
                model.cleared()
                return true
            }
            break
        }

        if ball.position.y < paddle.frame.minY - ballRadius {
            model.lifeLost()
            if !model.isOver {
                stickBall()
            }
            publish()
            return true
        }
        return false
    }

    /// 左半向左上，右半向右上，中间向上。速度大小保持不变。
    private func bounceFromPaddle() {
        let speed = max(hypot(velocity.dx, velocity.dy), 360)
        let relative = (ball.position.x - paddle.position.x) / (paddleWidth / 2)
        if abs(relative) < 0.22 {
            velocity = CGVector(dx: 0, dy: speed)
        } else if relative < 0 {
            velocity = CGVector(dx: -speed * 0.5, dy: speed * 0.86)
        } else {
            velocity = CGVector(dx: speed * 0.5, dy: speed * 0.86)
        }
        ball.position.y = paddle.frame.maxY + ballRadius + 1
    }

    /// 避免球完全横着飞，竖直方向始终留一点速度。
    private func keepVerticalSpeed() {
        guard abs(velocity.dy) < 120 else { return }
        velocity.dy = velocity.dy < 0 ? -120 : 120
    }

    private func publish() {
        guard let model, size.width > 1, size.height > 1 else { return }
        lastPublish = CACurrentMediaTime()
        let left = bricks.filter { $0.parent != nil }.count
        model.publish(
            launched: !stuck,
            ballX: ball.position.x / size.width,
            ballY: ball.position.y / size.height,
            paddleX: paddle.position.x / size.width,
            paddleY: paddle.position.y / size.height,
            bricks: left
        )
    }
}
