import SwiftUI
import UIKit
import AVFoundation

// MARK: - 出码

/// 把一个自定义供应商变成二维码给另一台手机扫。
///
/// 「带 Key」默认关着。带上就等于把 Key 明文画在屏幕上——
/// 面对面扫没问题，截图发出去就等于把 Key 送人了，所以这句话要写在脸上。
struct ProviderQRSheet: View {
    @EnvironmentObject var store: ChatStore
    let provider: CustomAIProvider
    var onClose: () -> Void

    @State private var includeSecrets = false
    @State private var copied = false

    private var lang: AppLanguage { store.appLanguage }

    private var payload: ProviderShare.Payload {
        ProviderShare.Payload(
            name: provider.name,
            baseURL: provider.baseURL,
            defaultModel: provider.defaultModel,
            keyPlaceholder: provider.keyPlaceholder,
            supportsVision: provider.supportsVision,
            supportsFunctionCalling: provider.supportsFunctionCalling,
            headerNames: provider.headerNames,
            extraBodyJSON: provider.extraBodyJSON,
            apiKey: includeSecrets ? APIKeyStore.key(for: provider.id) : "",
            headerValues: includeSecrets
                ? CustomProviderStore.headers(for: provider.id, names: provider.headerNames)
                : [:]
        )
    }

    private var encoded: Result<String, Error> {
        Result { try ProviderShare.encode(payload) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(provider.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 18)

                code

                Toggle(isOn: $includeSecrets) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t("把 API Key 一起带上", lang))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("备份文件里是没有 Key 的，只有这张码能带")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.accent)
                .padding(14)
                .glassCard(cornerRadius: 14)

                if includeSecrets {
                    Label("这张码里的 Key 是明文。当面扫，别截图、别转发",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.crabRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                copyButton
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .backButtonInset(onBack: onClose)
    }

    @ViewBuilder
    private var code: some View {
        switch encoded {
        case .success(let text):
            if let image = ProviderShare.qrImage(text) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18).fill(.white))
            } else {
                Text("画不出这张码")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        case .failure(let error):
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(Theme.crabRed)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var copyButton: some View {
        if case .success(let text) = encoded {
            Button {
                UIPasteboard.general.string = text
                copied = true
            } label: {
                Text(copied ? "已复制" : "复制配置串（对面可以粘贴导入）")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .glassCard(cornerRadius: 14)
            }
        }
    }
}

// MARK: - 扫码

/// 扫码导入。**摄像头不是必需的**——粘贴那条路径始终可用，
/// 用户拒了相机权限也不该卡死在这里
struct ProviderScanSheet: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var customProviders: CustomProviderStore
    var onClose: () -> Void

    @State private var scanned: ProviderShare.Payload?
    @State private var problem: String?
    @State private var cameraDenied = false

    var body: some View {
        VStack(spacing: 14) {
            Text("扫码导入 API")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)

            if let payload = scanned {
                preview(payload)
            } else {
                scanner
                pasteButton
            }

            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(Theme.crabRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)
        }
        .background(Theme.background)
        .backButtonInset(onBack: onClose)
    }

    @ViewBuilder
    private var scanner: some View {
        if cameraDenied {
            VStack(spacing: 6) {
                Text("没有相机权限")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Text("可以去「设置 → 隐私 → 相机」打开，或者直接用下面的粘贴")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
            .glassCard(cornerRadius: 18)
            .padding(.horizontal, 18)
        } else {
            QRCameraView(onFound: handle, onDenied: { cameraDenied = true })
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 18)
        }
    }

    private var pasteButton: some View {
        Button {
            handle(UIPasteboard.general.string ?? "")
        } label: {
            Text("从剪贴板粘贴配置串")
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(14)
                .glassCard(cornerRadius: 14)
        }
        .padding(.horizontal, 18)
    }

    private func preview(_ payload: ProviderShare.Payload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(payload.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Text(payload.baseURL)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            if !payload.defaultModel.isEmpty {
                Text("默认模型：" + payload.defaultModel)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(payload.carriesSecret ? "带着 Key，导入后可以直接用" : "不带 Key，导入后要自己填")
                .font(.caption2)
                .foregroundStyle(payload.carriesSecret ? Theme.accent : Theme.crabRed)

            Button {
                apply(payload)
            } label: {
                Text("导入")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
        .padding(.horizontal, 18)
    }

    private func handle(_ text: String) {
        guard scanned == nil else { return }
        do {
            scanned = try ProviderShare.decode(text)
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    /// 导入永远是**新增**，不覆盖同名的旧配置。
    /// 扫错一张码就把在用的配置改掉，比多出一条要难受得多
    private func apply(_ payload: ProviderShare.Payload) {
        var provider = CustomAIProvider(
            name: payload.name,
            baseURL: payload.baseURL,
            defaultModel: payload.defaultModel,
            keyPlaceholder: payload.keyPlaceholder,
            supportsVision: payload.supportsVision,
            supportsFunctionCalling: payload.supportsFunctionCalling)
        provider.headerNames = payload.headerNames
        provider.extraBodyJSON = payload.extraBodyJSON
        customProviders.add(provider)

        if !payload.apiKey.isEmpty {
            APIKeyStore.setKey(payload.apiKey, for: provider.id)
        }
        for (name, value) in payload.headerValues {
            CustomProviderStore.setHeader(value, name: name, for: provider.id)
        }
        onClose()
    }
}

// MARK: - 相机

/// 只做一件事：认出一张二维码就把字符串交出去。
///
/// 会话在后台队列上起停——`startRunning()` 是阻塞的，放主线程会卡住一下界面
struct QRCameraView: UIViewControllerRepresentable {
    var onFound: (String) -> Void
    var onDenied: () -> Void

    func makeUIViewController(context: Context) -> QRCameraController {
        let controller = QRCameraController()
        controller.onFound = onFound
        controller.onDenied = onDenied
        return controller
    }

    func updateUIViewController(_ controller: QRCameraController, context: Context) {}
}

final class QRCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?
    var onDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "keke.qr.session")
    private var preview: AVCaptureVideoPreviewLayer?
    private var delivered = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configure() } else { self?.onDenied?() }
                }
            }
        default:
            onDenied?()
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { onDenied?(); return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { onDenied?(); return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer

        queue.async { [session] in session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        queue.async { [session] in session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !delivered,
              let object = objects.first as? AVMetadataMachineReadableCodeObject,
              let text = object.stringValue,
              text.hasPrefix(ProviderShare.prefix) else { return }
        delivered = true
        queue.async { [session] in session.stopRunning() }
        onFound?(text)
    }
}
