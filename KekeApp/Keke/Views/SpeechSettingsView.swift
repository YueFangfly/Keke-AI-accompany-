import SwiftUI
import AVFoundation

/// 语音设置：选哪家、填凭据、挑音色，**当场试听**。
///
/// 「试听」这一条是刻意放在这里的：TTS 的配置错法有很多种
/// （key 不对、GroupId 忘了、音色 id 拼错、这家的音色不支持中文），
/// 每一种都要等到真的聊天时才暴露。给一个按钮当场验，比什么文档都有用。
struct SpeechSettingsView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var speech: SpeechService
    var onClose: () -> Void

    @State private var manualVoice = ""
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false
    @State private var player: AVAudioPlayer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("语音")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)

                vendorPicker
                credentialFields
                voiceSection
                modelSection
                testSection
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
        .backButtonInset(onBack: onClose)
        .task { await speech.loadVoices() }
    }

    // MARK: - 选哪家

    private var vendorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $speech.vendor) {
                ForEach(SpeechVendor.allCases) { vendor in
                    Text(vendor.displayName).tag(vendor)
                }
            }
            .pickerStyle(.segmented)

            Text(speech.vendor.blurb.replacingOccurrences(of: "**", with: ""))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            Text("去哪申请：" + speech.vendor.signupHint)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
        }
    }

    // MARK: - 凭据

    private var credentialFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(speech.vendor.fields) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.label)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    credentialField(field)
                }
            }
            Text("凭据存在钥匙串里，不进备份文件。")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    @ViewBuilder
    private func credentialField(_ field: SpeechVendor.Field) -> some View {
        let binding = Binding<String>(
            get: { SpeechService.credential(speech.vendor, field.key) },
            set: { SpeechService.setCredential($0, speech.vendor, field.key) }
        )
        Group {
            if field.secure {
                SecureField(field.placeholder, text: binding)
            } else {
                TextField(field.placeholder, text: binding)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .font(.subheadline)
        .padding(10)
        .glassCard(cornerRadius: 10)
    }

    // MARK: - 音色

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("音色")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if speech.voicesLoading {
                    ProgressView().controlSize(.mini)
                } else if speech.vendor.canListVoices {
                    Button("刷新列表") { Task { await speech.loadVoices() } }
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }

            if speech.voiceID.isEmpty {
                // 老版本这里写死的是 Rachel（英文女声），结果开箱第一次朗读就不对。
                // 现在宁可空着、催一句
                Text("还没挑音色。中文角色一定要挑一个中文音色，不然听起来会像外国人念中文。")
                    .font(.caption2)
                    .foregroundStyle(Theme.crabRed)
            } else {
                Text("当前：\(speech.voiceName.isEmpty ? speech.voiceID : speech.voiceName)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            ForEach(speech.selectableVoices) { voice in
                Button {
                    speech.pick(voice)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: voice.id == speech.voiceID
                              ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(voice.id == speech.voiceID ? Theme.accent : Theme.textSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(voice.name)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            if !voice.detail.isEmpty {
                                Text(voice.detail)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }

            if let error = speech.voicesError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.crabRed)
            }

            manualVoiceRow
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    /// 内置清单不可能全。想用别的音色，直接填 id
    private var manualVoiceRow: some View {
        HStack(spacing: 8) {
            TextField("或者直接填音色 id", text: $manualVoice)
                .font(.caption)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(8)
                .glassCard(cornerRadius: 8)
            Button("用这个") {
                let id = manualVoice.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else { return }
                speech.pick(SpeechVoice(id: id, name: id))
                manualVoice = ""
            }
            .font(.caption)
            .foregroundStyle(Theme.accent)
        }
    }

    // MARK: - 模型

    @ViewBuilder
    private var modelSection: some View {
        if !speech.vendor.models.isEmpty {
            Picker("合成模型", selection: $speech.model) {
                ForEach(speech.vendor.models, id: \.id) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .padding(10)
            .glassCard(cornerRadius: 10)
        }
    }

    // MARK: - 试听

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                runTest()
            } label: {
                HStack(spacing: 6) {
                    if testing { ProgressView().controlSize(.mini) }
                    Text(testing ? "合成中…" : "试听一句")
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
            }
            .disabled(testing)

            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(testOK ? Theme.textSecondary : Theme.crabRed)
            }
        }
    }

    private func runTest() {
        testing = true
        testResult = nil
        Task {
            defer { testing = false }
            do {
                let data = try await speech.speech("你好呀，我是\(PersonaStore.persona(for: store.personaId).name)。")
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                let player = try AVAudioPlayer(data: data)
                player.play()
                self.player = player
                testOK = true
                testResult = "成功，正在播放。"
            } catch {
                testOK = false
                testResult = error.localizedDescription
                ErrorLog.shared.record(source: "语音试听", message: error.localizedDescription)
            }
        }
    }
}
