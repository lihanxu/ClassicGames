import Foundation

/// 一款游戏的稳定标识。纪录键和导航路径都用它，首页只显示已登记的项。
struct GameID: Hashable {
    let rawValue: String
}

/// 最高纪录怎么比、什么时候写。和需求里的纪录表一致，具体判断留给外框。
enum RecordRule {
    /// 过关时写入，步数更少才替换。
    case lowerOnClear
    /// 死亡或结束时写入，分数更高才替换。
    case higherOnEnd
    /// 本局分数一变高就写。2048 用这条。
    case higherAsScoreGrows
    /// 分出胜负时给胜方加一胜。平局不加。
    case matchWins
}

/// 一局对局的结果。外框只据此给胜方加胜场，不看棋盘。
enum MatchOutcome: Equatable {
    case none
    case black
    case white
    case draw
}
