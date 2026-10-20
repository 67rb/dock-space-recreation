import AppKit
import ApplicationServices
import Combine
import SwiftUI

private final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DockIntegrationController: ObservableObject {
    @Published private(set) var placements: [WidgetPlacement]
    @Published private(set) var accessibilityAllowed = false
    @Published private(set) var status = "Setting up Dock integration…"
    @Published private(set) var isVisible = false
    @Published private(set) var visibleWidgets = Set<DockWidget>()
    @Published private(set) var enabled: Bool
    @Published private(set) var canUndoLayout = false
    @Published private(set) var liveIconSize: CGFloat = 32
    private var layoutHistory: [[WidgetPlacement]] = []
    private var timerStore: TimerStore?
    private var weatherStore: WeatherStore?
    private var musicStore: MusicStore?
    private var stockStore: StockStore?
    private let agenda = CalendarAccessStore()
    var calendarStore: CalendarAccessStore { agenda }
    private var panels: [String: WidgetPanel] = [:]
    private var panelFrames: [String: CGRect] = [:]
    private var popovers: [String: NSPopover] = [:]
    private var controls: [String: NSWindow] = [:]
    private var pulse: Timer?
    private var observer: NSObjectProtocol?
    private var inspectionInProgress = false
    private var reservedSignature = ""
    private var revision = 0
    private var ticks = 0
    private var lastDiagnostic = ""
    private var layoutReadyAt = Date.distantPast
    private var cleanedUnavailableAccess = false
    private let preferences = DockletPreferences.shared
    private let layoutKey = "docklet.integrated.layout.v1"
    private let idsKey = "docklet.integrated.spacerIDs.v1"
    private let countKey = "docklet.integrated.reservedCount.v2"

    init() {
        if let data = DockletPreferences.shared.data(forKey: "docklet.integrated.layout.v1"),
           let saved = try? JSONDecoder().decode([WidgetPlacement].self, from: data) {
            var seen = Set<DockWidget>()
            placements = saved.filter { (1...5).contains($0.slots) && seen.insert($0.kind).inserted }
        } else { placements = WidgetPlacement.defaults }
        enabled = DockletPreferences.shared.object(forKey: "docklet.integrated.enabled") as? Bool ?? true
    }
    func configure(timer: TimerStore, weather: WeatherStore, music: MusicStore, stocks: StockStore) {
        guard timerStore == nil else { return }
        timerStore = timer; weatherStore = weather; musicStore = music; stockStore = stocks
        pulse = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeReservedSpaces() }
        }
        preferences.set(AXIsProcessTrusted(), forKey: "docklet.integrated.accessibilityAvailable")
        tick()
    }
    func enableAccessibility() {
        setEnabled(true)
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if !AXIsProcessTrusted() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            status = "Turn on Docklet in System Settings → Privacy & Security → Accessibility. Widgets attach automatically when access is available."
        }
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        preferences.set(value, forKey: "docklet.integrated.enabled")
        revision += 1
        if !value { hidePanels(); removeReservedSpaces(); status = "Dock widgets are paused." }
        else { reservedSignature = ""; tick() }
    }
    func has(_ kind: DockWidget) -> Bool { placements.contains { $0.kind == kind } }
    func slots(_ kind: DockWidget) -> Int { placements.first { $0.kind == kind }?.slots ?? 1 }
    func addButtonTitle(_ kind: DockWidget) -> String {
        guard has(kind) else { return "Add to Dock" }
        if visibleWidgets.contains(kind) { return "In Dock" }
        if !enabled { return "Added · paused" }
        return accessibilityAllowed ? "Added · placing…" : "Added · needs access"
    }
    func add(_ kind: DockWidget) {
        guard !has(kind) else { return }
        rememberLayout()
        placements.append(.init(kind: kind, slots: kind == .music || kind == .stocks ? 3 : kind == .calendar ? 1 : 2))
        saveLayout()
        if !enabled { setEnabled(true) }
        if !AXIsProcessTrusted() { enableAccessibility() }
    }
    func remove(_ kind: DockWidget) {
        guard has(kind) else { return }
        rememberLayout(); placements.removeAll { $0.kind == kind }; saveLayout()
    }
    func setSlots(_ kind: DockWidget, _ count: Int) {
        guard let index = placements.firstIndex(where: { $0.kind == kind }) else { return }
        let width = min(5, max(1, count))
        guard placements[index].slots != width else { return }
        rememberLayout()
        placements[index].slots = width; saveLayout()
    }
    func move(_ kind: DockWidget, by amount: Int) {
        guard let index = placements.firstIndex(where: { $0.kind == kind }), placements.indices.contains(index + amount) else { return }
        rememberLayout()
        placements.swapAt(index, index + amount); saveLayout()
    }
    func replaceLayout(_ widgets: [WidgetPlacement]) {
        let normalized = LayoutProfiles.normalized(widgets)
        guard normalized != placements else { return }
        rememberLayout(); placements = normalized; saveLayout()
    }
    private func rememberLayout() {
        layoutHistory.append(placements)
        if layoutHistory.count > 20 { layoutHistory.removeFirst() }
        canUndoLayout = true
    }
    func undoLayout() {
        guard let previous = layoutHistory.popLast() else { return }
        placements = previous; canUndoLayout = !layoutHistory.isEmpty; saveLayout()
    }
    private func saveLayout() {
        if let data = try? JSONEncoder().encode(placements) { preferences.set(data, forKey: layoutKey) }
        revision += 1
        reservedSignature = ""
        layoutReadyAt = Date().addingTimeInterval(0.4)
        // Collapse consecutive UI changes into one Dock reload.
        let savedRevision = revision
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, self.revision == savedRevision else { return }
            self.tick()
        }
    }
    private func tick() {
        guard timerStore != nil else { return }
        ticks += 1
        if ticks % 34 == 0 { musicStore?.refresh() }
        if ticks % 400 == 0 { agenda.reload() }
        if ticks % 6000 == 0, let weatherStore { Task { await weatherStore.refresh() } }
        let trusted = AXIsProcessTrusted()
        if accessibilityAllowed != trusted { accessibilityAllowed = trusted; preferences.set(trusted, forKey: "docklet.integrated.accessibilityAvailable") }
        guard enabled else { return }
        guard accessibilityAllowed else {
            hidePanels()
            if !cleanedUnavailableAccess { removeReservedSpaces(); cleanedUnavailableAccess = true }
            let waiting = placements.isEmpty ? "Enable Accessibility to place widgets in your Dock." : "\(placements.count) \(placements.count == 1 ? "widget is" : "widgets are") ready. Enable Accessibility to show them in your Dock."
            if status != waiting { status = waiting }
            return
        }
        cleanedUnavailableAccess = false
        guard !placements.isEmpty else {
            hidePanels()
            if preferences.integer(forKey: countKey) > 0 || preferences.object(forKey: countKey) == nil { removeReservedSpaces() }
            if status != "Add a widget to get started." { status = "Add a widget to get started." }
            return
        }
        guard !inspectionInProgress, Date() >= layoutReadyAt else { return }
        let signature = placements.map { "\($0.id):\($0.slots)" }.joined(separator: ",")
        if signature != reservedSignature {
            do { try reserveSpaces(); reservedSignature = signature }
            catch { hidePanels(); status = error.localizedDescription; return }
        }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { hidePanels(); return }
        inspectionInProgress = true
        let pid = dock.processIdentifier
        let savedRevision = revision
        Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) { DockInspector.items(pid: pid) }.value
            guard let self else { return }
            self.inspectionInProgress = false
            guard self.enabled, self.revision == savedRevision, self.accessibilityAllowed else { return }
            self.positionPanels(items: snapshot)
        }
    }
    private func reserveSpaces() throws {
        let original = try readEntries()
        let count = placements.reduce(0) { $0 + $1.slots }
        var ids = (preferences.array(forKey: idsKey) as? [NSNumber] ?? []).map(\.uint32Value)
        let oldCount = preferences.object(forKey: countKey) as? Int ?? ids.count
        var used = Set(original.compactMap { ($0["GUID"] as? NSNumber)?.uint32Value })
        while ids.count < count - 1 {
            let candidate = UInt32.random(in: 0xE0000000...0xFFFFFFFE)
            guard used.insert(candidate).inserted else { continue }
            ids.append(candidate)
        }
        preferences.set(ids.map { NSNumber(value: $0) }, forKey: idsKey)
        let clean = DockSlotPlan.retiringHelpers(from: original)
        let result = DockSlotPlan.reserving(entries: clean, appURL: Bundle.main.bundleURL, slots: count, ids: ids, previousCount: oldCount)
        try writeEntries(result, original: original)
        preferences.set(max(0, count - 1), forKey: countKey)
    }
    private func removeReservedSpaces() {
        do {
            let old = try readEntries()
            let ids = Set((preferences.array(forKey: idsKey) as? [NSNumber] ?? []).map(\.uint32Value))
            let count = preferences.object(forKey: countKey) as? Int ?? ids.count
            try writeEntries(DockSlotPlan.removingSpaces(from: old, ids: ids, appURL: Bundle.main.bundleURL, reservedCount: count), original: old)
            preferences.set(0, forKey: countKey)
            reservedSignature = ""
        } catch { status = error.localizedDescription }
    }
    private func readEntries() throws -> [[String: Any]] {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        guard let value = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] else {
            throw NSError(domain: "Docklet", code: 20, userInfo: [NSLocalizedDescriptionKey: "Could not read existing Dock items. No Dock changes were made."])
        }
        return value
    }
    private func writeEntries(_ new: [[String: Any]], original: [[String: Any]]) throws {
        guard !NSArray(array: new).isEqual(to: original) else { return }
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Docklet/Dock Backups")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backup = try PropertyListSerialization.data(fromPropertyList: original, format: .xml, options: 0)
        try backup.write(to: directory.appendingPathComponent("integrated-\(UUID().uuidString).plist"), options: .atomic)
        CFPreferencesSetAppValue("persistent-apps" as CFString, new as CFArray, "com.apple.dock" as CFString)
        guard CFPreferencesAppSynchronize("com.apple.dock" as CFString) else {
            CFPreferencesSetAppValue("persistent-apps" as CFString, original as CFArray, "com.apple.dock" as CFString)
            CFPreferencesAppSynchronize("com.apple.dock" as CFString)
            throw NSError(domain: "Docklet", code: 21, userInfo: [NSLocalizedDescriptionKey: "macOS could not save Dock widget positions."])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
    }
    private func positionPanels(items: [DockItemGeometry]) {
        writeDiagnostic(items: items)
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String ?? "bottom"
        let vertical = orientation != "bottom"
        let count = placements.reduce(0) { $0 + $1.slots }
        guard let slots = DockGeometry.reservedFrames(items: items, appPath: Bundle.main.bundleURL.standardizedFileURL.path, count: count, vertical: vertical),
              let rects = DockGeometry.widgetFrames(slots: slots, placements: placements),
              let primary = NSScreen.screens.first else {
            hidePanels(); status = "Waiting for the Dock to appear. If spaces were moved, use Repair Placement."; return
        }
        let live = Set(placements.map(\.id))
        let iconSize = vertical ? slots[0].height : slots[0].width
        if abs(liveIconSize - iconSize) > 0.5 { liveIconSize = iconSize }
        for id in Array(panels.keys) where !live.contains(id) { panels[id]?.close(); panels.removeValue(forKey: id); panelFrames.removeValue(forKey: id); popovers[id]?.close(); popovers.removeValue(forKey: id) }
        var visible = Set<DockWidget>()
        for placement in placements {
            guard let axRect = rects[placement.id] else { continue }
            let measured = DockGeometry.cocoaRect(axRect, primaryTop: primary.frame.maxY)
            let slotLength = vertical ? slots[0].height : slots[0].width
            let rect = DockGeometry.iconRowRect(measured, slotLength: slotLength, orientation: orientation)
            guard NSScreen.screens.contains(where: { $0.frame.intersection(rect).height >= rect.height * 0.8 && $0.frame.intersection(rect).width >= rect.width * 0.8 }) else { panels[placement.id]?.orderOut(nil); continue }
            let panel = panels[placement.id] ?? makePanel(placement.kind)
            let view = DockIntegratedTile(kind: placement.kind, timer: timerStore!, stocks: stockStore!, weather: weatherStore!, music: musicStore!, agenda: agenda, onOpen: { [weak self] in self?.open(placement.kind) }, onResize: { [weak self] in self?.setSlots(placement.kind, $0) }, onRemove: { [weak self] in self?.remove(placement.kind) })
                .frame(width: rect.width, height: rect.height)
                .defaultAppStorage(preferences).preferredColorScheme(.dark)
            if panelFrames[placement.id] != rect || panel.contentView == nil {
                if let host = panel.contentView as? NSHostingView<AnyView> { host.rootView = AnyView(view) }
                else { panel.contentView = NSHostingView(rootView: AnyView(view)) }
                panel.setFrame(rect, display: true)
                panelFrames[placement.id] = rect
            }
            panel.orderFrontRegardless()
            visible.insert(placement.kind)
        }
        if visibleWidgets != visible { visibleWidgets = visible }
        let shown = visible.count
        if isVisible != (shown > 0) { isVisible = shown > 0 }
        let newStatus = shown > 0 ? "\(shown) widgets live in your Dock · one Docklet app" : "Dock widgets follow the Dock when it appears."
        if status != newStatus { status = newStatus }
    }
    private func writeDiagnostic(items: [DockItemGeometry]) {
        let content: [String: Any] = [
            "accessibility": accessibilityAllowed, "status": status,
            "appPath": Bundle.main.bundleURL.path,
            "placements": placements.map { ["kind": $0.kind.rawValue, "slots": $0.slots] },
            "items": items.map { ["title": $0.title, "url": $0.url ?? "", "subrole": $0.subrole,
                "x": $0.frame.minX, "y": $0.frame.minY, "width": $0.frame.width, "height": $0.frame.height] },
            "panels": panels.map { ["id": $0.key, "visible": $0.value.isVisible,
                "x": $0.value.frame.minX, "y": $0.value.frame.minY, "width": $0.value.frame.width, "height": $0.value.frame.height] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: content, options: [.prettyPrinted, .sortedKeys]),
              let signature = String(data: data, encoding: .utf8), signature != lastDiagnostic else { return }
        lastDiagnostic = signature
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Docklet")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent("dock-diagnostics.json"), options: .atomic)
        if CommandLine.arguments.contains("--diagnostics") {
            for (id, panel) in panels where panel.isVisible {
                guard let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: folder.appendingPathComponent("tile-\(id).png"), options: .atomic)
                }
            }
        }
    }
    private func makePanel(_ kind: DockWidget) -> WidgetPanel {
        let panel = WidgetPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Docklet \(kind.title)"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panels[kind.rawValue] = panel
        return panel
    }
    private func hidePanels() {
        panels.values.forEach { $0.orderOut(nil) }
        if isVisible { isVisible = false }
        if !visibleWidgets.isEmpty { visibleWidgets = [] }
    }
    func repair() { revision += 1; reservedSignature = ""; tick() }
    func handleURL(_ url: URL) {
        guard url.scheme == "docklet" else { return }
        if url.host == "diagnostics", CommandLine.arguments.contains("--diagnostics") {
            captureOwnViews()
            return
        }
        guard url.host == "widget" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, let kind = DockWidget(rawValue: parts[1]) else { return }
        switch parts[0] {
        case "add": add(kind)
        case "remove": remove(kind)
        case "size": if parts.count == 3, let size = Int(parts[2]), (1...5).contains(size) { setSlots(kind, size) }
        case "open": open(kind)
        default: break
        }
    }
    private func captureOwnViews() {
        guard let timerStore, let stockStore, let weatherStore, let musicStore else { return }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Docklet")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Render only this app's widget views. This does not capture the screen or other apps.
        for item in placements {
            let rect = CGRect(x: 0, y: 0, width: CGFloat(item.slots) * 80 + CGFloat(item.slots - 1) * 5, height: 80)
            let tile = DockIntegratedTile(kind: item.kind, timer: timerStore, stocks: stockStore, weather: weatherStore, music: musicStore, agenda: agenda, onOpen: {})
                .frame(width: rect.width, height: rect.height).defaultAppStorage(preferences).preferredColorScheme(.dark)
            let host = NSHostingView(rootView: tile)
            let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = host
            host.frame = rect
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: rect) else { continue }
            host.cacheDisplay(in: rect, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: folder.appendingPathComponent("preview-\(item.id).png"), options: .atomic)
            }
        }
    }
    func open(_ kind: DockWidget) {
        guard timerStore != nil else { return }
        let visibleHeight = panels[kind.rawValue]?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 700
        let popoverHeight = kind == .stocks
            ? StockPopover.preferredHeight(forVisibleHeight: visibleHeight)
            : min(560, max(250, visibleHeight * 0.62))
        let root: AnyView
        switch kind {
        case .music: root = AnyView(MusicPopover(store: musicStore!))
        case .timer: root = AnyView(TimerPopover(store: timerStore!))
        case .stocks: root = AnyView(StockPopover(store: stockStore!, maxHeight: popoverHeight))
        case .weather: root = AnyView(WeatherPopover(store: weatherStore!))
        case .calendar, .reminders: root = AnyView(AgendaView(store: agenda, remindersMode: kind == .reminders))
        case .clock: root = AnyView(ClockControls())
        case .notes: root = AnyView(NotesPopover())
        }
        let content = root
            .frame(width: kind == .stocks ? 320 : 360, height: kind == .stocks ? popoverHeight : nil)
            .defaultAppStorage(preferences).preferredColorScheme(.dark)
        if let panel = panels[kind.rawValue], panel.isVisible, let anchor = panel.contentView {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: content)
            popovers[kind.rawValue]?.close()
            popovers[kind.rawValue] = popover
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
            if let popoverWindow = popover.contentViewController?.view.window {
                // Docklet's tiles sit at status-bar level; keep their controls above them.
                popoverWindow.level = .popUpMenu
                popoverWindow.orderFrontRegardless()
                popoverWindow.makeKey()
            }
        } else {
            let window = controls[kind.rawValue] ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: kind == .stocks ? 320 : 360, height: kind == .stocks ? popoverHeight : 480), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = kind.title
            window.isReleasedWhenClosed = false
            if kind == .stocks { window.setContentSize(NSSize(width: 320, height: popoverHeight)) }
            window.contentView = NSHostingView(rootView: content)
            controls[kind.rawValue] = window
            window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        }
    }
}

private enum DockInspector {
    static func items(pid: pid_t) -> [DockItemGeometry] {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.15)
        func attribute(_ item: AXUIElement, _ key: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, key as CFString, &value) == .success else { return nil }
            return value
        }
        var output: [DockItemGeometry] = []
        func visit(_ item: AXUIElement, depth: Int) {
            guard depth <= 5, output.count < 256 else { return }
            let role = attribute(item, kAXRoleAttribute) as? String ?? ""
            let subrole = attribute(item, kAXSubroleAttribute) as? String ?? ""
            if role == "AXDockItem" || subrole.contains("DockItem") || role == "AXSeparator" {
                if let position = attribute(item, kAXPositionAttribute), let size = attribute(item, kAXSizeAttribute),
                   CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
                    var point = CGPoint.zero; var dimensions = CGSize.zero
                    if AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) {
                        let title = attribute(item, kAXTitleAttribute) as? String ?? ""
                        let rawURL = attribute(item, kAXURLAttribute)
                        let value = (rawURL as? URL)?.absoluteString ?? rawURL as? String
                        let url = value?.isEmpty == false ? value : nil
                        output.append(.init(title: title, url: url, subrole: subrole, frame: CGRect(origin: point, size: dimensions)))
                    }
                }
                return
            }
            for child in attribute(item, kAXChildrenAttribute) as? [AXUIElement] ?? [] { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        return output
    }
}
