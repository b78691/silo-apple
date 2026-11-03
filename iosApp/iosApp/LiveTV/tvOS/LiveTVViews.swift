#if os(tvOS)
import AetherEngine
import SwiftUI

private enum LiveTVSection: String, CaseIterable, Identifiable {
    case channels = "All Channels", categories = "Categories", favorites = "Favourites", recent = "Recently Watched", guide = "Guide"
    var id: Self { self }
}

struct LiveTVRootView: View {
    @State private var store = LiveTVStore.shared
    @State private var preferences = IPTVPreferencesStore.shared
    @State private var section: LiveTVSection = .channels
    @State private var playingChannel: LiveChannel?
    let focusRequest: Int
    let isTopMenuFocused: Bool
    let onTopMenuFocusRequest: () -> Void

    var body: some View {
        ZStack { Color.siloBackground.ignoresSafeArea(); content }
            .padding(.top, 118).padding(.horizontal, 72)
            .task { await store.bootstrap() }
            .fullScreenCover(item: $playingChannel) { channel in
                LiveTVPlayerView(channel: channel, store: store) { playingChannel = nil }
            }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .unconfigured:
            VStack(spacing: 24) {
                Image(systemName: "tv").font(.system(size: 72))
                Text("Set up Live TV").font(.largeTitle.bold())
                Text("Open Settings › IPTV to connect an Xtream provider.").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).tvPageFocusOwner(focusRequest: focusRequest, isTopMenuFocused: isTopMenuFocused, accessibilityLabel: "Set up Live TV", onMoveUp: onTopMenuFocusRequest)
        case .loading:
            LoadingView().tvPageFocusOwner(focusRequest: focusRequest, isTopMenuFocused: isTopMenuFocused, accessibilityLabel: "Loading Live TV", onMoveUp: onTopMenuFocusRequest)
        case .failed(let message):
            VStack(spacing: 24) { Text("Live TV is unavailable").font(.largeTitle.bold()); Text(message); Button("Try Again") { Task { await store.refresh() } } }
        case .ready:
            VStack(alignment: .leading, spacing: 24) {
                HStack { Text("Live TV").font(.system(size: 52, weight: .bold)); Spacer(); TextField("Search channels", text: $store.query).frame(width: 430) }
                Picker("Section", selection: $section) { ForEach(LiveTVSection.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                sectionContent
            }
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .channels: ChannelGrid(channels: store.filteredChannels, store: store, play: { playingChannel = $0 })
        case .favorites: ChannelGrid(channels: store.favoriteChannels, store: store, play: { playingChannel = $0 })
        case .recent: ChannelGrid(channels: store.recentChannels, store: store, play: { playingChannel = $0 })
        case .categories:
            ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 24)], spacing: 24) {
                ForEach(store.categories) { category in Button(category.name) { store.selectedCategoryID = category.id; section = .channels }.buttonStyle(.borderedProminent) }
            }.padding(24) }
        case .guide: EPGGuideView(store: store, play: { playingChannel = $0 })
        }
    }
}

private struct ChannelGrid: View {
    let channels: [LiveChannel]
    let store: LiveTVStore
    let play: (LiveChannel) -> Void
    var body: some View {
        ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 26)], spacing: 26) {
            ForEach(channels) { channel in
                Button { play(channel) } label: {
                    HStack(spacing: 18) {
                        AsyncImage(url: channel.logoURL) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "tv").font(.title) }
                            .frame(width: 76, height: 58)
                        VStack(alignment: .leading, spacing: 5) { Text(channel.name).font(.headline).lineLimit(1); Text(store.currentProgramme(for: channel)?.title ?? "Programme information unavailable").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                    }.padding(18).frame(height: 98).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }.contextMenu { Button(IPTVPreferencesStore.shared.favoriteChannelIDs.contains(channel.id) ? "Remove from Favourites" : "Add to Favourites") { store.toggleFavorite(channel) } }
                .task { store.loadEPG(for: channel) }
            }
        }.padding(24) }
    }
}

private struct EPGGuideView: View {
    let store: LiveTVStore
    let play: (LiveChannel) -> Void
    @State private var anchor = Date().addingTimeInterval(-30 * 60)
    private let pointsPerMinute: CGFloat = 5
    var body: some View {
        VStack(spacing: 12) {
            HStack { Button("Now") { anchor = Date().addingTimeInterval(-30 * 60) }; Text(anchor.formatted(date: .abbreviated, time: .shortened)); Spacer() }
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(store.filteredChannels) { channel in
                            HStack(spacing: 8) {
                                Button { play(channel) } label: { Text(channel.name).lineLimit(1).frame(width: 260, alignment: .leading) }
                                ForEach(store.programmesForChannel(channel).filter { $0.end > anchor && $0.start < anchor.addingTimeInterval(6 * 3600) }) { programme in
                                    Button { if programme.isAiring() { play(channel) } } label: {
                                        VStack(alignment: .leading) { Text(programme.title).font(.headline).lineLimit(1); Text("\(programme.start.formatted(date: .omitted, time: .shortened))–\(programme.end.formatted(date: .omitted, time: .shortened))").font(.caption) }
                                        .frame(width: max(160, CGFloat(programme.duration / 60) * pointsPerMinute), height: 82, alignment: .leading)
                                    }
                                }
                                if store.programmesForChannel(channel).isEmpty { Text("Programme information unavailable").frame(width: 420, height: 82).foregroundStyle(.secondary).task { store.loadEPG(for: channel) } }
                            }
                        }
                    }
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let minutes = context.date.timeIntervalSince(anchor) / 60
                        Rectangle().fill(Color.red).frame(width: 3).offset(x: 268 + CGFloat(minutes) * pointsPerMinute).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

private struct LiveTVPlayerView: View {
    let channel: LiveChannel
    let store: LiveTVStore
    let dismiss: () -> Void
    @State private var coordinator: LiveTVPlaybackCoordinator?
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?

    private var displayedChannel: LiveChannel { coordinator?.channel ?? channel }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let coordinator { AetherPlayerSurface(engine: coordinator.engine).ignoresSafeArea() }
            else { ProgressView() }
            if controlsVisible {
                VStack { Spacer(); HStack(spacing: 22) {
                    AsyncImage(url: displayedChannel.logoURL) { $0.resizable().scaledToFit() } placeholder: { Image(systemName: "tv") }.frame(width: 90, height: 70)
                    VStack(alignment: .leading) { Text(displayedChannel.name).font(.title.bold()); Text(store.currentProgramme(for: displayedChannel)?.title ?? "Live").font(.headline); if let next = store.programmesForChannel(displayedChannel).first(where: { $0.start > Date() }) { Text("Next: \(next.title)").foregroundStyle(.secondary) } }
                    Spacer(); Button("Channels") { dismiss() }; Button("Close") { dismiss() }
                }.padding(40).background(.ultraThinMaterial) }
            }
            if let message = coordinator?.errorMessage { VStack { Text(message); Button("Retry") { coordinator?.tune(to: channel, store: store) } }.padding(32).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) }
        }
        .onAppear { do { let value = try LiveTVPlaybackCoordinator(); coordinator = value; value.tune(to: channel, store: store); scheduleHide() } catch { } }
        .onDisappear { hideTask?.cancel(); coordinator?.stop() }
        .onPlayPauseCommand { controlsVisible.toggle(); if controlsVisible { scheduleHide() } }
        .onMoveCommand { direction in
            guard direction == .up || direction == .down, let current = coordinator?.channel,
                  let index = store.channels.firstIndex(where: { $0.id == current.id }) else { return }
            let next = direction == .up ? max(0, index - 1) : min(store.channels.count - 1, index + 1)
            guard next != index else { return }
            coordinator?.tune(to: store.channels[next], store: store); controlsVisible = true; scheduleHide()
        }
        .onExitCommand { dismiss() }
    }

    private func scheduleHide() { hideTask?.cancel(); hideTask = Task { try? await Task.sleep(for: .seconds(6)); guard !Task.isCancelled else { return }; controlsVisible = false } }
}
#endif
