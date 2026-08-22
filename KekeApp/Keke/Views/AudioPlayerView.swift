import SwiftUI
import UniformTypeIdentifiers

struct AudioPlayerView: View {
    @EnvironmentObject var audio: AudioPlayerService
    @EnvironmentObject var store: ChatStore
    @State private var showImporter = false
    @State private var editingTrack: AudioTrack?
    @State private var editName = ""
    @State private var showLibrary = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                nowPlayingSection
                controlsSection
                Divider().padding(.vertical, 8)
                playlistSection
            }
            .background(Theme.background)
            .navigationTitle(L.t("音频播放", store.appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L.t("音频库", store.appLanguage)) { showLibrary = true }
                        .font(.subheadline)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.audio, .mp3, .wav, .aiff, UTType("public.mpeg-4-audio") ?? .audio],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                if let track = audio.importAudio(from: url) {
                    audio.addToPlaylist(track)
                }
            }
        }
        .sheet(isPresented: $showLibrary) {
            AudioLibraryView()
                .environmentObject(audio)
                .environmentObject(store)
        }
        .alert(L.t("重命名", store.appLanguage), isPresented: .init(
            get: { editingTrack != nil },
            set: { if !$0 { editingTrack = nil } }
        )) {
            TextField(L.t("音频名称", store.appLanguage), text: $editName)
            Button(L.t("确定", store.appLanguage)) {
                if let t = editingTrack, !editName.trimmingCharacters(in: .whitespaces).isEmpty {
                    audio.rename(t, to: editName.trimmingCharacters(in: .whitespaces))
                }
                editingTrack = nil
            }
            Button(L.t("取消", store.appLanguage), role: .cancel) { editingTrack = nil }
        }
    }

    // MARK: - Now Playing

    private var nowPlayingSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.card)
                    .frame(width: 180, height: 180)
                Image(systemName: "music.note")
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, 20)

            Text(audio.currentTrack?.displayName ?? L.t("未在播放", store.appLanguage))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(spacing: 4) {
                Slider(value: Binding(
                    get: { audio.duration > 0 ? audio.currentTime / audio.duration : 0 },
                    set: { audio.seekTo($0 * audio.duration) }
                ))
                .tint(Theme.accent)
                .padding(.horizontal, 24)

                HStack {
                    Text(AudioPlayerService.formatTime(audio.currentTime))
                    Spacer()
                    Text(AudioPlayerService.formatTime(audio.duration))
                }
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 28)
            }
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 28) {
                Button { audio.playPrevious() } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                }
                Button { audio.seek(by: -15) } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                Button { audio.togglePlayPause() } label: {
                    Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }
                Button { audio.seek(by: 15) } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
                Button { audio.playNext() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title2)
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 12)

            HStack {
                Spacer()
                Button {
                    audio.playbackMode = audio.playbackMode.next
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: audio.playbackMode.icon)
                            .font(.system(size: 14))
                        Text(playbackModeLabel)
                            .font(.caption2)
                    }
                    .foregroundStyle(audio.playbackMode == .sequential ? Theme.textSecondary : Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.card))
                }
                Spacer()
            }
            .padding(.bottom, 4)
        }
    }

    private var playbackModeLabel: String {
        switch audio.playbackMode {
        case .sequential: return L.t("播完暂停", store.appLanguage)
        case .loopAll: return L.t("歌单循环", store.appLanguage)
        case .loopOne: return L.t("单曲循环", store.appLanguage)
        }
    }

    // MARK: - Playlist

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.t("播放列表", store.appLanguage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(audio.playlist.count)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16)

            if audio.playlist.isEmpty {
                Text(L.t("播放列表是空的，点右上角 + 导入音频", store.appLanguage))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            } else {
                List {
                    ForEach(audio.playlist) { track in
                        HStack(spacing: 10) {
                            if audio.currentTrack?.id == track.id {
                                Image(systemName: audio.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 20)
                            } else {
                                Image(systemName: "music.note")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 20)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(audio.currentTrack?.id == track.id ? Theme.accent : Theme.textPrimary)
                                    .lineLimit(1)
                                Text(AudioPlayerService.formatTime(track.duration))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { audio.play(track) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if let idx = audio.playlist.firstIndex(where: { $0.id == track.id }) {
                                    audio.removeFromPlaylist(at: IndexSet(integer: idx))
                                }
                            } label: {
                                Label(L.t("移除", store.appLanguage), systemImage: "minus.circle")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingTrack = track
                                editName = track.displayName
                            } label: {
                                Label(L.t("重命名", store.appLanguage), systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                    .onMove { audio.moveInPlaylist(from: $0, to: $1) }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Audio Library

struct AudioLibraryView: View {
    @EnvironmentObject var audio: AudioPlayerService
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var editingTrack: AudioTrack?
    @State private var editName = ""

    var body: some View {
        NavigationView {
            List {
                ForEach(audio.library) { track in
                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.displayName)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text("\(track.fileName) · \(AudioPlayerService.formatTime(track.duration))")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button {
                            audio.addToPlaylist(track)
                        } label: {
                            Image(systemName: audio.playlist.contains(where: { $0.id == track.id })
                                  ? "checkmark.circle.fill" : "plus.circle")
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            audio.deleteTrack(track)
                        } label: {
                            Label(L.t("删除", store.appLanguage), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            editingTrack = track
                            editName = track.displayName
                        } label: {
                            Label(L.t("重命名", store.appLanguage), systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if audio.library.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.textSecondary)
                        Text(L.t("还没有导入音频", store.appLanguage))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .navigationTitle(L.t("音频库", store.appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L.t("关闭", store.appLanguage)) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.audio, .mp3, .wav, .aiff, UTType("public.mpeg-4-audio") ?? .audio],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls { audio.importAudio(from: url) }
        }
        .alert(L.t("重命名", store.appLanguage), isPresented: .init(
            get: { editingTrack != nil },
            set: { if !$0 { editingTrack = nil } }
        )) {
            TextField(L.t("音频名称", store.appLanguage), text: $editName)
            Button(L.t("确定", store.appLanguage)) {
                if let t = editingTrack, !editName.trimmingCharacters(in: .whitespaces).isEmpty {
                    audio.rename(t, to: editName.trimmingCharacters(in: .whitespaces))
                }
                editingTrack = nil
            }
            Button(L.t("取消", store.appLanguage), role: .cancel) { editingTrack = nil }
        }
    }
}

// MARK: - Mini Player Overlay

struct MiniPlayerOverlay: View {
    @EnvironmentObject var audio: AudioPlayerService

    var body: some View {
        if audio.showMiniPlayer, audio.currentTrack != nil {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack(alignment: .topTrailing) {
                        Button {
                            audio.showFullPlayer = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Theme.accent)
                                    .frame(width: 52, height: 52)
                                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                                Image(systemName: audio.isPlaying ? "music.note" : "pause.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                            }
                        }

                        Button {
                            audio.stop()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Theme.card)
                                    .frame(width: 20, height: 20)
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .offset(x: 4, y: -4)
                    }
                    .padding(.trailing, 12)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Chat Audio Bubble

struct AudioBubble: View {
    let trackId: String
    @EnvironmentObject var audio: AudioPlayerService

    private var track: AudioTrack? {
        audio.library.first { $0.id == trackId }
            ?? audio.playlist.first { $0.id == trackId }
    }

    private var isThisTrack: Bool {
        audio.currentTrack?.id == trackId
    }

    var body: some View {
        if let track {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Theme.accent.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(track.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                }

                HStack(spacing: 16) {
                    Spacer()
                    Button { seekOrRestart(-30) } label: {
                        Image(systemName: "gobackward.30")
                            .font(.system(size: 16))
                    }
                    Button { seekOrRestart(-10) } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 16))
                    }
                    Button { playOrToggle(track) } label: {
                        Image(systemName: isThisTrack && audio.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                    }
                    Button { seekOrStart(10) } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 16))
                    }
                    Button { seekOrStart(30) } label: {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 16))
                    }
                    Spacer()
                }
                .foregroundStyle(Theme.textPrimary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
            .padding(.horizontal, 14)
        }
    }

    private func playOrToggle(_ track: AudioTrack) {
        if isThisTrack {
            audio.togglePlayPause()
        } else {
            audio.play(track)
        }
    }

    private func seekOrRestart(_ seconds: TimeInterval) {
        if isThisTrack { audio.seek(by: seconds) }
    }

    private func seekOrStart(_ seconds: TimeInterval) {
        if isThisTrack { audio.seek(by: seconds) }
    }
}
