import Foundation
import AVFoundation

struct AudioTrack: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var displayName: String
    var fileName: String
    var duration: TimeInterval = 0
}

@MainActor
final class AudioPlayerService: NSObject, ObservableObject {
    static weak var shared: AudioPlayerService?

    @Published var library: [AudioTrack] = []
    @Published var playlist: [AudioTrack] = []
    @Published var currentTrack: AudioTrack?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var showMiniPlayer = false
    @Published var showFullPlayer = false

    var pendingTrackId: String?

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private let personaId: String

    private var audioDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Audio/\(personaId)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var libraryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_audio_library.json")
    }

    private var playlistURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_audio_playlist.json")
    }

    init(personaId: String = "keke") {
        self.personaId = personaId
        super.init()
        Self.shared = self
        loadLibrary()
        loadPlaylist()
    }

    // MARK: - Import

    @discardableResult
    func importAudio(from sourceURL: URL) -> AudioTrack? {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let originalName = sourceURL.lastPathComponent
        let destURL = uniqueDestination(for: originalName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            return nil
        }

        let dur = Self.audioDuration(at: destURL)
        let name = sourceURL.deletingPathExtension().lastPathComponent
        let track = AudioTrack(displayName: name, fileName: destURL.lastPathComponent, duration: dur)
        library.append(track)
        saveLibrary()
        return track
    }

    private func uniqueDestination(for name: String) -> URL {
        var dest = audioDir.appendingPathComponent(name)
        var counter = 1
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = audioDir.appendingPathComponent("\(stem)_\(counter).\(ext)")
            counter += 1
        }
        return dest
    }

    private static func audioDuration(at url: URL) -> TimeInterval {
        (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
    }

    // MARK: - Playback

    func play(_ track: AudioTrack) {
        let url = audioDir.appendingPathComponent(track.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            currentTrack = track
            isPlaying = true
            duration = p.duration
            currentTime = 0
            showMiniPlayer = true
            startTimer()

            if !playlist.contains(where: { $0.id == track.id }) {
                playlist.append(track)
                savePlaylist()
            }
        } catch { }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func resume() {
        player?.play()
        isPlaying = true
        startTimer()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func seek(by seconds: TimeInterval) {
        guard let p = player else { return }
        let t = max(0, min(p.duration, p.currentTime + seconds))
        p.currentTime = t
        currentTime = t
    }

    func seekTo(_ time: TimeInterval) {
        guard let p = player else { return }
        p.currentTime = max(0, min(p.duration, time))
        currentTime = p.currentTime
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTrack = nil
        showMiniPlayer = false
        currentTime = 0
        duration = 0
        stopTimer()
    }

    func playNext() {
        guard let cur = currentTrack,
              let idx = playlist.firstIndex(where: { $0.id == cur.id }),
              idx + 1 < playlist.count else { return }
        play(playlist[idx + 1])
    }

    func playPrevious() {
        if currentTime > 3 { seekTo(0); return }
        guard let cur = currentTrack,
              let idx = playlist.firstIndex(where: { $0.id == cur.id }),
              idx > 0 else { return }
        play(playlist[idx - 1])
    }

    // MARK: - Library

    func rename(_ track: AudioTrack, to name: String) {
        guard let idx = library.firstIndex(where: { $0.id == track.id }) else { return }
        library[idx].displayName = name
        saveLibrary()
        if let pIdx = playlist.firstIndex(where: { $0.id == track.id }) {
            playlist[pIdx].displayName = name
            savePlaylist()
        }
        if currentTrack?.id == track.id { currentTrack?.displayName = name }
    }

    func deleteTrack(_ track: AudioTrack) {
        library.removeAll { $0.id == track.id }
        playlist.removeAll { $0.id == track.id }
        try? FileManager.default.removeItem(at: audioDir.appendingPathComponent(track.fileName))
        saveLibrary()
        savePlaylist()
        if currentTrack?.id == track.id { stop() }
    }

    func findTrack(nameContaining query: String) -> AudioTrack? {
        let q = query.lowercased()
        return library.first { $0.displayName.lowercased().contains(q) }
            ?? library.first { $0.fileName.lowercased().contains(q) }
    }

    // MARK: - Playlist

    func addToPlaylist(_ track: AudioTrack) {
        guard !playlist.contains(where: { $0.id == track.id }) else { return }
        playlist.append(track)
        savePlaylist()
    }

    func removeFromPlaylist(at offsets: IndexSet) {
        playlist.remove(atOffsets: offsets)
        savePlaylist()
    }

    func moveInPlaylist(from source: IndexSet, to destination: Int) {
        playlist.move(fromOffsets: source, toOffset: destination)
        savePlaylist()
    }

    // MARK: - Persistence

    private func loadLibrary() {
        guard let data = try? Data(contentsOf: libraryURL),
              let tracks = try? JSONDecoder().decode([AudioTrack].self, from: data) else { return }
        library = tracks
    }

    private func saveLibrary() {
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: libraryURL)
    }

    private func loadPlaylist() {
        guard let data = try? Data(contentsOf: playlistURL),
              let tracks = try? JSONDecoder().decode([AudioTrack].self, from: data) else { return }
        playlist = tracks
    }

    private func savePlaylist() {
        guard let data = try? JSONEncoder().encode(playlist) else { return }
        try? data.write(to: playlistURL)
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentTime = self?.player?.currentTime ?? 0
            }
        }
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    static func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

extension AudioPlayerService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
            self?.playNext()
        }
    }
}
