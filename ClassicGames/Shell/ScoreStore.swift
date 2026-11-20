import Foundation
import Observation

/// 最高纪录的唯一写入处。按游戏标识存在 UserDefaults，重开和返回都不清。
@MainActor
@Observable
final class ScoreStore {
    private let defaults: UserDefaults
    /// 写入后加一，让界面重新读取纪录。
    private var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 阶段总检查第一次启动时清掉旧纪录。再次打开不带这个参数，用来确认杀掉 App 后纪录还在。
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-reset-scores") {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("classicgames.best.") {
                defaults.removeObject(forKey: key)
            }
        }
        // 只清某一款，避免阶段检查把前面几款的纪录一起抹掉。
        if let index = arguments.firstIndex(of: "-reset-game"), arguments.indices.contains(index + 1) {
            let raw = arguments[index + 1]
            for key in defaults.dictionaryRepresentation().keys where key == "classicgames.best.\(raw)" || key.hasPrefix("classicgames.best.\(raw).") {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// 没有纪录时返回空。0 是合法成绩，和“还没写过”分开。
    func best(for id: GameID) -> Int? {
        _ = revision
        let key = storageKey(for: id)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    /// 首页和顶栏用的文案。没有纪录时是「—」。
    func text(for id: GameID) -> String {
        guard let best = best(for: id) else { return "—" }
        return String(best)
    }

    /// 越高越好。没有旧纪录时，这一局的分数直接成为纪录，包括 0。
    func recordHigher(_ id: GameID, score: Int) {
        if let best = best(for: id), score <= best { return }
        write(score, for: id)
    }

    /// 五子棋首页和顶栏用的胜场。还没分出过胜负时是「—」。
    func winText(for id: GameID) -> String {
        _ = revision
        let blackKey = storageKey(for: id) + ".black"
        let whiteKey = storageKey(for: id) + ".white"
        guard defaults.object(forKey: blackKey) != nil || defaults.object(forKey: whiteKey) != nil else {
            return "—"
        }
        return "黑 \(defaults.integer(forKey: blackKey)) · 白 \(defaults.integer(forKey: whiteKey))"
    }

    /// 胜方加一胜。另一边还没有数字时记成 0，这样首页能显示两边。
    func addWin(_ id: GameID, black: Bool) {
        let key = storageKey(for: id) + (black ? ".black" : ".white")
        let other = storageKey(for: id) + (black ? ".white" : ".black")
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        if defaults.object(forKey: other) == nil {
            defaults.set(0, forKey: other)
        }
        revision += 1
    }

    /// 越少越好。只有更少的成绩才替换已有纪录。
    func recordLower(_ id: GameID, score: Int) {
        if let best = best(for: id), score >= best { return }
        write(score, for: id)
    }

    private func write(_ score: Int, for id: GameID) {
        defaults.set(score, forKey: storageKey(for: id))
        revision += 1
    }

    private func storageKey(for id: GameID) -> String {
        "classicgames.best.\(id.rawValue)"
    }
}
