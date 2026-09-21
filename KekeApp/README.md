# KekeApp — 快速上手

> **完整介绍**请看仓库根目录的 [README.md](../README.md)。
> **架构细节**请看 [docs/项目地图.md](../docs/项目地图.md)。
>
> 这份文档只管一件事：**怎么把 App 跑起来**。

---

## 需要准备

1. 一台 Mac，装好 **Xcode 16+**
2. iPhone（**iOS 16+**），用数据线连到 Mac
3. Apple ID（免费的也可以；有开发者账号签名不过期）
4. 至少一家 AI 供应商的 API Key，例如：
   - Claude：[console.anthropic.com](https://console.anthropic.com)（`sk-ant-` 开头）
   - 也支持 GPT / DeepSeek / Gemini / Kimi / 豆包 / 任意自定义供应商

## 安装步骤

1. 用 Xcode 打开 `KekeApp/KekeApp.xcodeproj`
2. 左边点蓝色的项目图标 → TARGETS 选 **Keke** → **Signing & Capabilities**：
   - **Team** 选你自己的 Apple ID（没有的话点 Add an Account 登录）
   - 如果 Bundle Identifier `com.moon.keke` 报冲突，改成任何唯一的，比如 `com.yourname.keke`
3. 顶部设备选择你的 iPhone，按 **Cmd+R** 运行
4. 第一次运行 iPhone 会提示"未受信任的开发者"：去 iPhone 的 **设置 → 通用 → VPN与设备管理**，信任你的开发者证书，再运行一次
5. 打开 App：
   - 设置 → 粘贴你的 API Key
   - 可选：心跳 → 允许读取健康数据
6. 回到聊天页，跟 TA 说话吧

## 项目结构

```
KekeApp/
├── KekeApp.xcodeproj              # Xcode 项目
├── Info.plist                     # 权限声明（定位/日历/提醒/相机/健康）
└── Keke/
    ├── KekeApp.swift              # App 入口
    ├── Theme.swift                # 主题配色
    ├── Localization.swift         # 中英双语（重复键会运行时崩溃！）
    ├── Keke.entitlements          # HealthKit 权限
    ├── Assets.xcassets/           # 图标和颜色
    ├── Models/           (10)     # 纯数据结构
    │   ├── ChatMessage.swift      # 聊天消息（含 usage/trace/多版本）
    │   ├── Persona.swift          # 角色（人设/供应商/模型各自独立）
    │   ├── Fragment.swift         # 日记碎片
    │   ├── TimelineCard.swift     # 整理后的时间线卡片
    │   ├── Book.swift             # 书
    │   ├── Contact.swift          # 联系人
    │   ├── DiaryEntry.swift       # 日记条目
    │   ├── Drawing.swift          # 涂鸦
    │   ├── Moment.swift           # 朋友圈
    │   └── Anniversary.swift      # 纪念日
    ├── Services/         (78)     # 状态 + 业务逻辑
    │   ├── ChatStore.swift        # 聊天核心（发送/存储/设置/多角色分区）
    │   ├── ClaudeService.swift    # 所有供应商的请求出口
    │   ├── StreamDecoding.swift   # SSE 流式解码
    │   ├── ContextCompressor.swift # 滚动摘要压缩
    │   ├── APIFailure.swift       # 错误分类 + 退避重试
    │   ├── MemoryService.swift    # 长期记忆（检索 + 提炼）
    │   ├── MemorySmartAdd.swift   # 记忆去重（add/merge/conflict/skip）
    │   ├── MemoryDatabase.swift   # SQLite FTS5
    │   ├── PersonaTuning.swift    # 人设调教（注入/正则/世界书/预设）
    │   ├── Providers.swift        # 供应商定义 + 模型能力矩阵
    │   ├── Orchestration/         # 工具编排层
    │   │   ├── Tool.swift         # 统一 Tool 协议
    │   │   ├── MCP/               # 标准 MCP 协议客户端
    │   │   └── Search/            # 搜索适配（6 家）
    │   ├── Speech/                # 语音供应商（ElevenLabs/MiniMax/豆包）
    │   ├── ErrorLog.swift         # 报错汇总
    │   ├── RequestLog.swift       # 请求日志（只在内存）
    │   └── ...
    └── Views/            (53)     # SwiftUI 界面
        ├── RootView.swift         # 根视图
        ├── ChatView.swift         # 聊天
        ├── SettingsView.swift     # 设置
        ├── DiaryView.swift        # 日记 + 碎片流
        ├── MemoryView.swift       # 记忆
        ├── PersonaTuningView.swift # 人设调教
        └── ...
```

## 常见问题

| 问题 | 解决 |
|---|---|
| 编译报错找不到类型 | 新文件需要手动改 `project.pbxproj` 四处（PBXBuildFile / PBXFileReference / group children / PBXSourcesBuildPhase） |
| `SettingsView` 编译不过 | `Group` 有 10 个子视图上限，需要拆成多个 `Group` |
| `Localization.swift` 运行时崩溃 | 检查有没有重复的本地化键（重复键是运行时崩溃，不是编译错误） |
| 发消息直接 400 | 检查模型是否支持 temperature（新 Claude 模型已移除），或检查 API Key |
| 记忆搜中文搜不到 | 已知问题，FTS5 默认分词器对中文支持有限，后续会修 |

## 说明

- API Key 和聊天数据**只存在手机本地**
- 默认模型在设置里选，支持按角色分别配置
- 健康数据只读，不会改你的记录
- 人设在**角色设置**里写，不是改代码
