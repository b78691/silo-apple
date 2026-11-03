#if os(tvOS)
import Observation
import SwiftUI

private enum GuideStyle {
    static let rose = Color(red: 0.96, green: 0.32, blue: 0.49)
    static let violet = Color(red: 0.69, green: 0.23, blue: 0.83)
    static let tile = Color(red: 0.11, green: 0.12, blue: 0.17)
    static let minuteWidth: CGFloat = 4.3
    static let hours = 6
    static let rowHeight: CGFloat = 76
    static let channelWidth: CGFloat = 255
    static var timelineWidth: CGFloat { CGFloat(hours * 60) * minuteWidth }
}

private enum GuideFilter: Hashable {
    case all, favourites, recent, category(String)
}

struct LiveTVChipStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, isSelected: isSelected)
    }

    private struct ChipBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .font(.system(size: 22, weight: .semibold))
                .padding(.horizontal, 21).padding(.vertical, 12)
                .foregroundStyle(focused || isSelected ? Color.white : Color.white.opacity(0.7))
                .background(focused || isSelected ? AnyShapeStyle(LinearGradient(colors: [GuideStyle.rose, GuideStyle.violet], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(GuideStyle.tile), in: Capsule())
                .overlay(Capsule().strokeBorder(focused ? .white : .clear, lineWidth: 2))
                .scaleEffect(focused ? 1.045 : 1)
                .focusEffectDisabled()
                .animation(.easeOut(duration: 0.16), value: focused)
        }
    }
}

private struct GuideSidebarStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        SidebarButtonBody(configuration: configuration, isSelected: isSelected)
    }

    private struct SidebarButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .font(.system(size: 20, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 15).padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(focused || isSelected ? Color(red: 0.69, green: 0.23, blue: 0.75) : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(focused ? .white : .clear, lineWidth: 2))
                .focusEffectDisabled()
        }
    }
}

@MainActor @Observable
private final class GuideSelection {
    var channel: LiveChannel?
    var programme: EPGProgramme?
    func select(_ channel: LiveChannel?, _ programme: EPGProgramme?) {
        self.channel = channel
        self.programme = programme
    }
}

struct LiveTVGuideView: View {
    let store: LiveTVStore
    let play: (LiveChannel) -> Void
    @State private var selection = GuideSelection()
    @State private var anchor = LiveTVGuideView.rounded(Date()).addingTimeInterval(-1800)
    @State private var filter: GuideFilter = .all

    private var channels: [LiveChannel] {
        let matching = store.filteredChannels
        switch filter {
        case .all: return matching
        case .favourites:
            let ids = IPTVPreferencesStore.shared.favoriteChannelIDs
            return matching.filter { ids.contains($0.id) }
        case .recent:
            let byID = Dictionary(uniqueKeysWithValues: matching.map { ($0.id, $0) })
            return IPTVPreferencesStore.shared.recentChannelIDs.compactMap { byID[$0] }
        case .category(let id): return matching.filter { $0.categoryID == id }
        }
    }

    private var selectedChannel: LiveChannel? { selection.channel ?? channels.first }
    private var selectedProgramme: EPGProgramme? {
        if let programme = selection.programme { return programme }
        guard let selectedChannel else { return nil }
        return store.currentProgramme(for: selectedChannel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Live TV", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 43, weight: .bold))
                Spacer()
                TextField("Search channels", text: Binding(get: { store.query }, set: { store.query = $0 })).frame(width: 350)
            }
            HStack(alignment: .top, spacing: 24) {
                sidebar
                VStack(alignment: .leading, spacing: 15) {
                    hero
                    HStack(spacing: 16) {
                        Button { anchor = anchor.addingTimeInterval(-7200) } label: { Label("Earlier", systemImage: "chevron.left") }
                        Button("Now") { anchor = Self.rounded(Date()).addingTimeInterval(-1800) }
                        Button { anchor = anchor.addingTimeInterval(7200) } label: { Label("Later", systemImage: "chevron.right") }
                        Spacer()
                    }.buttonStyle(LiveTVChipStyle(isSelected: false))
                    guideGrid
                }
            }
        }
        .onChange(of: filter) { _, _ in selection.select(channels.first, nil) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("CHANNELS").font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 15)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    sidebarButton("All Channels", icon: "rectangle.grid.1x2", filter: .all)
                    sidebarButton("Favourites", icon: "heart", filter: .favourites)
                    sidebarButton("Recently Watched", icon: "clock.arrow.circlepath", filter: .recent)
                    Text("CATEGORIES").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 15).padding(.top, 21)
                    ForEach(store.categories) { category in
                        sidebarButton(category.name, icon: "square.stack", filter: .category(category.id))
                    }
                }
            }.scrollIndicators(.hidden)
        }
        .frame(width: 245).frame(maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 17)
        .background(GuideStyle.tile, in: RoundedRectangle(cornerRadius: 19))
        .focusSection()
    }

    private func sidebarButton(_ title: String, icon: String, filter item: GuideFilter) -> some View {
        Button {
            filter = item
        } label: {
            Label(title, systemImage: icon).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(GuideSidebarStyle(isSelected: filter == item))
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(selectedProgramme?.isAiring() == true ? "LIVE" : "GUIDE")
                        .font(.system(size: 17, weight: .bold)).padding(.horizontal, 12).padding(.vertical, 5)
                        .background(GuideStyle.rose, in: RoundedRectangle(cornerRadius: 5))
                    Text(selectedChannel.map { "\($0.name)\($0.number.map { " · Ch \($0)" } ?? "")" } ?? "Select a channel")
                        .font(.system(size: 20)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    if let programme = selectedProgramme {
                        Text(programme.start.formatted(date: .omitted, time: .shortened) + "–" + programme.end.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 19)).foregroundStyle(.white.opacity(0.65))
                    }
                }
                Text(selectedProgramme?.title ?? "Live TV Guide")
                    .font(.system(size: 50, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                Text(selectedProgramme?.description ?? selectedProgramme?.subtitle ?? "Browse channels and programmes with the Siri Remote.")
                    .font(.system(size: 21)).foregroundStyle(.white.opacity(0.74)).lineLimit(2)
                    .frame(maxWidth: 960, alignment: .leading)
                if let channel = selectedChannel {
                    HStack(spacing: 14) {
                        Button { play(channel) } label: { Label("Watch channel", systemImage: "play.fill") }
                            .buttonStyle(LiveTVChipStyle(isSelected: true))
                        Button { store.toggleFavorite(channel) } label: {
                            Label(IPTVPreferencesStore.shared.favoriteChannelIDs.contains(channel.id) ? "Favourited" : "Add favourite", systemImage: IPTVPreferencesStore.shared.favoriteChannelIDs.contains(channel.id) ? "heart.fill" : "heart")
                        }.buttonStyle(LiveTVChipStyle(isSelected: false))
                    }.padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            if let channel = selectedChannel {
                AsyncImage(url: channel.logoURL) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "tv").font(.system(size: 58)) }
                    .frame(width: 220, height: 150)
                    .background(LinearGradient(colors: [GuideStyle.rose.opacity(0.85), GuideStyle.violet.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
            }
        }
        .padding(25)
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .leading)
        .background(LinearGradient(colors: [GuideStyle.violet.opacity(0.26), GuideStyle.rose.opacity(0.08), GuideStyle.tile], startPoint: .topTrailing, endPoint: .bottomLeading), in: RoundedRectangle(cornerRadius: 24))
    }

    private var guideGrid: some View {
        Group {
        if channels.isEmpty {
            ContentUnavailableView("No channels in this section", systemImage: "tv", description: Text("Choose another category or change your search."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 8) {
                LazyVStack(spacing: 6) {
                    Text("CHANNELS").font(.system(size: 17, weight: .bold)).foregroundStyle(.white.opacity(0.55))
                        .frame(width: GuideStyle.channelWidth, height: 40, alignment: .leading)
                    ForEach(channels) { channel in
                        GuideChannelCell(channel: channel, store: store, selection: selection, play: play)
                    }
                }.frame(width: GuideStyle.channelWidth)
                ScrollView(.horizontal) {
                    VStack(spacing: 6) {
                        timeRuler
                        ZStack(alignment: .topLeading) {
                            LazyVStack(spacing: 6) {
                                ForEach(channels) { channel in
                                    GuideProgrammeRow(channel: channel, store: store, anchor: anchor, selection: selection, play: play)
                                }
                            }
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                let x = CGFloat(context.date.timeIntervalSince(anchor) / 60) * GuideStyle.minuteWidth
                                if x >= 0 && x <= GuideStyle.timelineWidth {
                                    Rectangle().fill(GuideStyle.rose).frame(width: 3)
                                        .frame(maxHeight: .infinity).offset(x: x)
                                        .allowsHitTesting(false).accessibilityHidden(true)
                                }
                            }
                        }.frame(width: GuideStyle.timelineWidth, height: CGFloat(channels.count) * (GuideStyle.rowHeight + 6), alignment: .topLeading)
                    }.frame(width: GuideStyle.timelineWidth)
                }.scrollIndicators(.hidden)
            }
        }
        .scrollIndicators(.hidden)
        .focusSection()
        }
        }
    }

    private var timeRuler: some View {
        ZStack(alignment: .leading) {
            ForEach(0...GuideStyle.hours * 2, id: \.self) { halfHour in
                Text(anchor.addingTimeInterval(TimeInterval(halfHour * 1800)).formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white.opacity(0.72))
                    .offset(x: CGFloat(halfHour * 30) * GuideStyle.minuteWidth)
            }
        }.frame(width: GuideStyle.timelineWidth, height: 40, alignment: .leading)
    }

    private static func rounded(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 1800) * 1800)
    }
}

private struct GuideChannelCell: View {
    let channel: LiveChannel
    let store: LiveTVStore
    let selection: GuideSelection
    let play: (LiveChannel) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button { play(channel) } label: {
            HStack(spacing: 11) {
                AsyncImage(url: channel.logoURL) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "tv").font(.title3) }
                    .frame(width: 52, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name).font(.system(size: 19, weight: .semibold)).lineLimit(1)
                    Text(channel.number.map(String.init) ?? "LIVE").font(.system(size: 15)).foregroundStyle(.white.opacity(0.56))
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).frame(width: GuideStyle.channelWidth, height: GuideStyle.rowHeight)
                .background(GuideStyle.tile, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(focused ? .white : .clear, lineWidth: 3))
        }
        .buttonStyle(.plain).focused($focused)
        .onChange(of: focused) { _, value in if value { selection.select(channel, store.currentProgramme(for: channel)) } }
        .contextMenu { Button(IPTVPreferencesStore.shared.favoriteChannelIDs.contains(channel.id) ? "Remove from Favourites" : "Add to Favourites") { store.toggleFavorite(channel) } }
        .task { store.loadEPG(for: channel) }
    }
}

private struct GuideProgrammeRow: View {
    let channel: LiveChannel
    let store: LiveTVStore
    let anchor: Date
    let selection: GuideSelection
    let play: (LiveChannel) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 13).fill(GuideStyle.tile)
            ForEach(store.programmesForChannel(channel).filter { $0.end > anchor && $0.start < anchor.addingTimeInterval(6 * 3600) }) { programme in
                let left = max(0, programme.start.timeIntervalSince(anchor))
                let right = min(6 * 3600, programme.end.timeIntervalSince(anchor))
                GuideProgrammeCell(channel: channel, programme: programme, selection: selection, play: play)
                    .frame(width: max(1, CGFloat((right - left) / 60) * GuideStyle.minuteWidth), height: GuideStyle.rowHeight)
                    .offset(x: CGFloat(left / 60) * GuideStyle.minuteWidth)
            }
            if store.programmesForChannel(channel).isEmpty {
                Text("Programme information loading or unavailable")
                    .font(.system(size: 18)).foregroundStyle(.white.opacity(0.48)).padding(.horizontal, 20)
            }
        }
        .frame(width: GuideStyle.timelineWidth, height: GuideStyle.rowHeight)
        .task { store.loadEPG(for: channel) }
    }
}

private struct GuideProgrammeCell: View {
    let channel: LiveChannel
    let programme: EPGProgramme
    let selection: GuideSelection
    let play: (LiveChannel) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button { selection.select(channel, programme); if programme.isAiring() { play(channel) } } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(programme.title).font(.system(size: 20, weight: .semibold)).lineLimit(1)
                Text(programme.start.formatted(date: .omitted, time: .shortened) + "–" + programme.end.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 16)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(.horizontal, 15)
                .background(LinearGradient(colors: [colour.opacity(0.9), colour.opacity(0.48)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(focused ? .white : .clear, lineWidth: 3))
        }
        .buttonStyle(.plain).focused($focused)
        .onChange(of: focused) { _, value in if value { selection.select(channel, programme) } }
        .accessibilityLabel("\(channel.name), \(programme.title), \(programme.start.formatted(date: .omitted, time: .shortened))")
    }

    private var colour: Color {
        switch abs(channel.id % 5) {
        case 0: GuideStyle.rose
        case 1: Color(red: 0.70, green: 0.31, blue: 0.79)
        case 2: Color(red: 0.13, green: 0.44, blue: 0.56)
        case 3: Color(red: 0.55, green: 0.32, blue: 0.73)
        default: Color(red: 0.12, green: 0.48, blue: 0.37)
        }
    }
}
#endif
