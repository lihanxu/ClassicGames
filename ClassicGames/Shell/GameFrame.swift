import SwiftUI

/// 游戏页外框。只负责返回、标题、本局、最高纪录和重新开始，不判断这一步能不能走。
struct GameFrame<Content: View>: View {
    let id: GameID
    let title: String
    let score: Int
    /// 本局成绩前面的字，例如「步数」或「本局」。
    let scorePrefix: String
    let isOver: Bool
    let banner: String?
    let rule: RecordRule
    /// 顶栏本局位置改显示这句话。五子棋用来显示进行中或胜负。
    var statusText: String? = nil
    /// Optional per-game versioned metric. Other games keep the existing ScoreStore behavior.
    var bestTextOverride: String? = nil
    var restartTitle = "重新开始"
    /// 胜负结果。只有 matchWins 会在变成果一方获胜时加胜场。
    var outcome: MatchOutcome = .none
    let onRestart: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(ScoreStore.self) private var scores
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button("返回") { router.pop() }
                    .accessibilityIdentifier("chrome.back")
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("chrome.title")
                Text(verbatim: statusText ?? "\(scorePrefix) \(score)")
                    .font(.subheadline.monospacedDigit())
                    .accessibilityIdentifier("chrome.score")
                Button(restartTitle, action: onRestart)
                    .accessibilityIdentifier("chrome.restart")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ShellPalette.ink)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Text(verbatim: bestLine)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(ShellPalette.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("chrome.best")

            ZStack {
                content()
                if let banner {
                    Text(banner)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(ShellPalette.accent, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("chrome.banner")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ShellPalette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onChange(of: score) { oldScore, newScore in
            guard case .higherAsScoreGrows = rule, newScore > oldScore else { return }
            scores.recordHigher(id, score: newScore)
        }
        .onChange(of: isOver) { _, over in
            guard over else { return }
            switch rule {
            case .lowerOnClear:
                scores.recordLower(id, score: score)
            case .higherOnEnd:
                scores.recordHigher(id, score: score)
            case .higherAsScoreGrows, .matchWins:
                break
            }
        }
        .onChange(of: outcome) { _, newOutcome in
            guard case .matchWins = rule else { return }
            switch newOutcome {
            case .black:
                scores.addWin(id, black: true)
            case .white:
                scores.addWin(id, black: false)
            case .none, .draw:
                break
            }
        }
    }

    /// 五子棋显示黑白胜场，其它游戏显示一个最高纪录。
    private var bestLine: String {
        if let bestTextOverride { return bestTextOverride }
        if case .matchWins = rule {
            return scores.winText(for: id)
        }
        return "最高纪录 \(scores.text(for: id))"
    }
}

/// 外框和首页共用的颜色。各游戏的棋子颜色留在自己的文件夹里。
enum ShellPalette {
    static let background = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let card = Color.white
    static let ink = Color(red: 0.16, green: 0.15, blue: 0.14)
    static let accent = Color(red: 0.78, green: 0.29, blue: 0.18)
}
