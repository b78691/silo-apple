import Foundation
import Observation

struct IPTVCredentialStore: Sendable {
    private static let account = "iptv.xtream.credentials.v1"
    private let keychain: SharedKeychain

    init(keychain: SharedKeychain = SharedKeychain(service: "org.siloserver.silo.iptv", audience: .userIndependent)) {
        self.keychain = keychain
    }

    func load() throws -> IPTVCredentials? {
        guard let value = try keychain.getChecked(Self.account), let data = value.data(using: .utf8) else { return nil }
        do { return try JSONDecoder().decode(IPTVCredentials.self, from: data) }
        catch { throw IPTVError.keychainFailure }
    }

    func save(_ credentials: IPTVCredentials) throws {
        guard !credentials.username.isEmpty, !credentials.password.isEmpty else { throw IPTVError.credentialsMissing }
        let data = try JSONEncoder().encode(credentials)
        guard let value = String(data: data, encoding: .utf8), keychain.set(value, for: Self.account) else {
            throw IPTVError.keychainFailure
        }
    }

    func remove() throws {
        guard keychain.delete(Self.account) else { throw IPTVError.keychainFailure }
    }
}

@MainActor @Observable
final class IPTVPreferencesStore {
    static let shared = IPTVPreferencesStore()
    private let defaults: UserDefaults
    private let providerKey = "iptv.provider.v1"
    private let favoritesKey = "iptv.favorites.v1"
    private let recentKey = "iptv.recent.v1"
    private let categoryOrderKey = "iptv.categoryOrder.v1"
    private(set) var provider: IPTVProvider?
    private(set) var favoriteChannelIDs: Set<Int> = []
    private(set) var recentChannelIDs: [Int] = []
    private(set) var orderedCategoryIDs: [String] = []

    private struct CategoryOrderRecord: Codable {
        let providerID: UUID
        let ids: [String]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = defaults.data(forKey: providerKey).flatMap { try? JSONDecoder().decode(IPTVProvider.self, from: $0) }
        favoriteChannelIDs = Set(defaults.array(forKey: favoritesKey) as? [Int] ?? [])
        recentChannelIDs = defaults.array(forKey: recentKey) as? [Int] ?? []
        if let provider,
           let data = defaults.data(forKey: categoryOrderKey),
           let record = try? JSONDecoder().decode(CategoryOrderRecord.self, from: data),
           record.providerID == provider.id {
            orderedCategoryIDs = record.ids
        }
    }

    var isConfigured: Bool { provider != nil }

    func setProvider(_ provider: IPTVProvider?) {
        if self.provider?.id != provider?.id {
            orderedCategoryIDs = []
            defaults.removeObject(forKey: categoryOrderKey)
        }
        self.provider = provider
        if let provider, let data = try? JSONEncoder().encode(provider) { defaults.set(data, forKey: providerKey) }
        else { defaults.removeObject(forKey: providerKey) }
    }

    func toggleFavorite(_ channelID: Int) {
        if !favoriteChannelIDs.insert(channelID).inserted { favoriteChannelIDs.remove(channelID) }
        defaults.set(Array(favoriteChannelIDs).sorted(), forKey: favoritesKey)
    }

    func recordRecent(_ channelID: Int) {
        recentChannelIDs.removeAll { $0 == channelID }
        recentChannelIDs.insert(channelID, at: 0)
        recentChannelIDs = Array(recentChannelIDs.prefix(40))
        defaults.set(recentChannelIDs, forKey: recentKey)
    }

    func orderedCategories(_ categories: [LiveCategory]) -> [LiveCategory] {
        guard !orderedCategoryIDs.isEmpty else { return categories }
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let saved = orderedCategoryIDs.compactMap { byID[$0] }
        let savedIDs = Set(orderedCategoryIDs)
        return saved + categories.filter { !savedIDs.contains($0.id) }
    }

    func saveCategoryOrder(_ ids: [String]) {
        guard let provider else { return }
        var seen = Set<String>()
        orderedCategoryIDs = ids.filter { seen.insert($0).inserted }
        let record = CategoryOrderRecord(providerID: provider.id, ids: orderedCategoryIDs)
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: categoryOrderKey) }
    }

    func clearProviderData() {
        setProvider(nil)
        favoriteChannelIDs = []
        recentChannelIDs = []
        orderedCategoryIDs = []
        defaults.removeObject(forKey: favoritesKey)
        defaults.removeObject(forKey: recentKey)
        defaults.removeObject(forKey: categoryOrderKey)
    }
}

actor IPTVCache {
    static let shared = IPTVCache()
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL { self.fileURL = fileURL }
        else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.fileURL = base.appendingPathComponent("LiveTV", isDirectory: true).appendingPathComponent("snapshot.json")
        }
    }

    func load(providerID: UUID, maximumAge: TimeInterval = 24 * 60 * 60) -> IPTVSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(IPTVSnapshot.self, from: data),
              snapshot.providerID == providerID,
              Date().timeIntervalSince(snapshot.savedAt) <= maximumAge else { return nil }
        return snapshot
    }

    func save(_ snapshot: IPTVSnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
    }
}
