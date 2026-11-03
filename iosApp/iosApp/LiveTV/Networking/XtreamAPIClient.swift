import Foundation

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}

private extension KeyedDecodingContainer where Key == AnyCodingKey {
    func string(_ key: String) -> String? {
        guard let codingKey = AnyCodingKey(stringValue: key) else { return nil }
        if let value = try? decodeIfPresent(String.self, forKey: codingKey) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: codingKey) { return String(value) }
        return nil
    }
    func int(_ key: String) -> Int? { string(key).flatMap(Int.init) }
}

private struct XtreamAuthEnvelope: Decodable {
    let account: XtreamAccount
    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: AnyCodingKey.self)
        let infoKey = AnyCodingKey(stringValue: "user_info")!
        let info = try root.nestedContainer(keyedBy: AnyCodingKey.self, forKey: infoKey)
        let formatsKey = AnyCodingKey(stringValue: "allowed_output_formats")!
        let formats = (try? info.decodeIfPresent([String].self, forKey: formatsKey)) ?? []
        let expiry = info.string("exp_date").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        account = XtreamAccount(
            username: info.string("username"), status: info.string("status"), expiryDate: expiry,
            isTrial: info.int("is_trial") == 1, activeConnections: info.int("active_cons"),
            maximumConnections: info.int("max_connections"), allowedOutputFormats: formats
        )
    }
}

private struct XtreamCategoryDTO: Decodable {
    let categoryID: String
    let categoryName: String
    let parentID: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        categoryID = c.string("category_id") ?? UUID().uuidString
        categoryName = c.string("category_name") ?? "Other"
        parentID = c.string("parent_id")
    }
}

private struct XtreamChannelDTO: Decodable {
    let channel: LiveChannel
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let id = c.int("stream_id") else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing stream_id")) }
        let added = c.string("added").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        channel = LiveChannel(id: id, name: c.string("name") ?? "Channel \(id)", number: c.int("num"),
            categoryID: c.string("category_id"), logoURL: c.string("stream_icon").flatMap(URL.init(string:)),
            epgChannelID: c.string("epg_channel_id") ?? c.string("tvg_id"), addedAt: added,
            containerExtension: c.string("container_extension"))
    }
}

private struct XtreamShortEPGEnvelope: Decodable {
    let epgListings: [XtreamEPGDTO]
    enum CodingKeys: String, CodingKey { case epgListings = "epg_listings" }
}
private struct XtreamEPGDTO: Decodable {
    let id: String?
    let epgID: String?
    let title: String?
    let description: String?
    let startTimestamp: String?
    let stopTimestamp: String?
    enum CodingKeys: String, CodingKey { case id; case epgID = "epg_id"; case title; case description; case startTimestamp = "start_timestamp"; case stopTimestamp = "stop_timestamp" }
}

actor XtreamAPIClient {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 45
            configuration.waitsForConnectivity = false
            configuration.httpAdditionalHeaders = ["User-Agent": "Silo-tvOS"]
            self.session = URLSession(configuration: configuration)
        }
    }

    func authenticate(provider: IPTVProvider, credentials: IPTVCredentials) async throws -> XtreamAccount {
        let data = try await request(provider: provider, credentials: credentials, action: nil)
        let account: XtreamAccount
        do { account = try decoder.decode(XtreamAuthEnvelope.self, from: data).account }
        catch { throw IPTVError.invalidCredentials }
        guard account.isActive else {
            if account.expiryDate.map({ $0 < Date() }) == true { throw IPTVError.accountExpired }
            throw IPTVError.invalidCredentials
        }
        return account
    }

    func categories(provider: IPTVProvider, credentials: IPTVCredentials) async throws -> [LiveCategory] {
        let data = try await request(provider: provider, credentials: credentials, action: "get_live_categories")
        do { return try decoder.decode([XtreamCategoryDTO].self, from: data).map { .init(id: $0.categoryID, name: $0.categoryName, parentID: $0.parentID) } }
        catch { throw IPTVError.malformedResponse }
    }

    func channels(provider: IPTVProvider, credentials: IPTVCredentials) async throws -> [LiveChannel] {
        let data = try await request(provider: provider, credentials: credentials, action: "get_live_streams")
        do { return try decoder.decode([XtreamChannelDTO].self, from: data).map(\.channel) }
        catch { throw IPTVError.malformedResponse }
    }

    func shortEPG(provider: IPTVProvider, credentials: IPTVCredentials, channelID: Int, limit: Int = 12) async throws -> [EPGProgramme] {
        try await epg(provider: provider, credentials: credentials, channelID: channelID, action: "get_short_epg", extra: ["limit": String(limit)])
    }

    func simpleDataTable(provider: IPTVProvider, credentials: IPTVCredentials, channelID: Int) async throws -> [EPGProgramme] {
        try await epg(provider: provider, credentials: credentials, channelID: channelID, action: "get_simple_data_table")
    }

    private func epg(provider: IPTVProvider, credentials: IPTVCredentials, channelID: Int, action: String, extra: [String: String] = [:]) async throws -> [EPGProgramme] {
        var query = extra; query["stream_id"] = String(channelID)
        let data = try await request(provider: provider, credentials: credentials, action: action, extra: query)
        let rows: [XtreamEPGDTO]
        do { rows = try decoder.decode(XtreamShortEPGEnvelope.self, from: data).epgListings }
        catch { throw IPTVError.malformedResponse }
        return rows.compactMap { row in
            guard let start = row.startTimestamp.flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:)),
                  let end = row.stopTimestamp.flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:)), end > start else { return nil }
            return EPGProgramme(id: row.id ?? "\(channelID)-\(Int(start.timeIntervalSince1970))", channelID: String(channelID),
                title: Self.decodeBase64(row.title) ?? "Programme", subtitle: nil,
                description: Self.decodeBase64(row.description), start: start, end: end)
        }
    }

    func streamURL(provider: IPTVProvider, credentials: IPTVCredentials, channel: LiveChannel) throws -> URL {
        let ext = channel.containerExtension?.lowercased() == "m3u8" ? "m3u8" : provider.outputFormat.rawValue
        return try authenticatedURL(provider: provider, credentials: credentials, path: "live/\(credentials.username)/\(credentials.password)/\(channel.id).\(ext)")
    }

    func xmlTVURL(provider: IPTVProvider, credentials: IPTVCredentials) throws -> URL {
        try endpoint(provider: provider, path: "xmltv.php", query: ["username": credentials.username, "password": credentials.password])
    }

    func xmlTVProgrammes(provider: IPTVProvider, credentials: IPTVCredentials) async throws -> [EPGProgramme] {
        let url = try xmlTVURL(provider: provider, credentials: credentials)
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  data.count <= 150 * 1024 * 1024 else { throw IPTVError.serverUnavailable }
            return try await Task.detached(priority: .utility) { try XMLTVParser().parse(data: data) }.value
        } catch is CancellationError { throw CancellationError() }
        catch let error as IPTVError { throw error }
        catch { throw IPTVError.malformedResponse }
    }

    private func request(provider: IPTVProvider, credentials: IPTVCredentials, action: String?, extra: [String: String] = [:]) async throws -> Data {
        var query = ["username": credentials.username, "password": credentials.password]
        if let action { query["action"] = action }
        query.merge(extra) { _, new in new }
        let url = try endpoint(provider: provider, path: "player_api.php", query: query)
        var lastError: Error = IPTVError.serverUnavailable
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else { throw IPTVError.serverUnavailable }
                if [429, 502, 503, 504].contains(http.statusCode) { throw IPTVError.serverUnavailable }
                guard (200...299).contains(http.statusCode) else { throw IPTVError.serverUnavailable }
                guard data.count <= 50 * 1024 * 1024 else { throw IPTVError.malformedResponse }
                return data
            } catch is CancellationError { throw CancellationError() }
            catch let error as URLError where error.code == .timedOut { lastError = IPTVError.timedOut }
            catch { lastError = error }
            guard attempt < 2 else { break }
            try await Task.sleep(for: .milliseconds(350 * (1 << attempt)))
        }
        if let error = lastError as? IPTVError { throw error }
        throw IPTVError.serverUnavailable
    }

    private func endpoint(provider: IPTVProvider, path: String, query: [String: String]) throws -> URL {
        let base = provider.serverURL.appendingPathComponent(path)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw IPTVError.invalidServerURL }
        components.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw IPTVError.invalidServerURL }
        return url
    }

    private func authenticatedURL(provider: IPTVProvider, credentials: IPTVCredentials, path: String) throws -> URL {
        path.split(separator: "/").reduce(provider.serverURL) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    private static func decodeBase64(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if let data = Data(base64Encoded: value), let decoded = String(data: data, encoding: .utf8), !decoded.isEmpty { return decoded }
        return value
    }
}
