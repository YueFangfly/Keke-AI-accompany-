import Foundation
import UIKit
import UserNotifications

/// 朋友圈/日记：我和克克都能发动态，克克的点赞/评论/回复不是秒回，
/// 是在一个随机排出来的时间点"刷到了才回"——不是固定延迟，每次都不一样。
@MainActor
final class MomentsStore: ObservableObject {
    let personaId: String
    @Published var moments: [Moment] = []

    private let center = UNUserNotificationCenter.current()

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_moments.json")
    }

    init(personaId: String = "keke") {
        self.personaId = personaId
        load()
    }

    // MARK: - 发动态 / 评论 / 点赞

    /// 我发一条动态；克克会在随机时间点"刷到"并回应。
    /// 其他好友（接了 Key 的）各自有 65% 概率"迟早会刷到"，刷到时间也是随机排的
    func postMine(text: String, image: UIImage? = nil, friends: [Contact] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || image != nil else { return }
        var moment = Moment(author: .me, text: trimmed, pendingReplyAt: reactionDate(from: Date()))
        if let image, let name = Attachments.saveImage(image) {
            moment.imagePath = name
        }
        var friendSchedule: [String: Date] = [:]
        for friend in friends where ContactsStore.hasKey(for: friend.provider) {
            if Double.random(in: 0..<1) < 0.65 {
                friendSchedule[friend.id] = reactionDate(from: Date())
            }
        }
        if !friendSchedule.isEmpty { moment.pendingFriendReactions = friendSchedule }
        moments.insert(moment, at: 0)
        save()
    }

    /// 让克克发一条她自己的动态（我手动点按钮触发）
    func postKeke(store: ChatStore) async {
        guard !store.apiKey.isEmpty else { return }
        let recent = store.messages.suffix(12)
            .map { ($0.role == .user ? "\(store.myName)：" : "\(PersonaStore.persona(for: store.personaId).name)：") + $0.text }
            .joined(separator: "\n")
        let pName = PersonaStore.persona(for: store.personaId).name
        guard let text = await GenerationFallback.attempt("发朋友圈", {
            try await ClaudeService.generateKekeMoment(
            recentChat: recent.isEmpty ? nil : recent, userName: store.myName,
            personaName: pName,
            provider: store.provider, apiKey: store.apiKey, model: store.model,
            systemPrompt: store.effectiveSystemPrompt
        )
        }) else { return }
        moments.insert(Moment(author: .keke, text: text), at: 0)
        save()
    }

    /// 聊得有意思，克克自己想发一条：每次她回完一句消息后有一点小概率触发，
    /// 加上冷却时间防止刷屏（不是每次聊天都会发）
    func maybeSpontaneousPost(store: ChatStore) async {
        guard !store.apiKey.isEmpty, canPostSpontaneously, Double.random(in: 0..<1) < 0.1 else { return }
        let pName = PersonaStore.persona(for: store.personaId).name
        let recent = store.messages.suffix(10)
            .map { ($0.role == .user ? "\(store.myName)：" : "\(pName)：") + $0.text }
            .joined(separator: "\n")
        guard let text = await GenerationFallback.attempt("发朋友圈", {
            try await ClaudeService.generateKekeMoment(
            recentChat: recent, userName: store.myName,
            personaName: pName,
            provider: store.provider, apiKey: store.apiKey,
            model: store.model, systemPrompt: store.effectiveSystemPrompt
        )
        }) else { return }
        moments.insert(Moment(author: .keke, text: text), at: 0)
        markPostedSpontaneously()
        save()
    }

    /// 「她自己想发」的冷却时间，至少隔 6 小时，避免刷屏。
    /// 只在真的聊天互动之后才可能触发（见 maybeSpontaneousPost），不是隔一段时间没聊天就自己发一条
    private var canPostSpontaneously: Bool {
        let lastPostedAt = UserDefaults.standard.double(forKey: "\(personaId)_spontaneous_moment_at")
        return Date().timeIntervalSince1970 - lastPostedAt > 6 * 3600
    }

    private func markPostedSpontaneously() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "\(personaId)_spontaneous_moment_at")
    }

    /// 我给一条动态点赞/取消点赞
    func toggleMyLike(_ id: UUID) {
        guard let index = moments.firstIndex(where: { $0.id == id }) else { return }
        moments[index].likedByMe.toggle()
        save()
    }

    /// 我给一条动态加评论（可以指定回复某一条具体的评论）。
    /// 回复的是某个好友的评论就排那个好友来接话；其余情况还是克克来接
    func addComment(to id: UUID, text: String, replyTo: MomentComment? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = moments.firstIndex(where: { $0.id == id }) else { return }
        var comment = MomentComment(author: .me, text: trimmed)
        if let replyTo {
            comment.replyToAuthor = replyTo.author
            comment.replyToPreview = String(replyTo.text.prefix(30))
        }
        moments[index].comments.append(comment)
        if let replyTo, replyTo.author == .friend, let friendID = replyTo.friendID {
            var schedule = moments[index].pendingFriendReactions ?? [:]
            schedule[friendID] = reactionDate(from: Date())
            moments[index].pendingFriendReactions = schedule
        } else {
            moments[index].pendingReplyAt = reactionDate(from: Date())
        }
        save()
    }

    /// 删除一条动态（只给我自己发的用）
    func delete(_ id: UUID) {
        moments.removeAll { $0.id == id }
        save()
    }

    // MARK: - 克克的延迟回应

    /// App 回到前台 / 打开朋友圈页时调用：处理所有已经到了该回应时间的动态（克克 + 各个好友）
    func checkPendingReactions(store: ChatStore, friends: [Contact] = []) async {
        if !store.apiKey.isEmpty {
            let dueIDs = moments.filter {
                if let at = $0.pendingReplyAt { return at <= Date() }
                return false
            }.map(\.id)
            for id in dueIDs {
                await react(to: id, store: store)
            }
        }

        // 好友们的"刷到了"
        for friend in friends where ContactsStore.hasKey(for: friend.provider) {
            let dueIDs = moments.filter {
                if let at = $0.pendingFriendReactions?[friend.id] { return at <= Date() }
                return false
            }.map(\.id)
            for id in dueIDs {
                await friendReact(to: id, friend: friend, store: store)
            }
        }
    }

    /// 某个好友刷到了这条：基本都会点个赞，55% 概率顺手评论一句（用他自己的模型和记忆）
    private func friendReact(to id: UUID, friend: Contact, store: ChatStore) async {
        guard let index = moments.firstIndex(where: { $0.id == id }) else { return }
        let moment = moments[index]

        var liked = moment.likedByFriends ?? []
        if !liked.contains(friend.id) {
            liked.append(friend.id)
            moments[index].likedByFriends = liked
        }
        moments[index].pendingFriendReactions?.removeValue(forKey: friend.id)
        save()

        guard Double.random(in: 0..<1) < 0.55 else { return }

        let threadLines = moment.comments.map { comment -> String in
            let name: String
            switch comment.author {
            case .me: name = store.myName
            case .keke: name = PersonaStore.persona(for: store.personaId).name
            case .friend: name = comment.friendName ?? "朋友"
            }
            let replyMark = comment.replyToPreview.map { "(回复「\($0)」) " } ?? ""
            return "\(name)：\(replyMark)\(comment.text)"
        }.joined(separator: "\n")

        let persona = friend.persona.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemPrompt = persona.isEmpty
            ? "你的名字是\(friend.name)，是 \(store.myName) 的朋友。"
            : persona

        let reply = await GenerationFallback.attempt("朋友圈好友评论", {
            try await ClaudeService.generateFriendMomentReply(
            friendName: friend.name,
            momentAuthorName: moment.author == .me ? store.myName : PersonaStore.persona(for: store.personaId).name,
            momentText: moment.text,
            threadLines: threadLines.isEmpty ? nil : threadLines,
            userName: store.myName,
            provider: friend.provider,
            apiKey: ContactsStore.apiKey(for: friend.provider),
            model: friend.model,
            systemPrompt: systemPrompt,
            extraContext: store.memory?.contextBlock(for: moment.text, userName: store.myName,
                                                     contact: friend.id))
        })
        guard let reply, let freshIndex = moments.firstIndex(where: { $0.id == id }) else { return }
        moments[freshIndex].comments.append(
            MomentComment(author: .friend, text: reply, friendID: friend.id, friendName: friend.name))
        save()
    }

    private func react(to id: UUID, store: ChatStore) async {
        guard let snapshotIndex = moments.firstIndex(where: { $0.id == id }) else { return }
        let moment = moments[snapshotIndex]
        let isFirstReaction = moment.comments.isEmpty

        // 不是每次都会说话：新动态她基本都会点赞，但评论不一定；
        // 已经有过往来的评论区里，她大概两成概率这次就划过去不回，不是每条都非回不可
        let willComment = isFirstReaction
            ? Double.random(in: 0..<1) < 0.85
            : Double.random(in: 0..<1) < 0.8

        guard let likeIndex = moments.firstIndex(where: { $0.id == id }) else { return }
        if isFirstReaction {
            moments[likeIndex].likedByKeke = true
        }
        guard willComment else {
            moments[likeIndex].pendingReplyAt = nil
            save()
            return
        }

        let thread = moment.comments.map { comment -> (author: String, text: String) in
            // 好友的评论把备注名传过去，克克能看出来是谁说的
            let author = comment.author == .friend ? (comment.friendName ?? "朋友") : comment.author.rawValue
            guard let preview = comment.replyToPreview else {
                return (author: author, text: comment.text)
            }
            return (author: author, text: "(回复「\(preview)」) " + comment.text)
        }

        let reply = await GenerationFallback.attempt("朋友圈评论", {
            try await ClaudeService.generateMomentReply(
            momentAuthor: moment.author.rawValue,
            momentText: moment.text,
            thread: thread,
            likedByMe: moment.likedByMe,
            userName: store.myName,
            personaName: PersonaStore.persona(for: store.personaId).name,
            provider: store.provider, apiKey: store.apiKey, model: store.model,
            systemPrompt: store.effectiveSystemPrompt,
            extraContext: store.memory?.contextBlock(for: moment.text, userName: store.myName)
        )
        })

        // 等网络请求的这段时间里数组可能已经变了（比如新发了一条动态被插到最前面），
        // 所以回来之后要重新按 id 找一次下标，不能沿用之前的
        guard let index = moments.firstIndex(where: { $0.id == id }) else { return }
        guard let reply else {
            moments[index].pendingReplyAt = nil
            return
        }

        moments[index].comments.append(MomentComment(author: .keke, text: reply))
        moments[index].pendingReplyAt = nil
        save()
        await notify(reply)
    }

    private func notify(_ text: String) async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        let content = UNMutableNotificationContent()
        content.title = "\(PersonaStore.persona(for: personaId).name)在朋友圈回复了你"
        content.body = text
        content.sound = .default
        let request = UNNotificationRequest(identifier: "moment_\(UUID().uuidString)", content: content, trigger: nil)
        try? await center.add(request)
    }

    /// 随机排一个回应时间：8 分钟到 5 小时之后；如果正好落在凌晨(0-8点)，
    /// 挪到当天早上 8-10 点之间——模拟"克克睡醒刷到了才回"，而不是掐着固定的一段时间回
    private func reactionDate(from now: Date) -> Date {
        let delay = TimeInterval.random(in: 8 * 60...5 * 3600)
        var candidate = now.addingTimeInterval(delay)
        let hour = Calendar.current.component(.hour, from: candidate)
        if hour < 8 {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: candidate)
            comps.hour = Int.random(in: 8...10)
            comps.minute = Int.random(in: 0...59)
            candidate = Calendar.current.date(from: comps) ?? candidate
        }
        return candidate
    }

    // MARK: - 持久化

    private func save() {
        guard let data = try? JSONEncoder().encode(moments) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([Moment].self, from: data) else { return }
        moments = saved
    }
}
