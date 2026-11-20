import SwiftUI

/// 首页列表。没有登记游戏时只显示空状态，不放占位行。
struct HomeView: View {
    @Environment(ScoreStore.self) private var scores

    var body: some View {
        ZStack {
            ShellPalette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("经典小游戏")
                    .font(.largeTitle.bold())
                    .foregroundStyle(ShellPalette.ink)
                    .accessibilityIdentifier("home.title")
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                if GameCatalog.entries.isEmpty {
                    Spacer()
                    Text("还没有游戏")
                        .font(.title3)
                        .foregroundStyle(ShellPalette.ink.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("home.empty")
                    Spacer()
                } else {
                    List(GameCatalog.entries) { entry in
                        NavigationLink(value: entry.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.title3.bold())
                                    .foregroundStyle(ShellPalette.ink)
                                Text(entry.hint)
                                    .font(.subheadline)
                                    .foregroundStyle(ShellPalette.ink.opacity(0.62))
                                Text(verbatim: entry.rule == .matchWins ? scores.winText(for: entry.id) : "最高 \(scores.text(for: entry.id))")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(ShellPalette.accent)
                                    .accessibilityIdentifier("home.best.\(entry.id.rawValue)")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 0)
                        }
                        .accessibilityIdentifier("home.row.\(entry.id.rawValue)")
                        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                        .listRowBackground(ShellPalette.card)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
