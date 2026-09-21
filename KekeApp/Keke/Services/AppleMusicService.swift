import Foundation
import MusicKit
import Combine

@MainActor
final class AppleMusicService: ObservableObject {
    @Published var authStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @Published var searchResults: [Song] = []
    @Published var isSearching = false
    @Published var currentSong: Song?
    @Published var isPlaying = false

    private let player = ApplicationMusicPlayer.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        player.state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncState()
            }
            .store(in: &cancellables)
    }

    private func syncState() {
        isPlaying = player.state.playbackStatus == .playing
    }

    func requestAuth() async {
        authStatus = await MusicAuthorization.request()
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        var request = MusicCatalogSearchRequest(term: trimmed, types: [Song.self])
        request.limit = 25
        guard let response = try? await request.response() else { return }
        searchResults = Array(response.songs)
    }

    func play(_ song: Song) {
        player.queue = [song]
        currentSong = song
        Task { try? await player.play() }
    }

    func togglePlayPause() {
        if player.state.playbackStatus == .playing {
            player.pause()
        } else {
            Task { try? await player.play() }
        }
    }

    func stop() {
        player.stop()
        currentSong = nil
        isPlaying = false
    }

    static func formatDuration(_ duration: TimeInterval?) -> String {
        guard let d = duration, d > 0 else { return "--:--" }
        let m = Int(d) / 60
        let s = Int(d) % 60
        return String(format: "%d:%02d", m, s)
    }
}
