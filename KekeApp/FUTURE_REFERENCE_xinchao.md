# 参考来源：xinchao-dynamic-mind

来源仓库：https://github.com/tianyupaipai-cmd/xinchao-dynamic-mind
MIT License，作者 tianyupaipai-cmd
原项目：Node.js 自托管 HTTP 服务，AI 动态心智引擎

## 已移植的算法（本次更新）

以下概念从 xinchao 的 JavaScript 实现移植为纯 Swift 本地实现，
集成到 `KekeStateService.swift`，不需要服务器，完全在设备上运行。

### 1. 驱力自然增长 / 满足衰减（来自 `dimensions.js` + `engine.js`）
- 每个维度有 `growPerHour` 自然增长率，空闲时驱力自动积累
- 被 AI 更新时若方向为"被满足"，应用 `satisfyMul` 衰减乘数放大效果
- 天花板饱和：值 > 95 时自动每小时衰减 10%，防止卡在极值
- 夜间倍率 `nightMul`：深夜（22:00-06:00）某些驱力增长更快

### 2. 驱力互抑制（来自 `dimensions.js` inhibitedBy）
- 控制力 → 抑制占有欲、敏感度
- 心软度 → 抑制蓄积感
- 蓄积感 → 抑制控制力
- 互抑制按小时线性计算，高维压低维

### 3. 黎明冻结（来自 `engine.js` dawnFreeze）
- 凌晨 1:00-8:00 所有驱力停止自然增长
- 互抑制仍然生效

### 4. 思绪池：闪念 → 执念（来自 `thought-pool.js`）
- **闪念**：每次 AI 提炼记忆时产生，初始强度 0.4
- 衰减：每半小时 × 0.82（`flashDecay`）
- **升级条件**：强度 ≥ 0.50 且存在 ≥ 3 个结算周期 → 升级为执念
- **执念**：每结算周期 × 1.10（`obsessionGrowth`），越想越强
- **驱力反馈**：执念强度 > 0.85 时反向推高占有欲/蓄积感/敏感度（最多 3 次）
- UI 展示：详情页用强度圆点 + "执念"标签；首页显示当前最强执念

### 5. 疲劳 / 睡眠周期（来自 `engine.js` sleep cycle）
- 正常交互 → `awake`
- 60 分钟无交互 → `drowsy`（犯困）
- 90 分钟无交互 → `sleeping`（睡着了）
- 任何交互（聊天、AI 状态更新）自动重置为 `awake`
- 疲劳状态下驱力增长减半
- 首页用 emoji 显示疲劳状态

### 6. 意图选择（来自 `engine.js` selectIntent）
- `dominantDrive()` 取当前最强驱力 + ±0.12 随机扰动
- 执念为相关驱力加 bonus 权重
- 用于驱动 AI 主动打电话时的动机选择

## 与原项目的差异

| 方面 | xinchao 原版 | KekeApp 移植版 |
|------|-------------|---------------|
| 运行方式 | Node.js HTTP 服务 | 纯 Swift 本地 |
| 维度数量 | 12 个 drive | 保持原有 6 个 |
| 结算周期 | 15 分钟定时器 | 打开 App 时结算（≥30min） |
| 思绪来源 | 对话事件 API | AI 记忆提炼时生成 |
| 意图池 | JSON 配置的行为列表 | 直接映射到现有功能（打电话等） |
| 外部依赖 | OpenAI / MCP / Bark | 无额外依赖 |

## 已实现的扩展功能

### 状态面板自定义
- 用户可以在创建/编辑角色时选择启用哪些状态维度（1-6 项可选）
- 每个维度的名称可以自定义（底层算法参数不变）
- 自定义配置存储在 UserDefaults，key: `{personaId}_state_dim_configs`
- AI 提取记忆时的 prompt 和 JSON 模板会动态适配自定义名称

### 角色形象选择
- `BuiltInCharacter` enum 定义可选的内置像素画角色
- 创建角色时可以选择角色形象，存储在 `Persona.characterType`
- `ClawdMiniPreview` 提供选择器中的缩略图

## 未移植的功能

以下功能暂未实现，未来可考虑：

- **更多内置像素画角色**：目前只有 Clawd 小螃蟹。
  实现方式：在 `BuiltInCharacter` enum 中新增 case，
  各自创建类似 `ClawdCharacterView` 的 Canvas 像素画 View，
  并在 `HomeView` 的 `petCard` 中根据 `persona.characterType` 切换显示
- **12 维度扩展**：xinchao 有 curiosity（好奇）、boredom（无聊）、social（社交）、
  duty（责任）、reflection（自省）、grieve（委屈）、anger（生气）等维度，
  可以扩展现有的 6 维度
- **意图池行为映射**：xinchao 的 intent 系统可以绑定具体行为模板
  （如不同类型的主动消息），目前只用于打电话动机
- **MCP memory 集成**：xinchao 支持通过 MCP 读写外部记忆服务
- **对话事件 API**：xinchao 的 POST /v1/conversation-event 实时更新驱力，
  目前只在记忆提炼时更新
