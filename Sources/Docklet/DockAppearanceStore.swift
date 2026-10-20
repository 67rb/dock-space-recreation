import AppKit
import Combine

@MainActor
final class DockAppearanceStore: ObservableObject {
    @Published var iconSize = 48.0
    @Published var magnification = false
    @Published var hoverSize = 96.0
    @Published private(set) var message: String?
    @Published private(set) var canUndo = false
    private var baselineSize = 48.0
    private var baselineMagnification = false
    private var baselineHover = 96.0
    private var undoValues: [String: Any] = [:]
    private var undoMissing = Set<String>()
    private let domain = "com.apple.dock" as CFString

    init() { reload() }
    var hasChanges: Bool {
        iconSize != baselineSize || magnification != baselineMagnification || hoverSize != baselineHover
    }
    func reload() {
        CFPreferencesAppSynchronize(domain)
        iconSize = min(128, max(16, (value("tilesize") as? NSNumber)?.doubleValue ?? 48))
        magnification = (value("magnification") as? NSNumber)?.boolValue ?? false
        hoverSize = min(128, max(16, (value("largesize") as? NSNumber)?.doubleValue ?? 96))
        baselineSize = iconSize
        baselineMagnification = magnification
        baselineHover = hoverSize
    }
    func preset(_ size: Double) { iconSize = size }
    private func value(_ key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, domain) }
    func apply() {
        guard hasChanges else { return }
        var changes: [String: Any] = [:]
        if iconSize != baselineSize { changes["tilesize"] = iconSize.rounded() }
        if magnification != baselineMagnification { changes["magnification"] = magnification }
        if hoverSize != baselineHover || (magnification && hoverSize < iconSize) {
            changes["largesize"] = max(hoverSize, iconSize).rounded()
        }
        CFPreferencesAppSynchronize(domain)
        var old: [String: Any] = [:]
        var missing = Set<String>()
        for key in changes.keys {
            if let previous = value(key) { old[key] = previous } else { missing.insert(key) }
        }
        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Docklet/Dock Backups")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: ["values": old, "missingKeys": Array(missing)], format: .xml, options: 0)
            try data.write(to: directory.appendingPathComponent("appearance-\(UUID().uuidString).plist"), options: .atomic)
            for (key, newValue) in changes { CFPreferencesSetAppValue(key as CFString, newValue as CFPropertyList, domain) }
            guard CFPreferencesAppSynchronize(domain) else {
                for key in changes.keys { CFPreferencesSetAppValue(key as CFString, old[key] as CFPropertyList?, domain) }
                CFPreferencesAppSynchronize(domain)
                throw NSError(domain: "Docklet", code: 10, userInfo: [NSLocalizedDescriptionKey: "macOS could not save the Dock size. The previous values were restored."])
            }
            undoValues = old
            undoMissing = missing
            canUndo = true
            try restartDock()
            reload()
            message = "Applied to the macOS Dock. macOS may reduce icon size to fit all your apps on screen."
        } catch { message = error.localizedDescription }
    }
    func undo() {
        guard canUndo else { return }
        for (key, old) in undoValues { CFPreferencesSetAppValue(key as CFString, old as CFPropertyList, domain) }
        for key in undoMissing { CFPreferencesSetAppValue(key as CFString, nil, domain) }
        guard CFPreferencesAppSynchronize(domain) else { message = "Could not restore the previous Dock size."; return }
        do {
            try restartDock()
            canUndo = false
            reload()
            message = "Restored the previous Dock appearance."
        } catch { message = error.localizedDescription }
    }
    private func restartDock() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }
}
