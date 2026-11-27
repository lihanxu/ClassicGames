import SwiftUI

/// v4.0 游玩页 / 结算卡 / 兑换弹层 / 选关星级的可复用零件。不包含测试入口。
enum SokobanShopHighlight: Equatable {
    case undo
    case hint
}

enum SokobanHintFail: Equatable {
    case deadlock
    case timeout

    var message: String {
        switch self {
        case .deadlock:
            return "当前局面已无解，先撤销几步或重置本关再试试吧"
        case .timeout:
            return "当前路线偏离较远，重置本关后再点提示可直接帮你推好第一个箱子"
        }
    }
}

struct SokobanCoinCapsule: View {
    var coins: Int
    var compact: Bool
    var action: () -> Void
    private var inkBrown: Color { Color(red: 78/255, green: 48/255, blue: 24/255) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image("icon_coin")
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 18 : 16, height: compact ? 18 : 16)
                Text("\(coins)")
                    .font(.custom(SokobanChromeFont.name, size: compact ? 20 : 16))
                    .foregroundStyle(inkBrown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
                Text("+")
                    .font(.custom(SokobanChromeFont.name, size: compact ? 18 : 14).weight(.bold))
                    .foregroundStyle(Color(red: 196/255, green: 112/255, blue: 36/255))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, compact ? 5 : 0)
            .frame(minWidth: 44, minHeight: 44)
            .background {
                Image("hud_coin_capsule")
                    .resizable(capInsets: EdgeInsets(top: 12, leading: 18, bottom: 14, trailing: 18), resizingMode: .stretch)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("金币 \(coins)")
        .accessibilityIdentifier("sokoban.coins")
        .accessibilityValue("\(coins)")
    }
}

struct SokobanFuncCard: View {
    var title: String
    var icon: String
    var id: String
    var kind: Kind = .normal
    var badge: Badge = .none
    var compact: Bool
    var disabled: Bool
    var status: String? = nil
    var action: () -> Void

    enum Kind { case normal, hint, disabledLook }
    enum Badge { case none, count(Int), plus }

    var body: some View {
        let artName: String = {
            if kind == .hint { return "btn_func_card_hint" }
            if disabled || kind == .disabledLook { return "btn_func_card_disabled" }
            return "btn_func_card_normal"
        }()
        let ink = disabled
            ? Color(red: 93/255, green: 83/255, blue: 70/255)
            : Color(red: 78/255, green: 48/255, blue: 24/255)
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: compact ? 2 : 3) {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)
                    Text(status ?? title)
                        .font(.custom(SokobanChromeFont.name, size: compact ? 13 : 12))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Image(artName)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                badgeView
                    .offset(x: 6, y: -6)
            }
            .frame(minWidth: 44, minHeight: 44)
            .frame(width: compact ? 72 : 76, height: compact ? 56 : 58)
        }
        .buttonStyle(SokobanOpaqueButtonStyle())
        .disabled(disabled)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var badgeView: some View {
        switch badge {
        case .none:
            EmptyView()
        case .count(let value):
            ZStack {
                Image("badge_count_bg").resizable().scaledToFit()
                Text("\(value)")
                    .font(.custom(SokobanChromeFont.name, size: 10))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
        case .plus:
            ZStack {
                Image("badge_plus_bg").resizable().scaledToFit()
                Text("+")
                    .font(.custom(SokobanChromeFont.name, size: 11).weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
        }
    }

    private var accessibilityValue: String {
        switch badge {
        case .count(let value): return "余量 \(value)"
        case .plus: return "余量 0，打开兑换"
        case .none: return ""
        }
    }
}

struct SokobanDPadView: View {
    var compact: Bool
    var pressed: SokobanDirection?
    var onPress: (SokobanDirection) -> Void
    var onRelease: () -> Void

    private var size: CGFloat { compact ? 48 : 50 }

    var body: some View {
        let gap: CGFloat = compact ? 4 : 6
        VStack(spacing: gap) {
            key(.up, "上", "dpad_up")
            HStack(spacing: gap) {
                key(.left, "左", "dpad_left")
                Color.clear.frame(width: size, height: size)
                key(.right, "右", "dpad_right")
            }
            key(.down, "下", "dpad_down")
        }
        .frame(width: size * 3 + gap * 2, height: size * 3 + gap * 2)
    }

    private func key(_ direction: SokobanDirection, _ label: String, _ art: String) -> some View {
        let isPressed = pressed == direction
        return Image(isPressed ? "\(art)_pressed" : "\(art)_normal")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress(direction) }
                    .onEnded { _ in onRelease() }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("sokoban.dpad.\(direction.name)")
    }
}

struct SokobanStarRow: View {
    var filled: Int
    var size: CGFloat
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...3, id: \.self) { index in
                Image(index <= filled ? "icon_star_filled" : "icon_star_empty")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(max(0, min(3, filled))) 星")
        .accessibilityIdentifier("sokoban.result.stars")
        .accessibilityValue("\(max(0, min(3, filled)))")
    }
}

struct SokobanSettlementBlock: View {
    var settlement: SokobanSettlement
    var compact: Bool

    var body: some View {
        VStack(spacing: compact ? 8 : 10) {
            SokobanStarRow(filled: settlement.stars, size: compact ? 24 : 36, spacing: compact ? 6 : 10)
            Text(settlement.title)
                .font(.custom(SokobanChromeFont.name, size: compact ? 18 : 20))
                .foregroundStyle(Color(red: 47/255, green: 107/255, blue: 79/255))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier("sokoban.result.grade")
            VStack(spacing: 2) {
                Text("本局得分 \(settlement.score) 分")
                    .font(.custom(SokobanChromeFont.name, size: compact ? 16 : 16))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier("sokoban.result.score")
                Text("本次 \(settlement.steps) 步 · 基准最少 \(settlement.parSteps) 步")
                    .font(.custom(SokobanChromeFont.name, size: compact ? 13 : 13))
                    .foregroundStyle(Color(red: 78/255, green: 48/255, blue: 24/255).opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(red: 1, green: 244/255, blue: 224/255), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            rewardBox
        }
    }

    @ViewBuilder private var rewardBox: some View {
        let pay = settlement.payout
        let text: String = {
            if !settlement.counts { return "本局不计入奖励" }
            if pay.isRepeat { return "重复通关奖励 +5 金币" }
            var parts: [String] = []
            if pay.coins > 0 { parts.append("+\(pay.coins) 金币") }
            if pay.undo > 0 { parts.append("+\(pay.undo) 撤销券") }
            if pay.hint > 0 { parts.append("+\(pay.hint) 提示") }
            return parts.isEmpty ? "本局无额外奖励" : parts.joined(separator: "  ")
        }()
        Text(text)
            .font(.custom(SokobanChromeFont.name, size: compact ? 14 : 14))
            .foregroundStyle(Color(red: 47/255, green: 107/255, blue: 79/255))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(red: 226/255, green: 242/255, blue: 224/255), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("sokoban.result.reward")
            .accessibilityLabel(text)
    }
}

struct SokobanShopSheet: View {
    var wallet: SokobanWallet
    var highlight: SokobanShopHighlight?
    var compact: Bool
    var onBuy: (SokobanShopItem) -> Bool
    var onClose: () -> Void

    var body: some View {
        let ink = Color(red: 78/255, green: 48/255, blue: 24/255)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("道具兑换")
                    .font(.custom(SokobanChromeFont.name, size: compact ? 24 : 22))
                    .foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("完成", action: onClose)
                    .font(.custom(SokobanChromeFont.name, size: 16))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(red: 196/255, green: 140/255, blue: 74/255), lineWidth: 1.4))
                    .accessibilityIdentifier("sokoban.shop.close")
            }
            HStack(spacing: 10) {
                label("金币 \(wallet.coins)")
                label("撤销 \(wallet.undoItemCount)")
                label("提示 \(wallet.hintItemCount)")
            }
            .accessibilityIdentifier("sokoban.shop.balance")
            ForEach(SokobanShopItem.allCases, id: \.self) { item in
                shopRow(item, ink: ink)
            }
            if wallet.coins < SokobanShopItem.allCases.map(\.coinCost).min() ?? 15 {
                Text("通关或冲刺更高星级即可获得更多金币")
                    .font(.footnote)
                    .foregroundStyle(ink.opacity(0.75))
                    .accessibilityIdentifier("sokoban.shop.hint")
            }
        }
        .padding(18)
        .background(Color(red: 1, green: 249/255, blue: 237/255), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(red: 176/255, green: 122/255, blue: 74/255), lineWidth: 1.4))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sokoban.shop")
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(red: 78/255, green: 48/255, blue: 24/255))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(red: 1, green: 244/255, blue: 224/255), in: Capsule())
    }

    private func shopRow(_ item: SokobanShopItem, ink: Color) -> some View {
        let affordable = wallet.coins >= item.coinCost
        let highlighted = (highlight == .undo && (item == .undo1 || item == .undo5))
            || (highlight == .hint && (item == .hint1 || item == .hint3))
        return HStack(spacing: 10) {
            Image(item.undoDelta > 0 ? "icon_item_undo" : "icon_item_hint")
                .resizable().scaledToFit().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title + (item.isBundle ? "（超值包）" : ""))
                    .font(.custom(SokobanChromeFont.name, size: 16))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(item.coinCost) 金币")
                    .font(.footnote)
                    .foregroundStyle(ink.opacity(0.7))
            }
            Spacer()
            Button(affordable ? "兑换" : "金币不足") {
                _ = onBuy(item)
            }
            .font(.custom(SokobanChromeFont.name, size: 14))
            .foregroundStyle(affordable ? Color.white : ink.opacity(0.45))
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(affordable ? Color(red: 47/255, green: 107/255, blue: 79/255) : Color(red: 220/255, green: 210/255, blue: 196/255))
            )
            .disabled(!affordable)
            .accessibilityIdentifier("sokoban.shop.\(item.rawValue)")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(highlighted ? Color(red: 1, green: 236/255, blue: 200/255) : Color.white.opacity(0.7))
        )
    }
}

enum SokobanChromeFont {
    static let name = "ZCOOLKuaiLe-Regular"
}
