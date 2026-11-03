#if os(tvOS)
import SwiftUI

struct LiveTVRootView: View {
    @State private var store = LiveTVStore.shared
    @State private var playingChannel: LiveChannel?
    let focusRequest: Int
    let isTopMenuFocused: Bool
    let onTopMenuFocusRequest: () -> Void

    var body: some View {
        ZStack {
            Color.siloBackground.ignoresSafeArea()
            content
        }
        .padding(.top, 118).padding(.horizontal, 72)
        .task { await store.bootstrap() }
        .fullScreenCover(item: $playingChannel) { channel in
            LiveTVModernPlayerView(channel: channel, store: store) { playingChannel = nil }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .unconfigured:
            VStack(spacing: 24) {
                Image(systemName: "tv").font(.system(size: 72))
                Text("Set up Live TV").font(.largeTitle.bold())
                Text("Open Settings › IPTV to connect an Xtream provider.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tvPageFocusOwner(focusRequest: focusRequest, isTopMenuFocused: isTopMenuFocused, accessibilityLabel: "Set up Live TV", onMoveUp: onTopMenuFocusRequest)
        case .loading:
            LoadingView()
                .tvPageFocusOwner(focusRequest: focusRequest, isTopMenuFocused: isTopMenuFocused, accessibilityLabel: "Loading Live TV", onMoveUp: onTopMenuFocusRequest)
        case .failed(let message):
            VStack(spacing: 24) {
                Text("Live TV is unavailable").font(.largeTitle.bold())
                Text(message)
                Button("Try Again") { Task { await store.refresh() } }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            LiveTVGuideView(store: store) { playingChannel = $0 }
        }
    }
}
#endif
