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

    func refresh() async {
        isWorking = true; statusMessage = nil
        defer { isWorking = false }
        await LiveTVStore.shared.refresh()
        account = LiveTVStore.shared.account
        switch LiveTVStore.shared.phase {
        case .ready: statusMessage = "Channels and guide refreshed"
        case .failed(let message): statusMessage = message
        default: statusMessage = "Refresh could not be completed"
        }
    }
    func clearCache() async {
        do { try await cache.clear(); statusMessage = "IPTV cache cleared" }
        catch { statusMessage = "Could not clear the IPTV cache" }
    }
    func remove() {
        try? credentials.remove(); Task { try? await cache.clear() }
        IPTVPreferencesStore.shared.clearProviderData(); LiveTVStore.shared.reset()
        server = ""; username = ""; password = ""; account = nil; statusMessage = "IPTV provider removed"
    }
}

struct TVIPTVSettingsPane: View {
    @State private var model = IPTVSettingsModel()
    @State private var showingRemoveConfirmation = false
    let detailFocus: FocusState<TVSettingsDetailFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let provider = IPTVPreferencesStore.shared.provider {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 35)).frame(width: 68, height: 68)
                            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 17))
                        VStack(alignment: .leading) {
                            Text(provider.name).font(.system(size: 29, weight: .bold))
                            Text(provider.serverURL.host ?? "IPTV provider")
                                .font(.system(size: 19)).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Label((model.account ?? LiveTVStore.shared.account)?.isActive == true ? "Connected" : "Configured", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    Text("Your Xtream account is stored securely on this Apple TV.")
                        .font(.system(size: 17)).foregroundStyle(.white.opacity(0.72))
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color(red: 0.55, green: 0.23, blue: 0.67), Color(red: 0.18, green: 0.17, blue: 0.33)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))

                if let account = model.account ?? LiveTVStore.shared.account {
                    HStack(spacing: 16) {
                        settingsMetric("SUBSCRIPTION", account.status?.capitalized ?? "Unknown", icon: "checkmark.seal")
                        settingsMetric("EXPIRES", account.expiryDate?.formatted(date: .abbreviated, time: .omitted) ?? "Not provided", icon: "calendar")
                        settingsMetric("CONNECTIONS", account.maximumConnections.map(String.init) ?? "Not provided", icon: "network")
                    }
                }
                Text("MANAGE PROVIDER").font(.system(size: 17, weight: .bold)).foregroundStyle(.secondary).padding(.leading, 8)
                Button { model.showsEditor = true } label: { Label("Edit connection", systemImage: "pencil.line") }
                    .buttonStyle(TVSettingsPaneRowStyle()).focused(detailFocus, equals: .iptvEdit)
                Button { Task { await model.refresh() } } label: { Label(model.isWorking ? "Refreshing…" : "Refresh channels and guide", systemImage: "arrow.clockwise") }
                    .disabled(model.isWorking).buttonStyle(TVSettingsPaneRowStyle()).focused(detailFocus, equals: .iptvRefresh)
                Button { Task { await model.clearCache() } } label: { Label("Clear downloaded guide data", systemImage: "trash.slash") }
                    .buttonStyle(TVSettingsPaneRowStyle()).focused(detailFocus, equals: .iptvClearCache)
                Button { showingRemoveConfirmation = true } label: { Label("Remove provider", systemImage: "minus.circle") }
                    .buttonStyle(TVSettingsPaneRowStyle(isDestructive: true)).focused(detailFocus, equals: .iptvRemove)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "tv.and.hifispeaker.fill").font(.system(size: 54))
                    Text("Bring your channels to Silo").font(.system(size: 33, weight: .bold))
                    Text("Connect an Xtream Codes provider to browse live channels and a full programme guide. Your credentials stay in the Apple TV Keychain.")
                        .font(.system(size: 20)).foregroundStyle(.white.opacity(0.72))
                }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [Color(red: 0.55, green: 0.23, blue: 0.67), Color(red: 0.15, green: 0.19, blue: 0.31)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
                Button { model.showsEditor = true } label: { Label("Connect IPTV provider", systemImage: "plus.circle.fill") }
                    .buttonStyle(TVSettingsPaneRowStyle()).focused(detailFocus, equals: .iptvEdit)
            }
            if let message = model.statusMessage {
                Text(message).font(.system(size: 18)).foregroundStyle(message == "Connected" || message.contains("refreshed") ? Color.siloSuccess : Color.siloSecondaryText).padding(.horizontal, 8)
            }
        }
        .sheet(isPresented: $model.showsEditor) { IPTVProviderEditor(model: model) }
        .confirmationDialog("Remove IPTV provider?", isPresented: $showingRemoveConfirmation) {
            Button("Remove provider", role: .destructive) { model.remove() }
        } message: { Text("This removes the saved credentials, favourites and recent channel history from this Apple TV.") }
    }

    private func settingsMetric(_ title: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.55))
            Text(value).font(.system(size: 22, weight: .semibold)).lineLimit(1)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct IPTVProviderEditor: View {
    @Bindable var model: IPTVSettingsModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect your IPTV provider").font(.system(size: 40, weight: .bold))
                        Text("Enter the Xtream Codes details supplied by your provider. Silo tests the connection before saving.")
                            .font(.system(size: 21)).foregroundStyle(.secondary)
                    }.padding(.bottom, 12)
                    labelledField("PROVIDER NAME") { TextField("Provider name", text: $model.providerName) }
                    labelledField("SERVER ADDRESS") { TextField("http://provider.example:8080", text: $model.server).textContentType(.URL).textInputAutocapitalization(.never) }
                    labelledField("USERNAME") { TextField("Username", text: $model.username).textInputAutocapitalization(.never) }
                    labelledField("PASSWORD") { SecureField("Password", text: $model.password) }
                    labelledField("STREAM FORMAT") {
                        Picker("Preferred format", selection: $model.outputFormat) {
                            Text("MPEG-TS").tag(IPTVOutputFormat.mpegTS)
                            Text("HLS").tag(IPTVOutputFormat.hls)
                        }.pickerStyle(.segmented)
                    }
                    if let message = model.statusMessage { Text(message).foregroundStyle(Color.siloSecondaryText) }
                    HStack(spacing: 15) {
                        Button(model.isWorking ? "Testing connection…" : "Test connection & save") { Task { await model.testAndSave() } }
                            .disabled(model.isWorking || model.server.isEmpty || model.username.isEmpty || model.password.isEmpty)
                            .buttonStyle(.borderedProminent)
                        Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(.bordered)
                    }.padding(.top, 8)
                }
                .padding(65).frame(maxWidth: 1050)
            }
            .background(Color.siloBackground)
            .navigationTitle("IPTV Provider")
        }
    }

    private func labelledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(.secondary)
            content()
        }
    }
}
#endif
