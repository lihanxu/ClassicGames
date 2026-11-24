import Foundation

/// 首页登记的一行：标识、中文名、操作说明、纪录规则。
struct GameEntry: Identifiable, Hashable {
    let id: GameID
    let title: String
    let hint: String
    let rule: RecordRule
}

/// 当前已经做完、可以出现在首页的游戏。没做完的不写进来。
enum GameCatalog {
    static let entries: [GameEntry] = [
        GameEntry(
            id: .sokoban,
            title: "推箱子",
            hint: "方向键、滑动或点空地，把箱子全部推到目标。",
            rule: .lowerOnClear
        ),
        GameEntry(
            id: .snake,
            title: "贪吃蛇",
            hint: "方向按钮转向，吃到食物变长",
            rule: .higherOnEnd
        ),
        GameEntry(
            id: .breakout,
            title: "打砖块",
            hint: "拖动挡板反弹球，打掉砖块",
            rule: .higherOnEnd
        ),
        GameEntry(
            id: .game2048,
            title: "2048",
            hint: "方向按钮滑动合并相同数字",
            rule: .higherAsScoreGrows
        ),
        GameEntry(
            id: .minesweeper,
            title: "扫雷",
            hint: "点开格子，插旗标记地雷",
            rule: .lowerOnClear
        ),
        GameEntry(
            id: .memory,
            title: "翻牌记忆",
            hint: "翻开两张相同的图案",
            rule: .lowerOnClear
        ),
        GameEntry(
            id: .gomoku,
            title: "五子棋",
            hint: "黑先，轮流落子，连成五子",
            rule: .matchWins
        ),
        GameEntry(
            id: .platformer,
            title: "跑跳",
            hint: "按住左右跑，点一下跳跃，到达终点",
            rule: .higherOnEnd
        )
    ]
}
