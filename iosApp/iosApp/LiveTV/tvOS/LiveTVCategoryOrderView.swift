#if os(tvOS)
import SwiftUI

struct LiveTVCategoryOrderView: View {
    @State private var categories: [LiveCategory]
    let onSave: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss

    init(categories: [LiveCategory], onSave: @escaping ([String]) -> Void) {
        _categories = State(initialValue: categories)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Rearrange Categories").font(.system(size: 42, weight: .bold))
                Text("Use the arrows to set your category order. New categories from your provider will appear below this list in their provider order.")
                    .font(.system(size: 21)).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(categories) { category in
                            categoryRow(category)
                        }
                    }.padding(.vertical, 8)
                }
                HStack(spacing: 16) {
                    Button("Save order") {
                        onSave(categories.map(\.id))
                        dismiss()
                    }.buttonStyle(.borderedProminent)
                    Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                }
            }
            .padding(60)
            .frame(maxWidth: 1080)
            .background(Color.siloBackground)
        }
    }

    private func categoryRow(_ category: LiveCategory) -> some View {
        let index = categories.firstIndex(where: { $0.id == category.id }) ?? 0
        return HStack(spacing: 17) {
            Text("\(index + 1)").font(.system(size: 19, weight: .bold))
                .foregroundStyle(.secondary).frame(width: 45)
            Text(category.name).font(.system(size: 23, weight: .semibold))
                .lineLimit(1)
            Spacer()
            Button { move(category.id, by: -1) } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0)
                .accessibilityLabel("Move \(category.name) up")
            Button { move(category.id, by: 1) } label: { Image(systemName: "arrow.down") }
                .disabled(index == categories.count - 1)
                .accessibilityLabel("Move \(category.name) down")
        }
        .padding(.horizontal, 22).frame(height: 76)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private func move(_ id: String, by delta: Int) {
        guard let index = categories.firstIndex(where: { $0.id == id }),
              categories.indices.contains(index + delta) else { return }
        categories.swapAt(index, index + delta)
    }
}
#endif
