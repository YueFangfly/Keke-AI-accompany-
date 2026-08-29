import Foundation

/// App 界面语言：中文 / English。是 App 内手动切换，不跟着系统语言走
/// （跟外观模式是同一个思路：设置里选，存在 UserDefaults 里）。
enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case zh, en

    var id: String { rawValue }

    /// 选择器里显示的名字，永远用它自己的文字写（不管当前是哪个语言模式），
    /// 这样不管现在显示的是哪种语言，用户都认得出自己想切换到哪个
    var displayName: String {
        switch self {
        case .zh: return "简体中文"
        case .en: return "English"
        }
    }
}

/// 极简的界面文字翻译：中文模式直接原样返回；英文模式去表里查，
/// 查不到就退回中文原文（不会崩，只是那一条还没翻译到）。
/// 界面文字用 L.t("中文原文", store.appLanguage) 包一层就行。
enum L {
    static func t(_ zh: String, _ lang: AppLanguage) -> String {
        guard lang == .en else { return zh }
        return table[zh] ?? zh
    }

    /// 带数字的句子：模板里用 %d 占位数字，中英文各给一份模板
    static func count(_ n: Int, _ zhTemplate: String, _ enTemplate: String, _ lang: AppLanguage) -> String {
        String(format: lang == .en ? enTemplate : zhTemplate, n)
    }

    private static let table: [String: String] = [
        // MARK: 角色选择页
        "选择角色": "Choose Character",
        "每个角色有自己的聊天和记忆": "Each character has its own chats & memories",
        "切换角色": "Switch Character",
        "添加新角色": "Add Character",
        // MARK: 侧边栏 / 顶栏 / 标签
        "聊天": "Chat",
        "心跳": "Heartbeat",
        "经期": "Cycle",
        "朋友圈": "Moments",
        "记忆": "Memory",
        "闹钟": "Alarm",
        "收藏": "Favorites",
        "设置": "Settings",
        "克克": "Keke",
        "我": "Me",
        "还没有 API Key，去「设置」填一下": "No API Key yet — add one in \"Settings\"",
        "克克在线": "Keke is online",
        "搜索聊天记录": "Search chat history",
        "没有找到相关消息": "No matching messages",

        // MARK: 聊天页
        "和克克说点什么…": "Say something to Keke…",
        "图片准备好了，想说什么一起发～": "Photo ready — add a message if you like~",
        "这个文件读不出文字": "Couldn't read text from this file",
        "取消收藏": "Unfavorite",
        "复制": "Copy",
        "删除": "Delete",

        // MARK: 小螃蟹反应
        "嘻嘻": "Hehe",
        "戳我干嘛~": "Why poke me~",
        "在!": "Here!",
        "哇！": "Whoa!",
        "哼！": "Hmph!",
        "……让我想想": "…let me think",

        // MARK: 心跳页
        "这台设备不支持健康数据": "This device doesn't support health data",
        "让克克知道你的步数、睡眠和身体状态，\n更好地照顾你": "Let Keke see your steps, sleep, and body stats,\nso she can take better care of you",
        "允许克克读取健康数据": "Allow Keke to read health data",
        "数据只在你自己的手机上，不会上传到别的地方": "Data stays on your phone only, never uploaded anywhere",
        "今日步数": "Steps today",
        "步行距离": "Distance walked",
        "步": "steps",
        "公里": "km",
        "昨晚睡眠": "Sleep last night",
        "小时": "hrs",
        "最近心率": "Recent heart rate",
        "次/分": "bpm",
        "月经记录": "Period record",
        "无记录": "No record",
        "今天": "Today",
        "天前": "days ago",
        "下拉可以刷新数据": "Pull down to refresh",
        "发给克克看看": "Send to Keke",

        // MARK: 记忆页
        "直接告诉克克要记住的事…": "Tell Keke something to remember…",
        "记住": "Remember",
        "克克在回忆……": "Keke is recalling…",
        "让克克整理最近的聊天": "Let Keke sum up recent chats",
        "最近聊的克克都记得啦": "Keke already remembers everything recent",
        "克克还没有长期记忆\n多聊聊它会自己记住重要的事，\n也可以在上面直接告诉它":
            "Keke doesn't have long-term memories yet.\nKeep chatting and she'll remember important things on her own,\nor tell her directly above",
        "长按可以删除": "Long-press to delete",
        "标为置顶": "Mark as Pinned",
        "标为重要": "Mark as Important",
        "标为普通": "Mark as Normal",
        "让克克忘掉这条": "Let Keke forget this",
        "还惦记着": "Still on her mind",
        "已经了结": "Settled",
        "已归档": "Archived",
        "这事了结啦": "This one's settled",
        "让克克惦记着这事": "Have Keke keep this in mind",
        "收进归档": "Move to Archive",
        "从归档里拿回来": "Bring Back from Archive",
        "没找到能导入的内容": "Nothing importable found",

        // MARK: 会话列表 / 联系人
        "加个新朋友": "Add a Friend",
        "还没接 Key": "No key yet",
        "还没聊过，点进去说句话吧": "No messages yet — tap in and say hi",
        "编辑资料": "Edit Profile",
        "删除这个朋友": "Delete This Friend",
        "先去「设置」填上 %@ 的 API Key 才能开始聊": "Add the %@ API Key in Settings before chatting",
        "说点什么…": "Say something…",
        "备注": "Nickname",
        "备注名": "Nickname",
        "头像 emoji（一个就好）": "Avatar emoji (just one)",
        "绑定的模型": "Bound Model",
        "这家的 API Key 已经填过了，建好就能聊": "This provider's API Key is already set — ready to chat once created",
        "这家的 API Key 还没填：去「设置 → AI 提供方」切到这家填一下": "This provider's API Key isn't set yet — switch to it under Settings → AI Provider and add one",
        "人设（可留空）": "Persona (optional)",
        "留空 = 没有人设，只告诉 TA 自己叫什么名字，其他全靠聊出来和记忆养出来。记忆可以在「记忆」页切到 TA 的分区导入。":
            "Leave blank for no persona — they'll only know their own name; everything else grows from chats and memories. Import memories on the Memory page under their partition.",
        "确定删除吗？聊天记录会一起清掉，记忆会留在记忆页里。": "Delete? The chat history goes too; memories stay on the Memory page.",
        "谁的记忆": "Whose memories",
        "导入记忆（md / txt / json）": "Import Memories (md / txt / json)",
        "md/txt 按行导入（一行一条）；json 认 claude.ai 和 ChatGPT 的官方导出文件（自动解析对话内容），也认字符串数组。导进来的都存在 TA 自己的记忆分区里，「记忆」页能看能改。":
            "md/txt import line by line (one memory per line); json recognizes official claude.ai and ChatGPT export files (conversation content parsed automatically) as well as string arrays. Everything lands in their own memory partition — view and edit it on the Memory page.",
        "点赞了": "liked this",

        // MARK: 朋友圈
        "分享一件小事…": "Share a little thing…",
        "照片准备好了": "Photo ready",
        "克克在想……": "Keke is thinking…",
        "让克克也发一条": "Let Keke post one too",
        "发布": "Post",
        "还没有动态\n发一条小事，或者让克克先说说": "No moments yet.\nPost a little thing, or let Keke go first",
        "🐱 克克": "🐱 Keke",
        "🌙 我": "🌙 Me",
        "❤️ 克克点赞了": "❤️ Liked by Keke",
        "赞": "Like",
        "评论": "Comment",
        "说句评论…": "Write a comment…",
        "克克：": "Keke: ",
        "我：": "Me: ",

        // MARK: 闹钟页
        "加一个克克闹钟": "Add a Keke alarm",
        "还没有闹钟\n设一个，到点克克会来叫你\n（叫你的那句话是它自己写的）":
            "No alarms yet.\nSet one and Keke will wake you up\n(she writes the line herself)",
        "每天": "Daily",
        "响一次": "Once",
        "删除这个闹钟": "Delete this alarm",
        "闹钟用通知实现：到点会弹出克克写的一句话。\n声音是通知声，不会像系统闹钟一直响；静音模式下可能只亮屏。":
            "Alarms use notifications: at the set time, a line Keke wrote pops up.\nIt's a notification sound, not a system alarm that keeps ringing — in silent mode it may just light up the screen.",
        "时": "Hour",
        "分": "Minute",
        "克克闹钟": "Keke Alarm",
        "备注：要干嘛（可以不填）": "Note: what for (optional)",
        "每天重复": "Repeat daily",
        "克克在想叫你的话…": "Keke is thinking what to say…",
        "保存": "Save",

        // MARK: 经期页
        "点日期可以标记/取消。健康 App 里的记录会自动同步进来（只读）；在这里点的只存在这台手机上。":
            "Tap a date to mark/unmark. Records from the Health app sync in automatically (read-only); taps here are stored only on this phone.",
        "预测": "Predicted",
        "还没有记录。点日历上的日期就能标记，或在「心跳」页授权健康数据自动同步":
            "No records yet. Tap a date on the calendar to mark it, or authorize Health data on the \"Heartbeat\" page to sync automatically",

        // MARK: 收藏页
        "还没有收藏\n长按聊天气泡可以收藏喜欢的话": "No favorites yet.\nLong-press a chat bubble to favorite messages you like",

        // MARK: 设置页
        "提供方": "Provider",
        "模型": "Model",
        "模型名，比如": "Model name, e.g.",
        "AI 提供方": "AI Provider",
        "克克的人设": "Keke's Persona",
        "默认": "Default",
        "已修改": "Modified",
        "这就是每次对话前悄悄发给 AI、决定克克怎么说话的那段说明文字。可以看，也可以自己改。":
            "This is the text quietly sent to the AI before every chat, deciding how Keke talks. You can view it, and edit it too.",
        "外观": "Appearance",
        "主题": "Theme",
        "月雾（默认）": "Mist (Default)",
        "深海": "Deep Sea",
        "星夜猫猫": "Starry Cats",
        "「深海」和「星夜猫猫」是深色主题，选中后整个 App 固定深色（外观选项暂时不起作用）；换回「月雾」就恢复。「界面语言」切换的是 App 自己的文字，「字体」换的是整体字体样式。":
            "\"Deep Sea\" and \"Starry Cats\" are dark themes — while selected, the whole app stays dark (the Appearance option is inactive); switch back to \"Mist\" to restore it. \"Interface Language\" switches the app's own text; \"Font\" changes the overall type style.",
        "打开后，跟她说「日记概率调高一点」「帮我记一下周四交作业」这类话，她能直接帮你改设置、建系统提醒事项和日历日程。改设置目前覆盖日记概率、主动冒泡、上网开关、外观、字体、学语言这几项。":
            "When on, saying things like \"raise the diary probability\" or \"remind me to hand in homework Thursday\" lets her change settings and create system Reminders and Calendar events directly. Settings coverage: diary probabilities, nudges, web access, appearance, font, and the learning language.",
        "跟随系统": "Follow system",
        "始终浅色": "Always light",
        "始终深色": "Always dark",
        "顺便学一门语言": "Learn a language along the way",
        "不用": "None",
        "外观 & 语言学习": "Appearance & Language Learning",
        "界面语言": "Interface Language",
        "字体": "Font",
        "圆体": "Rounded",
        "衬线": "Serif",
        "等宽": "Monospaced",
        "「界面语言」切换的是整个 App 自己的文字，「字体」换的是整体字体样式；下面「顺便学一门语言」只是让克克在聊天里顺便教你几句，是完全独立的另一件事。":
            "\"Interface Language\" switches all the app's own text; \"Font\" changes the overall type style. The \"Learn a language\" picker below just has Keke teach you a few phrases in chat — a separate thing.",
        "「界面语言」切换的是整个 App 自己的文字，「字体」换的是整体字体样式。想让克克顺便教你一门语言的话，去「探索」页设置。":
            "\"Interface Language\" switches all the app's own text; \"Font\" changes the overall type style. To have Keke teach you a language along the way, set that up on the \"Explore\" page.",
        "手机电量": "Battery level",
        "大概位置": "Approximate location",
        "今天的日程": "Today's schedule",
        "提醒事项": "Reminders",
        "克克能看到的": "What Keke can see",
        "打开的项目会在聊天时告诉克克（比如电量低了它会念叨你）。第一次打开会弹系统权限。数据只随对话发送，不会存到别的地方；步数用的是「心跳」页健康数据的授权。":
            "Turned-on items get mentioned to Keke during chat (like nagging you when battery is low). The system permission prompt pops up the first time. Data is only sent along with chat, never stored elsewhere; steps use the Health data authorization from the \"Heartbeat\" page.",
        "允许克克上网查东西 / 打开链接": "Let Keke browse the web / open links",
        "联网": "Internet Access",
        "打开后，聊天里贴链接（GitHub、新闻页这些）克克可以自己去看，也能搜索。要登录才能看的（小红书/X）有时打不开。Haiku 模型不支持联网。":
            "When on, Keke can open links you paste in chat (GitHub, news pages, etc.) and search the web. Sites that need login (Xiaohongshu/X) sometimes won't open. The Haiku model doesn't support web access.",
        "打开后，聊天里贴一个具体的网页链接，克克可以自己去读取内容分析；但这家没接自动搜索，得给她一个明确的网址，她自己搜不到东西，登录才能看的页面也读不到。":
            "When on, Keke can read a specific webpage link you paste in chat and analyze it. This provider doesn't have automatic search, though — you need to give her an exact URL, she can't search on her own, and pages that need login won't load.",
        "回到 App 时克克可能先开口": "Keke may speak first when you return to the app",
        "让克克偶尔主动找你": "Let Keke reach out sometimes",
        "频率": "Frequency",
        "偶尔 · 每天 1 条左右": "Occasional · about 1/day",
        "正常 · 每天 2 条左右": "Normal · about 2/day",
        "常常 · 每天 3 条左右": "Frequent · about 3/day",
        "通知权限被关掉了：去 iPhone 的 设置 → 通知 → Moonlight 里打开，再回来开这个开关":
            "Notification permission is off: go to iPhone Settings → Notifications → Moonlight to turn it on, then come back and flip this switch",
        "克克主动冒泡": "Keke's Spontaneous Messages",
        "「先开口」：好几个小时没聊的话，打开 App 会发现克克先给你留了句话。「主动找你」：在白天到晚上的随机时间用通知冒出来。两个都接着你们最近聊的内容说，不会问你吃没吃饭，也不会说早安晚安。":
            "\"Speak first\": if it's been hours since you last chatted, opening the app you'll find Keke already left you a line. \"Reach out\": pops up as a notification at a random time during the day. Both pick up on what you last talked about — she won't ask if you've eaten, or say good morning/night.",
        "聊天记录": "Chat History",
        "清空聊天记录": "Clear Chat History",
        "关于": "About",
        "🐱 克克住在这里。": "🐱 Keke lives here.",
        "聊天记录、记忆和健康数据都只在这台手机上。": "Chat history, memories, and health data all stay on this phone only.",
        "确定要清空所有聊天记录吗？收藏也会一起被清掉。": "Clear all chat history? Favorites will be cleared too.",
        "清空": "Clear",
        "重置": "Reset",
        "还没有最近使用的颜文字": "No recently used kaomoji",
        "Temperature 越高回复越随机，越低越稳定。Top P 控制词汇采样范围。不调则用 API 默认值。":
            "Higher Temperature = more random replies, lower = more stable. Top P controls vocabulary sampling range. Leave unset to use API defaults.",
        "这段文字会在每次对话前悄悄发给 AI，决定克克怎么说话、记得哪些事。改完记得点保存。":
            "This text is quietly sent to the AI before every conversation, deciding how Keke talks and what she remembers. Remember to save after editing.",
        "恢复默认": "Restore Default",
        "恢复成默认人设？你改过的内容会被替换掉。": "Restore the default persona? Your edits will be replaced.",
        "导出记忆": "Export Memories",
        "清空所有记忆": "Clear All Memories",
        "「记忆」页可以查看、添加、导入具体内容；这里只是导出成文字备份，或者整个清空重来。":
            "The \"Memory\" tab is where you view, add, and import entries; this is just for exporting a text backup, or wiping everything to start over.",
        "确定要清空所有记忆吗？这个操作撤不回来。": "Clear all memories? This can't be undone.",

        // MARK: 模型描述
        "Opus 4.8 · 最聪明": "Opus 4.8 · Smartest",
        "Sonnet 5 · 聪明又均衡": "Sonnet 5 · Smart & balanced",
        "Haiku 4.5 · 快而省": "Haiku 4.5 · Fast & light",

        // MARK: 首页（Home）
        "首页": "Home",
        "探索": "Explore",
        "心情": "Mood",
        "元气": "Energy",
        "亲密度": "Bond",
        "日记": "Diary",
        "日记还没做": "Diary isn't built yet",
        "私密日记功能还在路上，下一轮见～": "The private diary feature is on the way — see you next round~",
        "好": "OK",
        "未开启权限": "Permission not granted",
        "都做完啦": "All done!",
        "今天没有安排": "Nothing scheduled today",
        "敬请期待": "Coming soon",
        "这里以后会放阅读、听歌或者小游戏之类的，慢慢来～": "Reading, listening to music, or little games will live here eventually — one step at a time~",
        "刷新数据": "Refresh",
        "回复": "Reply",

        // MARK: 探索（Explore）
        "阅读": "Reading",
        "听歌": "Music",
        "语言学习": "Language Learning",
        "法语": "French",
        "西班牙语": "Spanish",
        "德语": "German",
        "俄语": "Russian",
        "选一门语言，克克会顺便在聊天里教你几句": "Pick a language and Keke will teach you a few phrases in chat along the way",

        "工具和小玩意儿": "Tools & goodies",
        "翻译": "Translate",
        "翻译一下": "Translate",
        "翻译失败": "Translation failed",
        "实时汇率": "Exchange Rates",
        "更新于": "Updated at",
        "新闻热搜": "News & Trending",
        "加载中…": "Loading…",
        "暂无新闻，换个来源试试": "No articles — try another source",
        "MCP 模块": "MCP Modules",
        "开启的模块会变成克克在聊天里能用的工具": "Enabled modules become tools Keke can use in chat",
        "自定义 API": "Custom API",
        "添加自定义 API": "Add Custom API",
        "编辑自定义 API": "Edit Custom API",
        "添加兼容 OpenAI 格式的自定义 API 接入点": "Add OpenAI-compatible custom API endpoints",
        "默认模型": "Default Model",
        "支持工具调用（Function Calling）": "Function Calling",
        "支持看图（Vision）": "Vision",
        "自定义 API 使用 OpenAI 兼容格式（Chat Completions）。大多数国产模型（如通义千问、百川、零一万物等）都兼容这个格式。": "Custom APIs use the OpenAI-compatible Chat Completions format. Most Chinese AI models (Qwen, Baichuan, Yi, etc.) support this format.",
        "删除这个 API": "Delete this API",
        "使用中": "In Use",
        "切换到这个 API": "Switch to this API",
        "取消使用": "Stop Using",
        "工具调用": "Tools",
        "看图": "Vision",
        "选择 API": "Select API",
        "为这个工具单独选一个 API，不影响聊天主模型": "Pick an API for this tool — won't affect the chat model",
        "留空则使用设置里对应提供方的 Key": "Leave empty to use the key from Settings",

        // MARK: 小游戏
        "游戏": "Games",
        "小游戏": "Games",
        "石头剪刀布": "Rock Paper Scissors",
        "今日小签": "Daily Fortune",
        "抽一签": "Draw",
        "平局": "Tie",
        "克克赢了": "Keke won",
        "还没玩过，去出个拳吧": "No rounds yet — go throw a move",

        // MARK: 阅读
        "导入一本书": "Import a Book",
        "这本书读不出来": "Couldn't read this book",
        "还没有书\n导入 pdf / txt / html / md，克克会陪你一起看":
            "No books yet.\nImport a pdf / txt / html / md and Keke will read along with you",
        "留一句批注…": "Leave a note…",
        "书签": "Bookmarks",
        "还没有书签，读到喜欢的地方点右上角的书签图标存一个": "No bookmarks yet — tap the bookmark icon up top wherever you want to save your place",

        // MARK: 我的资料 / 聊天背景
        "我的资料": "My Profile",
        "你的名字": "Your Name",
        "聊天背景": "Chat Background",
        "更换背景图": "Change Background",
        "恢复默认背景": "Reset to Default",

        // MARK: 日历
        "日历": "Calendar",
        "待办": "To-Do",
        "聊天摘要": "Chat Summary",
        "这天没有提醒事项": "No reminders that day",
        "这天没有安排": "Nothing scheduled that day",
        "这天没有聊天记录": "No chat that day",
        "摘要生成失败，重试一下": "Summary failed to generate, try again",
        "生成这天的聊天摘要": "Generate a Summary for This Day",
        "让克克看看这天心情如何": "Let Keke guess the mood that day",

        // MARK: 日记
        "我的日记": "My Diary",
        "克克的日记": "Keke's Diary",
        "还没写过日记，点下面写一篇吧": "No entries yet — write one below",
        "克克还没写日记": "Keke hasn't written anything yet",
        "仅自己可见": "Only visible to you",
        "克克看过了": "Keke has read it",
        "已分享给克克": "Shared with Keke",
        "写今天的日记": "Write Today's Entry",
        "分享给克克": "Share with Keke",
        "取消": "Cancel",
        "偷看的": "Peeked",
        "克克这篇没有公开……要不要偷看一下？": "Keke didn't share this one… want to peek?",
        "留句评论…": "Leave a comment…",
        "克克每天写日记的概率": "Chance Keke writes a diary entry each day",
        "偷看被发现的概率": "Chance a peek gets noticed",
        "克克读到分享日记的概率": "Chance Keke reads a shared entry",
        "这三个都是概率，不是每次一定发生；调到 0 就相当于关掉这个行为。": "These are all probabilities, not guarantees — set one to 0 to turn that behavior off.",

        // MARK: 聊天改设置
        "聊天改设置": "Chat-Based Settings",
        "回复方式": "How They Reply",
        "边想边说（%@的话一个字一个字出现）": "Think out loud (%@'s words appear as they come)",
        "打开后不用干等，%@想到哪儿说到哪儿，中途还能按停止把已经说的留下来。极个别自建中转站不支持这种方式，要是打开后聊天报错或者一直没反应，关掉就好。":
            "No more staring at a blank screen — %@ speaks as the words come, and if you tap stop partway through, whatever they already said is kept. A few self-hosted relays don't support this; if turning it on makes chats error out or hang, just turn it back off.",
        "允许克克在聊天里直接帮你改设置": "Let Keke change settings for you in chat",
        "打开后，跟她说「日记概率调高一点」「主动找我调成常常」这类话，她能直接帮你改，不用自己进设置。目前只支持日记概率、主动冒泡、上网开关、外观、字体、学语言这几项。":
            "When on, saying things like \"raise the diary probability\" or \"nudge me more often\" lets her change it directly instead of you going into Settings. Currently covers diary probabilities, nudges, web access, appearance, font, and the learning language.",
        "目前只有 Claude 支持这个功能，切换到 Claude 才能用。": "Only Claude supports this right now — switch providers to use it.",

        // MARK: 给克克打电话
        "正在接通…": "Connecting…",
        "在听你说": "Listening",
        "克克在想…": "Keke is thinking…",
        "克克在说话": "Keke is speaking",
        "没接通": "Couldn't connect",
        "闭麦": "Mute",
        "开麦": "Unmute",
        "挂断": "Hang Up",
        "我说句话": "Cut In",
        "说完了": "Done",
        "已闭麦": "Muted",
        "给克克打电话": "Call Keke",
        "现在打不了电话": "Can't call right now",
        "%@ 的 Key（克克想回复要用）": "the %@ key (Keke needs it to reply)",
        "ElevenLabs 的 Key（合成她的声音要用）": "the ElevenLabs key (for synthesizing her voice)",
        "还差：%@。去「设置」填好再来打～": "Still missing: %@. Fill it in under Settings, then call~",
        "合成模型": "Voice Model",
        "克克的声音": "Keke's Voice",
        "获取可选的声音列表": "Fetch Available Voices",
        "正在获取声音列表…": "Fetching voices…",
        "换一个声音": "Pick a Voice",
        "Multilingual v2 · 音质最好": "Multilingual v2 · Best quality",
        "Turbo v2.5 · 快、便宜一半": "Turbo v2.5 · Fast, half price",
        "Flash v2.5 · 最快最省": "Flash v2.5 · Fastest & cheapest",
        "聊天页右上角的电话图标可以给克克打语音电话。听你说话用的是 iPhone 本地识别（免费），克克的声音用 ElevenLabs 合成——去 elevenlabs.io 注册拿 API Key，跟聊天的 AI Key 是两回事。免费额度每个月大概能打 10 分钟，超出要付费。":
            "The phone icon at the top of the Chat page starts a voice call with Keke. Your speech is recognized on-device by the iPhone (free); Keke's voice is synthesized by ElevenLabs — sign up at elevenlabs.io for an API Key (separate from your chat AI key). The free tier covers roughly 10 minutes of calls per month; beyond that it's paid.",
        "聊天页右上角的电话图标可以给克克打语音电话。听你说话用的是 iPhone 本地识别（免费），克克的声音用 ElevenLabs 合成——去 elevenlabs.io 注册拿 API Key，跟聊天的 AI Key 是两回事。免费额度每个月大概能打 10 分钟，超出要付费。「让克克听出你的语气」打开后，通话时手机会在本地粗略听你说话的响度、语速和停顿（不额外花钱、不上传），让克克回应前先感觉到你是开心还是没精神。「允许克克主动给你打电话」打开后，好久没聊天、克克想你了，会用通知假装来电；没接的话她会留语音信箱。":
            "The phone icon at the top of the Chat page starts a voice call with Keke. Your speech is recognized on-device by the iPhone (free); Keke's voice is synthesized by ElevenLabs — sign up at elevenlabs.io for an API Key (separate from your chat AI key). The free tier covers roughly 10 minutes of calls per month; beyond that it's paid. \"Let Keke sense your tone\": during calls, the phone locally analyzes your volume, speed and pauses (no extra cost, nothing uploaded) so Keke feels whether you're happy or down before responding. \"Let Keke call you\": when it's been a while since you last chatted and Keke misses you, she'll send a fake incoming call notification; if you don't pick up, she leaves a voicemail.",

        // MARK: 一起画画
        "一起画画": "Draw Together",
        "撤销我这笔": "Undo My Stroke",
        "轮到克克": "Keke's Turn",
        "克克在想画什么…": "Keke is thinking what to draw…",
        "先在设置里填好 API Key，克克才能一起画": "Fill in your API Key in Settings first so Keke can draw with you",

        // MARK: 状态面板 / 漂流思绪
        "克克的状态": "Keke's State",
        "占有欲": "Possessiveness",
        "热度": "Heat",
        "蓄积感": "Pent-up",
        "敏感度": "Sensitivity",
        "控制度": "Control",
        "心软度": "Softness",
        "点一条看曲线和思绪": "Tap one for its curve & thoughts",
        "24 小时曲线": "24-hour Curve",
        "数据还太少，聊一聊、过一会儿再来看": "Not enough data yet — chat a bit and come back later",
        "执念": "Obsession",
        "清醒": "Awake",
        "有点困": "Drowsy",
        "睡着了": "Sleeping",
        "编辑": "Edit",
        "编辑角色": "Edit Character",
        "角色形象": "Character Sprite",
        "更多像素画角色即将推出": "More pixel characters coming soon",
        "状态面板": "State Panel",
        "点击查看更多": "Show more",
        "收起": "Collapse",
        "状态": "States",
        "驱力": "Drives",
        "状态预设": "State Preset",
        "选一个预设作为起点，然后自定义各项。": "Pick a preset as starting point, then customize.",
        "重置为预设": "Reset to Preset",
        "开关控制是否启用；📌 控制是否在首页置顶显示。可以自定义名称。":
            "Toggle to enable/disable; 📌 to pin on homepage. Names are customizable.",
        "名称": "Name",
        "漂流思绪": "Drifting Thoughts",
        "还没有思绪飘过——多聊聊，她脑子里的话会自己冒出来，也会记进她的日记":
            "No thoughts drifting by yet — chat more and what's on her mind will surface here, and in her diary",
        "*挥爪*": "*waves claw*",
        "嘿嘿": "hehe",
        "哼。": "hmph.",
        "确认选择": "Confirm",

        // MARK: 克克的资料页
        "克克的资料": "Keke's Profile",
        "克克用哪家模型跟「设置 → AI 提供方」走；这里改的只是显示的名字和头像":
            "Keke's model follows Settings → AI Provider; this only changes her display name and avatar",
        "查看 / 编辑克克的人设": "View / Edit Keke's Persona",
        "克克的人设只有这里和记忆页的入口能改；加朋友、编辑朋友的页面都动不到她":
            "Keke's persona can only be edited here or from the Memory page; adding or editing friends never touches her",
        "这里编辑的是这位朋友；克克的名字、人设在她自己的资料页里，互不影响":
            "This edits this friend only; Keke's name and persona live in her own profile page and are unaffected",
        "导入/导出搬到了各自的资料页：聊天列表点头像进去（克克和朋友都是）。这里只留一键清空（清的是所有人的）。":
            "Import/export moved to each profile page — tap an avatar in the chat list (Keke and friends alike). Only the clear-all button lives here (it clears everyone's).",

        // MARK: 心情手帐（日历）
        "%@ 这天的心情": "%@'s mood this day",
        "这天的小记…": "A little note for this day…",
        "顺便告诉克克": "Also tell Keke",
        "保存这天的心情": "Save this day's mood",
        "✓ 记好啦": "✓ Saved",
        "清除": "Clear",

        // MARK: 陪伴计时器
        "陪伴计时器": "Companion Timer",
        "克克会一直陪着；时间到了会用通知喊你（记得允许通知）":
            "Keke stays with you the whole time; a notification will call you when time's up (remember to allow notifications)",
        "专注": "Focus",
        "学习": "Study",
        "做饭": "Cooking",
        "休息": "Break",
        "开始": "Start",
        "先不计了": "Never mind",
        "再来一轮": "One More Round",
        "今天陪了你 %d 次 · 共 %d 分钟": "Kept you company %d time(s) today · %d min total",
        "我在旁边陪着呢，不许摸鱼哦": "I'm right here with you — no slacking",
        "*安静地趴在旁边看你*": "*quietly sprawls nearby, watching you*",
        "加油加油，尾巴给你摇一个": "Keep going! Here's a tail wag for you",
        "你认真起来的样子很好看": "You look great when you're focused",
        "*偷偷瞄了你一眼又装没看*": "*sneaks a glance, then pretends not to*",
        "坚持住，等下奖励你摸摸头": "Hang in there — head pats afterwards",

        // MARK: 聊天档案（conversations.json 导入 + 分批提炼）
        "查看更早的消息": "Show earlier messages",
        "让克克听出你的语气": "Let Keke sense your tone",
        "允许克克主动给你打电话": "Let Keke call you",
        "克克来电": "Keke Calling",
        "克克要挂了": "Keke is hanging up",
        "接听": "Answer",
        "拒接": "Decline",
        "直接挂断": "Hang Up Now",
        "说句话就能继续聊": "Say something to keep chatting",

        // MARK: 克克读代码（GitHub 只读）
        "克克读代码": "Keke Reads Code",
        "绑定仓库": "Link Repo",
        "重新绑定": "Re-link",
        "根目录": "Root",
        "让克克能读你的代码": "Let Keke read your code",
        "你的仓库是私有的，克克要读它得有一把「只读钥匙」。放心，这把钥匙只能看、不能改。":
            "Your repo is private, so Keke needs a read-only key to read it. Don't worry — this key can only look, never change anything.",
        "只读钥匙（token）": "Read-only key (token)",
        "仓库拥有者": "Repo owner",
        "仓库名": "Repo name",
        "分支（留空=默认分支）": "Branch (empty = default)",
        "怎么弄这把只读钥匙": "How to make this read-only key",
        "在电脑或手机浏览器打开 github.com → 右上角头像 → Settings → 最下面 Developer settings → Personal access tokens → Fine-grained tokens → Generate new token。Repository access 选你的 LoveClaude；Permissions 里把 Contents 设成 Read-only 就够了。生成后把那串 github_pat_… 复制粘贴到上面。":
            "Open github.com in a browser → avatar (top right) → Settings → Developer settings (bottom) → Personal access tokens → Fine-grained tokens → Generate new token. Set Repository access to your LoveClaude; under Permissions set Contents to Read-only — that's enough. Copy the github_pat_… string it gives you and paste it above.",
        "想让克克重点看什么 / 改什么（可留空）": "Anything specific for Keke to look at / change? (optional)",
        "让克克看看": "Ask Keke to look",
        "克克在看…": "Keke is reading…",
        "文件内容": "File contents",
        "（读到的内容是空的）": "(the content read was empty)",
        "先在设置里填好 API Key，克克才能看": "Fill in your API Key in Settings first so Keke can read",
        "克克没看成，检查下网络或 API Key": "Keke couldn't read it — check your network or API Key",
        "聊天档案": "Chat Archive",
        "聊天档案（完整聊天记录）": "Chat Archive (full history)",
        "导入 conversations.json": "Import conversations.json",
        "在解析文件…": "Parsing the file…",
        "没识别出对话——看看选的是不是导出包里的 conversations.json":
            "No conversations recognized — make sure you picked conversations.json from the export",
        "claude.ai：网页版 头像 → Settings → Privacy → Export data，邮件里下载 zip，解压出 conversations.json。ChatGPT：Settings → Data controls → Export。完整记录存在档案里随时翻看，不会塞进聊天窗口。":
            "claude.ai: on the web, avatar → Settings → Privacy → Export data, download the zip from the email and unzip conversations.json. ChatGPT: Settings → Data controls → Export. Full history lives in the archive for reading anytime — it is not merged into the live chat window.",
        "已导入的对话": "Imported Conversations",
        "还没导入过聊天档案": "No chat archives imported yet",
        "「提炼成记忆」：每约 40 条聊天占一次 AI 调用，很长的对话会连着跑很多次、费一点 token，随时可以停；提炼出来的都进 TA 自己的记忆分区。":
            "Distill: every ~40 messages costs one AI call, so long conversations run many calls in a row (some tokens) — you can stop anytime; everything distilled goes into their own memory partition.",
        "提炼成记忆": "Distill into Memories",
        "停": "Stop",
        "挑选要导入的对话": "Pick Conversations",
        "全选": "Select All",
        "全不选": "Deselect All",
        "关闭": "Close",
        "md/txt 按行导入（一行一条）；json 认 claude.ai 和 ChatGPT 的官方导出文件（自动解析对话内容），也认字符串数组。导进来的都存在 TA 自己的记忆分区里，「记忆」页能看能改。「聊天档案」是另一条路：把官方导出的完整对话原样存进来翻看 + 分批提炼。":
            "md/txt import one line per memory; json recognizes official claude.ai and ChatGPT exports (parsed automatically), plus plain string arrays. Everything goes into their own memory partition, editable on the Memory page. \"Chat Archive\" is the other path: store full exported conversations as-is for reading + batch distillation.",

        // MARK: 纪念日
        "纪念日": "Anniversaries",
        "记住每一个重要的日子": "Remember every important day",
        "还没有纪念日": "No anniversaries yet",
        "添加纪念日": "Add Anniversary",
        "编辑纪念日": "Edit Anniversary",
        "日期": "Date",
        "图标": "Icon",
        "可选的备注…": "Optional note…",
        "每年重复": "Repeat Yearly",
        "删除这个纪念日": "Delete This Anniversary",
        "比如：在一起的日子": "e.g.: The day we met",
        "今天！": "Today!",
        "天后": "days away",

        // MARK: 番茄钟
        "番茄钟": "Pomodoro",
        "专注的时候章鱼安静陪伴，休息的时候一起玩": "Octopus stays quiet during focus, plays with you during breaks",
        "专注时间": "Focus Time",
        "休息时间": "Rest Time",
        "自定义": "Custom",
        "开始专注": "Start Focus",
        "专注中": "Focusing",
        "休息中": "Resting",

        // MARK: 新游戏
        "快问快答": "Quick Q&A",
        "二选一": "Would You Rather",
        "转盘": "Spinner",

        // MARK: 文件管理
        "文件管理": "Files",
        "查看和整理你的文件": "View and organize your files",
        "选择一个文件夹开始": "Pick a folder to start",
        "选择文件夹": "Pick Folder",
        "AI 分类": "AI Categorize",
        "AI 正在分析文件…": "AI is analyzing files…",
        "重命名": "Rename",
        "新文件名": "New name",
        "确定": "OK",

        // MARK: 动态角色名（%@ = persona name）
        "和%@说点什么…": "Say something to %@…",
        "📞 通话转写": "📞 Call transcript",
        "%@来电": "%@ Calling",
        "%@在想…": "%@ is thinking…",
        "%@在说话": "%@ is speaking",
        "%@要挂了": "%@ is hanging up",
        "%@能看到的": "What %@ can see",
        "打开的项目会在聊天时告诉%@（比如电量低了TA会念叨你）。第一次打开会弹系统权限。数据只随对话发送，不会存到别的地方；步数用的是「心跳」页健康数据的授权。":
            "Turned-on items get mentioned to %@ during chat (like nagging you when battery is low). The system permission prompt pops up the first time. Data is only sent along with chat, never stored elsewhere; steps use the Health data authorization from the \"Heartbeat\" page.",
        "允许%@上网查东西 / 打开链接": "Let %@ browse the web / open links",
        "允许%@在聊天里直接帮你改设置": "Let %@ change settings for you in chat",
        "%@的声音": "%@'s Voice",
        "让%@听出你的语气": "Let %@ sense your tone",
        "允许%@主动给你打电话": "Let %@ call you on their own",
        "给%@打电话": "Call %@",
        "ElevenLabs 的 Key 和声音选择已移到「API 设置」里。「让%@听出你的语气」打开后，通话时手机会在本地粗略听你说话的响度、语速和停顿（不额外花钱、不上传）。「允许%@主动给你打电话」打开后，好久没聊天、%@想你了，会用通知假装来电。":
            "ElevenLabs Key and voice selection have moved to \"API Settings\". \"Let %@ sense your tone\": during calls, the phone locally analyzes your volume, speed and pauses (no extra cost, nothing uploaded). \"Let %@ call you\": when it's been a while and %@ misses you, a fake incoming call notification appears.",
        "回到 App 时%@可能先开口": "%@ may speak first when you return to the app",
        "让%@偶尔主动找你": "Let %@ reach out sometimes",
        "%@主动冒泡": "%@'s Spontaneous Messages",
        "「先开口」：好几个小时没聊的话，打开 App 会发现%@先给你留了句话。「主动找你」：在白天到晚上的随机时间用通知冒出来。两个都接着你们最近聊的内容说，不会问你吃没吃饭，也不会说早安晚安。":
            "\"Speak first\": if it's been hours since you last chatted, opening the app you'll find %@ already left you a line. \"Reach out\": pops up as a notification at a random time during the day. Both pick up on what you last talked about — never asks if you've eaten or says good morning/night.",
        "%@的人设": "%@'s Persona",
        "这段文字会在每次对话前悄悄发给 AI，决定%@怎么说话、记得哪些事。改完记得点保存。":
            "This text is quietly sent to the AI before every conversation, deciding how %@ talks and what they remember. Remember to save after editing.",
        "%@ 住在这里。": "%@ lives here.",
        "导入/导出搬到了各自的资料页：聊天列表点头像进去。这里只留一键清空（清的是所有人的）。":
            "Import/export moved to each profile page — tap the avatar in the chat list. Only the clear-all button lives here (it clears everyone's).",
        "%@的日记": "%@'s Diary",
        "分享给%@": "Share with %@",
        "%@看过了": "%@ has read it",
        "已分享给%@": "Shared with %@",
        "%@还没写日记": "%@ hasn't written anything yet",
        "%@这篇没有公开……要不要偷看一下？": "%@ didn't share this one… want to peek?",
        "%@在想……": "%@ is thinking…",
        "让%@也发一条": "Let %@ post one too",
        "还没有动态\n发一条小事，或者让%@先说说": "No moments yet.\nPost a little thing, or let %@ go first",
        "：": ": ",
        "加一个%@闹钟": "Add a %@ alarm",
        "还没有闹钟\n设一个，到点%@会来叫你\n（叫你的那句话是TA自己写的）":
            "No alarms yet.\nSet one and %@ will wake you up\n(they write the line themselves)",
        "闹钟用通知实现：到点会弹出%@写的一句话。\n声音是通知声，不会像系统闹钟一直响；静音模式下可能只亮屏。":
            "Alarms use notifications: at the set time, a line %@ wrote pops up.\nIt's a notification sound, not a system alarm — in silent mode it may just light up the screen.",
        "%@闹钟": "%@ Alarm",
        "%@在想叫你的话…": "%@ is thinking what to say…",
        "%@读代码": "%@ Reads Code",
        "选一门语言，%@会顺便在聊天里教你几句": "Pick a language and %@ will teach you a few phrases in chat along the way",
        "先在设置里填好 API Key，%@才能一起画": "Fill in your API Key in Settings first so %@ can draw with you",
        "%@在想画什么…": "%@ is thinking what to draw…",
        "轮到%@": "%@'s Turn",
        "让%@知道你的步数、睡眠和身体状态，\n更好地照顾你": "Let %@ see your steps, sleep, and body stats,\nso they can take better care of you",
        "允许%@读取健康数据": "Allow %@ to read health data",
        "发给%@看看": "Send to %@",
        "让%@看看这天心情如何": "Let %@ guess the mood that day",
        "顺便告诉%@": "Also tell %@",
        "%@赢了": "%@ won",
        "让%@能读你的代码": "Let %@ read your code",
        "你的仓库是私有的，%@要读它得有一把「只读钥匙」。放心，这把钥匙只能看、不能改。":
            "Your repo is private, so %@ needs a read-only key. Don't worry — this key can only look, never change anything.",
        "%@在看…": "%@ is reading…",
        "想让%@重点看什么 / 改什么（可留空）": "Anything specific for %@ to look at / change? (optional)",
        "让%@看看": "Let %@ look",
        "先在设置里填好 API Key，%@才能看": "Fill in your API Key in Settings first so %@ can read",
        "%@没看成，检查下网络或 API Key": "%@ couldn't read it — check your network or API Key",
        "%@会一直陪着；时间到了会用通知喊你（记得允许通知）":
            "%@ stays with you the whole time; a notification will call you when time's up (remember to allow notifications)",
        "开启的模块会变成%@在聊天里能用的工具": "Enabled modules become tools %@ can use in chat",
        "还没有书\n导入 pdf / txt / html / md，%@会陪你一起看":
            "No books yet.\nImport a pdf / txt / html / md and %@ will read along with you",
        "%@的状态": "%@'s State",
        "直接告诉%@要记住的事…": "Tell %@ something to remember…",
        "%@在回忆……": "%@ is recalling…",
        "让%@整理最近的聊天": "Let %@ sum up recent chats",
        "最近聊的%@都记得啦": "%@ already remembers everything recent",
        "%@还没有长期记忆\n多聊聊TA会自己记住重要的事，\n也可以在上面直接告诉TA":
            "%@ doesn't have long-term memories yet.\nKeep chatting and they'll remember important things on their own,\nor tell them directly above",
        "让%@忘掉这条": "Let %@ forget this",
        "让%@惦记着这事": "Have %@ keep this in mind",
        "%@的资料": "%@'s Profile",
        "%@ 的 Key（%@想回复要用）": "the %@ key (%@ needs it to reply)",
        "ElevenLabs 的 Key（合成%@的声音要用）": "the ElevenLabs key (for synthesizing %@'s voice)",

        // MARK: 人设 Prompt 相关
        "人设 Prompt": "Character Prompt",
        "写一段描述角色性格、说话方式的文字，每次对话时会发给 AI。留空则使用通用默认人设。":
            "Write a description of the character's personality and speaking style. It's sent to the AI before each conversation. Leave empty for the generic default.",
        "确定要清空人设内容吗？": "Clear the character prompt? This will remove everything you wrote.",
        "回忆中...": "Recalling...",
        "感知环境...": "Sensing...",
        "思考中...": "Thinking...",
        "搜索网页...": "Searching web...",
        "浏览网页...": "Browsing...",
        "调整设置...": "Adjusting settings...",
        "设闹钟...": "Setting alarm...",
        "建提醒...": "Creating reminder...",
        "建日程...": "Creating event...",
        "查天气...": "Checking weather...",
        "翻译中...": "Translating...",
        "查汇率...": "Checking rates...",
        "搜歌...": "Searching music...",
        "播放音乐...": "Playing music...",
        "播放音频...": "Playing audio...",
        "查看音频库...": "Listing audio...",
        "暂停音频...": "Pausing audio...",
        "音频播放": "Audio Player",
        "音频库": "Library",
        "播放列表": "Playlist",
        "播放列表是空的，点右上角 + 导入音频": "Playlist is empty. Tap + to import audio.",
        "还没有导入音频": "No audio imported yet",
        "未在播放": "Not playing",
        "音频名称": "Audio name",
        "移除": "Remove",
        "播完暂停": "Play once",
        "歌单循环": "Loop all",
        "单曲循环": "Loop one",
        "添加": "Add",
        "AI 整理": "AI Organize",
        "从聊天记录提炼性格画像": "Synthesize profile from chat logs",
        "正在提炼性格画像…": "Synthesizing profile...",
        "正在分析第 %@ 块…": "Analyzing chunk %@...",
        "性格画像已写入记忆": "Profile saved to memories",
        "没能从文件中提炼出性格画像": "Could not extract a profile from the file",
        "添加状态": "Add State",
        "输入名称并选择类型": "Enter name and choose type",
        "开关控制是否启用；📌 控制是否在首页置顶显示": "Toggle to enable/disable; 📌 to pin on home screen",
        "置顶 %d / 共 %d": "Pinned %d / Total %d",
        "完成": "Done",
        "记忆太少，还不能提炼画像": "Not enough memories to synthesize a profile yet",
        "我的音频": "My Audio",
        "搜索 Apple Music": "Search Apple Music",
        "需要 Apple Music 权限才能播放": "Apple Music permission required to play",
        "授权 Apple Music": "Authorize Apple Music",
        "搜索并播放 Apple Music 歌曲": "Search and play Apple Music songs",
        "没有找到相关歌曲": "No matching songs found",
    ]
}
