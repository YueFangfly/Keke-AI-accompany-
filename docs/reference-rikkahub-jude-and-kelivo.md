# 克克 App 外部参考分析：rikkahub-Jude 与 Kelivo

> 调研日期：2026-08-28 ｜ 基线复核：2026-08-28（对齐到 `c4a77e4` 快照）
> 调研对象：克克 iOS App（`KekeApp/`，SwiftUI，**85 个 swift 文件 / 23923 行**）
> 参考对象：`Lin-chpin/rikkahub-Jude`（Kotlin / Jetpack Compose，Android）、`Chevey339/kelivo`（Flutter / Dart，全平台）
>
> **维护约定**：第 2 节是「克克现状」的唯一事实来源，动手改代码前先看它、改完后更新它。
> 其余章节讲的是外部项目的设计，除非重新调研，否则不随克克的改动变化。

---

## 0. 使用本文档的唯一规则

> **只学设计，自己写实践。**

从这两个项目里只吸收**设计思路、数据模型的组织方式、流程与状态机的划分、提示词的结构、踩坑经验**；
**不复制它们的任何代码**。所有落到 `KekeApp/` 里的 Swift 代码都按克克现有的架构、命名习惯和代码风格重新写。

### 为什么这条规则是硬性的

| 项目 | 许可证 | 影响 |
|---|---|---|
| `Chevey339/kelivo` | **AGPL-3.0** | 有传染性。逐行抄进克克并分发，会要求整个克克开源。哪天想上架 App Store 就是实打实的问题 |
| `Lin-chpin/rikkahub-Jude` | 自定义「用户分段双重许可 (Segmented Dual Licensing)」 | 条款非标准，逐行抄同样有风险 |

架构思路、数据模型设计、提示词流程、参数取值经验这些**不受版权保护**，可以放心学。
另外一个现实因素：两个项目一个是 Kotlin、一个是 Dart，**本来也没有 Swift 代码可抄**——唯一的例外是 Kelivo 的 iOS Live Activity 扩展（182 行 Swift），那部分也只看设计不照搬。

---

## 1. 三个项目的定位

| | 定位 | 技术栈 | 对克克的价值 |
|---|---|---|---|
| **克克** | 陪伴体验 + iOS 系统能力（HealthKit / 日历 / 提醒 / 经期 / 闹钟） | SwiftUI，原生 iOS | 这是护城河，两个参考项目都没有 |
| **rikkahub-Jude** | 陪伴向功能的 Android 实现 | Kotlin / Compose / Room / DataStore | **陪伴功能**的参考：朋友圈时序、心跳状态机、通话状态闭环 |
| **Kelivo** | 通用工具型 LLM 客户端，已上架 App Store | Flutter / Dart / Hive + Drift | **底座工程**的参考：压缩、记忆、流式、备份、用量统计 |

Kelivo 的 `PRODUCT.md` 里写的品牌调性是 "Practical, calm, and capable / 界面应该退到对话背后"——它刻意不做陪伴向的东西：没有朋友圈、没有主动冒泡、没有语音通话、没有日记、没有养成。
反过来，rikkahub-Jude 的底座工程不如 Kelivo 干净。**两边取长补短。**

血缘关系：Kelivo 的 README 明确写了「UI 设计深受 RikkaHub 启发」，两者同源，但 Kelivo 是跨端重写版本。

---

## 2. 克克当前状态（对照基线）

> **上次复核：2026-08-28**（基线 `c4a77e4`）；**上次更新：2026-08-29**（编排层 + 表情栏修复后）。
> 本节所有结论都是在 `KekeApp/` 里 grep + 读代码确认的事实，不是推测。
> **改完一项就更新对应行**，避免后续照着过期信息动手。

规模：**92 个 swift 文件 / 26439 行**（40 Views + 41 Services + 8 Models）
—— 相对基线 `c4a77e4` 增加 7 个文件 / 2516 行，删除 `Services/KekePrompt.swift`。

### 2.1 仍然缺失的（本文档要解决的目标）

| 项 | 现状 | 位置 |
|---|---|---|
| ~~流式输出~~ | ✅ **已完成 2026-08-29**。provider 无关的 `StreamEvent` + 两个 SSE 解码器；流式结果重建成和非流式一样的结构，工具循环未改动。设置页有按人设的开关 | `Services/StreamDecoding.swift`、`Services/ClaudeService.swift` |
| ~~上下文管理~~ | ✅ **已完成 2026-08-29**。滚动摘要压缩：老消息压成摘要随请求发，近期消息原样发；保留段从用户消息起算；超上下文时二分重试，额度整棵树共用。压缩只影响请求窗口，聊天列表仍是全量原文 | `Services/ContextCompressor.swift`、`Services/ChatStore.swift` |
| ~~Markdown 渲染~~ | ✅ **已完成 2026-08-29**。块级（标题/列表/引用/代码块/分割线）自己排，行内（加粗/斜体/行内代码/链接）交给 `AttributedString(markdown:)`。代码块可横向滚动 + 一键复制。用户自己发的消息保持纯文本。表格和公式未做 | `Views/MarkdownText.swift` |
| ~~消息操作~~ | ✅ **已完成 2026-08-29**。长按加「重新生成」（只对最后一条 AI 回复）和「改一下重发」（会删掉这条之后的消息）。多版本用 `groupId`+`version`+`isActive` 表示，气泡下方 `‹ 2/3 ›` 切换，旧版本留在文件里不删。出错的那条也是 AI 消息，重新生成即重试 | `Services/ChatStore.swift`、`Views/ChatView.swift` |
| ~~错误处理~~ | ✅ **已完成 2026-08-29**。按状态码分 11 类，每类自己声明可不可重试；退避用全抖动，服务端给 `Retry-After` 就听它的（超 20 秒则不重试、直接告知）。三个请求出口收敛到共用的分类函数。流式已推过字的失败不重试 | `Services/APIFailure.swift` |
| ~~Token 用量的展示~~ | ✅ **已完成 2026-08-29**。气泡下一行小字（模型 · token · 缓存命中 · 耗时，设置里开关）+ 独立统计页（总量 / 缓存比例 / 按模型 / 按会话 / 统计覆盖率） | `Services/UsageStats.swift`、`Views/UsageStatsView.swift` |
| **API 请求日志** | ❌ 无。（注意：`Services/ActivityLog.swift` 是**用户行为日志**——记录「看了新闻」「查了汇率」这类事件喂给克克当上下文，**不是** API 请求日志，别混淆） | — |
| ~~`max_tokens`~~ | ✅ **已完成 2026-08-29**。改成 `send()` 的参数，按角色可配（1k/2k/4k/8k）。其余按任务调好的小上限没动 | `Services/ChatStore.swift`、`Views/SettingsView.swift` |
| **普通聊天 TTS** | ❌ ElevenLabs 只接在 `VoiceCallService` 里，聊天页无朗读、无语音条 | `Services/VoiceCallService.swift` |

### 2.2 已经有了 / 部分有了（上一版文档写错或已过时的行）

| 项 | 现状 | 位置 |
|---|---|---|
| **temperature / top_p** | ✅ **已有，且是按人设隔离的**。`-1` 表示不传、走 API 默认值；设置页有滑杆 + 开关 | `Services/ChatStore.swift:173-179`、`Views/SettingsView.swift:726-780` |
| **人设体系** | ✅ 已从 `Contact` 中独立出 `Persona`（id / name / icon / color / subtitle / systemPrompt / characterType），`ChatStore` 整体按 `personaId` 分区（聊天记录、主题、语言、字体、温度、开关全部独立） | `Models/Persona.swift`、`Services/ChatStore.swift:182` |
| **API Key 存储** | ✅ 已迁进 **Keychain**，并带 UserDefaults 旧数据自动迁移 | `Services/APIKeyStore.swift` |
| **供应商** | ✅ 从 4 家扩到 **6 家**（+ Gemini、Kimi）+ **自定义供应商**；新增 `supportsFunctionCalling` 能力标记 | `Services/Providers.swift`、`Views/CustomProviderView.swift` |
| ~~备份导出~~ | ✅ **导出 + 恢复都已完成 2026-08-29**（见 2.10）：整包备份，聊天/记忆/朋友圈/日记/经期/书/偏好全进去，图片音频可选；恢复分两步、隔一次启动 | `Services/BackupService.swift`、`Views/BackupView.swift` |
| **本地工具 / MCP** | ⚠️ 有一套自建的轻量 MCP 注册表（翻译、汇率、音乐搜索/播放、闹钟、天气、新闻），不是标准 MCP 协议 | `Services/MCPRegistry.swift`、`WeatherMCP` / `NewsMCP` / `AudioMCP` |
| **`ChatMessage` 字段** | ✅ **已补齐**（2026-08-28）：`usage`（`TokenUsage`：input / output / cacheRead / cacheWrite 四份互不重叠）、`durationMs`、`model`、`providerId`、`groupId` + `version`（为「重新生成」预留）、`translation`。全部走 `decodeIfPresent`，旧 JSONL 照常读；各家 usage 口径的差异在 `ClaudeService` 的 `parseClaudeUsage` / `parseOpenAIUsage` 边界抹平 | `Models/ChatMessage.swift`、`Services/ClaudeService.swift` |

### 2.4 人设与提示词的边界（2026-08-29 起）

**App 不再内置任何角色描述。** `KekePrompt.swift` 已删除，`genericSystemPrompt` 已删除，
联系人的兜底人设也已删除。发给模型的 system prompt = 用户自己写的人设 + 功能协议说明。

- 人设来源：设置页的自定义人设 > 该 Persona 自带的 `systemPrompt`；都为空就只发协议说明
- 协议说明在 `Services/ChatProtocolPrompt.swift`：目前只有「选项按钮」的格式说明，
  以及「改设置工具」的用法（跟着那个开关走）。这样换任何人设功能都不会失效
- 「心里话」（`<thinking>`）功能已整体移除：提示词、解析、UI 全删。
  `ChatMessage.thinking` 字段保留但改作**通话转写**存放处（`appendCallRecord` 在用），
  存储键名不变，老数据照常读
- system prompt 为空时整个字段不发（Claude 不发 `system`，OpenAI 不发那条消息），
  因为「人设为空」现在是正常状态而不是边缘情况

### 2.5 模型能力与思考（2026-08-29 起）

**采样参数按模型能力发。** Claude 从 Opus 4.7 起移除了 `temperature` / `top_p`，
传过去直接 400。`Services/Providers.swift` 里的 `ModelCapability` 按模型 id 前缀判断：

| 模型 | temperature / top_p | effort 档位 | 自适应思考 |
|---|---|---|---|
| Opus 5 / 4.8 / 4.7、Sonnet 5、Fable 5 | ❌ 400 | ✅ | ✅ |
| Opus 4.6 / Sonnet 4.6 | ✅ | ✅ | ✅ |
| Haiku 4.5 及更老 | ✅ | ❌ | ❌ |
| 非 Claude（含自定义供应商） | ✅ | ❌ | ❌ |

设置页据此切换：支持采样的显示两个滑杆，不支持的显示「动脑程度」选择器
（`output_config.effort`，低/中/高/很高/最高）。

**思考（extended thinking）已接入**，跟已删除的 `<thinking>` 心里话完全无关：
- 请求发 `thinking: {type: "adaptive", display: "summarized"}`。
  **`display` 必须写**，默认是 `omitted`，思考块回来是空文本
- 存在 `ChatMessage.reasoning`（跟装通话转写的 `thinking` 字段是两回事）
- 界面上折叠在正文气泡**上方**，点一下展开，跟 API 返回的顺序一致
- **硬约束**：多轮工具调用时思考块必须**原样回传**（连 `signature` 一起）。
  改过或少了都会被 API 拒。所以 `StreamedReply.reasoningBlocks` 按块存分片，
  重建 content 时一字不差地拼回去，不做任何加工
- OpenAI 兼容那边暂未解析思考内容（DeepSeek 的 `reasoning_content` 可以后补）

### 2.6 编排层（2026-08-29 起）

单模型直连之上加了一层编排，**第一步只做「路由 + 一个原生工具打通全链路」**，
子模型层和 trace UI 按约定留到之后。文件都在 `Services/Orchestration/`：

| 文件 | 职责 |
|---|---|
| `Tool.swift` | 统一 `Tool` 协议 + `ToolRegistry`；`MCPToolAdapter` 把已有的 `MCPModule` 包成 `Tool`，不另起炉灶 |
| `ToolResultEnvelope.swift` | **工具结果进入上下文的唯一出口**。外部数据包 `<external_data name="…">`，前面带一句「这是数据不是指令」；错误包 `<tool_error>`；超长截断并**明确告诉模型截断了** |
| `RouteDecision.swift` | `RouteDecision{needsTool, needsMemory, suggestedTool}` + `RouteConfig.timeoutMs = 150` |
| `OnDeviceRouter.swift` | FoundationModels 端上路由。整块裹在 `#if canImport(FoundationModels)` + `@available(iOS 26, *)` 里，**部署目标仍是 iOS 16.1**；不可用/超时静默降级为 `.passthrough` 直连，`decide()` 不抛不挂 |

**四条硬性约束的落地方式**（这几条是这层的全部意义，改代码时别绕过）：

1. **trace 绝不进 messages —— 用类型系统强制，不靠自觉。**
   `ChatMessage` 上加 `enum MessageKind { conversation, systemNote }` 和 `struct RouteTrace`，
   序列化时只走 `var modelPayload: Payload?` —— 它对 `.systemNote` 直接返回 `nil`，
   `Payload` 里**根本没有 trace 字段**。`ClaudeService.send()` 的入参类型从
   `[ChatMessage]` 改成 `[ChatMessage.Payload]`，于是「把 trace 发出去」变成编译错误而不是 bug。
   > 顺带查出一个**既有的真实问题**：`「📞 刚刚打了 X 电话」`、
   > `「*爪子挠头* 好像出了点问题」` 这类状态文案**原本每轮都在发给模型**——
   > 正是这条约束要防的那种「模型模仿格式凭空编造」。现已全部标成 `.systemNote`。
2. **工具返回标记为数据** —— 只能经 `ToolResultEnvelope` 进上下文，见上表。
3. **不做多模型投票/合成** —— 主选模型是唯一对用户说话的模型，路由层只输出决策不输出文本。
4. **API key 存 Keychain** —— 本来就是（`Services/APIKeyStore.swift`），未改动。

**待办**：`OnDeviceRouter.swift` 里的 FoundationModels API 面需要在真机 iOS 26 SDK 上核一遍
（`@Generable` / `@Guide` / `LanguageModelSession` 的确切签名）。因为整块在条件编译里，
不影响当前 iOS 16.1 构建。

### 2.8 错误分类与退避重试（2026-08-29 起）

在此之前所有非 200 都被抹成 `AIError.badResponse("HTTP 429")`——上层分不清
「等一下会好」和「配置错了永远不会好」，于是既没有重试，用户看到的也只是一串状态码。

`Services/APIFailure.swift` 按状态码分 11 类，**每类自己声明可不可重试**：

| 可重试 | 不可重试 |
|---|---|
| 429 限流、529 过载、5xx、网络、超时 | 400 格式、401 Key、403 权限、404 模型名、413 过大、认不出的状态码 |

几个判断上的取舍：

- **网关状态码给 500 但 body 里写着 `overloaded_error` 时以 body 为准** —— 分类更准
- **退避用全抖动** `random(0, min(cap, base·2ⁿ))`，不是固定的 1s/2s/4s。
  限流常常是多个请求同时撞上来的，固定间隔会让它们退避完又**同时**重来再撞一次
- **服务端给了 `Retry-After` 就听它的**（秒数和 HTTP 日期两种写法都认），
  但要求等待**超过 20 秒就不重试**，直接告诉用户还要等多久 ——
  与其让界面转圈转一分钟，不如把决定权交回去
- **默认 3 次尝试**（首次 + 2 次重试），注定失败的请求最多多等约 3 秒
- **报错文案改成「下一步该干什么」**。只有用户自己能改的（Key、模型名）才附服务端原文；
  服务端自己的毛病附上原文只会更迷惑

三个请求出口收敛到共用的 `failure(http:json:provider:)` 和 `perform(_:provider:)`，
不再各写各的状态码判断。`ClaudeService` 里现在只剩两处 `URLSession.shared`
（非流式一处、流式一处），都在这层之内。

**流式的两个额外约束**：

1. 解码器是有状态的，重试必须换新的 —— `runStream` 收的改成**工厂**而非实例，
   单次尝试拆成 `runStreamOnce`
2. **已经往界面推过字的失败一律不重试**（`APIFailure.emittedOutput`）——
   重来一遍用户会看见文字倒退再重放一次

中途错误原本只带文案，现在把 `error.type` 一起编进 `stopReason`（用 `\u{1F}` 分隔——
错误正文里出现冒号很正常，出现控制字符不正常），这样 `overloaded_error`
在流中途报出来也能被正确识别为可重试。老格式仍能解析。

> 顺带修掉一个**静默失败**：OpenAI 兼容流里中途的 `{"error": {...}}` 帧原本被整个忽略，
> 回复会无声无息断在半截，界面上完全看不出出过错。

`ContextCompressor.isContextLengthError` 改为优先读 `APIFailure.message`（服务端原文）——
否则会被新的友好文案挡住，超上下文时的二分重试就失效了。

### 2.9 Token 用量展示（2026-08-29 起）

数据 2026-08-28 就落在 `ChatMessage.usage` 里了，但界面上一个字都没有。
这一层**纯读**：不改数据、不碰请求链路。

**气泡下的一行小字**（设置里开关，默认关）：

```
claude-opus-4-8  ·  ↑12.3k ↓486  ·  ⚡︎74%  ·  3.4s
```

`↑` 是全部输入侧 token（普通输入 + 缓存读 + 缓存写）；`⚡︎` **只在真命中缓存时才出现**——
没命中时显示「缓存 0%」只是噪音。开关是**全局**的不是按人设分：
这是「想不想看后台数字」的偏好，跟人设是谁无关。

**统计页**（`Views/UsageStatsView.swift`）：

| 分区 | 内容 |
|---|---|
| Token 总量 | 四个桶互不重叠，加起来就是合计 |
| 缓存与速度 | **输入里来自缓存的比例**、平均耗时、平均输出 |
| 按模型 / 按会话 | 按总量降序 |
| 统计范围 | 统计到的回复数，**以及没有用量数据的回复数** |

缓存比例是**判断 prompt caching 有没有生效的直接证据**。分母用
`input + cacheRead + cacheWrite`——写缓存那部分也是这次真金白银发过去的输入。
长期是 0% 就说明前缀被弄脏了（通常是人设或工具列表每次都在变）。

「没有用量数据的回复数」必须显示出来：老消息、报错的、不回 usage 的中转站都统计不到，
不写出来的话用户会以为上面的数字是全量的。

**聚合（`Services/UsageStats.swift`）上的两个坑**：

1. 同一个人设可能**同时存在** `X_chat.jsonl` 和迁移前的 `X_chat.json`。
   `ChatStore.load()` 优先读 jsonl，这里必须照做，否则同一批消息会被数两遍
2. 人设 id 和联系人 id 是**两个命名空间，可能撞车**（联系人里就有
   `claude` / `gpt` / `deepseek` 这几个短 id）。聚合键给联系人加 `contact:` 前缀分开，
   不然两份不相干的记录会被加到一起

直接扫目录而不是照着人设列表去找，是为了把**已删除人设留下的记录**也算进来——
那些 token 也是真花掉了的。名字查不到就显示 id 本身，比瞎给一个名字诚实。
整个扫描扔进 `Task.detached`：聊到几万条时在主线程解 JSON 会卡出可见的白屏。

### 2.10 备份导出（2026-08-29 起）

在此之前只有记忆能导出，聊天记录、朋友圈、日记都出不来。

**格式是 JSONL**：第一行清单，后面每行一个文件条目。不用「一个大 JSON」，
是因为带图的备份可能上百 MB——整个拼在内存里再序列化，在手机上会被系统直接杀掉；
一行一个对象的话，导出写完一行就能丢掉，将来做导入也能一行一行读。

清单要等全写完才知道文件数和跳过列表，但**必须在第一行**。做法是先占 512 字节的
空行，正文写完再回填并用空格补齐行长——只改开头这一段，不用把后面几百 MB 搬一遍。
跳过列表撑爆占位行时降级成「跳过 N 个」：宁可少记信息，也不能把文件写坏。

| 进备份 | 不进 |
|---|---|
| Documents 下所有 `json` / `jsonl` / `sqlite3`（聊天、记忆、朋友圈、日记、经期、书、贴纸清单…） | API Key（见下） |
| 过滤后的偏好设置 | 系统自己的偏好（`Apple*` / `NS*` / `com.apple.*` / `WebKit*`） |
| 图片 / 音频 / 贴纸图（跟开关走，体积差一个量级） | 单个 > 25 MB 的文件（记进清单的跳过列表） |

**安全上的两件事**：

1. **备份不含 API Key。** Key 在 Keychain 里本来就读不到，偏好设置那部分还额外按名字
   过滤了一遍（`api_key` / `apikey` / `token` / `secret` / `password` / `_key` 子串 + 两个精确名）。
   对着全项目的 UserDefaults 键做了对拍：过滤器**命中且仅命中** `ai_api_keys`、
   `eleven_api_key`、`gh_token` 三个真密钥，**零误伤**（`keyboard_height` 这种含 "key"
   的正常键不受影响）。
2. ✅ **顺带发现并修掉的问题**：`eleven_api_key`（ElevenLabs）和 `gh_token`（GitHub）
   原本**明文存在 UserDefaults 里**，跟「API key 存 Keychain」的约定不符。
   已迁进 Keychain（`APIKeyStore.Secret`，用 `service:` 前缀跟提供方 id 分开）。
   迁移是读时自动做的：第一次读到空值就去 UserDefaults 捞老数据，捞到就搬进 Keychain
   并删掉明文原件，用户无感。备份侧的过滤保留不动，当第二道防线。

**恢复：分两步，中间隔一次启动。** 直接把文件写回 Documents 不行——`ChatStore`、
`MemoryService` 这十几个 Store 内存里还拿着旧数据，下一次自动保存就把刚恢复的内容
盖回去了，用户会以为恢复失败，其实是被自己覆盖的。

1. 第一步只把备份解到 `_restore_pending/`，**不动任何现有数据**
2. 第二步在 **`KekeApp.init()`** 里真正搬进 Documents。App 的 init 跑在 `body` 求值之前、
   早于任何 `@StateObject` 的构造，是唯一稳妥的位置。没有待恢复内容时开销就是一次 bool 读取

界面上明说了需要把 App 从后台完全划掉再打开。

**恢复侧的两道防线**：

- **路径不能信。** 备份是从外面导进来的：绝对路径、`~`、`..`、`.`、空路径段、
  以及两个内部目录名一律拒绝，被拒条目数显示给用户
- **偏好设置写回时再过滤一遍**密钥和系统键。就算是自己导出的备份，也不能假设中间没被改过

**被换下来的旧文件不删，挪到 `_pre_restore/`。** 同一个卷上这是改名，不占额外空间，
恢复错了还能捞回来，只留最近一次。备份里没有的文件保持原样不动。

读取按 1 MB 分块 + 按行切，内存占用只跟**单行**大小相关，不跟整个备份大小相关。
`inspect()` 只读第一行拿清单（哪天的、多大），不解正文；格式版本比当前 App 新的直接拒绝。

### 2.11 角色各自的提供方与生成上限（2026-08-29 起）

**每个角色可以挂在不同的 AI 上。** `provider` / `model` / `customProviderId` 原本是
**全局**的（键名 `ai_provider`、`ai_models`、`custom_provider_id`，都没有 personaId 前缀），
所有角色共用一家——这一点上一版文档里的「`ChatStore` 整体按 `personaId` 分区」说得不准确。
现在按角色分区，新建角色的界面里直接选提供方和模型。

- 默认跟着**上次用的那家**走，不写死某一家。平时用 DeepSeek 却默认成 Claude，
  然后因为没填 Claude 的 Key 一发消息就报错——这种事发生一次就够烦了
- 界面上直说这家**有没有填过 Key**，省得建完角色才发现要去别处配
- **Key 本身仍然按提供方共用**：一个 Anthropic 账号就一把 key，每个角色各存一份没意义

**回落规则里踩到的一个真 bug**（对拍时发现）：光靠「有没有角色专属的键」判断不了配没配过。
新建角色选了内置提供方时，代码只是**不写**自定义提供方的键，可老用户的全局
`custom_provider_id` 还在，回落下去就把人家刚选的那家顶掉了。
所以加了一个**正面标记** `_provider_configured`：配过的角色只看自己的键、一律不回落；
没配过的老角色才回落到旧全局键（升级前后看到的是同一家）。
解析逻辑集中在 `PersonaProvider.resolve` 一个函数里。

> `PersonaProvider` 放在 `ChatStore` **外面**而不是当它的静态成员：`ChatStore` 是
> `@MainActor` 的，而新建角色的界面要在 `@State` 默认值里就读到默认提供方——
> 那是个非隔离的同步上下文，调 `@MainActor` 成员编译不过。这里只读写 UserDefaults，
> 本来也不需要主线程。

**`max_tokens` 不再写死。** 主聊天四条路径（Claude / OpenAI × 流式 / 非流式）都是 4096，
想让 TA 写长一点就会被硬生生截断，而且截断了界面上还看不出来。
改成 `send()` 的参数，按角色可配（1k / 2k / 4k / 8k）。上限保守取 8192：再往上得按模型区分
（新 Claude 能到 128k，DeepSeek 只有 8k），发超了直接 400，与其猜不如给个各家都吃得下的数。
其余那些 200 / 300 / 1500 的小上限是按任务调好的，没动。

### 2.12 MCP：用户自己加服务器（2026-08-29 起）

内置那 7 个模块（翻译/汇率/天气/新闻/音乐/闹钟/音频）是**写死在 App 里的**，
用户加不了新的。现在填个地址就能挂任何第三方 MCP 服务器。

**接得进来是因为编排层当初就是为这个留的口子**：`MCPRemoteTool` 实现 `Tool` 协议，
工具循环、`ToolResultEnvelope` 的包装截断、缓存前缀排序**一行没改**。
内置模块和远端工具最后合成一份清单交给模型。

| 文件 | 职责 |
|---|---|
| `MCPProtocol.swift` | JSON-RPC 2.0 的形状 + `tools/call` 结果拍平 |
| `MCPTransport.swift` | 两种传输的实现（见下） |
| `MCPServerConfig.swift` | 服务器配置 + 存取（**header 走 Keychain**）+ `MCPStatus` 五态 |
| `MCPConnection.swift` | 单台服务器的会话：握手 → 列工具 → 调工具 |
| `MCPServerRegistry.swift` | 增删改、重连、汇总出可用的 `Tool` |
| `MCPRemoteTool.swift` | 远端工具 → `Tool` 的适配 |
| `MCPApprovalGate.swift` | 「执行前问我一声」的闸门 |

**两种传输都实现了**：

- **Streamable HTTP**（现行协议）：POST 一次拿回包，回包可能是 `application/json`
  也可能是 `text/event-stream`，后者要读到我们等的那个 id 为止。
  会话 id 从 `Mcp-Session-Id` 头拿，之后每个请求带上；服务器降级协议版本时照单接受
- **SSE**（旧协议，不少服务器只支持这个）：GET 开一条常驻流，服务器在
  `event: endpoint` 里给 POST 地址，**回包从流上回来**。所以要有后台任务读流 +
  一个 actor 按 id 派发给在等的请求；**流断了要把所有等待者一起失败掉**，
  不然它们会永远挂着

**从 rikkahub 抄的三个设计**：

1. **`MCPStatus` 五态**（idle / connecting / connected(n) / reconnecting(第几次/共几次) / failed(原因)）。
   连接状态**必须能在界面上看见**——否则工具静默失效跟没配过一模一样，
   用户只会觉得「这个模型怎么不会查天气」
2. **指数退避重连**，直接复用已有的 `RetryPolicy`。次数用完停在 failed 让用户手动重连：
   无限重试只会烧电量，地址配错了再试一万次也没用
3. **每个工具单独开关 + 「执行前问我一声」**。第三方给什么工具事先不知道，
   会删东西、会花钱的得能拦。**超时默认拒绝**——宁可这次没调成，
   也不能因为界面没弹出来就自动放行

**安全上的两点**：

- **请求头存 Keychain 不存 UserDefaults**。里面常常是 `Authorization: Bearer …`，
  跟 API Key 是一回事，也不会跟着备份文件流出去
- 远端返回一律标 `isExternalData`，经 `ToolResultEnvelope` 明确告诉模型
  **这是数据不是指令**

> **对拍时揪出的一个真 bug**：工具名消毒本来用 `isLetter` 判断，
> 可它**对中文返回 true**，而各家 API 的函数名都要求 `[a-zA-Z0-9_-]`——
> 一个中文名的工具会让整个请求 400。改成只留 ASCII，全中文的名字用
> FNV-1a 稳定哈希兜底（**不能用 Swift 的 `hashValue`**：它每次启动加的盐不同，
> 工具名一变 prompt cache 就全失效）。

### 2.7 期间修掉的缺陷

| 缺陷 | 根因 | 提交 |
|---|---|---|
| 采样参数在默认模型上必 400 | 基线代码无条件发 `temperature`/`top_p`，而默认模型 `claude-opus-4-8` 已移除该参数——用户一动滑杆就报错 | `9ae6aad` |
| 编译不过：颜文字里的反斜杠 | `"(/ω\)"` 里 `\)` 不是合法 Swift 转义。**来自基线快照，非本轮引入** | `17e88c7` |
| 编译不过：找不到三个 `@ViewBuilder` | 采样滑杆/档位/思考开关插进了 `SettingsView`，调用点却在 `PromptEditorView`（这三项属于人设编辑弹层，不属于设置主页） | `5eec2d0` |
| 表情快捷栏从第二个起显示「…」 | 写死 `.frame(width: 38)`，只有首个单 emoji 放得下；后面都是 2 字符以上，`.title3` 下需 40pt+。改成内容自适应胶囊 `fixedSize + minWidth 38`，`Circle` → `Capsule` | `9d21d3d` |

> 容器内没有 Swift 工具链，每次提交的验证手段是：全量括号配平（先剥字符串和注释）、
> 纯算法用 Python 重跑一遍对拍（Markdown 分块边界、`ContextCompressor.split`、
> 版本机制、`ToolResultEnvelope.wrap` 输出、`ModelCapability` 矩阵）、
> 死代码检查、字典字面量重复键审计（Swift 重复键是**运行时崩溃**，不是编译错误）、
> 非法转义序列扫描。**这些都不能替代真机编译**。

### 2.3 已有且做得不错的

多供应商（6 家 + 自定义）、SQLite 记忆库 + 相关度检索、人设体系、朋友圈、日记、经期日历、闹钟、健康数据、主动冒泡、语音通话、聊天档案、Apple Music / 本地音频播放器、贴纸、颜文字、番茄钟、纪念日、翻译、汇率、新闻、文件管理、中英双语。

---

## 3. 【最高优先级】三个可以直接开工的设计

### 3.1 上下文压缩 —— 学 Kelivo `compress_context_options.dart`

**参考位置**：`kelivo/lib/core/models/compress_context_options.dart`（纯逻辑、无框架依赖）

克克现在 `suffix(40)` 硬截断，聊得越久越失忆，MemoryService 兜不住。要学的设计点：

**四种压缩模式**
- `start` —— 保留开头
- `recent` —— 保留最近
- `keepRecent` —— 保留最近 N 轮**用户消息**（推荐给克克用这个）
- `unlimited` —— 不限

**按上下文窗口算字符预算**
```
window     = 模型上下文窗口 token 数（未知时保守取 32k）
usable     = window × (1 − 0.30)        // 预留 30% 给压缩提示词和模型输出
chars      = floor(usable × 1.6)        // 1.6 = 中文场景的 字符/token 系数
budget     = min(100_000, chars)        // 10 万字符硬上限，防止单次请求爆掉
```
token 估算按中英分开：`CJK 字数 / 1.6 + 其他字符数 / 4`。
中文一个字约 0.6 token，英文约 4 字符一 token——**混着算会严重低估中文**。

**压缩请求本身超上下文时的二分重试**
> 切成两半 → 分别摘要 → 把两份摘要拼起来再摘要一次

最多递归 5 层；单块小于 512 字符就不再切（防止对超密文本无限重试）。
判断「是不是上下文超限错误」要靠白名单短语匹配（`context_length` / `prompt is too long` / `reduce the length of the messages` 等），**不能只看到 `max_tokens` 就当成超限**——那可能只是配置错误。

**两个容易踩的坑**
1. **保留区间必须从一条 user 消息开始**。否则模型会看到一个没有提问的回答，行为会飘。
2. **小对话要少保留**。默认保留轮数按规模缩放：用户消息 < 5 轮 → 保 1 轮，< 10 → 保 2，≥ 10 → 保 3。否则小对话「压了个寂寞」（保留的就是全部）。

**模型降级链**（很实用）
```
压缩模型 → 摘要模型 → 标题模型 → 助手模型 → 全局默认
```
provider 和 model id **分别解析**，允许「用 A 家的 key 配 B 家的模型名」这种半配置状态继续往后降级。
对克克的直接收益：摘要用 Haiku、聊天用 Opus，省一大笔钱。

**Swift 实现注意**：Dart 那边要处理 UTF-16 代理对切分问题（`utf16_safe_cut.dart`）。Swift 的 `String.Index` 天然按 grapheme cluster 走，`prefix(n)` 不会切坏 emoji——**但如果按 `utf16.count` 算预算就要小心**。

---

### 3.2 流式输出 —— 学 Kelivo `docs/ai-stream.md` 的事件抽象

**参考位置**：`kelivo/docs/ai-stream.md`（68 行，写得极清楚）+ `lib/core/services/api/stream/`

**别一上来就写 Claude 专用解析。** 先定义 provider 无关的事件类型：

| 系列 | Start | 增量 | 结束 |
|---|---|---|---|
| 文本 | `TextStart` | `TextDelta` | `TextEnd` |
| 思考 | `ReasoningStart` | `ReasoningDelta` | `ReasoningEnd` |
| 本地工具 | `ToolCallStart` | `ToolCallDelta` | `ToolCallEnd` |
| 托管工具 | `ServerToolStart` | `ServerToolInputDelta` | `ServerToolEnd` |
| 图片 | `ImageStart` | `ImageDelta` / `ImageSnapshot` | `ImageEnd` |
| 收尾 | — | `Usage` / `Annotations` | `Finish`（恰好一次） |

Swift 里就是一个 `enum StreamChunk`（带 associated value），各家 provider 的解析器把自己的 wire protocol 翻译成它。

**四条关键经验**

1. **每个系列按 id 定位，交错到达时不要「更新最后一个 part」。**
   Claude 会把 thinking 块和 text 块交错吐出来，简单往尾部追加会串行。

2. **多轮工具调用要传不同的 sourceId**（`round-0`、`round-1`）。
   如果两轮都用字面量 `"text"` 当 id，第二轮的文本会被并进第一轮的 TextPart 里。这是他们真实踩过并写进文档的坑。

3. **非流式走同一条合并路径。**
   `stream: false` 也进同一个 handler 合并成 parts，这样只有一套解析逻辑，不会两边行为不一致。

4. **托管工具（Claude 的 web_search / web_fetch）单独一条通道**，不要和本地工具混用同一组事件。

**测试方法值得学**：真打一次 provider，把 **SSE 分帧之后、解码之前** 的原始事件录成 `events.jsonl`，之后当快照回放测试。改解析逻辑先看快照 diff。
他们也明确写了这套回放的**盲区**：非 SSE 的一次性 JSON 响应、以及把图片塞进 `delta.images` 普通字段的协议，都不会出现在轨迹里——改这两类解析时不能只靠快照变绿。

---

### 3.3 给 `ChatMessage` 补字段 —— 学 Kelivo `chat_message.dart`

**这一项最急**，因为克克的聊天记录是 **JSONL 追加写**的，晚一天就多一天历史数据补不回来。

> **2026-08-28 复核补充**：克克的 `ChatMessage` 已经有自定义 `init(from decoder:)`（为了兼容后加的 `choices` / `multiSelect` / `audioTrackId`），
> 所以补字段的向后兼容有现成落点——新字段一律 `decodeIfPresent` + 默认值，旧 JSONL 能照常读。

Kelivo 的 `ChatMessage` 相比克克多出来的字段：

| 字段 | 用途 |
|---|---|
| `promptTokens` / `completionTokens` / `cachedTokens` / `totalTokens` | 用量统计、算钱 |
| `durationMs` | 生成耗时 |
| `modelId` / `providerId` | 这条是哪个模型说的（换模型后回看很重要） |
| `reasoningText` / `reasoningStartAt` / `reasoningFinishedAt` | 思考过程和思考时长 |
| `translation` | 翻译结果，按条缓存 |
| `groupId` + `version` | **消息版本化**（见下） |
| `isStreaming` | 流式进行中标记 |

**消息版本化设计（比 rikkahub 的分支树轻，更适合克克）**

rikkahub 用的是完整的 `Conversation + MessageNode` 分支树，对克克这种单线聊天太重。
Kelivo 只用两个字段：**同一个语义位置的多次重生成共享 `groupId`，`version` 从 0 递增**，UI 上左右箭头切换版本。实现成本低得多，效果基本一样。

**TokenUsage 的合并语义有讲究**（流式场景）：
- 同一轮内合并（`merge`）：prompt / completion / cached 各取**较大值**，因为流式里这些字段会重复下发、逐步增长
- 跨轮累加（`accumulate`）：直接相加
- 两者不能混用。Claude 的两段式拼接、Gemini 的 usageMetadata 重放都依赖这个区分

---

## 4. 【次高优先级】记忆系统升级 —— 学 Kelivo `core/services/memory/`

**参考位置**：`kelivo/lib/core/services/memory/`（12 个文件 5600 行；代码注释里带 §12.4 §12.6 这类规格编号，说明背后有正经设计文档）

克克现在的 `MemoryService` 是「定期提炼 + 相关度检索」，Kelivo 是一条四段流水线：

```
Gatekeeper（这段对话值不值得记？）
  → Extractor（提炼成条目）
    → Smart Add（新增 / 合并 / 冲突 / 跳过，四选一）
      → Profile Distiller（把零散记忆蒸馏成「用户档案」字段）
```

要学的设计点：

**1. Gatekeeper 先过一道便宜的判断**
让模型只回 `<user_memory>true</user_memory>` 或 `false`，不值得记就不跑后面的贵流程。
克克现在是每隔几轮无条件跑一次提炼——这一步能省一半钱。

**2. Smart Add：新记忆撞上旧记忆，四选一**
```
neu      新增
merge    合并进已有条目（给出合并后的文本）
conflict 标记冲突（新旧矛盾，需要人来定）
skip     跳过（已有等价信息）
```
克克的 `MemoryDatabase` 现在只有 `insert`，聊久了必然堆一堆重复和自相矛盾的条目。

**3. 记忆分类型**
`identity`（身份/事实）/ `workflow`（习惯/做事方式）/ `voice`（说话风格）/ `instruction`（明确指令）。
注入上下文时**按类型分组**，每组超过上限就只取最近更新的几条，而不是一锅按相关度取 24 条。

**4. watermark（水位线）机制**
解析失败 / 请求失败**不推进水位线**，下次重跑同一段。保证不会因为一次 JSON 解析失败就永久漏掉一段对话。

**5. 中文候选召回**
`memory_tokenizer.dart` 里有一份中文停用词表（`用户 的 了 是 在 和 与 会 要 对 这 那 他 她 它`）+ CJK 二元组切分。
克克的 `searchCandidates` 用的是 SQL LIKE，换成这个思路能明显提升相关度。

**6. 作用域**
`MemoryScope { global, assistant }` + `MemorySource { manual, tool, extracted, distilled }`。
rikkahub 那边还多一个 `conversation` 作用域，并且有条重要规则：**本地记忆工具写入的记忆固定归属助手级**，会话/全局开关只控制「工具注不注入」，不改变已保存记录的作用域——否则同一个助手的不同聊天窗口会互相看不到对方记的事。

---

## 5. 【中优先级】值得抄的功能设计

### 来自 Kelivo

| 功能 | 参考位置 | 要点 |
|---|---|---|
| **Token 用量统计页** | `features/stats/` | GitHub 式热力图、按模型/助手/话题排名、输入/输出/缓存 token 分开算、时间范围预设（本月/上月/本季度…） |
| **备份 + 跨 App 导入** | `core/services/backup/`（30 个文件） | S3 / WebDAV；能直接导入 Cherry Studio 和 ChatBox 的备份。**恢复流程做得极重**：租约锁、暂存区、切换执行器、回执、启动闸门、失败回滚——因为恢复失败会丢全部数据，这个「重」是必要的 |
| **世界书 / Lorebook** | `core/models/world_book.dart` | 关键词触发（支持正则、大小写敏感、扫描深度）、`constantActive` 常驻项、按 `priority` 和 `injectDepth` 注入 |
| **提示词变量** | `core/services/chat/prompt_transformer.dart` | `{{ role }}` `{{ message }}` `{{ time }}` `{{ date }}` |
| **快捷短语** | `features/quick_phrase/` | 输入框上方一排常用句 |
| **对话导出成长图** | `chat/widgets/message_export_sheet.dart` | 长图分享，连 mermaid 图都渲染进去 |
| **存储空间管理页** | `settings/pages/storage_space_page.dart` | 看哪些附件/缓存占地方、可单独删。克克的 `attachments` 目录现在只进不出 |
| **应用内日志查看器** | `settings/pages/log_viewer_page.dart` | 看每次请求实际发了什么。调人设时这个排查能力极有价值 |
| **二维码分享供应商配置** | `features/scan/` | 换手机时扫个码把 API 配置搬过去 |
| **21 个搜索引擎适配** | `core/services/search/providers/` | Bing / DDG / Exa / Tavily / 智谱 / Brave / SearXNG / Perplexity / Serper / Jina… |

### 来自 rikkahub-Jude

| 功能 | 参考位置 | 要点 |
|---|---|---|
| **助手配置的完整字段集** | `data/model/Assistant.kt`（30+ 字段） | 见下方 5.1 |
| **正则输入/输出处理** | `AssistantRegex` | 带 `visualOnly` 标记——只影响显示、不影响发给模型。调教输出格式时极好用 |
| **按深度注入提示词** | `PromptInjection` | `position` 支持开头 / 结尾 / `AT_DEPTH`（从最新消息往前数第 N 条）；可指定以 user 还是 assistant 身份注入。对长对话维持人设明显比「拼在 system prompt 后面」有效 |
| **朋友圈的惰性时序** | `MomentsVM.kt` | AI 对用户动态首次反应等 10–20 分钟、对每条新评论等 3–8 分钟；**到期任务在打开/刷新时才处理**，不需要后台。这套模型对 iOS 后台限制特别友好，可以直接搬 |
| **匿名提问箱** | `AnonymousQuestionBoxOverlay.kt` | 助手作用域内的匿名提问，用户和 AI 都能发，AI 延迟回答，用户可回答一次，AI 再追评。实现成本低（一张表 + 一个 overlay） |
| **普通聊天里的 TTS** | `speech/`、`ui/hooks/ChatTts.kt` | 逐段朗读按钮、只朗读引号内内容、只朗读英文、生成后自动播放、按实际朗读文本缓存音频 |
| **AI 语音条** | `data/voice/ChatVoiceReply.kt` | 助手用 `【语音条】`/`【文本】` 混排输出，语音段合成成微信语音条那样的气泡，默认折叠点开才播。**对克克这种「住在手机里的角色」，语音条比通话更日常** |

#### 5.1 人设配置还缺什么

> **2026-08-28 复核**：这一节上一版写的是「`Contact` 只有 5 个字段」，**已过时**。
> 现在人设已独立成 `Persona`，`ChatStore` 整体按 `personaId` 分区，temperature / top_p 也已经是按人设隔离的了。

参考 rikkahub 的 `Assistant.kt` 和 Kelivo 的 `assistant.dart`，**仍然缺**的：

- `maxTokens` —— 目前主聊天写死 4096，未按人设开放
- `reasoningLevel` —— 推理等级
- `contextMessageSize` + `limitContextMessages` —— 每个人设单独设上下文长度（现在是全局 `suffix(40)`）
- `streamOutput` —— 是否流式（配合第 3.2 项）
- `presetMessages` —— 预设开场对话，用来给人设定调
- `quickMessageIds` —— 快捷短语
- `regexRules` —— 正则输入/输出处理（带 `visualOnly`：只改显示不改发给模型的内容）
- `customHeaders` / `customBody` —— 接第三方中转 API 用（注意：克克已有「自定义供应商」，但没有自定义 header/body）
- `messageTemplate`（`{{ message }}`）+ 提示词变量
- `appendCurrentTimeToUserMessage` —— 自动附加当前时间

**已经有的，不用再补**：`temperature`、`topP`、`avatar`（icon + color）、`systemPrompt`、独立聊天记录、独立主题/语言/字体。

---

## 6. 【iOS 专属彩蛋】Live Activity

**参考位置**：`kelivo/ios/Runner/KelivoGenerationActivityAttributes.swift` + `ios/GenerationActivityExtension/`（182 行，是这两个项目里**唯一的 Swift 代码**）

生成回复时在**灵动岛 / 锁屏**上显示进度。它的 `ContentState` 里放了这些：

```
displayTitle     标题
detail           详情
tokenCount       已生成 token 数
tokenLabel       token 标签文案
startedAt        开始时间
finishedAt       结束时间（可空）
elapsedSeconds   已耗时
wavePhase        动画相位
isFinished       是否已完成
```

iOS 16.1+ 起可用（`@available(iOS 16.1, *)`），成本不高。
**对克克的调性简直是为它准备的**：克克在灵动岛上想事情。

---

## 7. 明确**不要**抄的

| 项 | 原因 |
|---|---|
| rikkahub 的 Web 服务端（`web/` + `web-ui/`） | iOS 不能常驻 HTTP server |
| rikkahub 的应用锁 / 用量监控（`usage-tracker/`） | 依赖 Android UsageStats + 悬浮窗；iOS 的 Screen Time API 要申请权限且能力弱得多 |
| rikkahub 的 APK 更新检查 | 平台不相关 |
| MCP | iOS 上没有本地进程可以起 |
| rikkahub 心跳的 **调度实现**（AlarmManager 精确闹钟 + 前台服务） | iOS 没有对等能力。克克现有的「提前生成一批话排进本地通知」是对的做法 |

---

## 8. 心跳 / 主动冒泡：只抄状态机，不抄调度

克克的 `NudgeService` 和 rikkahub 的「私有心跳」（`功能列表/私有心跳.md`，全仓最详细的一篇）做的是同一件事，但它的状态机严谨得多。**调度实现不能抄（平台不同），状态机和守卫逻辑可以直接搬**：

- **多态运行状态机**：`IDLE / QUEUED / RUNNING / SENT / PASS / SKIPPED_PENDING_USER / SKIPPED_BUSY / SKIPPED_NO_MODEL / TIMED_OUT / CANCELLED / FAILED / TESTED`，每个状态附带稳定原因码、触发来源、耗时
- **模型可以回 `[PASS]` 主动跳过这次**——「没什么想说的」比硬凑一句强得多
- **投递前守卫**：生成完成后**再检查一次**用户是不是刚回来了、是不是在通话中，是就不投递。这是最关键的一条：模型思考期间用户回来了，还硬发一条主动消息会非常突兀
- **上一条是用户消息就跳过**（`SKIPPED_PENDING_USER`）——避免抢答
- **失败按原因分类 + 指数退避**：5 分钟起步、最高 6 小时、带小幅抖动。「用户回来了」「通话中」「会话忙」**不计入**基础设施失败
- **下次触发以最后一条用户消息为锚点**，不是以 App 打开时间为锚点——否则用户刚聊完就又被冒泡
- **晚安模式**：用户说晚安后改成 10 分钟一次的轻量检查，连续 3 次无事自动退出
- **内部念头与对话分离**：生成的候选文本、压力值、评分、跳过原因写进独立的记录，**只有真正发出去的消息才进重复检测历史**

---

## 9. 建议的执行顺序

> 2026-08-28 复核后调整：`temperature` / `topP` 已由分支自行完成，从清单移除。

**第一批**（每天都在损失体验）
1. ~~**给 `ChatMessage` 补字段**~~ ✅ **已完成 2026-08-28**。`usage` / `durationMs` / `model` / `providerId` / `groupId`+`version` / `translation` 都已落库，`send()` 改为返回 `Reply`（正文 + 账单 + 耗时）
2. ~~**流式输出**~~ ✅ **已完成 2026-08-29**。`StreamDecoding.swift` 放事件枚举 + SSE 分帧 + 两个解码器（只依赖 Foundation，不碰网络）；`ClaudeService` 负责发请求和驱动
3. ~~**上下文压缩**~~ ✅ **已完成 2026-08-29**。`ContextCompressor.swift` 放纯逻辑（挑选/分块/token 估算/超限判断），`ClaudeService.compressHistory` 负责调模型，`ChatStore` 负责触发和持久化

**第二批**
4. ~~Markdown / 代码块渲染~~ ✅ **已完成 2026-08-29**
5. ~~重新生成 / 编辑重发~~ ✅ **已完成 2026-08-29**

**第二批·补**（本文档之外、用户另行提出的需求）
- ~~删除全部内置人设~~ ✅ **已完成 2026-08-29**，见 2.4
- ~~采样参数按模型能力发 + 接入 extended thinking~~ ✅ **已完成 2026-08-29**，见 2.5
- ~~编排层第一步：路由 + 统一 Tool 协议 + 上下文物理隔离~~ ✅ **已完成 2026-08-29**，见 2.6

**下一批**（截至 2026-08-29 未开工）
6. ~~**错误分类 + 429 退避重试**~~ ✅ **已完成 2026-08-29**，见 2.8
7. ~~**Token 用量展示**~~ ✅ **已完成 2026-08-29**，见 2.9
8. ~~**聊天记录备份导出**~~ ✅ **导出 + 恢复都已完成 2026-08-29**，见 2.10
9. ~~**`max_tokens` 写死 4096**~~ ✅ **已完成 2026-08-29**，见 2.11

**下一批·扩展能力**（详见 §11，按当前基线重排过）
10. ~~**接真正的 MCP 协议**~~ ✅ **已完成 2026-08-29**，见 2.12
11. **搜索引擎适配层** —— 现在只有 Claude 官方 web_search，换供应商就没搜索了
12. **请求日志查看器** —— `ErrorLog` 只记失败；调人设需要看每次实际发了什么。
    也是「trace 绝不进 messages」那条约束的验证手段
13. **按深度注入提示词 `AT_DEPTH`** —— 长对话维持人设，比往 system prompt 后面加有效
14. **正则输入/输出处理（带 `visualOnly`）**

**再往后**
15. 记忆系统升级（Gatekeeper + Smart Add + watermark + 中文召回）—— 单项收益最大，工作量也最大
16. 人设配置补齐（`contextMessageSize` / `presetMessages` / 提示词变量）
17. 世界书 / Lorebook
18. 存储空间管理 —— `attachments/` 目前只进不出
19. 自定义 header / body（接中转站用）
20. AI 语音条 + 聊天内 TTS
21. 朋友圈惰性时序（对 iOS 后台限制友好，可直接搬）
22. 二维码分享供应商配置 —— 备份刻意不含 Key，这个补那一环
23. 编排层第二步：子模型层 + trace UI（用户明确说「之后再加」）
24. Live Activity / 匿名提问箱 / 导出长图
25. 项目地图（见第 10 节）—— 现在 README 的错误率比复核时更高了

---

## 11. 还能抄什么：按当前基线重排（2026-08-29）

> 前面 §4–§6 是 08-24 那次调研的原始清单。这一节是**在做完一大批之后重新排的**，
> 只列还没做的，并且标注了"能不能接上现有代码"——克克这边已经有了
> `Tool` 协议、`RetryPolicy`、`ErrorLog`、`BackupService.inventory()` 这些地基，
> 有些功能的成本比调研时低了不少。

### 11.1 用户能自己扩展的能力（最值得先做的一档）

**① 接真正的 MCP 协议** ✅ **已完成 2026-08-29，见 2.12** —— 学 rikkahub `data/ai/mcp/`

克克现在的「MCP」是自建的 7 个内置模块（翻译/汇率/音乐/闹钟/天气/新闻/音频），
**用户加不了新的**。接标准协议之后，填个 URL 就能挂任何第三方服务器。

好消息是**接口已经是现成的**：编排层的 `Tool` 协议 + `MCPToolAdapter` 就是为这个留的口子，
新的 MCP 客户端只要产出 `Tool`，整条工具链路（envelope 包装、截断、缓存前缀排序）不用动。

要抄的设计点：

| 设计 | 位置 | 为什么值得抄 |
|---|---|---|
| 两种传输分开建模 | `McpConfig.kt` `SseTransportServer` / `StreamableHTTPServer` | 服务器实现不统一，只支持一种会挂掉一半 |
| `McpStatus` 五态 | `McpStatus.kt` | `Idle / Connecting / Connected / Reconnecting(第几次/共几次) / Error(原因)`——**连接状态必须能在界面上看见**，否则工具静默失效跟没配一样 |
| 指数退避重连 + 次数上限 | `McpManager.kt:341-391` | 直接复用克克已有的 `RetryPolicy`（全抖动那套） |
| **每个工具单独开关 + `needsApproval`** | `McpConfig.kt` `McpTool` | 第三方服务器给什么工具你不知道，危险的要能关、能要求执行前确认。对「住在手机里的角色」这条尤其重要 |
| 自定义 headers | `McpCommonOptions.headers` | 接需要鉴权的服务器 |

**② 搜索引擎适配层** —— 学 kelivo `core/services/search/providers/`（21 家）

现在只有 Claude 官方的 `web_search`——**换到 DeepSeek / GPT 就没有搜索了**。
抄「一个协议 + 每家一个适配器」的结构（Bing / DDG / Tavily / Brave / SearXNG / Jina / 智谱…），
用户填自己的 key，跟供应商解耦。落到克克这边就是再写几个 `Tool` 实现。

**③ 自定义 header / body** —— 学 rikkahub `Assistant.kt` 的 `customHeaders` / `customBody`

克克已经有「自定义供应商」，但只能改 URL 和模型名。很多中转站要求额外的 header
（`HTTP-Referer`、`X-Title`）或 body 字段，现在接不上。

### 11.2 调教人设的杠杆（改动小、效果直接）

**④ 正则输入/输出处理，带 `visualOnly`** —— rikkahub `Assistant.kt:76-94`

```kotlin
data class AssistantRegex(
    val visualOnly: Boolean = false,  // 只影响显示，不影响发给模型
    val affectingScope: ...           // 作用在输入还是输出
)
```

`visualOnly` 是精髓：想把模型输出里的某些标记藏起来给自己看，
又不想改真正进历史的内容——这两件事必须分开。
克克的 `MessageKind` / `Payload` 分离已经是同一个思路，正则规则是它的自然延伸。

**⑤ 按深度注入提示词 `AT_DEPTH`** —— rikkahub `Assistant.kt:130-148`

```
position: 开头 / 结尾 / AT_DEPTH（从最新消息往前数第 N 条）
injectDepth: N
```

长对话里维持人设，**比一直往 system prompt 后面加有效得多**——
system prompt 离最新消息太远，注意力被稀释。
克克的 `payloadForRequest` 已经是统一出口，加一层注入正好。

**⑥ 世界书 / Lorebook** —— kelivo `core/models/world_book.dart`
关键词触发注入设定（支持正则、扫描深度、`constantActive` 常驻、按 `priority` 排序）。
比「把所有设定塞进 system prompt」省 token 得多。

**⑦ 人设配置的剩余字段**（§5.1 里还没做的）：
`presetMessages`（预设开场，给人设定调）、`contextMessageSize`（按人设定上下文长度）、
提示词变量 `{{time}}` `{{date}}` `{{message}}`、`appendCurrentTimeToUserMessage`。

### 11.3 排查与运维（跟刚做的报错记录是同一条线）

**⑧ 请求日志查看器** —— kelivo `settings/pages/log_viewer_page.dart`

克克刚做的 `ErrorLog` **只记失败**。调人设时真正需要的是看见
**每次请求实际发了什么**——完整的 system prompt、压缩后的历史、工具定义。

这一条跟「trace 绝不进 messages」那条硬约束互补：那条是**防**，
日志查看器是**验**——能亲眼确认发出去的 payload 里确实没有 trace。

**⑨ 存储空间管理** —— kelivo `settings/pages/storage_space_page.dart`

`attachments/` 目录现在**只进不出**，聊久了会悄悄涨。
做备份时已经写好的 `BackupService.inventory()` / `estimatedSize()` 直接就能复用，
只差一个按类型分组、可单独删的界面。

**⑩ 二维码分享供应商配置** —— kelivo `features/scan/`
换手机时扫码搬 API 配置。注意：**克克的备份是刻意不含 Key 的**，
所以搬家时 Key 仍要手填——这个功能正好补上那一环。

### 11.4 角色体验

**⑪ AI 语音条** —— rikkahub `data/voice/ChatVoiceReply.kt`
助手用 `【语音条】`/`【文本】` 混排输出，语音段渲染成微信语音条那样的气泡，默认折叠。
**对「住在手机里的角色」，语音条比通话更日常**——通话是事件，语音条是日常。

**⑫ 普通聊天 TTS** —— rikkahub `ui/hooks/ChatTts.kt`
逐段朗读、只朗读引号内内容、按实际朗读文本缓存音频（避免重复合成花钱）。
ElevenLabs 现在只接在 `VoiceCallService` 里。

**⑬ 朋友圈的惰性时序** —— rikkahub `MomentsVM.kt`
首次反应等 10–20 分钟、每条新评论等 3–8 分钟，**到期任务在打开/刷新时才处理**。
不需要后台任务，**对 iOS 的后台限制特别友好**，可以直接搬。

**⑭ 匿名提问箱** / **⑮ Live Activity（灵动岛）** / **⑯ 对话导出成长图** —— 见 §5、§6。

### 11.5 仍然整块没做的

**记忆系统升级（§4）** —— Gatekeeper（先花小钱判断值不值得记）、
Smart Add（新增/合并/冲突/跳过四选一，治重复和自相矛盾）、
记忆分类型注入、watermark（失败不推进水位线）、中文停用词 + CJK 二元组召回。
这是清单里**单项收益最大**的一块，也是工作量最大的一块。

---

## 10. 一条元级建议：补一份项目地图

rikkahub-Jude 根目录那三份文档（`项目地图.md` / `项目规则.md` / `功能列表/`）是**专门写给 AI 协作**的，结构是：

```
30 秒结论
  → 分层表（L0 产品 / L1 运行边界 / L2 代码分层）
    → 「要改什么 → 先看哪里」锚点表
      → 每个领域一页（能力 / 数据 / 核心入口 / 修改提示）
        → AI 推荐阅读顺序
```

克克现在只有一份 `KekeApp/README.md`，而且**脱节得比上一版复核时更严重了**（2026-08-28 实测）：

- README 目录树只列了 **10 个 View，实际有 39 个**——**30 个页面没被写进去**
- README 里写的 `SideMenuView.swift` **代码里已经不存在**（换成了 `BottomTabBar.swift`）
- 整个人设体系（`Persona` / `PersonaPickerView` / `PersonaStore`）、MCP 注册表、音频播放器、Keychain 存储、6 家供应商 + 自定义供应商——README 一个字没提
- README 还写着「默认模型是 `claude-opus-4-8`」「想改人设编辑 `ClaudeService.swift` 里的 `systemPrompt`」，但现在人设已经在 `Persona.systemPrompt` 里、按人设隔离了

以现在这个功能密度（**85 个文件、39 个页面、35 个 Service**），**补一份同样格式的项目地图，对以后每次让 AI 改代码的效率提升，可能比上面任何一条功能都大**——现在让 AI 读 README 上手，它拿到的信息有一半是错的。

---

## 附录：调研中确认的关键事实

**rikkahub-Jude**
- 分模块 Gradle 工程：`app` / `ai` / `common` / `search` / `speech` / `document` / `highlight` / `material3` / `usage-tracker` / `weather` / `web` / `web-ui`
- Room 版本 25，规则明确要求「新增/修改表必须同步 Entity、DAO、AppDatabase、Migration 和 schema」
- 会话不是平铺列表，是 `Conversation + MessageNode` 分支树
- 压缩状态由 `compressedSummary` + `compressedMessageNodeIds` 表示，**原始节点保留**，UI 上「小眼睛」可展开
- 「私有心跳」在 `app/src/personal/`，git 忽略、禁止提交；公开构建走 `public` flavor 空实现

**Kelivo**
- 541 个 dart 文件、36.7 万行（含生成代码和 i18n）
- 已上架 App Store（id6752122930），最后提交 2026-08-28（调研当天）
- 数据层：Hive → SQLite(Drift) 迁移中，有专门的 `hive_to_sqlite_migration_service.dart`（2438 行）
- iOS 侧有 `GenerationActivityExtension`（Live Activity）
- 最大的几个业务文件：`chat_database_repository.dart` 7748 行、`chat_message_widget.dart` 7081 行、`settings_provider.dart` 6447 行、`markdown_with_highlight.dart` 6255 行、`chat_service.dart` 4227 行

**本地路径**（容器回收后失效，需要时重新 clone）
```
/home/user/lin-chpin/rikkahub-jude
/home/user/chevey339/kelivo
```
