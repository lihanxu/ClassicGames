import SwiftUI

/// 室内首页。推箱子作为主卡片，其他七款仍从这里进入，不改它们的玩法。
struct HomeView: View {
    @Environment(ScoreStore.self) private var scores
    @Environment(AppRouter.self) private var router

    private let otherGames: [GameEntry] = GameCatalog.entries.filter { $0.id != .sokoban }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("口袋游乐室")
                        .font(.largeTitle.bold())
                        .foregroundStyle(ShellPalette.ink)
                        .accessibilityIdentifier("home.title")
                        .padding(.top, 4)
                    sokobanCard
                    if !otherGames.isEmpty {
                        Text("其他游戏")
                            .font(.headline)
                            .foregroundStyle(ShellPalette.ink)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(otherGames) { entry in
                                otherGameButton(entry)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
        }
        .safeAreaPadding(.top)
        .background {
            Image("sokoban_home_room")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var sokobanCard: some View {
        let progress = SokobanRecords.inProgressSummary()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("推箱子")
                        .font(.title2.bold())
                        .foregroundStyle(ShellPalette.ink)
                    Text("把箱子推到目标位置")
                        .font(.subheadline)
                        .foregroundStyle(ShellPalette.ink.opacity(0.62))
                    if let progress {
                        Text("关卡 \(String(format: "%02d", progress.level)) · 已走 \(progress.steps) 步")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 47/255, green: 107/255, blue: 79/255))
                    }
                    Text(verbatim: "已通关 \(SokobanRecords.clearedCount(from: 1, through: SokobanLevels.count))/\(SokobanLevels.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color(red: 47/255, green: 107/255, blue: 79/255))
                        .accessibilityIdentifier("home.best.sokoban")
                }
                Spacer(minLength: 8)
                Image("sokoban_home_sprig")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 72)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 12) {
                NavigationLink(value: GameID.sokoban) {
                    Text(progress == nil ? "开始游戏" : "继续游戏")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color.white)
                        .background(Color(red: 47/255, green: 107/255, blue: 79/255), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.row.sokoban")
                Button("选择关卡") {
                    SokobanLaunchIntent.openPickerOnAppear = true
                    router.path.append(.sokoban)
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(ShellPalette.ink)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().strokeBorder(Color(red: 201/255, green: 184/255, blue: 150/255), lineWidth: 1))
                .accessibilityIdentifier("home.sokoban.levels")
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 4)
    }

    private func otherGameButton(_ entry: GameEntry) -> some View {
        NavigationLink(value: entry.id) {
            HStack(spacing: 8) {
                Image(entryIcon(entry.id))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ShellPalette.ink)
                        .lineLimit(1)
                    Text(verbatim: entry.rule == .matchWins ? scores.winText(for: entry.id) : "最高 \(scores.text(for: entry.id))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ShellPalette.ink.opacity(0.62))
                        .lineLimit(1)
                        .accessibilityIdentifier("home.best.\(entry.id.rawValue)")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.row.\(entry.id.rawValue)")
    }

    private func entryIcon(_ id: GameID) -> String {
        switch id.rawValue {
        case "snake": return "sokoban_entry_snake"
        case "breakout": return "sokoban_entry_breakout"
        case "game2048": return "sokoban_entry_2048"
        case "minesweeper": return "sokoban_entry_minesweeper"
        case "memory": return "sokoban_entry_memory"
        case "gomoku": return "sokoban_entry_gomoku"
        case "platformer": return "sokoban_entry_platformer"
        default: return "sokoban_entry_sokoban"
        }
    }
}
