#if os(tvOS)
import SwiftUI

@MainActor @Observable
private final class IPTVSettingsModel {
    var server = ""
    var username = ""
    var password = ""
    var providerName = "Live TV"
    var outputFormat: IPTVOutputFormat = .mpegTS
    var statusMessage: String?
    var isWorking = false
    var account: XtreamAccount?
    var showsEditor = false

    private let api = XtreamAPIClient()
    private let credentials = IPTVCredentialStore()
    private let cache = IPTVCache.shared

    init() {
        if let provider = IPTVPreferencesStore.shared.provider {
            server = provider.serverURL.absoluteString
            providerName = provider.name
            outputFormat = provider.outputFormat
        }
        if let saved = try? credentials.load() { username = saved.username; password = saved.password }
    }

    func testAndSave() async {
        isWorking = true; statusMessage = nil
        defer { isWorking = false }
        do {
            let url = try IPTVProvider.normalizedServerURL(server)
            let provider = IPTVProvider(id: IPTVPreferencesStore.shared.provider?.id ?? UUID(), name: providerName, serverURL: url, outputFormat: outputFormat)
            let login = IPTVCredentials(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            let verified = try await api.authenticate(provider: provider, credentials: login)
            try credentials.save(login)
            IPTVPreferencesStore.shared.setProvider(provider)
            account = verified
            statusMessage = "Connected"
            showsEditor = false
            await LiveTVStore.shared.refresh()
        } catch { statusMessage = (error as? LocalizedError)?.errorDescription ?? "Connection failed." }
    }

    func refresh() async { await LiveTVStore.shared.refresh(); account = LiveTVStore.shared.account; statusMessage = "Live TV refreshed" }
    func clearCache() async { try? await cache.clear(); statusMessage = "IPTV cache cleared" }
    func remove() {
        try? credentials.remove(); Task { try? await cache.clear() }
        IPTVPreferencesStore.shared.clearProviderData(); LiveTVStore.shared.reset()
        server = ""; username = ""; password = ""; account = nil; statusMessage = "IPTV provider removed"
    }
}

struct TVIPTVSettingsPane: View {
    @State private var model = IPTVSettingsModel()
    let detailFocus: FocusState<TVSettingsDetailFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let provider = IPTVPreferencesStore.shared.provider {
                TVSettingsInfoRow(title: "Provider", value: provider.name)
                TVSettingsInfoRow(title: "Server", value: provider.serverURL.host ?? provider.serverURL.absoluteString)
                if let account = model.account ?? LiveTVStore.shared.account {
                    TVSettingsInfoRow(title: "Account", value: account.status ?? "Unknown")
                    if let expiry = account.expiryDate { TVSettingsInfoRow(title: "Subscription expires", value: expiry.formatted(date: .long, time: .omitted)) }
                }
                Button("Edit IPTV Provider") { model.showsEditor = true }.buttonStyle(TVSettingsPaneRowStyle()).focused($detailFocus, equals: .iptvEdit)
                Button(model.isWorking ? "Refreshing…" : "Refresh Channels and Guide") { Task { await model.refresh() } }.disabled(model.isWorking).buttonStyle(TVSettingsPaneRowStyle()).focused($detailFocus, equals: .iptvRefresh)
                Button("Clear IPTV Cache") { Task { await model.clearCache() } }.buttonStyle(TVSettingsPaneRowStyle()).focused($detailFocus, equals: .iptvClearCache)
                Button("Remove IPTV Provider") { model.remove() }.buttonStyle(TVSettingsPaneRowStyle(isDestructive: true)).focused($detailFocus, equals: .iptvRemove)
            } else {
                Text("Connect an Xtream Codes provider to add live channels and programme information. Credentials are stored in the Apple TV Keychain.").foregroundStyle(.secondary).padding(.horizontal, 24)
                Button("Add IPTV Provider") { model.showsEditor = true }.buttonStyle(TVSettingsPaneRowStyle()).focused($detailFocus, equals: .iptvEdit)
            }
            if let message = model.statusMessage { Text(message).foregroundStyle(message == "Connected" ? Color.siloSuccess : Color.siloSecondaryText).padding(.horizontal, 24) }
        }
        .sheet(isPresented: $model.showsEditor) { IPTVProviderEditor(model: model) }
    }
}

private struct IPTVProviderEditor: View {
    @Bindable var model: IPTVSettingsModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("Provider name", text: $model.providerName)
                TextField("Server URL", text: $model.server).textContentType(.URL).textInputAutocapitalization(.never)
                TextField("Username", text: $model.username).textInputAutocapitalization(.never)
                SecureField("Password", text: $model.password)
                Picker("Stream format", selection: $model.outputFormat) { Text("MPEG-TS").tag(IPTVOutputFormat.mpegTS); Text("HLS").tag(IPTVOutputFormat.hls) }
                if let message = model.statusMessage { Text(message) }
                Button(model.isWorking ? "Testing…" : "Test and Save") { Task { await model.testAndSave() } }.disabled(model.isWorking || model.server.isEmpty || model.username.isEmpty || model.password.isEmpty)
                Button("Cancel", role: .cancel) { dismiss() }
            }.navigationTitle("IPTV Provider")
        }
    }
}
#endif
