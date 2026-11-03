import Foundation
import Observation

@MainActor @Observable
final class LiveTVStore {
    static let shared = LiveTVStore()

    enum Phase: Equatable { case unconfigured, loading, ready, failed(String) }
    private(set) var phase: Phase = .unconfigured
    private(set) var refreshError: String?
    private(set) var account: XtreamAccount?
    private(set) var categories: [LiveCategory] = []
    private(set) var channels: [LiveChannel] = []
    private(set) var programmes: [String: [EPGProgramme]] = [:]
    var selectedCategoryID: String?
    var query = ""

    private let api: XtreamAPIClient
    private let credentials: IPTVCredentialStore
    private let cache: IPTVCache
    private var refreshTask: Task<Void, Never>?
    private var epgTasks: [Int: Task<Void, Never>] = [:]
    private var xmlTVTask: Task<Void, Never>?

    init(api: XtreamAPIClient = XtreamAPIClient(), credentials: IPTVCredentialStore = IPTVCredentialStore(), cache: IPTVCache = .shared) {
        self.api = api; self.credentials = credentials; self.cache = cache
        phase = IPTVPreferencesStore.shared.isConfigured ? .loading : .unconfigured
    }

    var filteredChannels: [LiveChannel] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return channels.filter { channel in
            (selectedCategoryID == nil || channel.categoryID == selectedCategoryID)
                && (needle.isEmpty || channel.searchableName.contains(needle))
        }
    }

    var favoriteChannels: [LiveChannel] {
        let ids = IPTVPreferencesStore.shared.favoriteChannelIDs
        return channels.filter { ids.contains($0.id) }
    }

    var recentChannels: [LiveChannel] {
        let byID = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
        return IPTVPreferencesStore.shared.recentChannelIDs.compactMap { byID[$0] }
    }

    func bootstrap() async {
        guard let provider = IPTVPreferencesStore.shared.provider else { phase = .unconfigured; return }
        if channels.isEmpty, let snapshot = await cache.load(providerID: provider.id) { apply(snapshot) }
        if channels.isEmpty { await refresh() }
        else { phase = .ready; Task { await refresh(silent: true) } }
    }

    func refresh(silent: Bool = false) async {
        refreshTask?.cancel()
        refreshError = nil
        guard let provider = IPTVPreferencesStore.shared.provider else { phase = .unconfigured; return }
        if !silent { phase = .loading }
        let task = Task { [api, credentials, cache] in
            do {
                guard let login = try credentials.load() else { throw IPTVError.credentialsMissing }
                async let account = api.authenticate(provider: provider, credentials: login)
                async let categories = api.categories(provider: provider, credentials: login)
                async let channels = api.channels(provider: provider, credentials: login)
                let result = try await (account, categories, channels)
                guard !Task.isCancelled else { return }
                let snapshot = IPTVSnapshot(providerID: provider.id, savedAt: Date(), account: result.0,
                    categories: result.1, channels: result.2, programmes: [:])
                try? await cache.save(snapshot)
                await MainActor.run { self.apply(snapshot) }
                await MainActor.run { self.loadXMLTV(provider: provider, credentials: login) }
            } catch is CancellationError { }
            catch {
                await MainActor.run {
                    let message = (error as? LocalizedError)?.errorDescription ?? "Live TV could not be refreshed."
                    self.refreshError = message
                    if !silent || self.channels.isEmpty { self.phase = .failed(message) }
                }
            }
        }
        refreshTask = task
        await task.value
    }

    func loadEPG(for channel: LiveChannel) {
        guard programmesForChannel(channel).isEmpty, epgTasks[channel.id] == nil,
              let provider = IPTVPreferencesStore.shared.provider else { return }
        epgTasks[channel.id] = Task { [api, credentials] in
            defer { Task { @MainActor in self.epgTasks[channel.id] = nil } }
            do {
                guard let login = try credentials.load() else { return }
                let rows: [EPGProgramme]
                do { rows = try await api.shortEPG(provider: provider, credentials: login, channelID: channel.id) }
                catch { rows = try await api.simpleDataTable(provider: provider, credentials: login, channelID: channel.id) }
                guard !Task.isCancelled else { return }
                let key = channel.epgChannelID ?? String(channel.id)
                await MainActor.run { self.programmes[key] = rows }
            } catch { }
        }
    }

    func programmesForChannel(_ channel: LiveChannel) -> [EPGProgramme] {
        programmes[channel.epgChannelID ?? String(channel.id)] ?? []
    }

    func currentProgramme(for channel: LiveChannel, at date: Date = Date()) -> EPGProgramme? {
        let rows = programmesForChannel(channel)
        var low = 0, high = rows.count
        while low < high { let mid = (low + high) / 2; if rows[mid].start <= date { low = mid + 1 } else { high = mid } }
        guard low > 0, rows[low - 1].isAiring(at: date) else { return nil }
        return rows[low - 1]
    }

    func toggleFavorite(_ channel: LiveChannel) { IPTVPreferencesStore.shared.toggleFavorite(channel.id) }
    func recordWatched(_ channel: LiveChannel) { IPTVPreferencesStore.shared.recordRecent(channel.id) }

    func streamURL(for channel: LiveChannel) async throws -> URL {
        guard let provider = IPTVPreferencesStore.shared.provider, let login = try credentials.load() else { throw IPTVError.credentialsMissing }
        return try await api.streamURL(provider: provider, credentials: login, channel: channel)
    }

    func reset() {
        refreshTask?.cancel(); xmlTVTask?.cancel(); epgTasks.values.forEach { $0.cancel() }; epgTasks = [:]
        account = nil; categories = []; channels = []; programmes = [:]; phase = .unconfigured
    }

    private func apply(_ snapshot: IPTVSnapshot) {
        account = snapshot.account
        categories = snapshot.categories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        channels = snapshot.channels.sorted { ($0.number ?? Int.max, $0.name) < ($1.number ?? Int.max, $1.name) }
        programmes = snapshot.programmes.mapValues { $0.sorted { $0.start < $1.start } }
        phase = .ready
    }

    private func loadXMLTV(provider: IPTVProvider, credentials login: IPTVCredentials) {
        xmlTVTask?.cancel()
        xmlTVTask = Task { [api, cache] in
            do {
                let rows = try await api.xmlTVProgrammes(provider: provider, credentials: login)
                guard !Task.isCancelled else { return }
                let grouped = Dictionary(grouping: rows, by: \.channelID).mapValues { $0.sorted { $0.start < $1.start } }
                await MainActor.run { self.programmes.merge(grouped) { _, new in new } }
                let snapshot = await MainActor.run { IPTVSnapshot(providerID: provider.id, savedAt: Date(), account: self.account, categories: self.categories, channels: self.channels, programmes: self.programmes) }
                try? await cache.save(snapshot)
            } catch { /* Short EPG remains available when XMLTV is unsupported. */ }
        }
    }
}
