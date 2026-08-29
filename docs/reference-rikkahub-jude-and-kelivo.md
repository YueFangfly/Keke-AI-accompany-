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

> **复核日期：2026-08-28**，基于 `claude/analyze-extract-kekeapp-n22096` 分支快照 `c4a77e4`。
> 本节所有结论都是在 `KekeApp/` 里 grep + 读代码确认的事实，不是推测。
> **改完一项就更新对应行**，避免后续照着过期信息动手。

规模：**85 个 swift 文件 / 23923 行**（39 Views + 35 Services + 8 Models）

### 2.1 仍然缺失的（本文档要解决的目标）

| 项 | 现状 | 位置 |
|---|---|---|
| ~~流式输出~~ | ✅ **已完成 2026-08-29**。provider 无关的 `StreamEvent` + 两个 SSE 解码器；流式结果重建成和非流式一样的结构，工具循环未改动。设置页有按人设的开关 | `Services/StreamDecoding.swift`、`Services/ClaudeService.swift` |
| ~~上下文管理~~ | ✅ **已完成 2026-08-29**。滚动摘要压缩：老消息压成摘要随请求发，近期消息原样发；保留段从用户消息起算；超上下文时二分重试，额度整棵树共用。压缩只影响请求窗口，聊天列表仍是全量原文 | `Services/ContextCompressor.swift`、`Services/ChatStore.swift` |
| ~~Markdown 渲染~~ | ✅ **已完成 2026-08-29**。块级（标题/列表/引用/代码块/分割线）自己排，行内（加粗/斜体/行内代码/链接）交给 `AttributedString(markdown:)`。代码块可横向滚动 + 一键复制。用户自己发的消息保持纯文本。表格和公式未做 | `Views/MarkdownText.swift` |
| **消息操作** | ❌ 仍只有 收藏 / 复制 / 删除 三项。无重新生成、无编辑重发、无失败重试 | `Views/ChatView.swift:474` |
| **错误处理** | ❌ `AIError` 只有 `noAPIKey` / `badResponse` 两个 case；非 200 一律 `"HTTP \(statusCode)"`。**无 429 识别、无重试、无退避** | `Services/ClaudeService.swift:1364`、`:1439` |
| **Token 用量的展示** | ⚠️ 用量本身已经记进 `ChatMessage.usage` 了（见 2.2），但**还没有任何界面展示**——没有统计页、气泡上也不显示 | — |
| **API 请求日志** | ❌ 无。（注意：`Services/ActivityLog.swift` 是**用户行为日志**——记录「看了新闻」「查了汇率」这类事件喂给克克当上下文，**不是** API 请求日志，别混淆） | — |
| **`max_tokens`** | ❌ 主聊天两条路径都写死 4096 | `Services/ClaudeService.swift:255`、`:307` |
| **普通聊天 TTS** | ❌ ElevenLabs 只接在 `VoiceCallService` 里，聊天页无朗读、无语音条 | `Services/VoiceCallService.swift` |

### 2.2 已经有了 / 部分有了（上一版文档写错或已过时的行）

| 项 | 现状 | 位置 |
|---|---|---|
| **temperature / top_p** | ✅ **已有，且是按人设隔离的**。`-1` 表示不传、走 API 默认值；设置页有滑杆 + 开关 | `Services/ChatStore.swift:173-179`、`Views/SettingsView.swift:726-780` |
| **人设体系** | ✅ 已从 `Contact` 中独立出 `Persona`（id / name / icon / color / subtitle / systemPrompt / characterType），`ChatStore` 整体按 `personaId` 分区（聊天记录、主题、语言、字体、温度、开关全部独立） | `Models/Persona.swift`、`Services/ChatStore.swift:182` |
| **API Key 存储** | ✅ 已迁进 **Keychain**，并带 UserDefaults 旧数据自动迁移 | `Services/APIKeyStore.swift` |
| **供应商** | ✅ 从 4 家扩到 **6 家**（+ Gemini、Kimi）+ **自定义供应商**；新增 `supportsFunctionCalling` 能力标记 | `Services/Providers.swift`、`Views/CustomProviderView.swift` |
| **备份导出** | ⚠️ **部分有**。记忆可导出成文本备份、可从 md/txt/json 导入（认 claude.ai 和 ChatGPT 官方导出）；聊天档案可导入完整对话原样存档。**但聊天记录本身、朋友圈、日记、经期数据仍无导出** | `Views/ChatListView.swift:553/702`、`Views/ChatArchiveView.swift:89-115`、`Services/MemoryService.swift:107` |
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
5. 重新生成 / 编辑重发（有了 `groupId` 就顺理成章）
6. 错误分类 + 429 退避重试（现在 `AIError` 只有两个 case）
7. 聊天记录本身的备份导出（记忆导出已有，聊天/朋友圈/日记还没有）

**第三批**
8. 记忆系统升级（Gatekeeper + Smart Add）
9. 人设配置补齐（见 5.1，`maxTokens` / `contextMessageSize` / `presetMessages` / `regexRules`）
10. Live Activity

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
