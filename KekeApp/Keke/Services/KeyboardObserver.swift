import UIKit
import Combine

/// 监听键盘高度，让聊天输入框能跟着键盘往上移
final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0

    private var showToken: NSObjectProtocol?
    private var hideToken: NSObjectProtocol?

    init() {
        showToken = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
            self?.height = frame.height
        }
        hideToken = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.height = 0
        }
    }

    deinit {
        if let showToken { NotificationCenter.default.removeObserver(showToken) }
        if let hideToken { NotificationCenter.default.removeObserver(hideToken) }
    }
}
