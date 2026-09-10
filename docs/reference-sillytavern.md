# 酒馆（SillyTavern）能给克克什么

> 读的是 [SillyTavern/SillyTavern](https://github.com/SillyTavern/SillyTavern) v1.18.0，
> **AGPL-3.0，传染性许可**。规矩跟前四个参考项目完全一样：
> **只学设计，自己写实现，代码一行不抄。**
>
> 实际看过的：`public/scripts/` 和 `src/` 的**文件清单**、`world-info.js` 的
> 字段注释和定时效果常量、`macros/definitions/` 里的宏名清单、
> `expressions/index.js` 的情绪标签表、`group-chats.js` 的激活策略枚举、
> `character-card-parser.js` 的 spec 版本常量。
> **没有读任何实现函数体。**

---

## 0. 先说最重要的一件事：酒馆是前面两个项目的**源头**

rikkahub 和 kelivo 那些人设功能——世界书、正则规则（带 `visualOnly`）、
预设开场、`AT_DEPTH` 深度注入、多候选切换——**全是 SillyTavern 先做出来的**，
那两个项目是二手转述。

也就是说：**这个 session 已经间接抄过一轮酒馆了**（见
`reference-rikkahub-jude-and-kelivo.md` §2.14「人设调教四件套」）。

所以这份分析要回答的不是「酒馆有什么」，而是**「转了两手之后，还剩什么没传过来」**。

---

## 1. 真正的新东西

### ① 角色卡 V2 / V3 —— 这不是功能，是**生态接口**

这是整份清单里最值钱的一条，而且甩开第二名很远。

一张 PNG 的 `tEXt` chunk 里嵌一段 base64 JSON，**一张图片就是一个完整角色**：
人设、开场白、示例对话、随卡携带的世界书、作者注。V3 之后还有
`.charx`（zip 包）和 BYAF（Backyard 归档格式）——酒馆源码里
`character-card-parser.js` / `charx.js` / `byaf.js` 三个文件各管一种。

**为什么对克克重要**：克克现在新建人设要**从零手写**。
支持导入角色卡，等于一夜之间有几十万个现成人设可用。
而且 memex 也支持导入 V2 卡（README 里明写「SillyTavern compatible」），
说明这已经是事实标准，不是酒馆的私有格式。

**成本**：PNG chunk 解析（纯 Foundation，不难）+ 字段映射到 `Persona`。

**但只做导入，不做导出**，两个理由：
1. 克克的人设有卡片规范里没有的东西（状态维度、亲密度、朋友圈行为），导出必丢
2. 导出等于鼓励用户把自己写的私密人设传出去，跟这个 App 的调性反着来

### ② 世界书的定时效果：sticky / cooldown / delay

克克的 `WorldBookEntry` 现在只有「关键词命中就注入」。酒馆多三个字段
（`world-info.js` 里 `sticky` / `cooldown` / `delay` 三张计时表）：

| 字段 | 作用 | 解决什么问题 |
|---|---|---|
| `sticky` | 命中之后连续 N 轮保持注入 | 聊着聊着设定就掉了 |
| `cooldown` | 刚用过的条目 N 轮内不再触发 | 同一条设定反复刷屏 |
| `delay` | 对话满 N 条之前不触发 | 开场就抛世界观太重 |

**这是长对话里维持设定的实战经验**，成本极低（三个 `Int` + 一张按会话存的计数表），
收益直接。是这份清单里**性价比最高**的一项。

还有**递归扫描**（注入的内容自己也参与下一轮匹配，A 触发 B），
带 `world_info_max_recursion_steps` 上限。这个有代价，可以后做。

### ③ `{{pick}}` 和 `{{random}}` 的区别

酒馆的宏系统很大（`macros/definitions/` 下有 60+ 个宏：变量读写、
`{{if}}/{{else}}`、时间、环境、状态）。但**最值得学的是一个细节**：

- `{{random}}` 每次渲染重新掷骰
- `{{pick}}` 对同一条消息**稳定**，重新渲染结果不变

克克的 `PersonaTuningEngine.expand` 现在只有
`{{user}}` / `{{char}}` / `{{time}}` / `{{date}}`。
**在加任何随机宏之前必须先想清楚这个区别**——不稳定的随机会让
「重新生成」变成两个完全不同的世界，用户会以为是 bug。

### ④ `{{idleDuration}}`：距离上次说话多久

克克有主动冒泡（`NudgeService`），但那是**App 侧的定时逻辑**。
把「你三天没理我了」变成一个**能进 prompt 的事实**，是另一回事——
前者决定「要不要开口」，后者决定「开口说什么」。
对陪伴类 App，这个宏太对味了，而且几乎零成本。

### ⑤ Data Maid：按**引用关系**找孤儿文件

克克有存储空间页（§2.15），但那是**按目录看大小**，不是**按引用找孤儿**。

碎片流水线上线之后这件事会变重要：`attachments/` 里会开始出现
「碎片删了图还在」。我在 `FragmentStore.delete` 里手工删了图，
但那是**靠自觉，不是靠机制**——下一个写删除逻辑的地方很可能忘。

### ⑥ Connection profile：把一整套连接配置打包切换

酒馆的 `connection-manager` 把「供应商 + 模型 + 采样参数 + 预设」
打包成一个可命名、可切换的档案。

克克现在是按人设分区的散字段。想做「白天用便宜的、晚上用聪明的」，
要改四个地方。有了 `SubModelConfig` 之后这条的价值反而降低了一些，
但主模型这边仍然是散的。

### ⑦ Continue（只要这个，不要 Impersonate）

- `continue`：让 TA **接着上一条往下写**，不是重新生成。
  对「话说到一半被 `max_tokens` 截断」很实用——克克确实会遇到这个 stop reason
- `impersonate`：让 AI **替你**写你的下一句

**只做 continue。** `impersonate` 对陪伴 App 是有害的：
让 AI 替你说话，等于取消了这段关系里的另一方。

---

## 2. 酒馆有、克克已经有了的

世界书基础、正则规则（含 `visualOnly`）、深度注入、预设开场、
多候选切换（`versionCount`）、自动摘要（`ContextCompressor`）、
TTS、翻译、图像生成、token 计数、表情立绘（`KekeCharacterView` + `KekeStateService`）。
向量检索在计划里（日记计划第 9 项）。

顺带一提，酒馆的 `expressions` 扩展用的是 **28 个情绪标签**
（admiration / amusement / anger / …，看着像 GoEmotions 那一套），
而且分了四种分类后端：本地小模型 / extras 服务 / LLM / WebLLM。
克克的 `KekeStateService` 是自己的维度体系，不必对齐，
但「情绪分类可以走本地小模型，不必每次问大模型」这个思路值得记一笔。

---

## 3. 明确不要抄的

| 不抄 | 原因 |
|---|---|
| **STscript / 斜杠命令 / 扩展生态** | 酒馆是给硬核用户的**平台**，克克是给一个人用的**伴侣**。加一门脚本语言等于把产品变成另一个东西 |
| **群聊多角色**（`group_activation_strategy` 四种策略） | 跟「一对一的关系」直接冲突。这条之前已经拒过一次（rikkahub 那边的「多角色评论」） |
| **对话分支 / 存档点**（`bookmarks.js`） | 技术上不难，但**分支意味着「这段关系有平行宇宙」**，跟「唯一的、连续的关系」这个调性是冲突的。倾向不做，但这条是价值判断，不是技术判断 |
| **Instruct mode / 上下文模板** | 那是为了适配没有 chat API 的本地小模型。克克接的都是商业模型，不需要 |
| **CFG / logit bias / 采样器全家桶** | Claude 新模型连 `temperature` 都不收了（见 `ModelCapability`） |

---

## 4. 建议的取舍

按「收益 ÷ 成本」排：

| 顺位 | 项 | 规模 | 一句话 |
|---|---|---|---|
| 1 | **世界书 sticky / cooldown / delay** | S | 三个 Int + 一张计数表，直接治「设定掉了」和「设定刷屏」 |
| 2 | **角色卡 V2/V3 导入** | M | 最值钱的一条，但它是**接生态**不是加功能，做之前先想清楚要不要接 |
| 3 | **`{{idleDuration}}` + 稳定的 `{{pick}}`** | S | 陪伴向的宏，几乎零成本 |
| 4 | **Continue** | S | 治 `max_tokens` 截断 |
| 5 | **孤儿文件清理** | M | 碎片流水线上线之后会变必要 |
| 6 | Connection profile | M | 有 `SubModelConfig` 之后价值降低了 |

**一句话总结**：酒馆能给克克的，最值钱的不是任何一个功能，
是**角色卡这个格式**。其余都是边角料——但第 1 项那个边角料，
是这几份调研里性价比最高的一条。
