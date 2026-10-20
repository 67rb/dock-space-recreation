import Combine
import Foundation

struct LayoutProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var widgets: [WidgetPlacement]
}

@MainActor
final class LayoutProfiles: ObservableObject {
    @Published private(set) var profiles: [LayoutProfile] = []
    @Published private(set) var removed: LayoutProfile?
    private let preferences: UserDefaults
    private let key = "docklet.layouts.v1"
    init(preferences: UserDefaults = DockletPreferences.shared) {
        self.preferences = preferences
        if let data = preferences.data(forKey: key), let saved = try? JSONDecoder().decode([LayoutProfile].self, from: data) {
            profiles = saved.map { .init(id: $0.id, name: $0.name, widgets: Self.normalized($0.widgets)) }
        }
    }
    static func normalized(_ items: [WidgetPlacement]) -> [WidgetPlacement] {
        var seen = Set<DockWidget>()
        return items.filter { (1...5).contains($0.slots) && seen.insert($0.kind).inserted }
    }
    @discardableResult func save(name: String, widgets: [WidgetPlacement]) -> Bool {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty else { return false }
        // Saving a name again deliberately updates that profile.
        if let index = profiles.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            profiles[index].widgets = Self.normalized(widgets)
        } else {
            profiles.append(.init(name: name, widgets: Self.normalized(widgets)))
        }
        persist(); return true
    }
    func remove(_ profile: LayoutProfile) {
        removed = profile; profiles.removeAll { $0.id == profile.id }; persist()
    }
    func undoRemove() {
        guard let removed else { return }
        if !profiles.contains(where: { $0.id == removed.id }) { profiles.append(removed) }
        self.removed = nil; persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) { preferences.set(data, forKey: key) }
    }
}
