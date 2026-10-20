import Foundation

let old = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.path
let installed = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
let domain = "com.apple.dock" as CFString
CFPreferencesAppSynchronize(domain)
guard let entries = CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]] else {
    fatalError("Could not read existing Dock entries. No entries were changed.")
}
var result: [[String: Any]] = []
var replaced = false
for var entry in entries {
    var data = entry["tile-data"] as? [String: Any] ?? [:]
    let file = data["file-data"] as? [String: Any] ?? [:]
    let path = (file["_CFURLString"] as? String).flatMap { URL(string: $0)?.standardizedFileURL.path }
    if data["bundle-identifier"] as? String == "app.personal.docklet" || path == old || path == installed.path {
        guard !replaced else { continue }
        data["file-data"] = ["_CFURLString": installed.absoluteString, "_CFURLStringType": 15]
        // A bookmark for the previous build can silently restore its old URL.
        data.removeValue(forKey: "book")
        data.removeValue(forKey: "file-mod-date")
        data.removeValue(forKey: "parent-mod-date")
        data["file-label"] = "Docklet"
        data["bundle-identifier"] = "app.personal.docklet"
        entry["tile-data"] = data
        replaced = true
    }
    result.append(entry)
}
if !NSArray(array: result).isEqual(to: entries) {
    let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Docklet/Dock Backups")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
        .write(to: folder.appendingPathComponent("install-\(UUID().uuidString).plist"), options: .atomic)
    CFPreferencesSetAppValue("persistent-apps" as CFString, result as CFArray, domain)
    guard CFPreferencesAppSynchronize(domain) else {
        CFPreferencesSetAppValue("persistent-apps" as CFString, entries as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
        fatalError("Could not update Docklet's existing Dock entry. The previous entries were restored.")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = ["Dock"]
    try process.run()
    process.waitUntilExit()
}
print("Other native Dock entries preserved; Docklet points to its installed copy.")
