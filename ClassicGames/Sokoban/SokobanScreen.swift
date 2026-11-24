import SwiftUI

/// 推箱子这一局。外框负责返回和总纪录，这里画关卡、棋盘和选关。
struct SokobanScreen: View {
    @Environment(SokobanAudio.self) private var audio
    @Environment(ScoreStore.self) private var scores
    @State private var model = SokobanModel()
    @State private var showPicker = false
    /// 走、推、顶墙的过渡。重开和换关会把它打断。
    @State private var motion = SokobanMotion()
    /// 棋盘放得下是 off。停在 28pt 仍超出时是 on，并带上双指平移的偏移。
    @State private var panStatus = "off"
    /// 格子尺寸和棋盘左上角，给点地换算手指落在哪一格。
    @State private var layoutStatus = "cell:0;ox:0;oy:0;gutter:2"

    var body: some View {
        GameFrame(
            id: .sokoban,
            title: "推箱子",
            score: scoreOnScreen,
            scorePrefix: "步数",
            // 步数还停在上一格时，先不把这一局交给外框，避免用少 1 的步数写纪录。看解的过关不参加比较。
            isOver: model.won && model.winCounts && motion.shownSteps == nil,
            banner: nil,
            rule: .lowerOnClear,
            onRestart: restart
        ) {
            VStack(spacing: 12) {
                levelBar
                Text(verbatim: bestLine)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(SokobanPalette.target)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sokoban.best")
                SokobanBoard(
                    model: model,
                    travel: motion.travel,
                    progress: motion.progress,
                    playbackBoxes: motion.playbackBoxes,
                    onMove: move,
                    onTap: tapFloor,
                    onPanStatus: { panStatus = $0 },
                    onLayout: { layoutStatus = $0 }
                )
                if model.won {
                    winRow
                }
                Text(verbatim: model.notice)
                    .font(.subheadline)
                    .foregroundStyle(SokobanPalette.target)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .accessibilityIdentifier("sokoban.notice")
                historyRow
                SokobanPad(locked: model.won, onMove: move)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(alignment: .top) {
            HStack(spacing: 4) {
                Text(verbatim: motion.label)
                    .accessibilityIdentifier("sokoban.motion")
                    .accessibilityLabel(motion.label)
                    .accessibilityValue(motion.label)
                Text(verbatim: panStatus)
                    .accessibilityIdentifier("sokoban.pan")
                    .accessibilityLabel(panStatus)
                    .accessibilityValue(panStatus)
                Text(verbatim: layoutStatus)
                    .accessibilityIdentifier("sokoban.layout")
                    .accessibilityLabel(layoutStatus)
                    .accessibilityValue(layoutStatus)
            }
            .font(.system(size: 1))
            .foregroundStyle(SokobanPalette.ink.opacity(0.02))
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showPicker) {
            SokobanLevelPicker(current: model.levelNumber) { number in
                motion.cancel()
                audio.cancelPendingClear()
                model.load(number)
                showPicker = false
            }
        }
    }

    /// 画面上的步数。过渡播完之前停在出发格，模型和外框用的是终局。
    private var scoreOnScreen: Int {
        motion.shownSteps ?? model.steps
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

    /// 撤销和重做各一格。播放中的过渡直接丢掉，不排队。成功时立刻停在恢复后的局面。
    private func undo() {
        guard !motion.busy else { return }
        guard model.undo() else { return }
        motion.cancel()
        audio.cancelPendingClear()
    }

    /// 把刚撤销的那一格放回来。没有可重做的步则画面不动。
    private func redo() {
        guard !motion.busy else { return }
        guard model.redo() else { return }
        motion.cancel()
        audio.cancelPendingClear()
    }

    /// 撤销、重做、提示和看解。播放中的过渡直接丢掉，不排队。
    private var historyRow: some View {
        HStack(spacing: 8) {
            historyButton("撤销", "sokoban.undo", undo)
            historyButton("重做", "sokoban.redo", redo)
            historyButton("提示", "sokoban.hint", hint)
            historyButton("看解", "sokoban.solution", showSolution)
            Spacer(minLength: 0)
        }
    }

    /// 和选关同一套按键样子。空栈时点下去局面不变。
    private func historyButton(_ title: String, _ identifier: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SokobanPalette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SokobanPalette.key, in: Capsule())
            .overlay {
                Capsule().strokeBorder(SokobanPalette.wallEdge, lineWidth: 1.5)
            }
            .accessibilityIdentifier(identifier)
    }

    /// 过关后才能进下一关。最后一关没有下一关。
    private var winRow: some View {
        HStack(spacing: 12) {
            SokobanWinMark()
            if model.levelNumber < SokobanLevels.count {
                Button("下一关") { advance() }
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

    /// 按这一步的结果发声并播放过渡。过渡还在播就丢掉，不排队。步数没加是顶墙或推不动，不响。人动而箱子没动才有脚步。过关短乐等这一格过渡结束。
    private func move(_ direction: SokobanDirection) {
        guard !motion.busy else { return }
        let stepsBefore = model.steps
        let boxesBefore = model.boxes
        let playerBefore = model.player
        let wonBefore = model.won
        model.move(direction)
        if model.steps == stepsBefore {
            // 过关之后的按键不顶墙。局面没变才是顶墙或推不动。
            guard !wonBefore else { return }
            motion.start(SokobanTravel(kind: .bump, direction: direction, from: playerBefore, to: playerBefore))
            return
        }
        let pushed = model.boxes != boxesBefore
        if !pushed {
            audio.playFootstep()
        }
        if !wonBefore && model.won {
            // 外框要等画面步数追上才记。这里先把终局步数交出去，重开打断过渡也不会少记。
            scores.recordLower(.sokoban, score: model.steps)
            audio.playClear(afterMilliseconds: pushed ? 180 : 140)
        }
        let boxFrom = pushed ? model.player : nil
        let boxTo = pushed ? model.player.moving(direction) : nil
        motion.start(SokobanTravel(
            kind: pushed ? .push : .walk,
            direction: direction,
            from: playerBefore,
            to: model.player,
            boxFrom: boxFrom,
            boxTo: boxTo
        ), stepsOnScreen: stepsBefore)
    }

    /// 重新开始立刻停在这一关开局，没播完的格子不再滑。
    private func restart() {
        motion.cancel()
        audio.cancelPendingClear()
        model.restart()
    }

    /// 下一关立刻进入开局。还没过关时模型自己不动。
    private func advance() {
        motion.cancel()
        audio.cancelPendingClear()
        model.advance()
    }

    /// 点空地或空目标。模型先到终局，画面再按每一格的走或推滑过去，格与格之间不空档。
    private func tapFloor(_ point: GridPoint) {
        guard !motion.busy else { return }
        let playerBefore = model.player
        let boxesBefore = model.boxes
        let stepsBefore = model.steps
        let wonBefore = model.won
        let taken = model.walkTo(point)
        guard !taken.isEmpty else { return }
        play(
            SokobanPlayback(steps: taken, player: playerBefore, boxes: boxesBefore, stepsAtStart: stepsBefore),
            wonBefore: wonBefore,
            recordWin: true
        )
    }

    /// 提示只走官方解的下一格，用单格的走或推，不接成路径。
    private func hint() {
        guard !motion.busy else { return }
        let playerBefore = model.player
        let boxesBefore = model.boxes
        let stepsBefore = model.steps
        let wonBefore = model.won
        guard let step = model.hint() else { return }
        if !step.pushed {
            audio.playFootstep()
        }
        if !wonBefore && model.won {
            scores.recordLower(.sokoban, score: model.steps)
            audio.playClear(afterMilliseconds: step.pushed ? 180 : 140)
        }
        motion.start(SokobanTravel(
            kind: step.pushed ? .push : .walk,
            direction: step.direction,
            from: playerBefore,
            to: model.player,
            boxFrom: step.pushed ? model.player : nil,
            boxTo: step.pushed ? model.player.moving(step.direction) : nil
        ), stepsOnScreen: stepsBefore)
    }

    /// 看解从这一关开局沿路径播放。这次过关不写纪录。
    private func showSolution() {
        guard !motion.busy else { return }
        let playback = model.showSolution()
        guard !playback.steps.isEmpty else { return }
        play(playback, wonBefore: false, recordWin: false)
    }

    /// 按已经写入的步骤播放。格与格之间不再加时间。
    private func play(_ playback: SokobanPlayback, wonBefore: Bool, recordWin: Bool) {
        var player = playback.player
        var boxes = playback.boxes
        var cells: [SokobanPathCell] = []
        for step in playback.steps {
            let next = player.moving(step.direction)
            let boxFrom = step.pushed ? next : nil
            let boxTo = step.pushed ? next.moving(step.direction) : nil
            cells.append(SokobanPathCell(
                travel: SokobanTravel(
                    kind: step.pushed ? .push : .walk,
                    direction: step.direction,
                    from: player,
                    to: next,
                    boxFrom: boxFrom,
                    boxTo: boxTo
                ),
                boxes: boxes
            ))
            if let boxFrom, let boxTo {
                boxes.remove(boxFrom)
                boxes.insert(boxTo)
            }
            player = next
        }
        let totalMilliseconds = cells.reduce(0) { $0 + $1.travel.kind.milliseconds }
        motion.playPath(cells, stepsAtStart: playback.stepsAtStart) { travel in
            if travel.kind == .walk {
                audio.playFootstep()
            }
        }
        if recordWin, !wonBefore, model.won {
            scores.recordLower(.sokoban, score: model.steps)
        }
        if !wonBefore, model.won {
            audio.playClear(afterMilliseconds: totalMilliseconds)
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

/// 走、推和顶墙的画面。模型先到终局，这里只负责滑过去；重开和换关会作废还没播完的一段。
@MainActor
@Observable
final class SokobanMotion {
    private(set) var travel: SokobanTravel?
    private(set) var progress: CGFloat = 1
    /// 沿路径播放时，箱子先停在这一格开始时的位置。空则用模型里的终局。
    private(set) var playbackBoxes: Set<GridPoint>?
    /// 过渡播完之前，画面步数停在出发的那一格。顶墙不改步数，这里保持空。
    private(set) var shownSteps: Int?
    /// 为真时新的走和推直接丢掉，不排队。
    private(set) var busy = false
    /// 最近一次过渡。检查关掉动画时也留下种类和时长。
    private(set) var label = "idle"
    private var generation = 0

    /// 开始这一格。检查关掉动画时不占住输入，画面直接停在终局。
    func start(_ travel: SokobanTravel, stepsOnScreen: Int? = nil) {
        generation += 1
        let token = generation
        label = travel.kind.label
        playbackBoxes = nil
        guard UIView.areAnimationsEnabled else { return }
        busy = true
        shownSteps = stepsOnScreen
        self.travel = travel
        progress = 0
        let seconds = travel.kind.seconds
        Task { @MainActor in
            await Task.yield()
            guard token == generation else { return }
            withAnimation(.linear(duration: seconds)) {
                self.progress = 1
            } completion: {
                guard token == self.generation else { return }
                self.finish()
            }
        }
    }

    /// 按顺序播放点地或看解的每一格。格与格之间不再加时间。检查关掉动画时只记下每一格的时长。
    func playPath(_ cells: [SokobanPathCell], stepsAtStart: Int, onCell: @escaping (SokobanTravel) -> Void) {
        generation += 1
        let token = generation
        label = "path:" + cells.map(\.travel.kind.label).joined(separator: "+")
        guard UIView.areAnimationsEnabled else {
            for cell in cells {
                onCell(cell.travel)
            }
            return
        }
        busy = true
        show(0, cells, stepsAtStart: stepsAtStart, token: token, onCell: onCell)
    }

    /// 立刻停在模型现在的局面。晚到的完成回调不再改画面。
    func cancel() {
        generation += 1
        finish()
        label = "idle"
    }

    /// 画出路径里的第 index 格，播完立刻接下一格。
    private func show(_ index: Int, _ cells: [SokobanPathCell], stepsAtStart: Int, token: Int, onCell: @escaping (SokobanTravel) -> Void) {
        guard token == generation, cells.indices.contains(index) else {
            finish()
            return
        }
        let cell = cells[index]
        shownSteps = stepsAtStart + index
        playbackBoxes = cell.boxes
        travel = cell.travel
        progress = 0
        onCell(cell.travel)
        let seconds = cell.travel.kind.seconds
        Task { @MainActor in
            await Task.yield()
            guard token == self.generation else { return }
            withAnimation(.linear(duration: seconds)) {
                self.progress = 1
            } completion: {
                guard token == self.generation else { return }
                self.show(index + 1, cells, stepsAtStart: stepsAtStart, token: token, onCell: onCell)
            }
        }
    }

    /// 过渡结束或被打断。步数和箱子回到模型的终局。
    private func finish() {
        travel = nil
        progress = 1
        playbackBoxes = nil
        busy = false
        shownSteps = nil
    }
}

/// 路径上的一格。箱子位置是这一格开始滑之前的局面。
struct SokobanPathCell {
    var travel: SokobanTravel
    var boxes: Set<GridPoint>
}

/// 正在播放的一格。人和被推的箱子从原格滑到终局，模型本身不再等这段。
struct SokobanTravel {
    enum Kind {
        case walk
        case push
        case bump

        /// 模拟器核对用。数字就是这一段的毫秒数。
        var label: String {
            switch self {
            case .walk: "walk:140"
            case .push: "push:180"
            case .bump: "bump:120"
            }
        }

        /// 和 label 里的数字相同，给过关短乐把整段加起来。
        var milliseconds: Int {
            switch self {
            case .walk: 140
            case .push: 180
            case .bump: 120
            }
        }

        /// 设计里的时长。走 140，推 180，顶墙 120。不另定。
        var seconds: Double {
            switch self {
            case .walk: 0.140
            case .push: 0.180
            case .bump: 0.120
            }
        }
    }

    var kind: Kind
    var direction: SokobanDirection
    var from: GridPoint
    var to: GridPoint
    var boxFrom: GridPoint?
    var boxTo: GridPoint?
}

/// 用色块画出当前关。放得下就铺满；格子小到 28pt 仍放不下时，单指仍只走一格，双指才平移。
struct SokobanBoard: View {
    var model: SokobanModel
    var travel: SokobanTravel?
    var progress: CGFloat
    /// 沿路径播放时用这一格开始时的箱子。空则画模型终局。
    var playbackBoxes: Set<GridPoint>?
    var onMove: (SokobanDirection) -> Void
    var onTap: (GridPoint) -> Void
    var onPanStatus: (String) -> Void
    var onLayout: (String) -> Void

    /// 格子之间的缝。墙色从缝里露出来。
    private let gutter: CGFloat = 2
    /// 再小就停住。放不下的部分靠双指看，不再缩小。
    private let minimumCell: CGFloat = 28
    /// 双指平移。单指不改它。换关时回到左上角。
    @State private var pan: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let metrics = metrics(in: geo.size)
            let status = panStatus(metrics)
            let layout = layoutText(metrics, in: geo.size)
            grid(metrics)
                .offset(metrics.scrolls ? pan : .zero)
                .frame(width: geo.size.width, height: geo.size.height, alignment: metrics.scrolls ? .topLeading : .center)
                .clipped()
                .overlay {
                    SokobanBoardTouch(
                        panEnabled: metrics.scrolls,
                        pan: pan,
                        layout: layout,
                        onMove: onMove,
                        onTap: onTap,
                        onPan: { proposed in
                            pan = clamped(proposed, metrics, in: geo.size)
                        }
                    )
                }
                .onChange(of: model.levelNumber) { _, _ in
                    pan = .zero
                }
                .task(id: status) {
                    onPanStatus(status)
                }
                .task(id: layout.label) {
                    onLayout(layout.label)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("sokoban.board")
        .accessibilityLabel("推箱子棋盘")
        .accessibilityValue(model.token)
    }

    /// 模拟器核对平移。放得下是 off。停在 28pt 仍超出时是 on，后面是当前偏移。
    private func panStatus(_ metrics: BoardMetrics) -> String {
        guard metrics.scrolls else { return "off" }
        return "on:\(Int(pan.width.rounded())):\(Int(pan.height.rounded()))"
    }

    /// 棋盘左上角和格子边长。点地用它判断手指落在哪一格，缝不算格子。
    private func layoutText(_ metrics: BoardMetrics, in size: CGSize) -> SokobanBoardLayout {
        let originX = metrics.scrolls ? pan.width : (size.width - metrics.boardWidth) / 2
        let originY = metrics.scrolls ? pan.height : (size.height - metrics.boardHeight) / 2
        let label = "cell:\(metrics.cell);ox:\(originX);oy:\(originY);gutter:\(gutter)"
        return SokobanBoardLayout(
            originX: originX,
            originY: originY,
            cell: metrics.cell,
            gutter: gutter,
            rows: model.rows,
            cols: model.cols,
            label: label
        )
    }

    /// 双指不能把棋盘拖出空白。左上是 0，往右下看是负数。
    private func clamped(_ proposed: CGSize, _ metrics: BoardMetrics, in size: CGSize) -> CGSize {
        let maxX = max(0, metrics.boardWidth - size.width)
        let maxY = max(0, metrics.boardHeight - size.height)
        return CGSize(
            width: min(0, max(-maxX, proposed.width)),
            height: min(0, max(-maxY, proposed.height))
        )
    }

    /// 能放下就放大到铺满。降到 28pt 仍放不下就停住，多出来的部分用双指看。
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

    /// 按格子尺寸把整张图排出来。过渡中的人和箱子画在格子上面，避免被旁边的格子盖住。
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
        .overlay(alignment: .topLeading) {
            movingPieces(metrics)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SokobanPalette.wallEdge, lineWidth: 2)
        }
    }

    /// 一格：墙或地板，地上的目标记号，再叠箱子和人。正在滑的棋子改由浮层画。
    private func cellView(_ point: GridPoint) -> some View {
        ZStack {
            Rectangle()
                .fill(model.walls.contains(point) ? SokobanPalette.wall : SokobanPalette.floor)
            if model.targets.contains(point) {
                SokobanTargetMark()
            }
            if drawnBoxes.contains(point), !hidesMovingBox(at: point) {
                SokobanCrate()
            }
            if model.player == point, travel == nil {
                SokobanPerson(facing: model.facing)
            }
        }
    }

    /// 这一格要画的箱子。路径播放用滑之前的位置，单步过渡用模型终局。
    private var drawnBoxes: Set<GridPoint> {
        playbackBoxes ?? model.boxes
    }

    /// 正在滑的箱子不留在格子里，改由浮层从原格画到新格。
    private func hidesMovingBox(at point: GridPoint) -> Bool {
        if playbackBoxes != nil {
            return point == travel?.boxFrom || point == travel?.boxTo
        }
        return point == travel?.boxTo
    }

    /// 人和被推的箱子沿这一格移动。顶墙只移出 0.2 格再回来。
    @ViewBuilder
    private func movingPieces(_ metrics: BoardMetrics) -> some View {
        if let travel {
            if let boxFrom = travel.boxFrom, let boxTo = travel.boxTo {
                SokobanCrate()
                    .frame(width: metrics.cell, height: metrics.cell)
                    .offset(pieceOffset(slide(travel, from: boxFrom, to: boxTo), metrics))
            }
            SokobanPerson(facing: travel.kind == .bump ? model.facing : travel.direction)
                .frame(width: metrics.cell, height: metrics.cell)
                .offset(pieceOffset(slide(travel, from: travel.from, to: travel.to), metrics))
        }
    }

    /// 这一格在棋盘上的位置。走和推线性插值，顶墙前半出去、后半回来。
    private func slide(_ travel: SokobanTravel, from: GridPoint, to: GridPoint) -> (row: CGFloat, col: CGFloat) {
        switch travel.kind {
        case .bump:
            let out = progress < 0.5 ? progress / 0.5 : (1 - progress) / 0.5
            let shift = 0.2 * out
            return (CGFloat(from.row) + CGFloat(travel.direction.rowDelta) * shift, CGFloat(from.col) + CGFloat(travel.direction.colDelta) * shift)
        case .walk, .push:
            return (mix(CGFloat(from.row), CGFloat(to.row), progress), mix(CGFloat(from.col), CGFloat(to.col), progress))
        }
    }

    /// 格子坐标换成棋盘左上角起算的偏移。缝也算进跨格的距离。
    private func pieceOffset(_ cell: (row: CGFloat, col: CGFloat), _ metrics: BoardMetrics) -> CGSize {
        let stride = metrics.cell + gutter
        return CGSize(width: cell.col * stride, height: cell.row * stride)
    }

    private func mix(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

}

/// 棋盘在点击区域里的位置。缝不属于相邻的格。
struct SokobanBoardLayout: Equatable {
    var originX: CGFloat
    var originY: CGFloat
    var cell: CGFloat
    var gutter: CGFloat
    var rows: Int
    var cols: Int
    var label: String

    /// 点在格子里才返回。落在缝上、棋盘外，都是空。
    func cell(at point: CGPoint) -> GridPoint? {
        let x = point.x - originX
        let y = point.y - originY
        let stride = cell + gutter
        guard stride > 0, x >= 0, y >= 0 else { return nil }
        let col = Int(x / stride)
        let row = Int(y / stride)
        let localX = x - CGFloat(col) * stride
        let localY = y - CGFloat(row) * stride
        guard localX < cell, localY < cell else { return nil }
        guard row >= 0, col >= 0, row < rows, col < cols else { return nil }
        return GridPoint(row: row, col: col)
    }
}

/// 棋盘上的手指。单指先到 24pt 的那一轴走一格；不到 24pt 且落在同一格才是点。
private struct SokobanBoardTouch: UIViewRepresentable {
    var panEnabled: Bool
    var pan: CGSize
    var layout: SokobanBoardLayout
    var onMove: (SokobanDirection) -> Void
    var onTap: (GridPoint) -> Void
    var onPan: (CGSize) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let one = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.oneFinger(_:)))
        one.minimumNumberOfTouches = 1
        one.maximumNumberOfTouches = 1
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        // 手指没移动时平移手势会失败，这时才算点。滑出去了就不点。
        tap.require(toFail: one)
        let two = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.twoFinger(_:)))
        two.minimumNumberOfTouches = 2
        two.maximumNumberOfTouches = 2
        view.addGestureRecognizer(one)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(two)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.panEnabled = panEnabled
        context.coordinator.pan = pan
        context.coordinator.layout = layout
        context.coordinator.onMove = onMove
        context.coordinator.onTap = onTap
        context.coordinator.onPan = onPan
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// 记下这一下手指有没有越过 24pt，以及双指开始时棋盘的位置。
    final class Coordinator: NSObject {
        var panEnabled = false
        var pan: CGSize = .zero
        var layout = SokobanBoardLayout(originX: 0, originY: 0, cell: 1, gutter: 2, rows: 0, cols: 0, label: "")
        var onMove: (SokobanDirection) -> Void = { _ in }
        var onTap: (GridPoint) -> Void = { _ in }
        var onPan: (CGSize) -> Void = { _ in }
        private var locked: SokobanDirection?
        private var origin: CGSize = .zero
        private var startCell: GridPoint?

        /// 单指。先到 24pt 的轴在松手时走一格。不到 24pt 且起落在同一格，才是点地。
        @objc func oneFinger(_ gesture: UIPanGestureRecognizer) {
            if gesture.numberOfTouches > 1 {
                locked = nil
                startCell = nil
                return
            }
            let translation = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .began:
                locked = nil
                startCell = layout.cell(at: gesture.location(in: gesture.view))
            case .changed:
                guard locked == nil else { return }
                // 同一采样里两轴都过了 24pt 时，取绝对值更大的那一轴。
                if abs(translation.x) >= 24, abs(translation.x) >= abs(translation.y) {
                    locked = translation.x > 0 ? .right : .left
                } else if abs(translation.y) >= 24 {
                    locked = translation.y > 0 ? .down : .up
                }
            case .ended:
                if let locked {
                    onMove(locked)
                } else if hypot(translation.x, translation.y) < 24,
                          let startCell,
                          let endCell = layout.cell(at: gesture.location(in: gesture.view)),
                          startCell == endCell {
                    onTap(endCell)
                }
                locked = nil
                startCell = nil
            case .cancelled, .failed:
                locked = nil
                startCell = nil
            default:
                break
            }
        }

        /// 几乎没移动的点。滑过 24pt 的那下不会进这里。
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let cell = layout.cell(at: gesture.location(in: gesture.view)) else { return }
            onTap(cell)
        }

        /// 双指只平移。格子还没被 28pt 卡住时不改位置，也不走步。
        @objc func twoFinger(_ gesture: UIPanGestureRecognizer) {
            guard panEnabled else { return }
            let translation = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .began:
                origin = pan
            case .changed, .ended:
                onPan(CGSize(width: origin.width + translation.x, height: origin.height + translation.y))
            default:
                break
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

/// 站着的人：头发、头、身体、两条腿。脸只表示朝向，不重画身体。
struct SokobanPerson: View {
    var facing: SokobanDirection = .down

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
                SokobanFace(scale: s, facing: facing)
                    .offset(y: -s * 0.24)
                Capsule()
                    .fill(SokobanPalette.hair)
                    .frame(width: s * 0.40, height: facing == .up ? s * 0.36 : s * 0.18)
                    .offset(y: facing == .up ? -s * 0.26 : -s * 0.36)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// 脸上的朝向。鼻子伸出头部轮廓，后脑不画五官。
private struct SokobanFace: View {
    var scale: CGFloat
    var facing: SokobanDirection

    var body: some View {
        switch facing {
        case .down:
            ZStack {
                eyes
                nose
                    .frame(width: max(4, scale * 0.10), height: max(6, scale * 0.18))
                    .offset(y: scale * 0.18)
            }
        case .left:
            side(noseSign: -1)
        case .right:
            side(noseSign: 1)
        case .up:
            Color.clear
        }
    }

    /// 朝屏幕的两只眼睛。
    private var eyes: some View {
        HStack(spacing: scale * 0.08) {
            Circle().frame(width: max(2, scale * 0.05), height: max(2, scale * 0.05))
            Circle().frame(width: max(2, scale * 0.05), height: max(2, scale * 0.05))
        }
        .foregroundStyle(SokobanPalette.hair)
        .offset(y: scale * 0.02)
    }

    /// 侧脸：一只眼睛，鼻子朝这一侧伸出轮廓。
    private func side(noseSign: CGFloat) -> some View {
        ZStack {
            Circle()
                .frame(width: max(2, scale * 0.05), height: max(2, scale * 0.05))
                .foregroundStyle(SokobanPalette.hair)
                .offset(x: noseSign * scale * 0.08, y: scale * 0.02)
            nose
                .frame(width: max(6, scale * 0.22), height: max(3, scale * 0.08))
                .offset(x: noseSign * scale * 0.18)
        }
    }

    /// 鼻子用深色，和肤色分开，缩小时仍能看出伸出的方向。
    private var nose: some View {
        Capsule().fill(SokobanPalette.hair)
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
