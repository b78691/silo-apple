import XCTest
@testable import Silo

final class IPTVFoundationTests: XCTestCase {
    func testProviderURLNormalization() throws {
        XCTAssertEqual(try IPTVProvider.normalizedServerURL("example.com/").absoluteString, "http://example.com")
        XCTAssertEqual(try IPTVProvider.normalizedServerURL("https://example.com/iptv/?token=secret").absoluteString, "https://example.com/iptv")
        XCTAssertThrowsError(try IPTVProvider.normalizedServerURL("file:///tmp/provider"))
    }

    func testXMLTVParsesOffsetAndProgrammeDuration() throws {
        let xml = """
        <?xml version="1.0"?><tv><programme start="20261103190000 +0000" stop="20261103203000 +0000" channel="bbc.one"><title>Evening News</title><sub-title>Late edition</sub-title><desc>Headlines.</desc></programme></tv>
        """
        let rows = try XMLTVParser().parse(data: Data(xml.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].channelID, "bbc.one")
        XCTAssertEqual(rows[0].title, "Evening News")
        XCTAssertEqual(rows[0].duration, 5_400, accuracy: 0.1)
    }

    func testMalformedXMLTVTimesAreDiscarded() throws {
        let xml = "<tv><programme start=\"bad\" stop=\"also-bad\" channel=\"one\"><title>Broken</title></programme></tv>"
        XCTAssertTrue(try XMLTVParser().parse(data: Data(xml.utf8)).isEmpty)
    }

    @MainActor func testFavoritesAndRecentHistoryAreLocalAndBounded() {
        let suite = "IPTVFoundationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = IPTVPreferencesStore(defaults: defaults)
        store.toggleFavorite(7); XCTAssertEqual(store.favoriteChannelIDs, [7])
        store.toggleFavorite(7); XCTAssertTrue(store.favoriteChannelIDs.isEmpty)
        for id in 0..<50 { store.recordRecent(id) }
        XCTAssertEqual(store.recentChannelIDs.count, 40)
        XCTAssertEqual(store.recentChannelIDs.first, 49)
    }

    func testXtreamAuthenticationAndTolerantChannelMapping() async throws {
        let stub = StubURLProtocol.Handler()
        stub.route(StubURLProtocol.path("/player_api.php")) { request in
            switch request.query["action"] {
            case "get_live_streams":
                return .json(#"[{"stream_id":"42","num":7,"name":"News HD","category_id":"2","stream_icon":"https://img.example/news.png","epg_channel_id":"news.example"}]"#)
            default:
                return .json(#"{"user_info":{"username":"viewer","status":"Active","exp_date":"1793750400","is_trial":"0","active_cons":"1","max_connections":2,"allowed_output_formats":["ts","m3u8"]}}"#)
            }
        }
        let client = XtreamAPIClient(session: stub.makeSession())
        let provider = IPTVProvider(serverURL: URL(string: "https://iptv.example")!)
        let login = IPTVCredentials(username: "viewer", password: "secret")
        let account = try await client.authenticate(provider: provider, credentials: login)
        XCTAssertTrue(account.isActive)
        XCTAssertEqual(account.maximumConnections, 2)
        let channels = try await client.channels(provider: provider, credentials: login)
        XCTAssertEqual(channels.first?.id, 42)
        XCTAssertEqual(channels.first?.number, 7)
        XCTAssertEqual(channels.first?.epgChannelID, "news.example")
        XCTAssertEqual(stub.requests.first?.query["password"], "secret")
    }

    func testXtreamAuthenticationFailureIsExplicit() async throws {
        let stub = StubURLProtocol.Handler()
        stub.route(StubURLProtocol.any) { _ in .json(#"{"user_info":{"status":"Disabled"}}"#) }
        let client = XtreamAPIClient(session: stub.makeSession())
        do {
            _ = try await client.authenticate(provider: IPTVProvider(serverURL: URL(string: "https://iptv.example")!), credentials: .init(username: "bad", password: "bad"))
            XCTFail("Expected authentication failure")
        } catch {
            XCTAssertEqual(error as? IPTVError, .invalidCredentials)
        }
    }

    @MainActor func testLiveLoadSpecEnablesAetherLiveMode() throws {
        let spec = try AetherLoadSpec(liveURL: URL(string: "https://iptv.example/live/user/redacted/42.m3u8")!, usesNativeHLS: true)
        XCTAssertTrue(spec.options.isLive)
        XCTAssertTrue(spec.options.nativeRemoteHLS)
        XCTAssertEqual(spec.options.liveJoinProfile, .fastZap)
        XCTAssertFalse(spec.options.autoplay)
    }

    func testIPTVCacheRejectsExpiredAndWrongProviderSnapshots() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IPTVFoundationTests-\(UUID().uuidString)")
        let file = root.appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = IPTVCache(fileURL: file)
        let provider = UUID()
        try await cache.save(IPTVSnapshot(providerID: provider, savedAt: Date(timeIntervalSinceNow: -120), account: nil, categories: [], channels: [], programmes: [:]))
        XCTAssertNil(await cache.load(providerID: provider, maximumAge: 60))
        XCTAssertNil(await cache.load(providerID: UUID(), maximumAge: 300))
        XCTAssertNotNil(await cache.load(providerID: provider, maximumAge: 300))
    }

    func testLiveTVRootIsAddedWithoutChangingExistingRootOrder() {
        XCTAssertEqual(
            TVRootDestination.visibleRoots(libraries: [], showAudiobooks: false, showLiveTV: true),
            [.home, .liveTV, .recommendations, .calendar]
        )
    }
}
