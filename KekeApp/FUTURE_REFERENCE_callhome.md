# 未来可参考的功能 — 来源：callhome

来源仓库：https://github.com/Cheiineeey/callhome
MIT License，作者 Elle & Matt

## 已实现的功能（本次更新）

- ✅ AI 主动发起通话（通过本地通知模拟来电）
- ✅ 柔和挂断协议（AI 先说再见，15 秒窗口内用户说话可取消挂断）
- ✅ 语音信箱（未接来电时 AI 留一条语音消息在聊天里）

## 未来可以加的功能

### 1. SenseVoice 情绪检测（服务器端）
callhome 用 SenseVoice/FunASR 做端到端的语音情绪分类（喜/怒/哀/惧），比目前克克 App 用的端上 RMS 响度分析更准确。
- 需要自建服务器跑 SenseVoice 模型
- 对中文友好，支持 trigram 分词
- 可以对比个人基线（相对变化而非绝对阈值）
- 参考：callhome 的 `stt-service/` 目录

### 2. 勿扰模式语音控制（DND via voice）
在通话中用自然语言控制勿扰模式，比如说"我现在不方便"就自动开启勿扰。
- 纯对话触发，不需要菜单操作
- 参考：callhome 的 marker 协议（`⟪dnd⟫` 标记）

### 3. 升级拨号（Escalation Dialing）
如果用户长时间没打开 App 也没回消息，AI 会自动发起一通"来电"通知检查用户是否安好。
- 设置每日最大次数限制
- 尊重夜间时段（不在深夜打扰）
- 用户可以设置"不回"的文字/预设理由
- 参考：callhome 的 gateway-reference 目录

### 4. 通话拒绝回复（Call Decline Responses）
用户可以用预设文字理由拒接 AI 的来电（类似 iPhone 的"短信回复拒接"）。
- 预设理由如："在开会"、"稍后再聊"、"正在忙"
- 拒绝理由会被 AI 记住，影响下次主动联系的时机

### 5. 实时流式语音（WebRTC 级别）
callhome 用 PWA + WebRTC-like 的实时音频流，延迟比现在的回合制更低。
- 目前克克的"你一句我一句"体验已经很好
- 如果要做真正的实时打断和双工通话，需要接 WebRTC 或类似的流式方案
- 参考：callhome 的 `pwa-reference/` 目录

### 6. 情绪时间线（Emotion Timeline）
通话结束后生成一条情绪变化的时间线记录，回顾通话中的情绪波动。
- 需要配合更精确的情绪检测
- 可以存在日记或记忆里

## 技术栈差异说明

callhome 是 PWA + 自建服务器架构，克克是纯 iOS App。以上功能在移植时需要适配：
- 服务器端功能（SenseVoice）需要自建后端或找替代的端上方案
- PWA 的 Service Worker 通知机制对应 iOS 的 UNUserNotificationCenter
- WebRTC 音频流在 iOS 上可以用 AVAudioEngine + Network.framework 替代
