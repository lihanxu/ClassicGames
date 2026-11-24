import SwiftUI

/// 推箱子这一局。外框负责返回和总纪录，这里画关卡、棋盘和选关。
struct SokobanScreen: View {
    @Environment(SokobanAudio.self) private var audio
    @State private var model = SokobanModel()
    @State private var showPicker = false

    var body: some View {
        GameFrame(
            id: .sokoban,
            title: "推箱子",
            score: model.steps,
            scorePrefix: "步数",
            isOver: model.won,
            banner: nil,
            rule: .lowerOnClear,
            onRestart: model.restart
        ) {
            VStack(spacing: 12) {
                levelBar
                Text(verbatim: bestLine)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(SokobanPalette.target)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sokoban.best")
                SokobanBoard(model: model, onMove: move)
                if model.won {
                    winRow
                }
                SokobanPad(locked: model.won, onMove: move)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showPicker) {
            SokobanLevelPicker(current: model.levelNumber) { number in
                model.load(number)
                showPicker = false
            }
        }
    }

    /// 当前关号和选关入口。选关的值是关卡总数，给模拟器核对用。
    private var levelBar: some View {
        HStack(spacing: 8) {
            Button("选关") { showPicker = true }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SokobanPalette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(SokobanPalette.key, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(SokobanPalette.wallEdge, lineWidth: 1.5)
                }
                .accessibilityIdentifier("sokoban.levels")
                .accessibilityValue("\(SokobanLevels.count)")
            Spacer(minLength: 0)
            Text(verbatim: "第 \(model.levelNumber) 关 / \(SokobanLevels.count)")
                .font(.headline)
                .foregroundStyle(SokobanPalette.ink)
                .accessibilityIdentifier("sokoban.level")
        }
    }

    /// 过关后才能进下一关。最后一关没有下一关。
    private var winRow: some View {
        HStack(spacing: 12) {
            SokobanWinMark()
            if model.levelNumber < SokobanLevels.count {
                Button("下一关") { model.advance() }
                    .buttonStyle(.plain)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(SokobanPalette.player, in: Capsule())
                    .accessibilityIdentifier("sokoban.next")
            }
        }
    }

    /// 按这一步的结果发声。步数没加就是顶墙或推不动，不响。人动而箱子没动才有脚步。过关短乐等这一格过渡结束：走出一格 140 毫秒，推动一格 180 毫秒。
    private func move(_ direction: SokobanDirection) {
        let stepsBefore = model.steps
        let boxesBefore = model.boxes
        let wonBefore = model.won
        model.move(direction)
        guard model.steps > stepsBefore else { return }
        let pushed = model.boxes != boxesBefore
        if !pushed {
            audio.playFootstep()
        }
        if !wonBefore && model.won {
            audio.playClear(afterMilliseconds: pushed ? 180 : 140)
        }
    }

    /// 这一关自己的最少步数。没有过关时是「—」。
    private var bestLine: String {
        guard let levelBest = model.levelBest else { return "本关纪录 —" }
        return "本关纪录 \(levelBest)"
    }
}

/// 过关标记放在棋盘下面，避免盖住人和箱子。
struct SokobanWinMark: View {
    var body: some View {
        Text("过关")
            .font(.title2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(SokobanPalette.target, in: Capsule())
            .accessibilityIdentifier("sokoban.win")
    }
}

/// 100 关按难度分成五组。点编号进入该关开局，标题不响应点击。
struct SokobanLevelPicker: View {
    var current: Int
    var onPick: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    /// 分组界线和需求一致。每组 20 关，标题写已过数。
    private let groups: [(name: String, start: Int, end: Int)] = [
        ("入门", 1, 20),
        ("初级", 21, 40),
        ("中级", 41, 60),
        ("进阶", 61, 80),
        ("挑战", 81, 100)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(SokobanLevels.credit)
                        .font(.footnote)
                        .foregroundStyle(SokobanPalette.ink.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("sokoban.credit")
                    ForEach(groups, id: \.name) { group in
                        groupSection(group.name, group.start, group.end)
                    }
                }
                .padding(16)
            }
            .background(SokobanPalette.floor.ignoresSafeArea())
            .navigationTitle("选关")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// 一组的标题和编号。标题只展示进度，点它不换关。
    private func groupSection(_ name: String, _ start: Int, _ end: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "\(name) \(SokobanRecords.clearedCount(from: start, through: end))/20")
                .font(.headline)
                .foregroundStyle(SokobanPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("sokoban.group.\(name)")
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(start...end, id: \.self) { number in
                    levelButton(number)
                }
            }
        }
    }

    /// 一关的编号。已过的在编号下写「已过」；当前关保留深色描边。
    private func levelButton(_ number: Int) -> some View {
        let cleared = SokobanRecords.best(level: number) != nil
        let selected = number == current
        return Button {
            onPick(number)
        } label: {
            VStack(spacing: 2) {
                Text("\(number)")
                    .font(.headline)
                if cleared {
                    Text("已过")
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("sokoban.cleared.\(number)")
                }
            }
            .foregroundStyle(selected ? Color.white : SokobanPalette.ink)
            .frame(maxWidth: .infinity, minHeight: cleared ? 64 : 46)
            .background(
                selected ? SokobanPalette.player : SokobanPalette.key,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(SokobanPalette.wallEdge, lineWidth: selected ? 3 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sokoban.pick.\(number)")
    }
}

/// 用色块画出当前关。格子太小时可以滚动，避免人和箱子缩成一点。
struct SokobanBoard: View {
    var model: SokobanModel
    var onMove: (SokobanDirection) -> Void

    /// 格子之间的缝。墙色从缝里露出来。
    private let gutter: CGFloat = 2
    /// 再小就看不清人、箱子和地上的记号。
    private let minimumCell: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let metrics = metrics(in: geo.size)
            ScrollView([.horizontal, .vertical]) {
                playableGrid(metrics)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .scrollDisabled(!metrics.scrolls)
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("sokoban.board")
        .accessibilityLabel("推箱子棋盘")
        .accessibilityValue(model.token)
    }

    /// 能放下就放大到铺满，放不下就保持最小格子并滚动。
    private func metrics(in size: CGSize) -> BoardMetrics {
        let cols = CGFloat(max(model.cols, 1))
        let rows = CGFloat(max(model.rows, 1))
        let fitted = min(
            (size.width - gutter * (cols - 1)) / cols,
            (size.height - gutter * (rows - 1)) / rows
        )
        let cell = max(fitted, minimumCell)
        let boardWidth = cell * cols + gutter * (cols - 1)
        let boardHeight = cell * rows + gutter * (rows - 1)
        let scrolls = boardWidth > size.width + 1 || boardHeight > size.height + 1
        return BoardMetrics(cell: cell, boardWidth: boardWidth, boardHeight: boardHeight, scrolls: scrolls)
    }

    /// 棋盘放得下时，滑动走一步。需要滚动时不抢手势。
    @ViewBuilder
    private func playableGrid(_ metrics: BoardMetrics) -> some View {
        if metrics.scrolls {
            grid(metrics)
        } else {
            grid(metrics).gesture(swipe)
        }
    }

    /// 按格子尺寸把整张图排出来。
    private func grid(_ metrics: BoardMetrics) -> some View {
        VStack(spacing: gutter) {
            ForEach(0..<model.rows, id: \.self) { row in
                HStack(spacing: gutter) {
                    ForEach(0..<model.cols, id: \.self) { col in
                        cellView(GridPoint(row: row, col: col))
                            .frame(width: metrics.cell, height: metrics.cell)
                    }
                }
            }
        }
        .frame(width: metrics.boardWidth, height: metrics.boardHeight)
        .background(SokobanPalette.wall)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SokobanPalette.wallEdge, lineWidth: 2)
        }
    }

    /// 一格：墙或地板，地上的目标记号，再叠箱子和人。
    private func cellView(_ point: GridPoint) -> some View {
        ZStack {
            Rectangle()
                .fill(model.walls.contains(point) ? SokobanPalette.wall : SokobanPalette.floor)
            if model.targets.contains(point) {
                SokobanTargetMark()
            }
            if model.boxes.contains(point) {
                SokobanCrate()
            }
            if model.player == point {
                SokobanPerson()
            }
        }
    }

    /// 在棋盘上滑动一步，和方向按钮走同一个方法。棋盘需要滚动时把滑动留给滚动。
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { value in
            let dx = value.translation.width
            let dy = value.translation.height
            if abs(dx) > abs(dy) {
                onMove(dx > 0 ? .right : .left)
            } else {
                onMove(dy > 0 ? .down : .up)
            }
        }
    }
}

/// 一局棋盘排出来之后的尺寸。
private struct BoardMetrics {
    var cell: CGFloat
    var boardWidth: CGFloat
    var boardHeight: CGFloat
    var scrolls: Bool
}

/// 站着的人：头发、头、身体、两条腿。没有帽子和商标外形。
struct SokobanPerson: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: s * 0.46, height: s * 0.12)
                    .offset(y: s * 0.38)
                Capsule()
                    .fill(SokobanPalette.playerLeg)
                    .frame(width: s * 0.16, height: s * 0.28)
                    .offset(x: -s * 0.12, y: s * 0.26)
                Capsule()
                    .fill(SokobanPalette.playerLeg)
                    .frame(width: s * 0.16, height: s * 0.28)
                    .offset(x: s * 0.12, y: s * 0.26)
                RoundedRectangle(cornerRadius: s * 0.16, style: .continuous)
                    .fill(SokobanPalette.player)
                    .frame(width: s * 0.52, height: s * 0.34)
                    .offset(y: s * 0.02)
                Circle()
                    .fill(SokobanPalette.skin)
                    .frame(width: s * 0.40, height: s * 0.40)
                    .offset(y: -s * 0.24)
                    .overlay {
                        SokobanFace(scale: s)
                            .offset(y: -s * 0.24)
                    }
                Capsule()
                    .fill(SokobanPalette.hair)
                    .frame(width: s * 0.40, height: s * 0.18)
                    .offset(y: -s * 0.36)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// 脸上的两点。只占头部中间，避免画成某个已知角色。
private struct SokobanFace: View {
    var scale: CGFloat

    var body: some View {
        HStack(spacing: scale * 0.08) {
            Circle().frame(width: scale * 0.05, height: scale * 0.05)
            Circle().frame(width: scale * 0.05, height: scale * 0.05)
        }
        .foregroundStyle(SokobanPalette.hair)
        .offset(y: scale * 0.02)
    }
}

/// 木箱：方盒、横板和一条竖带。轮廓是箱子，不是地上的叉号。
struct SokobanCrate: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let inset = s * 0.16
            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: s * 0.62, height: s * 0.12)
                    .offset(y: s * 0.36)
                RoundedRectangle(cornerRadius: s * 0.06, style: .continuous)
                    .fill(SokobanPalette.box)
                    .overlay {
                        RoundedRectangle(cornerRadius: s * 0.06, style: .continuous)
                            .strokeBorder(SokobanPalette.pieceEdge, lineWidth: max(2, s * 0.07))
                    }
                    .padding(inset)
                VStack(spacing: s * 0.07) {
                    Rectangle().frame(height: max(2, s * 0.045))
                    Rectangle().frame(height: max(2, s * 0.045))
                    Rectangle().frame(height: max(2, s * 0.045))
                }
                .foregroundStyle(SokobanPalette.pieceEdge)
                .padding(.horizontal, inset + s * 0.05)
                .padding(.vertical, inset + s * 0.07)
                Rectangle()
                    .fill(SokobanPalette.pieceEdge)
                    .frame(width: max(2, s * 0.055))
                    .padding(.vertical, inset + s * 0.03)
            }
        }
    }
}

/// 地上的目标：一个叉号，没有体积，也不挡住箱子的轮廓。
struct SokobanTargetMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            Path { path in
                let a = s * 0.08
                let b = s * 0.92
                path.move(to: CGPoint(x: a, y: a))
                path.addLine(to: CGPoint(x: b, y: b))
                path.move(to: CGPoint(x: b, y: a))
                path.addLine(to: CGPoint(x: a, y: b))
            }
            .stroke(SokobanPalette.target, style: StrokeStyle(lineWidth: max(3, s * 0.11), lineCap: .round))
        }
    }
}

/// 棋盘下面的方向按钮。过关后变淡，点了也不会推动棋子，限制写在模型里。
struct SokobanPad: View {
    var locked: Bool
    var onMove: (SokobanDirection) -> Void

    var body: some View {
        VStack(spacing: 8) {
            key("上", "pad.up", .up)
            HStack(spacing: 8) {
                key("左", "pad.left", .left)
                key("下", "pad.down", .down)
                key("右", "pad.right", .right)
            }
        }
        .opacity(locked ? 0.4 : 1)
    }

    /// 一颗方向键。白底深边，和页面底色分开。标识给模拟器检查用。
    private func key(_ title: String, _ identifier: String, _ direction: SokobanDirection) -> some View {
        Button {
            onMove(direction)
        } label: {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(SokobanPalette.ink)
                .frame(width: 76, height: 48)
                .background(SokobanPalette.key, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(SokobanPalette.wallEdge, lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// 推箱子自己的色块。不放到别的游戏里复用。
enum SokobanPalette {
    static let wall = Color(red: 0.24, green: 0.16, blue: 0.12)
    static let wallEdge = Color(red: 0.16, green: 0.10, blue: 0.08)
    static let floor = Color(red: 0.96, green: 0.90, blue: 0.80)
    static let target = Color(red: 0.78, green: 0.16, blue: 0.14)
    static let box = Color(red: 0.86, green: 0.55, blue: 0.24)
    static let pieceEdge = Color(red: 0.36, green: 0.20, blue: 0.08)
    static let player = Color(red: 0.12, green: 0.48, blue: 0.58)
    static let playerLeg = Color(red: 0.10, green: 0.28, blue: 0.40)
    static let skin = Color(red: 0.96, green: 0.78, blue: 0.62)
    static let hair = Color(red: 0.25, green: 0.16, blue: 0.12)
    static let key = Color.white
    static let ink = Color(red: 0.12, green: 0.10, blue: 0.09)
}
