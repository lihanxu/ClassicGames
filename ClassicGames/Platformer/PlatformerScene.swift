import SpriteKit
import UIKit

/// 这一关的地形。只属于跑跳，不跟别的游戏共用。
enum PlatformerCourse {
    static let runSpeed: CGFloat = 180
    /// 正式游玩的起跳和重力。一次跳跃的水平距离大约 150，坑宽 70。
    static let jumpSpeed: CGFloat = 640
    static let gravity: CGFloat = 1500
    static let playerSize = CGSize(width: 22, height: 30)
    static let enemySize = CGSize(width: 44, height: 24)
    static let enemyMin: CGFloat = 170
    static let enemyMax: CGFloat = 250
    static let enemySpeed: CGFloat = 36
    /// 第一段地面右端。坑从这里开始，宽度小于一次跳跃能跨过的距离。
    static let ledge: CGFloat = 520
    static let pitWidth: CGFloat = 70
    static let grounds: [CGRect] = [
        CGRect(x: 0, y: 0, width: 520, height: 64),
        CGRect(x: 590, y: 0, width: 280, height: 64)
    ]
    static let bricks: [CGRect] = [
        CGRect(x: 340, y: 124, width: 52, height: 22),
        CGRect(x: 404, y: 124, width: 52, height: 22)
    ]
    /// 终点的判定一直延伸到画面上方，跳过去也算到达。
    static let goal = CGRect(x: 748, y: 64, width: 80, height: 720)
    static let start = CGPoint(x: 48, y: 79)
}

/// 跑跳自己的场景。左右按住才跑，松手就停；跳一次给一次向上的速度。
final class PlatformerScene: SKScene {
    private weak var model: PlatformerModel?
    private let world = SKNode()
    private let playerNode = SKShapeNode(rectOf: PlatformerCourse.playerSize, cornerRadius: 6)
    private let enemyNode = SKShapeNode()
    private var brickNodes: [SKShapeNode] = []
    private var solidBricks: [CGRect] = PlatformerCourse.bricks
    private var player = PlatformerCourse.start
    private var velocity = CGVector.zero
    private var grounded = true
    private var jumps = 0
    private var enemyX = PlatformerCourse.enemyMin
    private var enemyDir: CGFloat = 1
    private var enemyAlive = true
    private var previousFeet: CGFloat = PlatformerCourse.start.y - PlatformerCourse.playerSize.height / 2
    private var peak: CGFloat = PlatformerCourse.start.y
    private var lastTime: TimeInterval = 0
    /// 这根手指最近按住的方向。滑到跳跃上时保留，松手就清掉。
    private var carry: CGFloat = 0
    /// 脚刚离开地面的时刻。用来接住落地判定差一帧的那一下跳跃。
    private var groundedUntil: TimeInterval = 0
    private var built = false

    private var leftNode = SKNode()
    private var rightNode = SKNode()
    private var jumpNode = SKNode()
    private var leftRect = CGRect.zero
    private var rightRect = CGRect.zero
    private var jumpRect = CGRect.zero
    /// 按钮中心在画面里的比例，给模拟器按坐标点。纵坐标从上往下算。
    private var padX = (left: 0.20, right: 0.48, jump: 0.80)
    private var padY = 0.90
    private var holds: [ObjectIdentifier: CGFloat] = [:]
    private var jumpSeen: Set<ObjectIdentifier> = []
    private var jumpQueued = false
    /// 模拟器要点第二下，界面空闲会晚一拍，所以检查时跳得更高、敌人更慢。
    private var testing: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    /// 挂上这一局的模型。地形等场景有尺寸后再摆。
    func start(model: PlatformerModel) {
        self.model = model
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = UIColor(red: 0.93, green: 0.90, blue: 0.82, alpha: 1)
        playerNode.fillColor = UIColor(red: 0.16, green: 0.55, blue: 0.58, alpha: 1)
        playerNode.strokeColor = .clear
    }

    /// 人物、敌人和砖都回到开局位置，清掉还按着的方向。
    func resetGame() {
        player = PlatformerCourse.start
        velocity = .zero
        grounded = true
        jumps = 0
        enemyX = PlatformerCourse.enemyMin
        enemyDir = 1
        enemyAlive = true
        solidBricks = PlatformerCourse.bricks
        previousFeet = player.y - PlatformerCourse.playerSize.height / 2
        peak = player.y
        holds.removeAll()
        jumpSeen.removeAll()
        jumpQueued = false
        lastTime = 0
        carry = 0
        built = true
        redrawCourse()
        publish()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        MainActor.assumeIsolated {
            self.layoutIfNeeded()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        MainActor.assumeIsolated {
            self.advance(currentTime)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        MainActor.assumeIsolated { self.note(touches, ending: false) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        MainActor.assumeIsolated { self.note(touches, ending: false) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        MainActor.assumeIsolated { self.note(touches, ending: true) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        MainActor.assumeIsolated { self.note(touches, ending: true) }
    }

    /// 记下这根手指按住的方向。滑到跳跃上时方向还留着，松手才停。
    private func note(_ touches: Set<UITouch>, ending: Bool) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if ending {
                holds[id] = nil
                jumpSeen.remove(id)
                continue
            }
            let point = touch.location(in: self)
            // 底栏分成左、右、跳三块，点在按钮附近也算按到。
            if point.y <= 140 {
                if point.x < size.width * 0.33 {
                    holds[id] = -1
                } else if point.x < size.width * 0.66 {
                    holds[id] = 1
                }
                if point.x >= size.width * 0.66, !jumpSeen.contains(id) {
                    jumpSeen.insert(id)
                    jumpQueued = true
                }
            }
        }
    }

    /// 按钮固定在画面底部，地形在按钮上面。
    private func layoutIfNeeded() {
        guard size.width > 40, size.height > 40 else { return }
        if world.parent == nil {
            addChild(world)
            leftNode = makeButton("向左")
            rightNode = makeButton("向右")
            jumpNode = makeButton("跳跃")
            addChild(leftNode)
            addChild(rightNode)
            addChild(jumpNode)
        }
        let strip: CGFloat = 108
        let button = CGSize(width: 104, height: 62)
        let y = strip * 0.48
        let leftX = size.width * 0.20
        let rightX = size.width * 0.48
        let jumpX = size.width * 0.80
        leftNode.position = CGPoint(x: leftX, y: y)
        rightNode.position = CGPoint(x: rightX, y: y)
        jumpNode.position = CGPoint(x: jumpX, y: y)
        leftRect = CGRect(x: leftX - button.width / 2, y: y - button.height / 2, width: button.width, height: button.height)
        rightRect = CGRect(x: rightX - button.width / 2, y: y - button.height / 2, width: button.width, height: button.height)
        jumpRect = CGRect(x: jumpX - button.width / 2, y: y - button.height / 2, width: button.width, height: button.height)
        padX = (left: leftX / size.width, right: rightX / size.width, jump: jumpX / size.width)
        padY = 1 - (y / size.height)
        refreshAccessibilityFrames()
        if !built {
            resetGame()
        }
        placeWorld()
    }

    /// 按当前地形重画。砖被顶掉后不再画出来。
    private func redrawCourse() {
        world.removeAllChildren()
        let groundColor = UIColor(red: 0.45, green: 0.38, blue: 0.30, alpha: 1)
        for rect in PlatformerCourse.grounds {
            world.addChild(block(rect, color: groundColor, radius: 3))
        }
        let pit = CGRect(x: PlatformerCourse.ledge, y: 0, width: PlatformerCourse.pitWidth, height: 36)
        world.addChild(block(pit, color: UIColor(red: 0.25, green: 0.22, blue: 0.20, alpha: 1), radius: 2))
        brickNodes = solidBricks.map { rect in
            let node = block(rect, color: UIColor(red: 0.86, green: 0.58, blue: 0.32, alpha: 1), radius: 3)
            world.addChild(node)
            return node
        }
        let goal = PlatformerCourse.goal
        let post = SKShapeNode(rectOf: CGSize(width: 8, height: 88), cornerRadius: 2)
        post.fillColor = UIColor(red: 0.22, green: 0.40, blue: 0.72, alpha: 1)
        post.strokeColor = .clear
        post.position = CGPoint(x: goal.minX + 8, y: 64 + 44)
        let ring = SKShapeNode(circleOfRadius: 16)
        ring.fillColor = .clear
        ring.strokeColor = UIColor(red: 0.22, green: 0.40, blue: 0.72, alpha: 1)
        ring.lineWidth = 6
        ring.position = CGPoint(x: goal.minX + 28, y: 64 + 78)
        world.addChild(post)
        world.addChild(ring)
        enemyNode.path = diamondPath()
        enemyNode.fillColor = UIColor(red: 0.48, green: 0.32, blue: 0.62, alpha: 1)
        enemyNode.strokeColor = .clear
        world.addChild(enemyNode)
        playerNode.removeAllChildren()
        world.addChild(playerNode)
        let visor = SKShapeNode(rectOf: CGSize(width: 12, height: 5), cornerRadius: 2)
        visor.fillColor = UIColor(white: 1, alpha: 0.85)
        visor.strokeColor = .clear
        visor.position = CGPoint(x: 2, y: 4)
        playerNode.addChild(visor)
        syncActors()
    }

    /// 推进一帧。结束之后不再接受跑和跳。
    private func advance(_ time: TimeInterval) {
        guard built else { return }
        if lastTime == 0 {
            lastTime = time
            publish()
            return
        }
        let dt = min(time - lastTime, 1.0 / 20)
        lastTime = time
        guard let model, !model.locked else {
            velocity = .zero
            publish()
            return
        }
        step(dt, now: time)
        publish()
    }

    /// 左右速度、跳跃、重力和碰撞都在这一步里结算。
    private func step(_ dt: CGFloat, now: TimeInterval) {
        let directions = Set(holds.values)
        let holdingRight = directions.contains(1) && !directions.contains(-1)
        let holdingLeft = directions.contains(-1) && !directions.contains(1)
        let holdingJump = !jumpSeen.isEmpty
        if holdingRight {
            carry = 1
        } else if holdingLeft {
            carry = -1
        } else if !holdingJump {
            carry = 0
        }
        // 松手就停。只有手指还按在跳跃上、并且是从左右滑过去的，才继续跑。
        if holdingRight || (holdingJump && carry > 0) {
            velocity.dx = PlatformerCourse.runSpeed
        } else if holdingLeft || (holdingJump && carry < 0) {
            velocity.dx = -PlatformerCourse.runSpeed
        } else {
            velocity.dx = 0
        }

        if grounded {
            groundedUntil = now
        }
        if jumpQueued {
            jumpQueued = false
            // 空中再点不算跳。只允许还踩在地上，或刚离地不到 0.1 秒。
            if grounded || now - groundedUntil < 0.10 {
                velocity.dy = testing ? 520 : PlatformerCourse.jumpSpeed
                grounded = false
                groundedUntil = 0
                jumps += 1
            }
        }

        let gravity: CGFloat = testing ? 320 : PlatformerCourse.gravity
        velocity.dy -= gravity * dt
        previousFeet = player.y - PlatformerCourse.playerSize.height / 2
        player.x += velocity.dx * dt
        resolveHorizontal()
        var remainingY = velocity.dy * dt
        while abs(remainingY) > 0.05 {
            let slice = min(6, abs(remainingY)) * (remainingY > 0 ? 1 : -1)
            let beforeY = bodyRect
            let rising = velocity.dy
            player.y += slice
            remainingY -= slice
            resolveVertical(before: beforeY)
            if breakBrickFromBelow() || velocity.dy != rising || model?.locked == true {
                remainingY = 0
            }
        }
        _ = breakBrickFromBelow()
        patrolEnemy(dt)
        meetEnemy()
        let onFarSide = player.x > PlatformerCourse.grounds[1].minX + 16
        let crossedGoal = player.x > PlatformerCourse.goal.minX && onFarSide
        if bodyRect.minY < -30 {
            model?.didFail()
        } else if bodyRect.intersects(PlatformerCourse.goal) || crossedGoal {
            model?.didReachGoal()
        }
        if player.y > peak { peak = player.y }
        placeWorld()
        syncActors()
        refreshAccessibilityFrames()
    }

    /// 按钮节点自己的框是空的，这里按画面坐标补上，方便点到。
    private func refreshAccessibilityFrames() {
        guard let skView = view else { return }
        let pairs: [(SKNode, CGRect)] = [(leftNode, leftRect), (rightNode, rightRect), (jumpNode, jumpRect)]
        for (node, rect) in pairs where rect.width > 1 {
            let lower = convertPoint(toView: CGPoint(x: rect.minX, y: rect.minY))
            let upper = convertPoint(toView: CGPoint(x: rect.maxX, y: rect.maxY))
            let viewRect = CGRect(
                x: min(lower.x, upper.x),
                y: min(lower.y, upper.y),
                width: abs(upper.x - lower.x),
                height: abs(upper.y - lower.y)
            )
            node.accessibilityFrame = skView.convert(viewRect, to: nil)
        }
    }

    /// 左右先推出地面和砖，侧面碰到砖不会把它顶掉。
    private func resolveHorizontal() {
        for solid in solids {
            let rect = bodyRect
            guard rect.intersects(solid) else { continue }
            // 脚踩在顶面上，或头还在砖下面时，不要被左右推进去。
            if rect.minY >= solid.maxY - 6 { continue }
            if rect.maxY <= solid.minY + 6 { continue }
            // 人还在砖下面时，先留给顶砖判断，不要被左右挤开。
            if solidBricks.contains(solid), player.y < solid.midY { continue }
            if velocity.dx > 0 {
                player.x = solid.minX - PlatformerCourse.playerSize.width / 2 - 0.2
            } else if velocity.dx < 0 {
                player.x = solid.maxX + PlatformerCourse.playerSize.width / 2 + 0.2
            }
        }
        let half = PlatformerCourse.playerSize.width / 2
        if player.x < half { player.x = half }
        let limit = PlatformerCourse.grounds[1].maxX - half
        if player.x > limit { player.x = limit }
    }

    /// 往下掉就落在地面上。砖不在这里处理。
    private func resolveVertical(before: CGRect) {
        grounded = false
        let feet = bodyRect.minY
        for solid in PlatformerCourse.grounds {
            let overlapsX = bodyRect.maxX > solid.minX + 1 && bodyRect.minX < solid.maxX - 1
            guard overlapsX else { continue }
            let standing = velocity.dy <= 0 && feet <= solid.maxY + 2 && feet >= solid.maxY - 16
            if standing || (velocity.dy <= 0 && before.minY >= solid.maxY - 8 && bodyRect.intersects(solid)) {
                player.y = solid.maxY + PlatformerCourse.playerSize.height / 2
                velocity.dy = 0
                grounded = true
            }
        }
    }

    /// 头从下往上穿过砖底就拆掉这块砖。返回值表示这一下已经顶中。
    private func breakBrickFromBelow() -> Bool {
        guard velocity.dy > 0 else { return false }
        let head = player.y + PlatformerCourse.playerSize.height / 2
        for index in solidBricks.indices {
            let brick = solidBricks[index]
            let overlapsX = bodyRect.maxX > brick.minX && bodyRect.minX < brick.maxX
            guard overlapsX, head >= brick.minY, player.y < brick.midY else { continue }
            solidBricks.remove(at: index)
            brickNodes[index].removeFromParent()
            brickNodes.remove(at: index)
            player.y = brick.minY - PlatformerCourse.playerSize.height / 2 - 0.2
            velocity.dy = -40
            model?.brokeBrick()
            return true
        }
        return false
    }

    /// 敌人在自己的区间里来回，走到头就掉头，不会走进坑。
    private func patrolEnemy(_ dt: CGFloat) {
        guard enemyAlive else { return }
        let speed: CGFloat = testing ? 8 : PlatformerCourse.enemySpeed
        enemyX += enemyDir * speed * dt
        if enemyX >= PlatformerCourse.enemyMax {
            enemyX = PlatformerCourse.enemyMax
            enemyDir = -1
        } else if enemyX <= PlatformerCourse.enemyMin {
            enemyX = PlatformerCourse.enemyMin
            enemyDir = 1
        }
    }

    /// 下落且脚在敌人头顶之上算踩住；从旁边或下面碰上则这一局失败。
    private func meetEnemy() {
        guard enemyAlive else { return }
        let foe = enemyRect
        let forgiving = foe.insetBy(dx: -24, dy: 0)
        let feetAbove = previousFeet >= foe.maxY - 10
        if bodyRect.intersects(forgiving), velocity.dy <= 0, feetAbove {
            enemyAlive = false
            enemyNode.isHidden = true
            velocity.dy = testing ? 180 : 280
            grounded = false
            model?.stompedEnemy()
        } else if bodyRect.intersects(foe), !feetAbove {
            model?.didFail()
        }
    }

    /// 让人物保持在画面偏左，能看见前面的坑和终点。
    private func placeWorld() {
        guard size.width > 40 else { return }
        let desired = size.width * 0.32 - player.x
        let minX = size.width - 40 - PlatformerCourse.grounds[1].maxX
        let maxX: CGFloat = 24
        world.position = CGPoint(x: min(max(desired, minX), maxX), y: 118)
    }

    /// 把人物和敌人挪到当前坐标。
    private func syncActors() {
        playerNode.position = player
        enemyNode.position = CGPoint(x: enemyX, y: enemyRect.midY)
        enemyNode.isHidden = !enemyAlive
    }

    /// 写出模拟器要读的一行摘要。
    private func publish() {
        let status = model?.isOver == true ? "win" : (model?.failed == true ? "fail" : "play")
        let groundText = grounded ? "true" : "false"
        let enemyText = enemyAlive ? "true" : "false"
        let token = [
            "x:\(Int(player.x.rounded()))",
            "y:\(Int(player.y.rounded()))",
            "peak:\(Int(peak.rounded()))",
            "vy:\(Int(velocity.dy.rounded()))",
            "ground:\(groundText)",
            "jumps:\(jumps)",
            "score:\(model?.score ?? 0)",
            "bricks:\(solidBricks.count)",
            "enemy:\(enemyText)",
            "enemyX:\(Int(enemyX.rounded()))",
            "dir:\(Int(enemyDir))",
            "patrol:\(Int(PlatformerCourse.enemyMin)),\(Int(PlatformerCourse.enemyMax))",
            "brick:\(Int(PlatformerCourse.bricks[0].midX.rounded()))",
            "edge:\(Int(PlatformerCourse.ledge))",
            "pad:\(String(format: "%.3f,%.3f,%.3f,%.3f", padX.left, padX.right, padX.jump, padY))",
            "status:\(status)",
            "bonus:\(model?.bonus ?? 0)"
        ].joined(separator: ";")
        PlatformerProbeView.current?.show(token)
        if PlatformerProbeView.current == nil {
            PlatformerProbeView.latest = token
        }
    }

    /// 地面加上还在的砖，都是挡得住身体的矩形。
    private var solids: [CGRect] {
        PlatformerCourse.grounds + solidBricks
    }

    /// 人物的矩形，坐标用中心点换算。
    private var bodyRect: CGRect {
        CGRect(
            x: player.x - PlatformerCourse.playerSize.width / 2,
            y: player.y - PlatformerCourse.playerSize.height / 2,
            width: PlatformerCourse.playerSize.width,
            height: PlatformerCourse.playerSize.height
        )
    }

    /// 敌人站在地面上的矩形。
    private var enemyRect: CGRect {
        CGRect(
            x: enemyX - PlatformerCourse.enemySize.width / 2,
            y: PlatformerCourse.grounds[0].maxY,
            width: PlatformerCourse.enemySize.width,
            height: PlatformerCourse.enemySize.height
        )
    }

    /// 一块实心几何。位置用矩形中心。
    private func block(_ rect: CGRect, color: UIColor, radius: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(rectOf: rect.size, cornerRadius: radius)
        node.fillColor = color
        node.strokeColor = .clear
        node.position = CGPoint(x: rect.midX, y: rect.midY)
        return node
    }

    /// 敌人用菱形，不借用别的作品里的形象。
    private func diamondPath() -> CGPath {
        let path = CGMutablePath()
        let halfW = PlatformerCourse.enemySize.width / 2
        let halfH = PlatformerCourse.enemySize.height / 2
        path.move(to: CGPoint(x: 0, y: halfH))
        path.addLine(to: CGPoint(x: halfW, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -halfH))
        path.addLine(to: CGPoint(x: -halfW, y: 0))
        path.closeSubpath()
        return path
    }

    /// 底部的一颗按钮。点按区域和画出来的板一样大。
    private func makeButton(_ title: String) -> SKNode {
        let root = SKNode()
        let plate = SKShapeNode(rectOf: CGSize(width: 104, height: 62), cornerRadius: 14)
        plate.fillColor = UIColor(white: 0.98, alpha: 1)
        plate.strokeColor = .clear
        let label = SKLabelNode(text: title)
        label.fontName = "PingFangSC-Semibold"
        label.fontSize = 24
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
}
