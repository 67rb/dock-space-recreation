import AppKit
import Combine
import UniformTypeIdentifiers

struct AppShortcut: Codable, Identifiable, Equatable {
    let path: String
    let name: String

    var id: String { path }
}

@MainActor
final class AppShortcutStore: ObservableObject {
    @Published private(set) var shortcuts: [AppShortcut]

    static let maximumShortcuts = 12
    private let storageKey = "docklet.shortcuts.v1"
    private let defaults = [
        AppShortcut(path: "/System/Library/CoreServices/Finder.app", name: "Finder"),
        AppShortcut(path: "/Applications/Safari.app", name: "Safari")
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([AppShortcut].self, from: data) {
            shortcuts = Array(saved.prefix(Self.maximumShortcuts))
        } else {
            shortcuts = defaults
        }
    }

    func addApp() {
        guard shortcuts.count < Self.maximumShortcuts else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an app for Docklet"
        panel.prompt = "Add App"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !shortcuts.contains(where: { $0.path == url.path }) else { return }

        let bundle = Bundle(url: url)
        let appName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        shortcuts.append(AppShortcut(path: url.path, name: appName))
        persist()
    }

    func remove(_ shortcut: AppShortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
        if shortcuts.isEmpty { shortcuts = defaults.prefix(1).map { $0 } }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
