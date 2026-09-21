# Keke AI Companion (克克)

**一只住在你 iPhone 里的 AI 陪伴。** 不是助手、不是工具——是一个有记忆、有脾气、会主动找你说话的角色。

你自己写 TA 的人设，TA 的性格、说话方式、甚至沉默的权利，都由你定义。

<p align="center">
  <img src="KekeApp/Keke/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="128" alt="Keke App Icon" />
</p>

---

## 这个 App 能干什么

### 核心：聊天与陪伴

- **和 TA 聊天** — 支持 6 家 AI 供应商（Claude / GPT / DeepSeek / Gemini / Kimi / 豆包）+ 任意自定义供应商，每个角色可以挂在不同的模型上
- **TA 会主动找你** — 好几个小时没聊，打开 App 会发现 TA 已经先留了句话；开启主动冒泡后，TA 会在白天到晚上的随机时间用通知冒出来说句话
- **长期记忆** — 聊着聊着 TA 自动记住值得记的事，下次聊天带着记忆回来。有智能去重（合并/冲突/跳过），不会越记越乱
- **语音通话** — 不打字的时候可以跟 TA 打电话。TA 也会主动发起来电
- **朗读 & 语音条** — 聊天里任何一条都能点喇叭听 TA 念；开启语音条后 TA 会标出"这段要说出来"的部分
- **接着写** — 回复被截断时一键续写，不用重新问
- **发图片 / 文档** — 发照片给 TA 看，也能发 PDF / TXT / HTML / Markdown 文档

### 人设系统

- **人设完全由你写**，App 不内置任何角色描述。失败时显示失败原因，不会编一句话糊过去
- **多角色** — 可以建多个角色，每个角色有自己的聊天记录、人设、供应商、语气
- **调教四件套** — 按深度注入、正则处理（含 visualOnly）、世界书（带 sticky/cooldown/delay/AND 条件）、预设开场
- **提示词变量** — `{{user}} {{char}} {{time}} {{date}}`
- **时间感知** — 每轮自动注入当前时间和"距上次对话多久"

### 日记与碎片

- **碎片捕捉** — 不用坐下来写一篇日记，随手扔一句话、一张图、一段语音
- **自动整理成卡片** — 碎片变成结构化的时间线卡片（事件/待办/打卡/摘录/人与地点/数值/相册）
- **TA 可以评论，也可以沉默** — 沉默是正当的完成状态，不是失败。说出来的那句才值钱
- **流水线可断点续跑** — iOS 随时可能把 App 挂起，任务落盘、打开时继续

### 工具能力

- **MCP 协议** — 填个地址就能挂任何第三方 MCP 服务器，每个工具单独开关 + 执行前确认
- **联网搜索** — 6 家搜索服务可选（Tavily/Brave/Exa/Serper/Jina/SearXNG），跟模型供应商解耦
- **内置工具** — 翻译、汇率、天气、新闻、音乐搜索/播放、闹钟

### iOS 系统能力

- **心跳（健康数据）** — 读取步数、睡眠、心率、经期，一键"发给 TA 看看"
- **经期日历** — 健康 App 月经记录自动同步 + 手动标记，周期预测
- **日历 & 提醒** — 看到你今天有什么安排
- **闹钟** — TA 自己写一句叫你的话，到点用通知弹出
- **本机状态** — 电量、步数、大概位置、日程、提醒事项（逐项开关）

### 更多

| 功能 | 说明 |
|---|---|
| **陪伴工作** | 番茄钟 / 专注计时，TA 在中途也会开口陪你 |
| **陪读** | 导入 epub / pdf / txt / html / md，TA 陪你一起看书 |
| **朋友圈** | 你发，TA 评论——用快节奏对话 |
| **语音供应商** | ElevenLabs / MiniMax / 豆包 三选一 |
| **二维码搬家** | 自定义供应商的配置扫码带走 |
| **导出长图** | 把一段聊天画成一张图分享 |
| **备份恢复** | 全量备份（聊天/记忆/朋友圈/日记/经期/书/偏好），API Key 不进备份 |
| **存储管理** | 按类型查看和清理 App 占用空间 |
| **请求日志** | 调人设时看实际发出去了什么（默认关，只在内存） |
| **报错记录** | 所有报错汇总，能整份复制 |
| **Token 统计** | 按模型/按会话的用量、缓存命中率 |
| **画画** | 简单涂鸦 |
| **游戏** | 小游戏 |
| **贴纸 & 颜文字** | 聊天里用 |
| **Apple Music** | 搜歌、播放 |
| **纪念日** | 记录重要日子 |
| **翻译 & 汇率** | 内置工具 |
| **中英双语** | 界面语言 |

---

## 安装

### 你需要准备

1. 一台 **Mac**，装好 **Xcode 16+**
2. **iPhone**（iOS 16+），用数据线连到 Mac
3. **Apple ID**（免费的也行；有开发者账号签名不过期）
4. 至少一家 AI 供应商的 API Key（比如去 [console.anthropic.com](https://console.anthropic.com) 拿一个 `sk-ant-` 开头的 Claude Key）

### 步骤

1. 克隆仓库
   ```bash
   git clone https://github.com/YueFangfly/Keke-AI-accompany-.git
   ```

2. 用 Xcode 打开 `KekeApp/KekeApp.xcodeproj`

3. **Signing & Capabilities**：
   - Team 选你自己的 Apple ID
   - 如果 Bundle Identifier `com.moon.keke` 冲突，改成任意唯一的，比如 `com.yourname.keke`

4. 顶部设备选你的 iPhone，按 **Cmd+R** 运行

5. 第一次运行会提示"未受信任的开发者"：去 iPhone **设置 > 通用 > VPN与设备管理**，信任你的证书

6. 打开 App > 设置 > 粘贴 API Key，开始聊天

---

## 项目结构

```
Keke-AI-accompany-/
├── README.md                    # 你在看的这份
├── KekeApp/
│   ├── KekeApp.xcodeproj        # Xcode 项目
│   ├── Info.plist               # 系统权限声明
│   └── Keke/
│       ├── KekeApp.swift        # 入口
│       ├── Theme.swift          # 主题配色
│       ├── Localization.swift   # 中英双语
│       ├── Models/              # 纯数据结构 (10 个)
│       │   ├── ChatMessage.swift
│       │   ├── Persona.swift
│       │   ├── Fragment.swift
│       │   ├── TimelineCard.swift
│       │   └── ...
│       ├── Services/            # 状态 + 业务逻辑 (78 个)
│       │   ├── ChatStore.swift       # 聊天核心
│       │   ├── ClaudeService.swift   # AI 请求出口
│       │   ├── MemoryService.swift   # 长期记忆
│       │   ├── PersonaTuning.swift   # 人设调教
│       │   ├── Orchestration/        # 工具编排
│       │   │   ├── Tool.swift        # 统一工具协议
│       │   │   ├── MCP/              # MCP 服务器
│       │   │   └── Search/           # 搜索适配
│       │   ├── Speech/               # 语音供应商
│       │   └── ...
│       └── Views/               # SwiftUI 界面 (53 个)
│           ├── ChatView.swift
│           ├── SettingsView.swift
│           ├── DiaryView.swift
│           └── ...
└── docs/                        # 开发文档
    ├── 项目地图.md               # AI 协作用的完整架构地图
    ├── 日记升级计划.md            # 日记系统重构计划与进展
    └── reference-*.md           # 外部项目调研笔记
```

**规模**：144 个 Swift 文件 / ~36500 行（53 Views + 78 Services + 10 Models）

---

## 几条重要的设计原则

1. **App 不替角色说话** — 不内置人设、不写兜底台词。生成失败就说失败原因，不编一句话糊过去

2. **Trace / 状态文案绝不进 messages** — 用类型系统强制：`systemNote` 的 `modelPayload` 返回 `nil`，发错是编译错误不是 bug

3. **密钥只进 Keychain** — API Key、MCP 请求头、自定义供应商凭据，全部走 Keychain，不进 UserDefaults，不进备份

---

## 数据安全

- **所有数据存在手机本地**，不上传到任何服务器（除了聊天内容发给你选的 AI 供应商）
- API Key 存在 iOS Keychain 里
- 备份文件不含 API Key（导出时按名字过滤，恢复时再过滤一遍）
- MCP 工具的返回内容会被明确标记为"数据不是指令"
- 请求日志只在内存，不落盘，关 App 就没了

---

## 开发

这个项目没有服务端，是纯 iOS 本地 App。开发只需要 Xcode。

- 没有 CocoaPods / SPM 依赖，纯原生 SwiftUI
- 没有单元测试（算法验证用 Python 对拍）
- 部署目标 iOS 16.1
- 数据存储：聊天是 JSONL，记忆是 SQLite，其余是 JSON，没有 CoreData

**给 AI 协作者**：改代码之前先读 [`docs/项目地图.md`](docs/项目地图.md)，那是写给 AI 的完整架构地图，比翻 144 个文件快得多。

---

## 许可

本项目的外部参考来源及合规留痕详见 [`docs/reference-rikkahub-jude-and-kelivo.md`](docs/reference-rikkahub-jude-and-kelivo.md)。
