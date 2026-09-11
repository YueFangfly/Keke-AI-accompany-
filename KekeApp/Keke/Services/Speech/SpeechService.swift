import Foundation

/// 语音合成的总入口。界面和调用方只跟它打交道，不认具体哪一家。
///
/// 按人设分区：不同角色可以是不同的声音，这本来就是应该的。
/// 供应商和凭据是全局的（一个账号不会为每个角色重新买一次）。
@MainActor
final class SpeechService: ObservableObject {
    let personaId: String

    /// 用哪一家。全局设置
    @Published var vendor: SpeechVendor {
        didSet {
            UserDefaults.standard.set(vendor.rawValue, forKey: Self.vendorKey)
            // 换了家，音色 id 就不通用了——重新落到这家的默认值上，
            // 不然会拿着上一家的 id 去请求，报一个看不懂的错
            reloadVoiceForVendor()
        }
    }

    /// 当前这家、当前这个角色用的音色
    @Published var voiceID: String {
        didSet { UserDefaults.standard.set(voiceID, forKey: voiceKey) }
    }
    @Published var voiceName: String {
        didSet { UserDefaults.standard.set(voiceName, forKey: voiceNameKey) }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: modelKey) }
    }

    /// 从服务器拉回来的音色（只有 ElevenLabs 支持）
    @Published var fetchedVoices: [SpeechVoice] = []
    @Published var voicesLoading = false
    @Published var voicesError: String?

    private static let vendorKey = "speech_vendor"
    private var voiceKey: String { "\(personaId)_speech_voice_\(vendor.rawValue)" }
    private var voiceNameKey: String { "\(personaId)_speech_voice_name_\(vendor.rawValue)" }
    private var modelKey: String { "speech_model_\(vendor.rawValue)" }

    init(personaId: String = "keke") {
        self.personaId = personaId
        let saved = UserDefaults.standard.string(forKey: Self.vendorKey) ?? ""
        let vendor = SpeechVendor(rawValue: saved) ?? .elevenLabs
        self.vendor = vendor

        let ud = UserDefaults.standard
        let vKey = "\(personaId)_speech_voice_\(vendor.rawValue)"
        self.voiceID = ud.string(forKey: vKey) ?? vendor.defaultVoice?.id ?? ""
        self.voiceName = ud.string(forKey: "\(personaId)_speech_voice_name_\(vendor.rawValue)")
            ?? vendor.defaultVoice?.name ?? ""
        self.model = ud.string(forKey: "speech_model_\(vendor.rawValue)") ?? vendor.defaultModel

        migrateLegacyElevenLabs()
    }

    // MARK: - 凭据

    static func credentialKey(_ vendor: SpeechVendor, _ field: String) -> String {
        "tts:\(vendor.rawValue):\(field)"
    }

    static func credential(_ vendor: SpeechVendor, _ field: String) -> String {
        let stored = APIKeyStore.key(for: credentialKey(vendor, field))
        guard stored.isEmpty else { return stored }
        // 没填过就用这个字段的默认值（比如豆包的 Resource ID）
        return vendor.fields.first(where: { $0.key == field })?.defaultValue ?? ""
    }

    static func setCredential(_ value: String, _ vendor: SpeechVendor, _ field: String) {
        APIKeyStore.setKey(value.trimmingCharacters(in: .whitespacesAndNewlines),
                           for: credentialKey(vendor, field))
    }

    static func credentials(for vendor: SpeechVendor) -> [String: String] {
        var out: [String: String] = [:]
        for field in vendor.fields { out[field.key] = credential(vendor, field.key) }
        return out
    }

    /// 这家的必填项是不是都填了。**有默认值的字段不算必填**
    static func isConfigured(_ vendor: SpeechVendor) -> Bool {
        vendor.fields.allSatisfy { field in
            !field.defaultValue.isEmpty || !credential(vendor, field.key).isEmpty
        }
    }

    /// 现在这家能不能用：凭据齐了、音色也选了
    var configured: Bool {
        Self.isConfigured(vendor) && !voiceID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 缺什么。**要能直接说给用户听**，「未配置」三个字没有任何帮助
    var missingHint: String? {
        for field in vendor.fields where field.defaultValue.isEmpty
            && Self.credential(vendor, field.key).isEmpty {
            return "还没填 \(vendor.displayName) 的\(field.label)"
        }
        if voiceID.trimmingCharacters(in: .whitespaces).isEmpty {
            return "还没挑\(vendor.displayName)的音色"
        }
        return nil
    }

    // MARK: - 合成

    func speech(_ text: String) async throws -> Data {
        if let missingHint { throw SpeechError.bad(missingHint) }
        return try await SpeechEngines.speech(vendor: vendor, text: text, voice: voiceID,
                                              model: model,
                                              credentials: Self.credentials(for: vendor))
    }

    // MARK: - 音色

    /// 挑的时候看到的全部音色：内置的 + 拉回来的
    var selectableVoices: [SpeechVoice] {
        vendor.builtInVoices + fetchedVoices
    }

    func loadVoices() async {
        guard vendor.canListVoices, !voicesLoading else { return }
        voicesLoading = true
        voicesError = nil
        defer { voicesLoading = false }
        do {
            let key = Self.credential(vendor, "key")
            let list = try await ElevenLabsService.voices(apiKey: key)
            fetchedVoices = list.map { SpeechVoice(id: $0.id, name: $0.name, detail: $0.detail) }
            if fetchedVoices.isEmpty { voicesError = "账号里没有可用的声音" }
        } catch {
            voicesError = error.localizedDescription
        }
    }

    func pick(_ voice: SpeechVoice) {
        voiceID = voice.id
        voiceName = voice.name
    }

    private func reloadVoiceForVendor() {
        let ud = UserDefaults.standard
        voiceID = ud.string(forKey: voiceKey) ?? vendor.defaultVoice?.id ?? ""
        voiceName = ud.string(forKey: voiceNameKey) ?? vendor.defaultVoice?.name ?? ""
        model = ud.string(forKey: modelKey) ?? vendor.defaultModel
        fetchedVoices = []
        voicesError = nil
    }

    // MARK: - 老设置搬家

    /// 以前 ElevenLabs 的 Key 存在 `APIKeyStore.Secret.elevenLabs` 里，
    /// 音色存在 `<persona>_eleven_voice_id`。搬过来一次，用户不用重填。
    ///
    /// **老的那个默认音色 `Rachel` 不搬**——它是个英文女声，
    /// 是「填了 key 开箱第一次朗读就不对」的根源。宁可让用户重新挑一个
    private func migrateLegacyElevenLabs() {
        let ud = UserDefaults.standard
        let doneKey = "speech_migrated_from_eleven"
        guard !ud.bool(forKey: doneKey) else { return }
        ud.set(true, forKey: doneKey)

        let legacyKey = APIKeyStore.secret(.elevenLabs)
        if !legacyKey.isEmpty, Self.credential(.elevenLabs, "key").isEmpty {
            Self.setCredential(legacyKey, .elevenLabs, "key")
        }
        let legacyVoice = ud.string(forKey: "\(personaId)_eleven_voice_id") ?? ""
        if !legacyVoice.isEmpty, legacyVoice != ElevenLabsService.defaultVoiceID,
           vendor == .elevenLabs, voiceID.isEmpty {
            voiceID = legacyVoice
            voiceName = ud.string(forKey: "\(personaId)_eleven_voice_name") ?? legacyVoice
        }
        if let legacyModel = ud.string(forKey: "eleven_tts_model"), vendor == .elevenLabs {
            model = legacyModel
        }
    }
}
