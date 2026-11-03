#if os(tvOS)
import AetherEngine
import Combine
import Foundation
import Observation

@MainActor @Observable
final class LiveTVPlaybackCoordinator {
    let playback: AetherPlaybackController
    var engine: AetherEngine { playback.engine }
    private(set) var channel: LiveChannel?
    private(set) var state: PlaybackState = .idle
    private(set) var errorMessage: String?
    private var loadTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init() throws {
        playback = try AetherPlaybackController()
        let engine = playback.engine
        engine.$state.receive(on: DispatchQueue.main).sink { [weak self] in self?.state = $0 }.store(in: &cancellables)
    }

    var isLoading: Bool { state == .loading || state == .seeking }

    func tune(to channel: LiveChannel, store: LiveTVStore) {
        loadTask?.cancel()
        self.channel = channel
        errorMessage = nil
        store.recordWatched(channel)
        loadTask = Task {
            do {
                let url = try await store.streamURL(for: channel)
                guard !Task.isCancelled else { return }
                let isHLS = url.pathExtension.lowercased() == "m3u8"
                let spec = try AetherLoadSpec(liveURL: url, usesNativeHLS: isHLS)
                let epoch = playback.beginLoad(spec)
                try await playback.finishLoad(epoch)
                guard !Task.isCancelled else { playback.stop(); return }
                playback.play()
            } catch is CancellationError { }
            catch let error as IPTVError { errorMessage = error.errorDescription }
            catch { errorMessage = "This channel could not be played. Try again or choose another channel." }
        }
    }

    func stop() { loadTask?.cancel(); loadTask = nil; playback.stop() }
    deinit { loadTask?.cancel() }
}
#endif
