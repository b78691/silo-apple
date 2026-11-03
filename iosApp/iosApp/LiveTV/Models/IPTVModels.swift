import Foundation

struct IPTVProvider: Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var serverURL: URL
    var outputFormat: IPTVOutputFormat

    init(id: UUID = UUID(), name: String = "Live TV", serverURL: URL, outputFormat: IPTVOutputFormat = .mpegTS) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Live TV" : name
        self.serverURL = serverURL
        self.outputFormat = outputFormat
    }

    static func normalizedServerURL(_ input: String) throws -> URL {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw IPTVError.invalidServerURL }
        if !value.contains("://") { value = "http://" + value }
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host != nil else { throw IPTVError.invalidServerURL }
        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = trimmedPath.isEmpty ? "" : "/" + trimmedPath
        guard let url = components.url else { throw IPTVError.invalidServerURL }
        return url
    }
}

enum IPTVOutputFormat: String, Codable, CaseIterable, Sendable {
    case mpegTS = "ts"
    case hls = "m3u8"
}

struct IPTVCredentials: Codable, Equatable, Sendable {
    var username: String
    var password: String
}

struct XtreamAccount: Codable, Equatable, Sendable {
    var username: String?
    var status: String?
    var expiryDate: Date?
    var isTrial: Bool
    var activeConnections: Int?
    var maximumConnections: Int?
    var allowedOutputFormats: [String]

    var isActive: Bool { status?.lowercased() == "active" }
}

struct LiveCategory: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let parentID: String?
}

struct LiveChannel: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let number: Int?
    let categoryID: String?
    let logoURL: URL?
    let epgChannelID: String?
    let addedAt: Date?
    let containerExtension: String?

    var searchableName: String { name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
}

struct EPGProgramme: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let channelID: String
    let title: String
    let subtitle: String?
    let description: String?
    let start: Date
    let end: Date

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    func isAiring(at date: Date = Date()) -> Bool { start <= date && date < end }
}

struct IPTVSnapshot: Codable, Sendable {
    let providerID: UUID
    let savedAt: Date
    let account: XtreamAccount?
    let categories: [LiveCategory]
    let channels: [LiveChannel]
    let programmes: [String: [EPGProgramme]]
}

enum IPTVError: LocalizedError, Equatable {
    case invalidServerURL
    case credentialsMissing
    case invalidCredentials
    case accountExpired
    case serverUnavailable
    case timedOut
    case malformedResponse
    case unsupportedStream
    case keychainFailure
    case providerMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: "Enter a valid IPTV server address."
        case .credentialsMissing: "Enter an IPTV username and password."
        case .invalidCredentials: "The IPTV provider rejected these credentials."
        case .accountExpired: "This IPTV subscription has expired."
        case .serverUnavailable: "The IPTV provider could not be reached."
        case .timedOut: "The IPTV provider took too long to respond."
        case .malformedResponse: "The IPTV provider returned data Silo could not read."
        case .unsupportedStream: "This channel uses an unsupported stream format."
        case .keychainFailure: "Silo could not securely save the IPTV credentials."
        case .providerMessage(let message): message
        }
    }
}
