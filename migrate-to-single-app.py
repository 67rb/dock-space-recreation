#!/usr/bin/env python3
"""Retire only the per-widget apps previously installed by this personal project."""
import datetime
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import time

kinds = ['stocks', 'timer', 'weather', 'music', 'calendar', 'reminders', 'clock']
for bundle_id in ['app.personal.docklet'] + ['app.personal.docklet.widget.' + kind for kind in kinds if (pathlib.Path.home() / 'Applications/Docklet Widgets' / ('Docklet ' + kind.title() + '.app')).exists()]:
    subprocess.run(['osascript', '-e', f'if application id "{bundle_id}" is running then tell application id "{bundle_id}" to quit'], check=True)

# Modify the pinned-app key only. Other Dock preferences are left in their domain.
source = r'''
import Foundation
let domain = "com.apple.dock" as CFString
CFPreferencesAppSynchronize(domain)
guard let old = CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]] else {
    fatalError("Could not read the Dock; no changes made.")
}
let ids = Set(["stocks", "timer", "weather", "music", "calendar", "reminders", "clock"].map { "app.personal.docklet.widget.\($0)" })
let current = old.filter { entry in
    let tile = entry["tile-data"] as? [String: Any] ?? [:]
    return !ids.contains(tile["bundle-identifier"] as? String ?? "")
}
if current.count != old.count {
    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Docklet/Dock Backups")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(fromPropertyList: old, format: .xml, options: 0)
    try data.write(to: directory.appendingPathComponent("retired-\(UUID().uuidString).plist"), options: .atomic)
    CFPreferencesSetAppValue("persistent-apps" as CFString, current as CFArray, domain)
    guard CFPreferencesAppSynchronize(domain) else {
        CFPreferencesSetAppValue("persistent-apps" as CFString, old as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
        fatalError("Could not save the Dock; previous items restored.")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = ["Dock"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
}
print("Removed \(old.count - current.count) old widget Dock entries; preserved \(current.count) other entries.")
'''
with tempfile.TemporaryDirectory(prefix='docklet-migration-') as temporary:
    path = pathlib.Path(temporary) / 'migrate.swift'
    path.write_text(source)
    subprocess.run(['swift', str(path)], check=True)

installed = pathlib.Path.home() / 'Applications/Docklet Widgets'
archive = pathlib.Path.home() / 'Library/Application Support/Docklet/Retired Widget Apps' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
for kind in kinds:
    path = installed / ('Docklet ' + kind.title() + '.app')
    if not path.exists(): continue
    with (path / 'Contents/Info.plist').open('rb') as f:
        info = plistlib.load(f)
    if info.get('CFBundleIdentifier') != 'app.personal.docklet.widget.' + kind: continue
    binary = str(path / 'Contents/MacOS/Docklet')
    for attempt in range(20):
        if subprocess.run(['pgrep', '-f', binary], capture_output=True).returncode != 0: break
        time.sleep(0.1)
    else: raise RuntimeError('Widget still running; left its app files untouched: ' + str(path))
    archive.mkdir(parents=True, exist_ok=True)
    shutil.move(str(path), str(archive / path.name))
    print('Archived:', path.name)
if installed.exists() and not any(installed.iterdir()): installed.rmdir()
