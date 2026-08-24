import SwiftUI

struct KaomojiPickerView: View {
    var lang: AppLanguage = .zh
    var onSelect: (String) -> Void
    @State private var selectedCategory = 0
    @State private var recentKaomoji: [String] = {
        (UserDefaults.standard.array(forKey: "kaomoji_recent") as? [String]) ?? []
    }()

    static let categories: [(icon: String, name: String, nameEN: String, items: [String])] = [
        ("clock.arrow.circlepath", "最近", "Recent", []),
        ("face.smiling", "开心", "Happy", [
            "(◕ᴗ◕✿)", "(≧▽≦)", "(✿◠‿◠)", "(*≧ω≦)", "(〃▽〃)",
            "(｡◕‿◕｡)", "(◍•ᴗ•◍)", "ヽ(>∀<☆)ノ", "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧", "(*´▽`*)",
            "(✧ω✧)", "(◠‿◠)", "(◕‿◕)", "٩(◕‿◕｡)۶", "ᕕ( ᐛ )ᕗ",
            "(๑˃ᴗ˂)ﻭ", "٩(^‿^)۶", "(ᗒᗨᗕ)", "(☆▽☆)", "⸜(⸝⸝⸝´꒳`⸝⸝⸝)⸝",
        ]),
        ("heart.fill", "爱", "Love", [
            "(♥ω♥*)", "(´,,•ω•,,)♡", "(◕‿◕)♡", "(✿ ♥‿♥)", "♡(ŐωŐ人)",
            "(灬♥ω♥灬)", "(*♡∀♡)", "(´♡‿♡`)", "(｡♥‿♥｡)", "( ˘ ³˘)♥",
            "♡＼(￣▽￣)／♡", "(◍♡‿♡◍)", "(っ˘з(˘⌣˘ )", "σ(≧ε≦σ) ♡", "(♡˙︶˙♡)",
            "꒰ᵕ༚ᵕ⑅꒱♡", "(ㅅ´ ˘ `)", "♡(◡‿◡)", "(⸝⸝⸝°_°⸝⸝⸝)♡", "₍ᐢ..ᐢ₎♡",
        ]),
        ("face.dashed", "害羞", "Shy", [
            "(⁄ ⁄•⁄ω⁄•⁄ ⁄)", "(*/ω＼*)", "(〃ω〃)", "(//▽//)", "(*ﾉωﾉ)",
            "(≧◡≦)", "(⌒_⌒;)", "(〃▽〃)ゞ", "(*μ_μ)", "(⁄ ⁄>⁄ ▽ ⁄<⁄ ⁄)",
            "(灬ºωº灬)", "(/ω\)", "(,,>﹏<,,)", "⸜( *ˊᵕˋ* )⸝", "(⁄⁄⁄ ⁄•⁄-⁄•⁄ ⁄⁄⁄)",
        ]),
        ("cloud.rain", "难过", "Sad", [
            "(ᵕ—ᴗ—)", "(╥_╥)", "(T_T)", "(。•́︿•̀。)", "(ノ_<。)",
            "( ´_ゝ`)", "(´;ω;`)", "(இ﹏இ`｡)", "·°(ˊ˘ˋ*)°·", "(｡•́︿•̀｡)",
            "( ; ω ; )", "(つ﹏⊂)", "(ᗒᗩᗕ)", "ಥ_ಥ", "( ´ ; ω ; ` )",
            "(｡ŏ﹏ŏ)", "(╯︵╰,)", "(-̩̩̩-̩̩̩-̩̩̩_-̩̩̩-̩̩̩-̩̩̩)", "⊙︿⊙", "(πーπ)",
        ]),
        ("bolt.fill", "生气", "Angry", [
            "(╬▔皿▔)╯", "(ノಠ益ಠ)ノ彡┻━┻", "(>_<)", "(≧σ≦)", "(ꐦ°᷄д°᷅)",
            "٩(╬ʘ益ʘ╬)۶", "(눈_눈)", "ヽ(`Д´)ノ", "(¬_¬)", "凸(¬‿¬)",
            "(ﾉ｀Д´)ﾉ", "(/‵Д′)/~ ╧╧", "(╬ Ò﹏Ó)", "(‡▼益▼)", "(`ε´)",
        ]),
        ("sparkles", "可爱", "Cute", [
            "(=^・ω・^=)", "(=①ω①=)", "ʕ•ᴥ•ʔ", "ʕ·ᴥ·ʔ", "(・ω・)",
            "₍ᐢ._.ᐢ₎", "ᓚᘏᗢ", "(=^-ω-^=)", "U・ᴥ・U", "ʕ •ᴥ• ʔ",
            "( ´(ｴ)` )", "(*・ω・)ﾉ", "(◕ᴥ◕)", "⊂(・▽・⊂)", "＼(◎o◎)／",
            "₍ᐢ⑅ᐢ₎", "(ミ╹ᆽ╹ミ)", "ʕ→ᴥ←ʔ", "(⁎˃ᆺ˂)", "≧◡≦",
        ]),
        ("hand.wave", "动作", "Actions", [
            "(ノ´ヮ`)ノ*: ・ﾟ✧", "ヾ(•ω•`)o", "(づ ◕‿◕ )づ", "(*・ω・)ﾉ", "(ﾉ◕ヮ◕)ﾉ",
            "ε=ε=ε=┌(;*´Д`)ﾉ", "┬─┬ノ( º _ ºノ)", "(ﾉ≧∀≦)ﾉ", "ヽ(°〇°)ﾉ", "(っ´▽`)っ",
            "(ノ^_^)ノ", "~(˘▾˘~)", "(~‾▿‾)~", "ᕙ(⇀‸↼‶)ᕗ", "ᕦ(ò_óˇ)ᕤ",
            "ヾ(≧▽≦*)o", "(∩^o^)⊃━☆", "(☞ﾟヮﾟ)☞", "☜(ﾟヮﾟ☜)", "╰(*°▽°*)╯",
        ]),
        ("cup.and.saucer", "日常", "Daily", [
            "(˘▽˘)っ♨", "( ˘ω˘ )zzZ", "(。-ω-)zzZ", "(¬‿¬ )", "¯\\_(ツ)_/¯",
            "( ˙▿˙ )", "(⊙_⊙)", "(°△°|||)", "Σ(°△°|||)", "(•̀ᴗ•́)و ̑̑",
            "( ・ᴗ・ )", "(*¯︶¯*)", "(ˊ˘ˋ*)", "ᑐᑌᑐᑌ", "(¬‿¬ )",
            "( •̀ω•́ )σ", "(˶ᵔ ᵕ ᵔ˶)", "⸜(˙▿˙)⸝", "(´▽`ʃ♡ƪ)", "꒰ঌ(⑅´•⌔•`)⸃꒱",
        ]),
        ("text.justify", "颜文字", "Text", [
            "orz", "_(：3 」∠ )_", "Σ(ﾟДﾟ)", "(ー_ー)!!", "(^_−)☆",
            "m(_ _)m", "(*ﾟ▽ﾟ)ﾉ", "( ﾟ∀ﾟ)", "(；一_一)", "(´-ω-`)",
            "\\(^o^)/", "(p_-)", "( ˇωˇ )", "(✿╹◡╹)", "ψ(｀∇´)ψ",
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Self.categories.indices, id: \.self) { i in
                        Button {
                            withAnimation(.easeOut(duration: 0.12)) { selectedCategory = i }
                        } label: {
                            Image(systemName: Self.categories[i].icon)
                                .font(.system(size: 14))
                                .foregroundStyle(selectedCategory == i ? Theme.accent : Theme.textSecondary)
                                .frame(width: 36, height: 30)
                                .background(
                                    selectedCategory == i
                                        ? RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.12))
                                        : nil
                                )
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .padding(.vertical, 4)

            Divider().opacity(0.3)

            let items = selectedCategory == 0 ? recentKaomoji : Self.categories[selectedCategory].items

            if items.isEmpty && selectedCategory == 0 {
                Text(L.t("还没有最近使用的颜文字", lang))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 90), spacing: 6)
                    ], spacing: 6) {
                        ForEach(items, id: \.self) { kaomoji in
                            Button {
                                onSelect(kaomoji)
                                addToRecent(kaomoji)
                            } label: {
                                Text(kaomoji)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .foregroundStyle(Theme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .frame(height: 150)
            }
        }
        .background(Theme.backgroundDeep.opacity(0.6))
    }

    private func addToRecent(_ kaomoji: String) {
        var list = recentKaomoji
        list.removeAll { $0 == kaomoji }
        list.insert(kaomoji, at: 0)
        if list.count > 20 { list = Array(list.prefix(20)) }
        recentKaomoji = list
        UserDefaults.standard.set(list, forKey: "kaomoji_recent")
    }
}
