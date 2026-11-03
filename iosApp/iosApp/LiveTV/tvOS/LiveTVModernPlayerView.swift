#if os(tvOS)
import AetherEngine
import SwiftUI

struct LiveTVModernPlayerView: View {
    let channel: LiveChannel
    let store: LiveTVStore
    let dismiss: () -> Void
    @State private var coordinator: LiveTVPlaybackCoordinator?
    @State private var controlsVisible = true
    @State private var showChannels = false
    @State private var showTracks = false
    @State private var hideTask: Task<Void, Never>?

    private var currentChannel: LiveChannel { coordinator?.channel ?? channel }
    private var programme: EPGProgramme? { store.currentProgramme(for: currentChannel) }
    private var nextProgramme: EPGProgramme? {
        store.programmesForChannel(currentChannel).first { $0.start > Date() }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let coordinator {
                AetherPlayerSurface(engine: coordinator.engine).ignoresSafeArea()
            }
            LinearGradient(colors: [.black.opacity(0.66), .clear, .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)

            if let coordinator, coordinator.isLoading {
                ProgressView("Tuning \(currentChannel.name)…")
                    .font(.title3).padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }

            if controlsVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if showChannels { channelDrawer }
                    if showTracks { trackDrawer }
                    transportBar
                }
                .padding(.horizontal, 75).padding(.top, 42).padding(.bottom, 48)
                .transition(.opacity)
            }

            if let message = coordinator?.errorMessage {
                VStack(spacing: 20) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 44))
                    Text("Channel unavailable").font(.title.bold())
                    Text(message).foregroundStyle(.secondary)
                    HStack {
                        Button("Retry") { coordinator?.tune(to: currentChannel, store: store); revealControls() }
                        Button("Channels") { showChannels = true; revealControls() }
                    }.buttonStyle(.borderedProminent)
                }
                .padding(40).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            }
        }
        .onAppear {
            do {
                let player = try LiveTVPlaybackCoordinator()
                coordinator = player
                player.tune(to: channel, store: store)
                store.loadEPG(for: channel)
                revealControls()
            } catch {
                dismiss()
            }
        }
        .onDisappear { hideTask?.cancel(); coordinator?.stop() }
        .onPlayPauseCommand { coordinator?.togglePause(); revealControls() }
        .onMoveCommand { direction in
            if !controlsVisible { revealControls(); return }
            guard !showChannels && !showTracks else { return }
            if direction == .up || direction == .down { switchChannel(direction == .up ? -1 : 1) }
            else { revealControls() }
        }
        .onExitCommand {
            if showChannels { showChannels = false }
            else if showTracks { showTracks = false }
            else { dismiss() }
        }
    }

    private var topBar: some View {
        HStack(spacing: 22) {
            Button(action: dismiss) { Image(systemName: "chevron.left").font(.title2.bold()) }
                .buttonStyle(PlayerCircleStyle())
            AsyncImage(url: currentChannel.logoURL) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "tv") }
                .frame(width: 65, height: 55)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 14) {
                    Text(programme?.title ?? currentChannel.name).font(.system(size: 30, weight: .bold)).lineLimit(1)
                    Text("LIVE").font(.system(size: 16, weight: .heavy)).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(red: 0.9, green: 0.25, blue: 0.35), in: RoundedRectangle(cornerRadius: 6))
                }
                Text(currentChannel.name + (currentChannel.number.map { " · Ch \($0)" } ?? ""))
                    .font(.system(size: 20)).foregroundStyle(.white.opacity(0.73))
            }
            Spacer()
            Button { showChannels.toggle(); showTracks = false; revealControls() } label: { Image(systemName: "list.bullet.rectangle") }
                .buttonStyle(PlayerCircleStyle()).accessibilityLabel("Channel list")
            Button { showTracks.toggle(); showChannels = false; revealControls() } label: { Image(systemName: "captions.bubble") }
                .buttonStyle(PlayerCircleStyle()).accessibilityLabel("Audio and subtitles")
        }
    }

    private var transportBar: some View {
        VStack(spacing: 17) {
            HStack(spacing: 20) {
                Button { switchChannel(-1) } label: { Label("Previous channel", systemImage: "chevron.up") }
                Button { coordinator?.togglePause(); revealControls() } label: {
                    Label(coordinator?.isPaused == true ? "Play" : "Pause", systemImage: coordinator?.isPaused == true ? "play.fill" : "pause.fill")
                }
                Button { switchChannel(1) } label: { Label("Next channel", systemImage: "chevron.down") }
            }.buttonStyle(LiveTVChipStyle(isSelected: false))

            TimelineView(.periodic(from: .now, by: 30)) { context in
                let progress: Double = programme.map { min(1, max(0, context.date.timeIntervalSince($0.start) / max(1, $0.duration))) } ?? 0
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.3))
                        Capsule().fill(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * progress)
                    }
                }.frame(height: 8)
            }
            HStack {
                if let programme {
                    Text(programme.start.formatted(date: .omitted, time: .shortened) + "–" + programme.end.formatted(date: .omitted, time: .shortened))
                } else { Text("Live programme information unavailable") }
                Spacer()
                if let nextProgramme {
                    Text("Next: \(nextProgramme.title) · \(nextProgramme.start.formatted(date: .omitted, time: .shortened))")
                }
            }.font(.system(size: 18)).foregroundStyle(.white.opacity(0.72))
        }
    }

    private var channelDrawer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Channels").font(.title2.bold())
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.channels) { item in
                        Button {
                            coordinator?.tune(to: item, store: store)
                            store.loadEPG(for: item)
                            showChannels = false
                            revealControls()
                        } label: {
                            HStack {
                                Text(item.number.map(String.init) ?? "").frame(width: 55, alignment: .leading)
                                Text(item.name).lineLimit(1)
                                Spacer()
                                Text(store.currentProgramme(for: item)?.title ?? "").foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.buttonStyle(TVSettingsPaneRowStyle())
                        .task { store.loadEPG(for: item) }
                    }
                }
            }.frame(height: 340)
        }.padding(24).frame(maxWidth: 800)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var trackDrawer: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Audio & Subtitles").font(.title2.bold())
            if let coordinator {
                if coordinator.engine.audioTracks.isEmpty { Text("Audio tracks will appear when the stream provides them.").foregroundStyle(.secondary) }
                ForEach(coordinator.engine.audioTracks, id: \.id) { track in
                    Button(track.name.isEmpty ? "Audio \(track.id)" : track.name) {
                        coordinator.playback.selectAudioTrack(id: track.id); revealControls()
                    }.buttonStyle(TVSettingsPaneRowStyle())
                }
                Button("Subtitles Off") { coordinator.playback.selectSubtitleTrack(id: nil); revealControls() }
                    .buttonStyle(TVSettingsPaneRowStyle())
                ForEach(coordinator.engine.subtitleTracks, id: \.id) { track in
                    Button(track.name.isEmpty ? "Subtitles \(track.id)" : track.name) {
                        coordinator.playback.selectSubtitleTrack(id: track.id); revealControls()
                    }.buttonStyle(TVSettingsPaneRowStyle())
                }
            }
        }.padding(24).frame(maxWidth: 650)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func switchChannel(_ delta: Int) {
        guard let index = store.channels.firstIndex(where: { $0.id == currentChannel.id }) else { return }
        let target = min(max(0, index + delta), store.channels.count - 1)
        guard target != index else { return }
        let next = store.channels[target]
        coordinator?.tune(to: next, store: store)
        store.loadEPG(for: next)
        revealControls()
    }

    private func revealControls() {
        controlsVisible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled, !showChannels, !showTracks else { return }
            controlsVisible = false
        }
    }
}

private struct PlayerCircleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(width: 70, height: 70)
            .background(.white.opacity(0.17), in: Circle())
    }
}
#endif
