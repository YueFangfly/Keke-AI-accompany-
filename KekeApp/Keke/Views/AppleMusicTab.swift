import SwiftUI
import MusicKit

struct AppleMusicTab: View {
    @EnvironmentObject var appleMusic: AppleMusicService
    @EnvironmentObject var store: ChatStore
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            if appleMusic.authStatus != .authorized {
                authPrompt
            } else {
                searchBar
                if appleMusic.isSearching {
                    ProgressView()
                        .padding(.top, 40)
                    Spacer()
                } else if !appleMusic.searchResults.isEmpty {
                    resultsList
                } else if !query.isEmpty {
                    Text(L.t("没有找到相关歌曲", store.appLanguage))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 40)
                    Spacer()
                } else {
                    nowPlayingOrHint
                }
            }
        }
    }

    // MARK: - Auth

    private var authPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.note.tv")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
            Text(L.t("需要 Apple Music 权限才能播放", store.appLanguage))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(L.t("授权 Apple Music", store.appLanguage)) {
                Task { await appleMusic.requestAuth() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            Spacer()
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            TextField(L.t("搜索 Apple Music", store.appLanguage), text: $query)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .submitLabel(.search)
                .onSubmit { doSearch() }
            if !query.isEmpty {
                Button {
                    query = ""
                    appleMusic.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Results

    private var resultsList: some View {
        List(appleMusic.searchResults, id: \.id) { song in
            HStack(spacing: 12) {
                if let artwork = song.artwork {
                    ArtworkImage(artwork, width: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.card)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundStyle(Theme.textSecondary)
                        }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isCurrentSong(song) ? Theme.accent : Theme.textPrimary)
                        .lineLimit(1)
                    Text(song.artistName)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if isCurrentSong(song) {
                    Image(systemName: appleMusic.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                } else {
                    Text(AppleMusicService.formatDuration(song.duration))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isCurrentSong(song) {
                    appleMusic.togglePlayPause()
                } else {
                    appleMusic.play(song)
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
    }

    // MARK: - Now Playing / Hint

    private var nowPlayingOrHint: some View {
        VStack(spacing: 16) {
            Spacer()
            if let song = appleMusic.currentSong {
                if let artwork = song.artwork {
                    ArtworkImage(artwork, width: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Text(song.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(song.artistName)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 32) {
                    Button { appleMusic.togglePlayPause() } label: {
                        Image(systemName: appleMusic.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.accent)
                    }
                    Button { appleMusic.stop() } label: {
                        Image(systemName: "stop.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.top, 8)
            } else {
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.textSecondary)
                Text(L.t("搜索并播放 Apple Music 歌曲", store.appLanguage))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Helpers

    private func isCurrentSong(_ song: Song) -> Bool {
        appleMusic.currentSong?.id == song.id
    }

    private func doSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        Task { await appleMusic.search(q) }
    }
}
