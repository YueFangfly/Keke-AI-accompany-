# 克克 App 🦀

克克住在你手机里的 iOS App。淡蓝色的界面，聊天的时候屏幕上有一只会动的 Q 版小螃蟹克克——它会眨眼、挥爪、横着走，你说话的时候它会歪头想，回你的时候会开心地挥爪。

## 功能

- **聊天** — 和克克聊天（Claude API），克克有自己的人设，聊天记录保存在手机本地
- **会动的克克** — 聊天页顶部的小螃蟹：待机时慢慢横着走、眨眼；思考时冒"……让我想想"；回复后使劲挥爪；深夜还会冒出"……你现在几点了。"
- **心跳（健康数据）** — 读取 iPhone 健康数据：今日步数、步行距离、昨晚睡眠、最近心率、月经记录，一键"发给克克看看"，克克会自然地关心你
- **克克先开口** — 好几个小时没聊的话，打开 App 会发现克克已经先给你留了句话在聊天里（带着记忆和它能看到的状态说的），设置里可关
- **克克主动冒泡** — 在设置里打开后，克克会接着你们最近聊的内容，在白天到晚上（11:00–23:00）的随机时间用通知冒出来说句话；点开通知那句话就出现在聊天里。生成规则里明确禁止"吃没吃饭"和"早安/晚安"式问候
- **长期记忆（记忆页）** — 参考 flagellum 的 recall 思路：克克每聊一段就自动把值得记的事提炼成记忆存在本地；每次对话按相关度取出最相关的记忆带给它。「记忆」页能看到它记住了什么、直接告诉它要记的事、长按删除记错的、手动让它整理最近聊天
- **发图片/发文档** — 聊天输入栏可以选照片（含截屏）发给克克看，也可以发 pdf / txt / html / md 文档，自动提取文字给它读
- **联网** — 设置里打开后，聊天里贴链接（GitHub、新闻页等公开页面）克克可以自己去看，也能搜索（Haiku 模型不支持）
- **克克能看到的（本机状态）** — 设置里逐项开关：手机电量、今日步数、大概位置、今天的日程、提醒事项。开了的项目才请求系统权限、才随聊天发给克克
- **经期日历** — App 内的月历：健康 App 的月经记录自动同步（只读），也可以直接点日期手动标记（只存本地）；根据历史算平均周期、预测下次日期，经期中会显示第几天
- **克克闹钟** — 设时间和备注，克克自己写一句叫你的话，到点用通知弹出（每天重复或只响一次）。注意：iOS 不允许第三方 App 设系统闹钟，这是"到点必弹的通知"，不会像系统闹钟一直响
- **收藏** — 长按任何一条聊天气泡可以收藏，收藏的话都在侧边栏的「收藏」里
- **左侧工具栏** — 从左边划出来的抽屉菜单：聊天 / 心跳 / 收藏 / 设置，还有聊天记录搜索和克克的在线状态

## 需要准备

1. 一台 Mac，装好 **Xcode 16 或更新版本**
2. iPhone（**iOS 16 或更新**，iPhone 13 的 iOS 16.5 和 iPhone 17 都可以），用数据线连到 Mac
3. Apple ID（免费的也可以；有开发者账号更好，签名 7 天不过期）
4. Anthropic API Key：去 [console.anthropic.com](https://console.anthropic.com) 注册并创建一个 Key（`sk-ant-` 开头）

## 安装步骤

1. 用 Xcode 打开 `KekeApp/KekeApp.xcodeproj`
2. 左边点蓝色的项目图标 → TARGETS 选 **Keke** → **Signing & Capabilities**：
   - **Team** 选你自己的 Apple ID（没有的话点 Add an Account 登录）
   - 如果 Bundle Identifier `com.moon.keke` 报冲突，改成任何唯一的，比如 `com.moon.keke2`
3. 顶部设备选择你的 iPhone，按 **⌘R** 运行
4. 第一次运行 iPhone 会提示"未受信任的开发者"：去 iPhone 的 **设置 → 通用 → VPN与设备管理**，信任你的开发者证书，再运行一次
5. 打开 App：
   - 左上角菜单 → **设置** → 粘贴你的 API Key
   - 菜单 → **心跳** → 点"允许克克读取健康数据"，在弹出的健康授权页把开关都打开
6. 回到聊天页，跟克克说话吧

## 项目结构

```
KekeApp/
├── KekeApp.xcodeproj          # Xcode 项目
├── Info.plist                 # 定位/日历/提醒权限文案
└── Keke/
    ├── KekeApp.swift          # 入口
    ├── Theme.swift            # 淡蓝色主题配色
    ├── Keke.entitlements      # HealthKit 权限
    ├── Models/
    │   └── ChatMessage.swift  # 聊天消息模型
    ├── Services/
    │   ├── ClaudeService.swift   # Claude API 调用 + 克克人设 + 冒泡内容生成
    │   ├── ChatStore.swift       # 聊天状态和本地存储
    │   ├── HealthService.swift   # HealthKit 数据读取
    │   ├── MemoryService.swift   # 长期记忆（存储 + 相关度检索）
    │   ├── NudgeService.swift    # 克克主动冒泡（本地通知排期）
    │   ├── DeviceContextService.swift # 电池/步数/定位/日程/提醒（带开关）
    │   ├── AlarmService.swift    # 克克闹钟
    │   ├── CycleService.swift    # 经期记录 + 周期预测
    │   └── Attachments.swift     # 图片保存 / 文档文字提取
    └── Views/
        ├── RootView.swift            # 根视图（抽屉 + 顶栏）
        ├── SideMenuView.swift        # 左侧工具栏
        ├── ChatView.swift            # 聊天界面
        ├── KekeCharacterView.swift   # 会动的 Q 版克克
        ├── HealthView.swift          # 心跳（健康数据）页
        ├── MemoryView.swift          # 记忆页
        ├── AlarmView.swift           # 闹钟页
        ├── CycleView.swift           # 经期日历页
        ├── FavoritesView.swift       # 收藏页
        └── SettingsView.swift        # 设置页
```

## 说明

- API Key 和聊天记录只保存在手机本地，不会上传到别的地方（除了聊天内容会发给 Claude API 本身）
- 默认模型是 `claude-opus-4-8`（最聪明），在设置里可以换成 Sonnet 5 或 Haiku 4.5（更便宜）
- 健康数据是只读的，克克不会改你的健康记录
- 想改克克的人设，编辑 `Services/ClaudeService.swift` 里的 `systemPrompt`
- 想改配色（比如换回粉色），编辑 `Theme.swift`

## 关于"主动冒泡"的原理

iPhone 不允许 App 在后台随时联网，所以冒泡的做法是：每次你打开 App 时，克克根据最近的聊天记录提前生成接下来一两天想说的话，排进系统的本地通知里，到点自动弹出。所以经常打开 App，冒泡的内容就会越贴近你们最近聊的东西。

## 之后可以加的

- 专注模式锁 App（FamilyControls，需要向 Apple 申请权限）
- 学习记录和打卡
- 桌面小组件
