import Foundation

struct AudioMCP: MCPModule {
    let id = "audio_player"
    let name = "音频播放"
    let nameEN = "Audio Player"
    let icon = "headphones"
    let descriptionZH = "播放导入的音频文件"
    let descriptionEN = "Play imported audio files"

    var toolSchemas: [[String: Any]] {
        [
            ClaudeService.toolSchema(
                name: "play_audio",
                description: "播放用户导入的音频。根据名字搜索音频库，找到就播放。她让你放歌、放音乐、放某个音频的时候调用。",
                properties: [
                    "query": ClaudeService.stringSchema(description: "要播放的音频名字或关键词"),
                ],
                required: ["query"]
            ),
            ClaudeService.toolSchema(
                name: "list_audio",
                description: "列出用户导入的所有音频文件。她问有什么歌、有什么音频的时候调用。",
                properties: [:],
                required: []
            ),
            ClaudeService.toolSchema(
                name: "pause_audio",
                description: "暂停当前播放的音频。她让你暂停、停一下的时候调用。",
                properties: [:],
                required: []
            ),
        ]
    }

    func execute(toolName: String, input: [String: Any]) async -> String {
        guard let service = await AudioPlayerService.shared else {
            return "音频服务还没准备好"
        }

        switch toolName {
        case "play_audio":
            guard let query = input["query"] as? String, !query.isEmpty else {
                return "参数不对，播不了"
            }
            let track = await service.findTrack(nameContaining: query)
            guard let track else {
                let names = await service.library.map(\.displayName)
                if names.isEmpty { return "音频库是空的，还没有导入过音频" }
                return "没找到「\(query)」，音频库里有：\(names.joined(separator: "、"))"
            }
            await service.play(track)
            await MainActor.run { service.pendingTrackId = track.id }
            return "正在播放「\(track.displayName)」"

        case "list_audio":
            let tracks = await service.library
            if tracks.isEmpty { return "音频库是空的，还没有导入过音频" }
            let lines = tracks.enumerated().map { (i, t) in
                "\(i + 1). \(t.displayName)"
            }
            return "音频库里有 \(tracks.count) 首：\n" + lines.joined(separator: "\n")

        case "pause_audio":
            let playing = await service.isPlaying
            if playing {
                await service.pause()
                let name = await service.currentTrack?.displayName ?? "音频"
                return "已暂停「\(name)」"
            }
            return "当前没有在播放音频"

        default:
            return "不认识这个工具"
        }
    }
}
