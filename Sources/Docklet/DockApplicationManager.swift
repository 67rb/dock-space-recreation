import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

// All widgets live in the same application and share its preferences.
enum DockletPreferences {
    static let shared: UserDefaults = {
        if Bundle.main.bundleIdentifier == "app.personal.docklet" { return .standard }
        return UserDefaults(suiteName: "app.personal.docklet") ?? .standard
    }()
}

enum DockWidget: String, CaseIterable, Identifiable, Codable {
    case stocks, timer, weather, music, calendar, reminders, clock, notes
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .stocks: return "chart.xyaxis.line"
        case .timer: return "timer"
        case .weather: return "cloud.sun.fill"
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .clock: return "clock.fill"
        case .notes: return "note.text"
        }
    }
    var summary: String {
        switch self {
        case .stocks: return "Your watchlist, price changes and charts from one day to one year."
        case .timer: return "Countdowns, focus sessions and a stopwatch with laps."
        case .weather: return "Current temperature in your Dock, with a four-day forecast on click."
        case .music: return "Current song and playback controls for Music or Spotify."
        case .calendar: return "Today's date and your upcoming events. Calendar access is optional."
        case .reminders: return "See pending tasks, add a reminder and mark tasks complete."
        case .clock: return "A live clock with the date and a choice of 12- or 24-hour time."
        case .notes: return "A private scratchpad that saves as you type. No account needed."
        }
    }
}

// Pure transformations let us verify that pinning preserves every unrelated Dock item.
enum DockEntries {
    static func url(of item: [String: Any]) -> URL? {
        guard let tile = item["tile-data"] as? [String: Any],
              let file = tile["file-data"] as? [String: Any],
              let value = file["_CFURLString"] as? String else { return nil }
        if value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        return URL(string: value)
    }
    static func contains(_ url: URL, in entries: [[String: Any]]) -> Bool {
        entries.contains { self.url(of: $0)?.standardizedFileURL.path == url.standardizedFileURL.path }
    }
    static func adding(_ url: URL, name: String, bundleID: String, to entries: [[String: Any]]) -> [[String: Any]] {
        guard !contains(url, in: entries) else { return entries }
        return entries + [[
            "tile-type": "file-tile",
            "tile-data": [
                "file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15],
                "file-label": name, "bundle-identifier": bundleID, "file-type": 41
            ]
        ]]
    }
    static func removing(_ url: URL, from entries: [[String: Any]]) -> [[String: Any]] {
        entries.filter { self.url(of: $0)?.standardizedFileURL.path != url.standardizedFileURL.path }
    }
}

struct InstalledApp: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String
    var id: String { url.path }
}

@MainActor
final class DockApplicationManager: ObservableObject {
    @Published private(set) var applications: [InstalledApp] = []
    @Published private(set) var message: String?
    @Published private(set) var isBusy = false
    @Published private(set) var isScanning = false
    private var pinnedAppPaths = Set<String>()
    private var picker: NSOpenPanel?
    private var observer: AnyCancellable?

    init() {
        refreshPinned()
        observer = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshPinned() }
    }
    private func readEntries() throws -> [[String: Any]] {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        guard let entries = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] else {
            throw NSError(domain: "Docklet", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not read your existing Dock items. No Dock changes were made."])
        }
        return entries
    }
    func refreshPinned() {
        guard let entries = try? readEntries() else { return }
        pinnedAppPaths = Set(entries.compactMap { DockEntries.url(of: $0)?.standardizedFileURL.path })
    }
    func isPinned(_ url: URL) -> Bool { pinnedAppPaths.contains(url.standardizedFileURL.path) }

    private func writeEntries(_ entries: [[String: Any]], original: [[String: Any]]) throws {
        let backupDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Docklet/Dock Backups")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let backup = try PropertyListSerialization.data(fromPropertyList: original, format: .xml, options: 0)
        try backup.write(to: backupDir.appendingPathComponent("\(UUID().uuidString).plist"), options: .atomic)
        CFPreferencesSetAppValue("persistent-apps" as CFString, entries as CFArray, "com.apple.dock" as CFString)
        guard CFPreferencesAppSynchronize("com.apple.dock" as CFString) else {
            throw NSError(domain: "Docklet", code: 1, userInfo: [NSLocalizedDescriptionKey: "macOS could not save the Dock change."])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        refreshPinned()
    }
    func pinApplication(_ app: InstalledApp) {
        guard let bundle = Bundle(url: app.url), bundle.bundleIdentifier != nil else {
            message = "Choose an installed macOS application (.app)."
            return
        }
        do {
            let old = try readEntries()
            if !DockEntries.contains(app.url, in: old) {
                try writeEntries(DockEntries.adding(app.url, name: app.name, bundleID: app.bundleID, to: old), original: old)
            }
            message = "\(app.name) is in your macOS Dock."
            objectWillChange.send()
        } catch { message = error.localizedDescription }
    }
    func chooseApplication() {
        let panel = NSOpenPanel()
        picker = panel
        panel.title = "Add an application to your macOS Dock"
        panel.prompt = "Add to Dock"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            defer { self.picker = nil }
            guard response == .OK, let url = panel.url, let app = Self.app(at: url) else { return }
            self.pinApplication(app)
        }
    }
    nonisolated static func app(at url: URL) -> InstalledApp? {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        return InstalledApp(url: url, name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent, bundleID: id)
    }
    func scanApplications() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let found = await Task.detached { Self.findApplications() }.value
            applications = found
            isScanning = false
        }
    }
    nonisolated private static func findApplications() -> [InstalledApp] {
        let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var found: [InstalledApp] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if let app = Self.app(at: url) { found.append(app) }
            }
        }
        if let finder = Self.app(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")) { found.append(finder) }
        return Array(Set(found)).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

}
