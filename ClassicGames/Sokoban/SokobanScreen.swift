import SwiftUI
import UIKit
import CoreText
#if DEBUG
import os
#endif

/// Normal production destination, reached from the unchanged home navigation.
/// Scroll metrics, never the board. No pad, path playback, hint, zoom or pan.
struct SokobanScreen: View {
    @Environment(SokobanAudio.self) private var audio
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model = SokobanModel()
    @State private var motion = SokobanMotion()
    @State private var showPicker = false
    @State private var showPause = false
    @State private var showRecords = false
    @State private var rootSize = CGSize.zero
    @State private var rootInsets = EdgeInsets()
    @State private var confirmRestart = false
    @State private var confirmLeave = false
    @State private var showPauseHelp = false
    @State private var pendingDestination = ""
    @State private var frames: [String: CGRect] = [:]
    @State private var layoutStatus = "cell:0;ox:0;oy:0;gutter:0"
    @State private var boardFit = SokobanBoardFit.calculate(width: 0, height: 0, rows: 1, cols: 1)
    @State private var hideFirstHint = false
    @State private var showShop = false
    @State private var shopHighlight: SokobanShopHighlight?
    @State private var hintPhase: HintPhase = .idle
    @State private var hintFail: SokobanHintFail?
    @State private var dpadRepeat = SokobanDPadRepeat()
    @State private var dpadPressed: SokobanDirection?
    @State private var dpadTimer: Timer?

    private enum HintPhase { case idle, thinking, playing }

    private var inputLocked: Bool {
        motion.busy
            || hintPhase != .idle
            || showShop || showPause || showRecords || confirmRestart || confirmLeave || showPicker
            || model.visitKind == .completedNow
            || model.isReadOnlyCompletion
            || !model.hasBoard
    }

    var body: some View {
        GeometryReader { root in
            let reserved = reservedBoardFit(in: root)
            let showingResult = model.visitKind == .completedNow && hintPhase != .playing && hintPhase != .thinking
            VStack(spacing: 8) {
                header.sokobanMeasure("header")
                infoRegion
                if model.hasBoard {
                    ZStack {
                        VStack(spacing: 0) {
                            ZStack {
                                SokobanNativeCanvas(model: model, travel: motion.travel, progress: motion.progress, fit: reserved)
                                SokobanSingleSwipe(onMove: move)
                                    .frame(width: reserved.width, height: reserved.height)
                                    .sokobanMeasure("drawn")
                                if showsFirstHint(fit: reserved) { firstHint(fit: reserved) }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onChange(of: "\(root.size)-\(model.levelNumber)-\(reserved.cell)", initial: true) { _, _ in
                                boardFit = reserved
                                layoutStatus = "cell:\(reserved.cell);ox:\((root.size.width-reserved.width)/2);oy:0;gutter:\(reserved.gap)"
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("sokoban.board")
                            .accessibilityLabel("棋盘，单次滑动移动一格")
                            .accessibilityValue(model.token)
                            .sokobanMeasure("board")
                            .allowsHitTesting(!showingResult)
                            if !showingResult {
                                controls.sokobanMeasure("controls")
                                    .padding(.bottom, 12)
                            }
                        }
                        if showingResult {
                            resultLayer
                                .allowsHitTesting(!showPicker)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(model.visitKind == .scoreOnly ? "仅有已存成绩，暂无可恢复棋盘" : "此局暂时无法恢复，原档未改动")
                            .padding().accessibilityIdentifier("sokoban.board.unavailable")
                    }.frame(maxHeight: .infinity)
                    if !showingResult {
                        controls.sokobanMeasure("controls")
                    }
                }
            }
            .padding(.horizontal, 16)
            .background {
                Image("bg_garden_play")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            .background(alignment: .topLeading) { observations(root) }
            .onChange(of: "\(root.size)-\(root.safeAreaInsets)", initial: true) { _, _ in
                rootSize = root.size; rootInsets = root.safeAreaInsets
            }
            .onAppear {
                if SokobanLaunchIntent.openPickerOnAppear {
                    SokobanLaunchIntent.openPickerOnAppear = false
                    showPicker = true
                }
                #if DEBUG
                installTestHooks()
                #endif
            }
        }
        .coordinateSpace(name: "sokoban.screen")
        .tint(SokobanPalette.target)
        .toolbar(.hidden, for: .navigationBar).navigationBarBackButtonHidden(true)
        .onPreferenceChange(SokobanFramesKey.self) { mergeFrames($0) }
        .overlay {
            if showPicker {
                SokobanLevelPicker(
                    current: model.levelNumber,
                    coins: model.coins,
                    totalStars: model.totalStars,
                    starsForLevel: { model.persistenceBestStars(level: $0) },
                    onClose: { showPicker = false },
                    onOpenShop: { showPicker = false; shopHighlight = nil; showShop = true }
                ) { number in
                    motion.cancel(); audio.cancelPendingClear(); model.load(number); showPicker = false
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .overlay {
            if !showPicker && (showShop || hintFail != nil || showPause || showRecords || confirmRestart || confirmLeave) {
                ZStack {
                    Color.black.opacity(0.32).ignoresSafeArea()
                    if showShop {
                        SokobanShopSheet(
                            wallet: model.persistenceWallet,
                            highlight: shopHighlight,
                            compact: typeSize.isAccessibilitySize,
                            onBuy: { model.purchase($0) },
                            onClose: { showShop = false; shopHighlight = nil }
                        )
                    } else if let fail = hintFail {
                        hintFailCard(fail)
                    } else if confirmLeave { leaveCard }
                    else if confirmRestart { resetCard }
                    else if showRecords { recordsCard }
                    else { pauseCard }
                }
            }
        }
        #if DEBUG
        .background(alignment: .topLeading) { hiddenTestDiagnostics }
        #endif
    }
    private enum SokobanAppFont {
        static let name = "ZCOOLKuaiLe-Regular"
        static let register: Void = {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { return }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }()
    }
    private func kuaiLe(_ style: Font.TextStyle, size: CGFloat) -> Font {
        _ = SokobanAppFont.register
        return .custom(SokobanAppFont.name, size: size, relativeTo: style)
    }
    private var inkBrown: Color { Color(red: 78/255, green: 48/255, blue: 24/255) } // #4E3018
    private var inkGreen: Color { Color(red: 46/255, green: 114/255, blue: 72/255) } // #2E7248
    private var pillInsets: EdgeInsets { EdgeInsets(top: 12, leading: 18, bottom: 14, trailing: 18) }
    private var plaqueInsets: EdgeInsets { EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20) }
    private func strokedTitle(_ text: String, size: CGFloat, identifier: String) -> some View {
        let fill = Color(red: 1, green: 253/255, blue: 242/255) // #FFFDF2
        let stroke = Color(red: 112/255, green: 66/255, blue: 30/255) // #70421E
        return ZStack {
            ForEach([-1, 0, 1], id: \.self) { x in
                ForEach([-1, 0, 1], id: \.self) { y in
                    if x != 0 || y != 0 {
                        Text(text).font(kuaiLe(.title2, size: size)).foregroundStyle(stroke).offset(x: CGFloat(x), y: CGFloat(y))
                            .accessibilityHidden(true)
                    }
                }
            }
            Text(text).font(kuaiLe(.title2, size: size)).foregroundStyle(fill)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(text)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    private func pillBackground() -> some View {
        Image("hud_pill_capsule")
            .resizable(capInsets: pillInsets, resizingMode: .stretch)
    }
    private var header: some View {
        let titleId = model.isReadOnlyCompletion ? "sokoban.completed.title" : (model.won ? "sokoban.win" : "chrome.title")
        let compact = typeSize.isAccessibilitySize
        return HStack(alignment: .center, spacing: 8) {
            Button { requestDestination("home") } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(inkBrown)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(Color(red: 1, green: 253/255, blue: 242/255).opacity(0.94))
                    )
                    .overlay(Circle().strokeBorder(Color(red: 176/255, green: 122/255, blue: 74/255), lineWidth: 1.4))
            }
            .accessibilityLabel("返回").accessibilityIdentifier("chrome.back").sokobanMeasure("back")
            if !compact {
                ZStack {
                    Image("hud_title_plaque")
                        .resizable(capInsets: plaqueInsets, resizingMode: .stretch)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)
                    strokedTitle(model.completionTitle, size: 24, identifier: titleId)
                        .padding(.horizontal, 18)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: 1)
                    .accessibilityIdentifier(titleId)
                    .accessibilityLabel(model.completionTitle)
            }
            Button { requestDestination("levels") } label: {
                Text("选关")
                    .font(kuaiLe(.subheadline, size: compact ? 20 : 16))
                    .foregroundStyle(inkBrown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, compact ? 5 : 0)
                    .frame(minWidth: 44, minHeight: 44)
                    .background { pillBackground() }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sokoban.levels")
            .accessibilityValue("\(SokobanLevels.count)").sokobanMeasure("levels")
            Button { showRecords = true } label: {
                Text("纪录")
                    .font(kuaiLe(.subheadline, size: compact ? 20 : 16))
                    .foregroundStyle(inkBrown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, compact ? 5 : 0)
                    .frame(minWidth: 44, minHeight: 44)
                    .background { pillBackground() }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sokoban.records.open").sokobanMeasure("records")
        }
    }
    /// One constrained info window holds level / steps / best / save copy.
    /// Height is constant for a type size so a failed-save banner does not move or shrink the board.
    /// AX5 keeps the failed message + retry on the first screen; leftover metrics may scroll.
    private var reservedInfoHeight: CGFloat { typeSize.isAccessibilitySize ? 188 : 100 }
    private func reservedBoardFit(in root: GeometryProxy) -> SokobanBoardFit {
        // GeometryReader is already laid out in the safe area; do not subtract insets again.
        let header: CGFloat = typeSize.isAccessibilitySize ? 72 : 48
        let controls: CGFloat = typeSize.isAccessibilitySize ? 160 : 164
        let spacing: CGFloat = 16
        let compactChrome = header + reservedInfoHeight + controls + spacing
        let width = max(0, root.size.width - 32)
        let slot = max(120, root.size.height - compactChrome)
        // Inset so the #243416 @ 35% / 10pt / y+4 board shadow is not clipped.
        let inset: CGFloat = 16
        let visual = SokobanVisualGrid.make(rows: model.rows, cols: model.cols)
        return SokobanBoardFit.calculate(
            width: max(0, width - inset * 2),
            height: max(100, slot - inset * 2),
            rows: visual.side,
            cols: visual.side,
            gap: 0
        )
    }
    private func showsFirstHint(fit: SokobanBoardFit) -> Bool {
        guard !hideFirstHint, !typeSize.isAccessibilitySize, model.hasBoard,
              model.visitKind == .playing, model.steps == 0, !model.won else { return false }
        let occupied = [model.player] + Array(model.boxes) + Array(model.targets)
        return occupied.allSatisfy { $0.row > 1 }
    }
    private func firstHint(fit: SokobanBoardFit) -> some View {
        VStack {
            HStack(spacing: 4) {
                Text("滑动一次，移动一格").font(.footnote)
                Button { hideFirstHint = true } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("关闭").accessibilityIdentifier("sokoban.hint.close")
            }
            .padding(.leading, 14)
            .background(Color.white.opacity(0.92), in: Capsule())
            .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
            Spacer()
        }
        .padding(.top, 6)
        .frame(width: fit.width, height: fit.height)
        .allowsHitTesting(true)
    }
    private var resultLayer: some View {
        let compact = typeSize.isAccessibilitySize
        let plantHeight: CGFloat = compact ? 40 : 88
        let canAdvance = model.won && !model.isReadOnlyCompletion && model.levelNumber < SokobanLevels.count && !model.isCampaignComplete
        let title = model.completionTitle
        return ZStack {
            Color(red: 1, green: 249/255, blue: 237/255)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0))
            ForEach(1...24, id: \.self) { index in
                Image(String(format: "sokoban_cele_confetti_%02d", index))
                    .resizable().scaledToFit().frame(width: 22, height: 22)
                    .offset(confettiOffset(index))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Image("sokoban_cele_plant_left").resizable().scaledToFit().frame(height: plantHeight)
                    Spacer()
                    Image("sokoban_cele_plant_right").resizable().scaledToFit().frame(height: plantHeight)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            VStack(spacing: compact ? 8 : 10) {
                Spacer(minLength: 8)
                Text(title)
                    .font(compact ? .system(size: 24, weight: .bold) : .largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color(red: 47/255, green: 107/255, blue: 79/255))
                if let settlement = model.lastSettlement {
                    SokobanSettlementBlock(settlement: settlement, compact: compact)
                }
                if let kind = model.lastCompletionKind, let subtitle = celebrationSubtitle(kind) {
                    if kind == .first || kind == .campaign || kind == .newRecord || kind == .tie {
                        Text(subtitle)
                            .font(compact ? .system(size: 18, weight: .semibold) : .subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 47/255, green: 107/255, blue: 79/255))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color(red: 47/255, green: 107/255, blue: 79/255).opacity(0.12), in: Capsule())
                    } else {
                        Text(subtitle)
                            .font(compact ? .system(size: 16, weight: .regular) : .subheadline)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                    }
                }
                if model.lastSettlement == nil {
                    Text("本次 \(model.steps) 步")
                        .font(compact ? .system(size: 22, weight: .bold) : .title2.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let best = model.levelBest {
                        Text("个人最少 \(best) 步")
                            .font(compact ? .system(size: 18, weight: .regular) : .body)
                            .foregroundStyle(SokobanPalette.ink.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                VStack(spacing: 10) {
                    if canAdvance {
                        resultButton("下一关", primary: true, id: "sokoban.next", compact: compact) {
                            if model.saveState == .failed { requestDestination("next") } else { advance() }
                        }
                        resultButton("选择关卡", primary: false, id: "sokoban.result.levels", compact: compact) {
                            requestDestination("levels")
                        }
                        resultButton("再玩一次", primary: false, id: "chrome.restart", compact: compact) { restart() }
                    } else {
                        resultButton("返回选关", primary: true, id: "sokoban.result.levels", compact: compact) {
                            requestDestination("levels")
                        }
                        resultButton("返回首页", primary: false, id: "sokoban.result.home", compact: compact) {
                            requestDestination("home")
                        }
                        resultButton("再玩一次", primary: false, id: "chrome.restart", compact: compact) { restart() }
                    }
                }
                .padding(.horizontal, compact ? 12 : 28)
                Spacer(minLength: plantHeight + 8)
            }
            .padding(.horizontal, 12)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 22,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 22,
                style: .continuous
            )
        )
    }

    private func resultButton(_ title: String, primary: Bool, id: String, compact: Bool = false, action: @escaping () -> Void) -> some View {
        // Full-width capsules sit over the old board hit area. Use a tap gesture
        // (not Button's press-and-drag) so a post-clear swipe cannot advance.
        Text(title)
            .font(compact ? .system(size: 18, weight: .semibold) : .body.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(primary ? Color.white : SokobanPalette.ink)
            .background(
                Capsule().fill(primary ? Color(red: 47/255, green: 107/255, blue: 79/255) : Color.white.opacity(0.92))
            )
            .overlay(
                Capsule().strokeBorder(primary ? Color.clear : Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1)
            )
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(id)
            .accessibilityLabel(title)
    }

    private func celebrationSubtitle(_ kind: SokobanCompletionKind) -> String? {
        switch kind {
        case .first: return "首次完成"
        case .newRecord: return "新纪录"
        case .tie: return "追平纪录"
        case .normal: return nil
        case .lastNotAll: return "还可以继续挑战其他关卡。"
        case .campaign: return "100 关都已完成"
        }
    }
    private func confettiOffset(_ index: Int) -> CGSize {
        let x = ((index * 47) % 160) - 80
        let y = ((index * 31) % 220) - 110
        return CGSize(width: x, height: y)
    }
    private var bestLine: String { model.levelBest.map { "本关纪录 \($0)" } ?? (model.hasUnverifiedPredecessor ? "本关纪录 待核实" : "本关纪录 —") }
    /// Constrained, constant-height info window. Level + failed-save stay on the first
    /// screen at AX5; other metrics may scroll. Board size does not follow this content.
    private func infoPill(_ text: String, id: String, emphasize: Bool = false) -> some View {
        let compact = typeSize.isAccessibilitySize
        return Text(text)
            .font(kuaiLe(.body, size: compact ? 22 : 16))
            .foregroundStyle(emphasize ? inkGreen : inkBrown)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, 12)
            .padding(.vertical, compact ? 6 : 4)
            .frame(minHeight: 44)
            .background { pillBackground() }
            .accessibilityIdentifier(id)
            .accessibilityLabel(text)
    }
    private var infoRegion: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if typeSize.isAccessibilitySize {
                    levelLine.frame(maxWidth: .infinity)
                    saveStatus
                    HStack(alignment: .center, spacing: 8) {
                        if model.visitKind != .completedNow {
                            stepsParCapsule.sokobanMeasure("steps").sokobanMeasure("best")
                                .frame(maxWidth: .infinity)
                        }
                        coinCapsule
                    }
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        levelLine.frame(maxWidth: .infinity)
                        stepsParCapsule.frame(maxWidth: .infinity).sokobanMeasure("steps").sokobanMeasure("best")
                        coinCapsule.frame(maxWidth: .infinity)
                    }
                    saveStatus
                    if let history = model.historicalBest {
                        Text("历史纪录（旧版） \(history)").font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("sokoban.history.best")
                    }
                    if !model.notice.isEmpty {
                        Text(model.notice).font(.footnote).accessibilityIdentifier("sokoban.notice")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .sokobanMeasure("metrics.content")
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, minHeight: reservedInfoHeight, maxHeight: reservedInfoHeight, alignment: .top)
        .clipped()
        .accessibilityIdentifier("sokoban.metrics.scroll")
        .sokobanMeasure("metrics")
    }
    private var levelLine: some View {
        infoPill("第 \(model.levelNumber) 关 / \(SokobanLevels.count)", id: "sokoban.level")
            .sokobanMeasure("level")
    }
    private func metricBlock(label: String, value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(SokobanPalette.ink.opacity(0.7))
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(id)
                .accessibilityLabel(value)
        }
        .sokobanMeasure(id == "sokoban.level" ? "level" : id)
    }
    private var saveStatus: some View {
        Group {
            if model.saveState == .failed {
                failedSaveBanner
            } else if model.saveState == .retrying {
                Text("正在重试保存…")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sokoban.save.retrying")
            } else if model.saveState == .saved {
                Text("已保存到本机")
                    .font(.footnote)
                    .foregroundStyle(SokobanPalette.target)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sokoban.save.saved")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var failedSaveBanner: some View {
        let message = Text("本步尚未保存")
            .font(.subheadline)
            .foregroundStyle(Color(red: 140/255, green: 64/255, blue: 36/255))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("sokoban.save.failed")
        let retry = Button("重试") { _ = model.retrySave() }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 44, minHeight: 44)
            .background(Color(red: 47/255, green: 107/255, blue: 79/255), in: Capsule())
            .accessibilityIdentifier("sokoban.save.retry")
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    message
                    HStack {
                        Spacer(minLength: 0)
                        retry
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    message
                    Spacer(minLength: 8)
                    retry
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 1, green: 236/255, blue: 227/255), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("纪录").font(.title3.bold())
                Spacer()
                Button("完成") { showRecords = false }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SokobanPalette.ink)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color(red: 1, green: 249/255, blue: 237/255), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1.5))
                    .accessibilityIdentifier("sokoban.records.close")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("第 \(model.levelNumber) 关").font(.caption)
                    Text(bestLine).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sokoban.records.current")
                    if let history = model.historicalBest {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("历史纪录（旧版）")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("旧版最少 \(history) 步")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("sokoban.records.legacy")
                                .accessibilityLabel("历史纪录（旧版） \(history)")
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 1, green: 244/255, blue: 230/255), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    if model.hasUnverifiedPredecessor {
                        Text("原存档已隔离保留，原纪录暂无法核实；当前纪录只来自可验证的同版本记录。")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("sokoban.records.unverified")
                    }
                }
                .sokobanMeasure("history.summary")
                .sokobanMeasure("history.content")
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("sokoban.records.scroll")
            .sokobanMeasure("history")
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(Color(red: 1, green: 249/255, blue: 237/255), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.vertical, 48)
        .frame(maxHeight: .infinity)
        .background(alignment: .topLeading) {
            #if DEBUG
            if SokobanTestSession.active != nil {
                Text(measurements()).font(.system(size: 1)).foregroundStyle(SokobanPalette.ink.opacity(0.02))
                    .allowsHitTesting(false).accessibilityIdentifier("sokoban.records.measurements")
            }
            #endif
        }
        .onPreferenceChange(SokobanFramesKey.self) { mergeFrames($0) }
    }
    private var pauseCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("已暂停")
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
            Button("继续游戏") { showPause = false; showPauseHelp = false }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(red: 47/255, green: 107/255, blue: 79/255), in: Capsule())
                .accessibilityIdentifier("sokoban.pause.resume")
            Button("选择关卡") { showPause = false; requestDestination("levels") }
                .font(.body.weight(.semibold))
                .foregroundStyle(SokobanPalette.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(Capsule().strokeBorder(Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1))
                .accessibilityIdentifier("sokoban.pause.levels")
            Button("返回首页") { showPause = false; requestDestination("home") }
                .font(.body.weight(.semibold))
                .foregroundStyle(SokobanPalette.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(Capsule().strokeBorder(Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1))
                .accessibilityIdentifier("sokoban.pause.home")
            Button("玩法说明") { showPauseHelp.toggle() }
                .font(.body.weight(.semibold))
                .foregroundStyle(SokobanPalette.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(Capsule().strokeBorder(Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1))
                .accessibilityIdentifier("sokoban.pause.help")
            if showPauseHelp {
                Text("滑动一次，移动一格。目标：把所有箱子推到目标点。")
                    .font(.body)
                    .foregroundStyle(SokobanPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sokoban.pause.rules")
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(Color(red: 1, green: 249/255, blue: 237/255), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1))
        .padding(.horizontal, 20)
    }
    private var resetCard: some View {
        VStack(spacing: 16) {
            Text("重新开始这一关？")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sokoban.reset.title")
            Text("本局进度将清空，纪录保留。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("取消") { confirmRestart = false }
                .font(.body.weight(.semibold))
                .foregroundStyle(SokobanPalette.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(Capsule().strokeBorder(Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1))
                .accessibilityIdentifier("sokoban.reset.cancel")
            Button("确认重置") { confirmRestart = false; restart() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(red: 165/255, green: 62/255, blue: 45/255), in: Capsule())
                .accessibilityIdentifier("sokoban.reset.confirm")
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(Color(red: 1, green: 249/255, blue: 237/255), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1))
        .padding(.horizontal, 20)
    }
    private var leaveCard: some View {
        VStack(spacing: 16) {
            Text("尚有进度未保存")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sokoban.leave.title")
            Text("离开后只能恢复到最近保存位置。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("重试并离开") {
                if model.retrySave() {
                    confirmLeave = false
                    performDestination()
                }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(red: 47/255, green: 107/255, blue: 79/255), in: Capsule())
            .accessibilityIdentifier("sokoban.leave.retry")
            Button("留在本局") { confirmLeave = false }
                .font(.body.weight(.semibold))
                .foregroundStyle(SokobanPalette.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(Capsule().strokeBorder(Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1))
                .accessibilityIdentifier("sokoban.leave.stay")
            Button("仍然离开") { confirmLeave = false; performDestination() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(red: 165/255, green: 62/255, blue: 45/255), in: Capsule())
                .accessibilityIdentifier("sokoban.leave.leave")
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(Color(red: 1, green: 249/255, blue: 237/255), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1))
        .padding(.horizontal, 20)
    }
    #if DEBUG
    private var hiddenTestDiagnostics: some View {
        Group {
            if let session = SokobanTestSession.active {
                Text(session.diagnostic(model: model))
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("sokoban.testing.state")
                    .accessibilityLabel(session.diagnostic(model: model))
            }
        }
        .frame(width: 1, height: 1)
        .clipped()
    }
    private func installTestHooks() {
        SokobanTestHooks.install { command in
            handleTestCommand(command)
        }
    }
    private func handleTestCommand(_ command: String) {
        guard let session = SokobanTestSession.active else { return }
        if command.hasPrefix("fault."), let mode = SokobanFaultStorage.Mode(rawValue: String(command.dropFirst(6))) {
            session.storage.mode = mode
        } else if command == "retry" {
            _ = model.retrySave()
        } else if command == "corrupt" {
            session.corruptCurrentSlot(model: model)
        } else if command == "undo" {
            _ = model.undo(); motion.cancel()
        } else if command == "redo" {
            _ = model.redo(); motion.cancel()
        }
    }
    #endif
    private func mergeFrames(_ values: [String: CGRect]) {
        var combined = frames; combined.merge(values, uniquingKeysWith: { _, new in new })
        if combined != frames { frames = combined }
    }
    private var score: some View {
        infoPill(model.visitKind == .scoreOnly ? "已通关" : "步数 \(motion.shownSteps ?? model.steps)", id: "chrome.score")
            .sokobanMeasure("steps")
    }
    private var best: some View {
        infoPill(bestLine, id: "sokoban.best", emphasize: true)
            .sokobanMeasure("best")
    }
    private var stepsParCapsule: some View {
        let steps = motion.shownSteps ?? model.steps
        let visible = model.visitKind == .scoreOnly ? "已通关" : "步数 \(steps) · 最少 \(max(model.parSteps, 1))"
        return ZStack {
            infoPill(visible, id: "sokoban.steps.par")
            VStack(spacing: 0) {
                Text(model.visitKind == .scoreOnly ? "已通关" : "步数 \(steps)")
                    .accessibilityIdentifier("chrome.score")
                    .accessibilityLabel(model.visitKind == .scoreOnly ? "已通关" : "步数 \(steps)")
                Text(bestLine)
                    .accessibilityIdentifier("sokoban.best")
                    .accessibilityLabel(bestLine)
            }
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .allowsHitTesting(false)
            .accessibilityElement(children: .contain)
        }
    }
    private var coinCapsule: some View {
        SokobanCoinCapsule(coins: model.coins, compact: typeSize.isAccessibilitySize) {
            shopHighlight = nil
            showPicker = false
            showShop = true
        }
        .sokobanMeasure("coins")
    }
    private var controls: some View {
        let compact = typeSize.isAccessibilitySize
        let undoDisabled = model.steps == 0 || model.won || !model.hasBoard || model.isReadOnlyCompletion
        let hintStatus: String? = {
            switch hintPhase {
            case .thinking: return "思考中"
            case .playing: return "推进中"
            case .idle: return nil
            }
        }()
        return HStack(alignment: .center, spacing: compact ? 8 : 12) {
            VStack(spacing: compact ? 6 : 8) {
                HStack(spacing: compact ? 6 : 8) {
                    SokobanFuncCard(
                        title: "撤销", icon: "icon_item_undo", id: "sokoban.undo",
                        kind: undoDisabled ? .disabledLook : .normal,
                        badge: model.undoItemCount > 0 ? .count(model.undoItemCount) : .plus,
                        compact: compact, disabled: undoDisabled, action: undo
                    )
                    .sokobanMeasure("undo")
                    SokobanFuncCard(
                        title: "提示", icon: "icon_item_hint", id: "sokoban.hint",
                        kind: .hint,
                        badge: model.hintItemCount > 0 ? .count(model.hintItemCount) : .plus,
                        compact: compact,
                        disabled: model.won || !model.hasBoard || model.isReadOnlyCompletion || hintPhase != .idle,
                        status: hintStatus,
                        action: requestHint
                    )
                    .sokobanMeasure("hint")
                }
                HStack(spacing: compact ? 6 : 8) {
                    SokobanFuncCard(
                        title: "重置", icon: "sokoban_icon_reset", id: "chrome.restart",
                        compact: compact, disabled: false
                    ) {
                        if model.steps > 0 && !model.won && !model.isReadOnlyCompletion { confirmRestart = true } else { restart() }
                    }
                    .sokobanMeasure("restart")
                    SokobanFuncCard(
                        title: "暂停", icon: "sokoban_icon_pause", id: "sokoban.pause",
                        compact: compact, disabled: false
                    ) { showPause = true }
                    .sokobanMeasure("pause")
                }
            }
            Spacer(minLength: 8)
            SokobanDPadView(compact: compact, pressed: dpadPressed, onPress: pressDPad, onRelease: releaseDPad)
                .sokobanMeasure("dpad")
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: compact ? 148 : 156)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func hintFailCard(_ fail: SokobanHintFail) -> some View {
        let ink = Color(red: 78/255, green: 48/255, blue: 24/255)
        return VStack(alignment: .leading, spacing: 14) {
            Text(fail.message)
                .font(.body)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sokoban.hint.fail")
            HStack(spacing: 10) {
                Button("好的") { hintFail = nil }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("sokoban.hint.fail.ok")
                Spacer()
                Button("重置本关") {
                    hintFail = nil
                    restart()
                }
                .font(.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("sokoban.hint.reset")
            }
        }
        .padding(18)
        .background(Color(red: 1, green: 249/255, blue: 237/255), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
    }
    /// Disabled ink is solid #5D5346 — never a lowered opacity that shows the grass through the art.
    private var disabledControlInk: Color { Color(red: 93/255, green: 83/255, blue: 70/255) }
    private func circularControl(_ title: String, _ systemImage: String, _ id: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        let accessibility = typeSize.isAccessibilitySize
        let size: CGFloat = accessibility ? 64 : 72
        let ink = disabled ? disabledControlInk : inkBrown
        let art = disabled ? "btn_circle_disabled" : "btn_circle_normal"
        // Fixed icon size so AX5 Dynamic Type cannot flush the glyph against the ring.
        let iconSize: CGFloat = accessibility ? 17 : 20
        return Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Image(art).resizable().scaledToFit().frame(width: size, height: size)
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(ink)
                        .accessibilityHidden(true)
                }
                .frame(width: size, height: size)
                controlCaption(title, ink: ink, size: accessibility ? 16 : 13)
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(SokobanOpaqueButtonStyle())
        .disabled(disabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
    /// Soft cream halo so captions stay readable on the garden, without fading the label.
    private func controlCaption(_ title: String, ink: Color, size: CGFloat) -> some View {
        let halo = Color(red: 1, green: 253/255, blue: 242/255)
        return Text(title)
            .font(kuaiLe(.caption, size: size))
            .foregroundStyle(ink)
            .multilineTextAlignment(.center)
            .shadow(color: halo.opacity(0.95), radius: 0.8, x: 0, y: 0)
            .shadow(color: halo.opacity(0.8), radius: 2.2, x: 0, y: 0)
    }
    private func requestDestination(_ destination: String) {

        pendingDestination = destination
        if model.saveState == .failed || model.saveState == .retrying { confirmLeave = true } else { performDestination() }
    }
    private func performDestination() {
        switch pendingDestination { case "home": router.pop(); case "next": advance(); default: showPicker = true }
        pendingDestination = ""
    }
    private func restart() { motion.cancel(); audio.cancelPendingClear(); stopDPad(); hintPhase = .idle; model.restart() }
    private func advance() { motion.cancel(); audio.cancelPendingClear(); stopDPad(); hintPhase = .idle; model.advance() }
    private func undo() {
        guard !motion.busy, hintPhase == .idle else { return }
        switch model.requestUndo() {
        case .undone:
            motion.cancel(); audio.cancelPendingClear()
        case .needsShop:
            shopHighlight = .undo
            showShop = true
        case .empty, .blocked:
            break
        }
    }
    private func pressDPad(_ direction: SokobanDirection) {
        if dpadPressed == direction { return }
        let now = Date().timeIntervalSinceReferenceDate
        let action = dpadRepeat.press(direction, at: now, allowed: model.canMove(direction), locked: inputLocked, won: model.won)
        switch action {
        case .step:
            dpadPressed = direction
            move(direction)
            startDPadTimer()
        case .stop:
            dpadPressed = nil
        }
    }
    private func releaseDPad() {
        _ = dpadRepeat.release()
        stopDPad()
    }
    private func startDPadTimer() {
        dpadTimer?.invalidate()
        dpadTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            tickDPad()
        }
    }
    private func tickDPad() {
        guard let direction = dpadRepeat.direction else { stopDPad(); return }
        let action = dpadRepeat.tick(
            at: Date().timeIntervalSinceReferenceDate,
            allowed: model.canMove(direction),
            locked: inputLocked && hintPhase == .idle,
            won: model.won
        )
        switch action {
        case .step:
            move(direction)
            if model.won { stopDPad() }
        case .stop:
            stopDPad()
        case nil:
            break
        }
    }
    private func stopDPad() {
        dpadTimer?.invalidate()
        dpadTimer = nil
        dpadPressed = nil
        dpadRepeat.reset()
    }
    private func requestHint() {
        guard hintPhase == .idle, !motion.busy, !showShop, hintFail == nil, !showPause, !confirmRestart, !confirmLeave, !showPicker else { return }
        guard model.hasBoard, !model.won, !model.isReadOnlyCompletion else { return }
        if model.hintItemCount == 0 {
            shopHighlight = .hint
            showShop = true
            return
        }
        if let line = SokobanHintPlanner.referenceLine(level: model.levelNumber, player: model.player, boxes: model.boxes), !line.isEmpty {
            startHintPlayback(line)
            return
        }
        hintPhase = .thinking
        let number = model.levelNumber
        let player = model.player
        let boxes = model.boxes
        Task.detached {
            let plan = SokobanHintPlanner.search(level: number, player: player, boxes: boxes, budget: SokobanHintPlanner.budget)
            await MainActor.run { self.finishHintPlan(plan) }
        }
    }
    private func finishHintPlan(_ plan: SokobanHintOutcome) {
        guard hintPhase == .thinking else { return }
        switch plan {
        case .sequence(let moves, _):
            startHintPlayback(moves)
        case .deadlock:
            hintPhase = .idle
            hintFail = .deadlock
            model.noticeHintFail("当前局面已无解，先撤销几步或重置本关再试试吧")
        case .timeout:
            hintPhase = .idle
            hintFail = .timeout
            model.noticeHintFail("当前路线偏离较远，重置本关后再点提示可直接帮你推好第一个箱子")
        }
    }
    private func startHintPlayback(_ moves: [SokobanDirection]) {
        guard model.beginHintPlayback(moves) else {
            hintPhase = .idle
            shopHighlight = .hint
            showShop = true
            return
        }
        hintPhase = .playing
        hideFirstHint = true
        let startSteps = model.steps
        var player = model.player
        var boxes = model.boxes
        var cells: [SokobanPathCell] = []
        for direction in moves {
            guard let stepped = SokobanReplay.stepped(player: player, boxes: boxes, walls: model.walls, rows: model.rows, cols: model.cols, direction: direction) else { break }
            let pushed = stepped.pushed
            let boxFrom = pushed ? stepped.player : nil
            let boxTo = pushed ? stepped.player.moving(direction) : nil
            let travel = SokobanTravel(kind: pushed ? .push : .walk, direction: direction, from: player, to: stepped.player, boxFrom: boxFrom, boxTo: boxTo)
            cells.append(SokobanPathCell(travel: travel, boxes: boxes))
            player = stepped.player
            boxes = stepped.boxes
        }
        guard !cells.isEmpty else {
            hintPhase = .idle
            return
        }
        motion.playPath(cells, stepsAtStart: startSteps) { travel in
            self.model.move(travel.direction)
            if travel.kind == .push { self.audio.playPush() } else { self.audio.playFootstep() }
        }
        if !self.motion.busy {
            self.hintPhase = .idle
        } else {
            self.watchHintPlayback()
        }
    }
    private func watchHintPlayback() {
        Task { @MainActor in
            while motion.busy {
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            hintPhase = .idle
        }
    }
    private func move(_ direction: SokobanDirection) {
        #if DEBUG
        SokobanGestureProbe.emit("move direction=\(direction) busy=\(motion.busy) animations=\(UIView.areAnimationsEnabled) before=\(model.token)")
        #endif
        guard !motion.busy, hintPhase == .idle, !showShop, hintFail == nil, !showPause, !confirmRestart, !confirmLeave, !showPicker else { return }
        let stepsBefore = model.steps
        let boxesBefore = model.boxes
        let playerBefore = model.player
        let wonBefore = model.won
        model.move(direction)
        #if DEBUG
        SokobanGestureProbe.emit("model after=\(model.token)")
        #endif
        if model.steps == stepsBefore {
            // 过关之后的按键不顶墙。局面没变才是顶墙或推不动。
            guard !wonBefore else { return }
            motion.start(SokobanTravel(kind: .bump, direction: direction, from: playerBefore, to: playerBefore))
            return
        }
        let pushed = model.boxes != boxesBefore
        if pushed {
            audio.playPush()
        } else {
            audio.playFootstep()
        }
        if !wonBefore && model.won {
            // 纪录已由模型的版本化存档记录；这里仅安排过关音效。
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


    @ViewBuilder private func observations(_ geo: GeometryProxy) -> some View {
        #if DEBUG
        if let session = SokobanTestSession.active {
            VStack {
                Text(motion.label).accessibilityIdentifier("sokoban.motion")
                Text(layoutStatus).accessibilityIdentifier("sokoban.layout")
                Text(measurements()).accessibilityIdentifier("sokoban.layout.metrics")
            }.font(.system(size: 1)).foregroundStyle(SokobanPalette.ink.opacity(0.02)).allowsHitTesting(false)
        }
        #endif
    }
    private func measurements() -> String {
        var rects: [String: [Double]] = [:]
        for (key, f) in frames {
            if key.hasPrefix("history") && !showRecords { continue }
            if (key == "board" || key == "drawn") && !model.hasBoard { continue }
            if key == "next" && (!model.won || model.isReadOnlyCompletion || model.levelNumber >= SokobanLevels.count || model.isCampaignComplete) { continue }
            // Named space origin is the safe-area root; convert to window
            // coordinates so layout assertions stay comparable across type sizes.
            rects[key] = [f.minX + rootInsets.leading, f.minY + rootInsets.top, f.width, f.height]
        }
        var obj: [String: Any] = ["viewport": [UIScreen.main.bounds.width, UIScreen.main.bounds.height],
            "safeArea": [rootInsets.top, rootInsets.leading, rootInsets.bottom, rootInsets.trailing],
            "root": [rootSize.width, rootSize.height], "category": String(describing: typeSize),
            "level": model.levelNumber, "rows": model.rows, "cols": model.cols,
            "cell": boardFit.cell, "gap": boardFit.gap, "drawnWidth": boardFit.width, "drawnHeight": boardFit.height, "frames": rects]
        func region(_ name: String, scrolling: Bool) -> [String: Any] {
            let viewport = frames[name] ?? .zero, content = frames[name+".content"] ?? .zero
            return ["frame": [viewport.minX,viewport.minY,viewport.width,viewport.height],
                "contentSize": [content.width,content.height],
                "contentOffset": scrolling ? [max(0,viewport.minX-content.minX),max(0,viewport.minY-content.minY)] : [0.0,0.0],
                "scrolling": scrolling]
        }
        obj["metrics"] = region("metrics", scrolling: false)
        obj["history"] = showRecords ? region("history", scrolling: true) : NSNull()
        obj["recordsExpanded"] = showRecords
        obj["renderMode"] = "assets"
        let names = [
            "tile_floor_walkable","tile_floor_blocked","tile_floor_target",
            "wall_outer_brick_cream","wall_outer_brick_mint","wall_outer_brick_peach","wall_outer_brick_sky",
            "crate_normal","crate_on_target","player_front","player_back","player_left","player_right",
            "bg_garden_play","hud_title_plaque","hud_pill_capsule","hud_coin_capsule","btn_circle_normal","btn_circle_disabled",
            "btn_func_card_normal","btn_func_card_disabled","btn_func_card_hint","icon_coin","icon_item_undo","icon_item_hint",
            "icon_star_filled","icon_star_empty","dpad_up_normal","badge_count_bg","badge_plus_bg",
            "sokoban_floor","sokoban_wall","sokoban_goal","sokoban_crate","sokoban_crate_on_target",
            "sokoban_player_front","sokoban_player_back","sokoban_player_left","sokoban_player_right"
        ]
        obj["boardAssetsLoaded"] = names.allSatisfy { UIImage(named: $0) != nil }
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

private struct SokobanFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private extension View {
    func sokobanMeasure(_ name: String) -> some View {
        background(GeometryReader { geo in Color.clear.preference(key: SokobanFramesKey.self, value: [name: geo.frame(in: .named("sokoban.screen"))]) })
    }
}

/// UIKit's relative translation may be reset at recognition; retain actual
/// touch-down/end window coordinates. Actions still run once, only at ended.
/// Window coordinates also avoid interpreting a view-layout change as travel.
private final class SokobanTouchPan: UIPanGestureRecognizer {
    private var trackingSequence = false
    private var isSingleTouch = true
    private var start: CGPoint?
    private var latest: CGPoint?
    private(set) var originInView: CGPoint?
    var fullDisplacement: CGPoint? {
        guard isSingleTouch, let start, let latest else { return nil }
        return CGPoint(x: latest.x-start.x, y: latest.y-start.y)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if !trackingSequence {
            trackingSequence = true
            isSingleTouch = touches.count == 1 && event.allTouches?.count == 1
            start = touches.first?.location(in: nil); latest = start
            originInView = touches.first?.location(in: view)
        } else { isSingleTouch = false }
        super.touchesBegan(touches, with: event)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        capture(touches, event); super.touchesMoved(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        capture(touches, event); super.touchesEnded(touches, with: event)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        isSingleTouch = false; super.touchesCancelled(touches, with: event)
    }
    override func reset() {
        super.reset(); trackingSequence = false
        // Preserve end coordinates until target-actions have been delivered;
        // the next real touchesBegan replaces them, never replays a move.
    }
    private func capture(_ touches: Set<UITouch>, _ event: UIEvent) {
        isSingleTouch = isSingleTouch && touches.count == 1 && event.allTouches?.count == 1
        latest = touches.first?.location(in: nil)
    }
}

/// One finger, one completed gesture, one model move. No changed-event repeats,
/// tap handler, second-finger scrolling, long press, or system-edge interception.
private struct SokobanSingleSwipe: UIViewRepresentable {
    var onMove: (SokobanDirection) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onMove) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.backgroundColor = .clear
        let pan = SokobanTouchPan(target: context.coordinator, action: #selector(Coordinator.ended(_:)))
        pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1; pan.delegate = context.coordinator
        view.addGestureRecognizer(pan); return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.onMove = onMove }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onMove: (SokobanDirection) -> Void
        init(_ onMove: @escaping (SokobanDirection) -> Void) { self.onMove = onMove }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let p = gestureRecognizer as? SokobanTouchPan, let view = p.view, let origin = p.originInView else { return false }
            let x = origin.x, y = origin.y
            let allowed = x >= 16 && x <= view.bounds.width-16 && y >= 12 && y <= view.bounds.height-12
            #if DEBUG
            SokobanGestureProbe.emit("begin allowed=\(allowed) origin=\(x),\(y) bounds=\(view.bounds)")
            #endif
            return allowed
        }
        @objc func ended(_ pan: UIPanGestureRecognizer) {
            #if DEBUG
            if pan.state != .changed { SokobanGestureProbe.emit("pan state=\(pan.state.rawValue) delta=\(pan.translation(in: pan.view))") }
            #endif
            guard pan.state == .ended else { return }
            #if DEBUG
            if SokobanTestSession.active?.forceRelativeGestureReset == true {
                pan.setTranslation(CGPoint(x: 1, y: 0), in: pan.view)
                SokobanGestureProbe.emit("injected observed relative reset to1; real touch input unchanged")
            }
            #endif
            guard let d = (pan as? SokobanTouchPan)?.fullDisplacement else { return }
            #if DEBUG
            SokobanGestureProbe.emit("ended actualTouchDelta=\(d) relativeDelta=\(pan.translation(in: pan.view))")
            #endif
            if let direction = SokobanSwipe.direction(dx: d.x, dy: d.y) { onMove(direction) }
        }
    }
}

/// Keeps disabled circular controls fully opaque so `btn_circle_disabled` and
/// solid ink do not inherit Button's default dimming (which would show the grass).
struct SokobanOpaqueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// Exterior blanks and padding use blocked floors; levels stay unchanged.
private struct SokobanNativeCanvas: View, Animatable {
    var model: SokobanModel
    var travel: SokobanTravel?
    var progress: CGFloat
    var fit: SokobanBoardFit
    var animatableData: CGFloat { get { progress } set { progress = newValue } }

    /// v2.4 solid feel: sprites fill the cell; the player's feet sit at (0.5, 0.90).
    private let frameScale: CGFloat = 1.0
    private let footAnchor = CGPoint(x: 0.5, y: 0.90)

    var body: some View {
        Canvas { context, size in
            let grid = SokobanVisualGrid.make(rows: model.rows, cols: model.cols)
            let cell = CGFloat(fit.cell), stride = CGFloat(fit.cell + fit.gap)
            let ox = (size.width - fit.width) / 2
            let oy = (size.height - fit.height) / 2
            func visualRect(row: Int, col: Int) -> CGRect {
                CGRect(x: ox + CGFloat(col) * stride, y: oy + CGFloat(row) * stride, width: cell, height: cell)
            }
            func rect(_ p: GridPoint) -> CGRect {
                let v = grid.map(p)
                return visualRect(row: v.row, col: v.col)
            }
            func centered(_ a: GridPoint, _ b: GridPoint) -> CGRect {
                let ra = rect(a), rb = rect(b)
                return CGRect(x: ra.minX + (rb.minX - ra.minX) * progress, y: ra.minY + (rb.minY - ra.minY) * progress, width: cell, height: cell)
            }
            func scaledRect(_ r: CGRect, anchor: CGPoint) -> CGRect {
                let w = r.width * frameScale, h = r.height * frameScale
                let foot = CGPoint(x: r.minX + r.width * 0.5, y: r.minY + r.height * anchor.y)
                return CGRect(x: foot.x - w * anchor.x, y: foot.y - h * anchor.y, width: w, height: h)
            }
            let boardRect = CGRect(x: ox, y: oy, width: fit.width, height: fit.height)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: Color(red: 36/255, green: 52/255, blue: 22/255).opacity(0.35), radius: 10, x: 0, y: 4))
                layer.fill(Path(roundedRect: boardRect, cornerRadius: 2), with: .color(Color(red: 249/255, green: 232/255, blue: 200/255)))
            }
            let bricks = ["wall_outer_brick_cream", "wall_outer_brick_mint", "wall_outer_brick_peach", "wall_outer_brick_sky"]
            let exterior = SokobanBoardFit.exterior(rows: model.rows, cols: model.cols, walls: model.walls)
            func wallName(row: Int, col: Int) -> String {
                let last = grid.side - 1
                let index: Int
                if row == 0 { index = col }
                else if col == last { index = last + row }
                else if row == last { index = last * 2 + (last - col) }
                else { index = last * 3 + (last - row) }
                return bricks[((index % 4) + 4) % 4]
            }
            for row in 0..<grid.side {
                for col in 0..<grid.side {
                    let r = visualRect(row: row, col: col)
                    guard let paint = SokobanFloorPaint.paint(
                        visualRow: row,
                        visualCol: col,
                        grid: grid,
                        rows: model.rows,
                        cols: model.cols,
                        walls: model.walls,
                        targets: model.targets,
                        exterior: exterior
                    ) else {
                        context.draw(context.resolve(Image(wallName(row: row, col: col))), in: r)
                        continue
                    }
                    let tile: String
                    switch paint {
                    case .blocked: tile = "tile_floor_blocked"
                    case .target: tile = "tile_floor_target"
                    case .walkable: tile = "tile_floor_walkable"
                    }
                    context.draw(context.resolve(Image(tile)), in: r)
                }
            }
            func box(_ r: CGRect, onTarget: Bool) {
                context.draw(context.resolve(Image(onTarget ? "crate_on_target" : "crate_normal")), in: scaledRect(r, anchor: CGPoint(x: 0.5, y: 0.5)))
            }
            for p in model.boxes where p != travel?.boxTo { box(rect(p), onTarget: model.targets.contains(p)) }
            if let t = travel, let from = t.boxFrom, let to = t.boxTo {
                box(centered(from, to), onTarget: progress > 0.99 && model.targets.contains(to))
            }
            var playerRect = travel.map { centered($0.from, $0.to) } ?? rect(model.player)
            if let t = travel, t.kind == .bump {
                let delta = t.to.moving(t.direction)
                let distance = sin(progress * .pi) * cell * 0.13
                playerRect = playerRect.offsetBy(dx: CGFloat(delta.col - t.to.col) * distance, dy: CGFloat(delta.row - t.to.row) * distance)
            }
            let name: String
            switch model.facing {
            case .up: name = "player_back"
            case .down: name = "player_front"
            case .left: name = "player_left"
            case .right: name = "player_right"
            }
            context.draw(context.resolve(Image(name)), in: scaledRect(playerRect, anchor: footAnchor))
        }.accessibilityHidden(true)
    }
}

struct SokobanLevelPicker: View {
    var current: Int
    var coins: Int = 0
    var totalStars: Int = 0
    var starsForLevel: (Int) -> Int = { _ in 0 }
    var onClose: () -> Void = {}
    var onOpenShop: () -> Void = {}
    var onPick: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    if typeSize.isAccessibilitySize {
                        Text("返回")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Color.white.opacity(0.92), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1))
                    } else {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Color.white.opacity(0.92), in: Circle())
                            .overlay(Circle().strokeBorder(Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1))
                    }
                }
                .foregroundStyle(SokobanPalette.ink)
                .accessibilityLabel("返回")
                .accessibilityIdentifier("sokoban.levels.close")
                Text("选择关卡")
                    .font(.title3.bold())
                    .foregroundStyle(SokobanPalette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                HStack(spacing: 6) {
                    Image("icon_star_filled").resizable().scaledToFit().frame(width: 16, height: 16)
                    Text("\(totalStars)/300")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(SokobanPalette.ink)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(Color.white.opacity(0.92), in: Capsule())
                .accessibilityIdentifier("sokoban.stars.total")
                .accessibilityLabel("已获 \(totalStars) 星，共 300 星")
                SokobanCoinCapsule(coins: coins, compact: typeSize.isAccessibilitySize, action: onOpenShop)
            }
            Text("共 \(SokobanLevels.count) 关 · 点选关卡开始或继续")
                .font(.subheadline)
                .foregroundStyle(SokobanPalette.ink.opacity(0.75))
            Text(SokobanLevels.credit)
                .font(.footnote)
                .foregroundStyle(SokobanPalette.ink.opacity(0.7))
                .accessibilityIdentifier("sokoban.credit")
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(1...SokobanLevels.count, id: \.self) { number in
                        levelCard(number)
                    }
                }
                .padding(.bottom, 24)
            }
            .accessibilityIdentifier("sokoban.levels.scroll")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .background {
            Image("sokoban_select_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .background(Color(red: 1, green: 249/255, blue: 237/255).ignoresSafeArea())
    }

    private func levelCard(_ number: Int) -> some View {
        let best = SokobanRecords.best(level: number)
        let progress = SokobanRecords.inProgressSteps(level: number)
        let historical = SokobanRecords.historicalBest(level: number)
        let selected = number == current
        let palette = Self.cardPalette[(number - 1) % Self.cardPalette.count]
        return Button { onPick(number) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%02d", number))
                        .font(.title.bold())
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    if historical != nil {
                        Text("旧版纪录")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.8), in: Capsule())
                    }
                }
                HStack(spacing: 3) {
                    ForEach(1...3, id: \.self) { index in
                        Image(index <= starsForLevel(number) ? "icon_star_filled" : "icon_star_empty")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                    }
                }
                .accessibilityLabel("\(starsForLevel(number)) 星")
                .accessibilityIdentifier("sokoban.pick.stars.\(number)")
                if let progress {
                    Text("进行中")
                        .font(.subheadline.weight(.semibold))
                    Text("已走 \(progress) 步")
                        .font(.footnote)
                } else if let best {
                    Text("已通关")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("sokoban.cleared.\(number)")
                    Text("最少 \(best) 步")
                        .font(.footnote)
                } else {
                    Text("未玩")
                        .font(.subheadline)
                }
            }
            .foregroundStyle(SokobanPalette.ink)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(palette, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? SokobanPalette.ink.opacity(0.55) : Color.white.opacity(0.6), lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sokoban.pick.\(number)")
    }

    private static let cardPalette: [Color] = [
        Color(red: 210/255, green: 232/255, blue: 214/255),
        Color(red: 186/255, green: 216/255, blue: 160/255),
        Color(red: 242/255, green: 196/255, blue: 196/255),
        Color(red: 186/255, green: 214/255, blue: 230/255),
        Color(red: 245/255, green: 232/255, blue: 196/255),
        Color(red: 214/255, green: 196/255, blue: 230/255)
    ]
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
enum SokobanPalette {
    static let wall = Color(red: 0.24, green: 0.16, blue: 0.12)
    static let wallEdge = Color(red: 0.16, green: 0.10, blue: 0.08)
    static let floor = Color(red: 0.96, green: 0.90, blue: 0.80)
    static let target = Color(red: 66.0/255, green: 116.0/255, blue: 87.0/255)
    static let box = Color(red: 0.86, green: 0.55, blue: 0.24)
    static let pieceEdge = Color(red: 0.36, green: 0.20, blue: 0.08)
    static let player = Color(red: 0.12, green: 0.48, blue: 0.58)
    static let playerLeg = Color(red: 0.10, green: 0.28, blue: 0.40)
    static let skin = Color(red: 0.96, green: 0.78, blue: 0.62)
    static let hair = Color(red: 0.25, green: 0.16, blue: 0.12)
    static let key = Color.white
    static let ink = Color(red: 48.0/255, green: 44.0/255, blue: 35.0/255)
}

#if DEBUG
/// Only synthetic, bounded UI sessions emit touch evidence. No production path/input.
private enum SokobanGestureProbe {
    static let logger = Logger(subsystem: "practice.classicgames.sokoban.gestureprobe", category: "touch")
    static func emit(_ text: @autoclosure () -> String) {
        guard SokobanTestSession.active != nil else { return }
        let value = text()
        logger.notice("\(value, privacy: .public)")
    }
}
#endif

#if DEBUG
/// Hidden, non-visible hook channel for isolated UI tests. No user-facing
/// "隔离测试" entry is shown in production or the test package.
enum SokobanTestHooks {
    static let prefix = "practice.classicgames.sokoban.test."
    static var handler: ((String) -> Void)?
    private static var installed = false
    private static let callback: CFNotificationCallback = { _, _, name, _, _ in
        guard let name else { return }
        let raw = name.rawValue as String
        guard raw.hasPrefix(SokobanTestHooks.prefix) else { return }
        let command = String(raw.dropFirst(SokobanTestHooks.prefix.count))
        DispatchQueue.main.async { SokobanTestHooks.handler?(command) }
    }
    static func install(_ handler: @escaping (String) -> Void) {
        self.handler = handler
        guard !installed else { return }
        installed = true
        let commands = SokobanFaultStorage.Mode.allCasesForUI.map { "fault." + $0.rawValue } + ["retry", "corrupt", "undo", "redo"]
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for command in commands {
            CFNotificationCenterAddObserver(center, nil, callback, (prefix + command) as CFString, nil, .deliverImmediately)
        }
    }
}
#endif

