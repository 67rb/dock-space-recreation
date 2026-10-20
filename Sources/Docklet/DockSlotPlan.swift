import Foundation

struct WidgetPlacement: Codable, Identifiable, Equatable {
    let kind: DockWidget
    var slots: Int
    var id: String { kind.rawValue }
    static let defaults: [Self] = []
}

enum DockSlotPlan {
    static let owner = "app.personal.docklet"
    static func isOwnedSpace(_ entry: [String: Any], ids: Set<UInt32>) -> Bool {
        guard entry["tile-type"] as? String == "spacer-tile" else { return false }
        let tagged = (entry["tile-data"] as? [String: Any])?["docklet-owner"] as? String == owner
        let recorded = (entry["GUID"] as? NSNumber).map { ids.contains($0.uint32Value) } ?? false
        return tagged || recorded
    }
    static func removingSpaces(from entries: [[String: Any]], ids: Set<UInt32>, appURL: URL? = nil, reservedCount: Int = 0) -> [[String: Any]] {
        var owned = Set(entries.indices.filter { isOwnedSpace(entries[$0], ids: ids) })
        // Dock normalizes spacer tiles, discarding custom fields and GUIDs. Keep a
        // bounded reservation beside our anchor so normalized tiles can be removed.
        if let appURL, let anchor = entries.firstIndex(where: { DockEntries.url(of: $0)?.standardizedFileURL.path == appURL.standardizedFileURL.path }) {
            var index = anchor + 1
            var remaining = reservedCount
            while remaining > 0, entries.indices.contains(index), entries[index]["tile-type"] as? String == "spacer-tile" {
                owned.insert(index); index += 1; remaining -= 1
            }
        }
        return entries.enumerated().filter { !owned.contains($0.offset) }.map(\.element)
    }
    static func reserving(entries: [[String: Any]], appURL: URL, slots: Int, ids: [UInt32], previousCount: Int = 0) -> [[String: Any]] {
        var result = removingSpaces(from: entries, ids: Set(ids), appURL: appURL, reservedCount: previousCount)
        guard slots > 0 else { return result }
        var anchor = result.firstIndex { DockEntries.url(of: $0)?.standardizedFileURL.path == appURL.standardizedFileURL.path }
        if anchor == nil {
            result = DockEntries.adding(appURL, name: "Docklet", bundleID: owner, to: result)
            anchor = result.count - 1
        }
        let spaces: [[String: Any]] = ids.prefix(max(0, slots - 1)).map {
            ["GUID": NSNumber(value: $0), "tile-type": "spacer-tile", "tile-data": ["docklet-owner": owner]]
        }
        result.insert(contentsOf: spaces, at: anchor! + 1)
        return result
    }
    static func retiringHelpers(from entries: [[String: Any]]) -> [[String: Any]] {
        let ids = Set(DockWidget.allCases.map { "app.personal.docklet.widget.\($0.rawValue)" })
        return entries.filter {
            let tile = $0["tile-data"] as? [String: Any] ?? [:]
            return !ids.contains(tile["bundle-identifier"] as? String ?? "")
        }
    }
}

struct DockItemGeometry: Equatable, Sendable {
    var title: String
    var url: String?
    var subrole: String
    var frame: CGRect
    var isSpace: Bool { url == nil && (title.isEmpty || subrole.localizedCaseInsensitiveContains("spacer")) }
}

enum DockGeometry {
    // All frames arrive from Accessibility in global coordinates with a top-left origin.
    static func reservedFrames(items: [DockItemGeometry], appPath: String, count: Int, vertical: Bool) -> [CGRect]? {
        guard count > 0 else { return [] }
        let sorted = items.filter { $0.frame.width > 1 && $0.frame.height > 1 }.sorted {
            vertical ? $0.frame.minY < $1.frame.minY : $0.frame.minX < $1.frame.minX
        }
        let exact = sorted.indices.filter { index in
            guard let value = sorted[index].url, let url = URL(string: value) else { return false }
            return url.standardizedFileURL.path == appPath
        }
        let titled = sorted.indices.filter { sorted[$0].title == "Docklet" }
        guard let anchorIndex = exact.first ?? (titled.count == 1 ? titled.first : nil) else { return nil }
        let anchor = sorted[anchorIndex]
        if count == 1 { return [anchor.frame] }
        if sorted.count >= anchorIndex + count {
            let candidate = Array(sorted[(anchorIndex + 1)..<(anchorIndex + count)])
            if candidate.allSatisfy(\.isSpace) {
                let frames = [anchor.frame] + candidate.map(\.frame)
                let thickness = vertical ? anchor.frame.width : anchor.frame.height
                if frames.allSatisfy({ vertical ? abs($0.width - thickness) < thickness * 0.5 : abs($0.height - thickness) < thickness * 0.5 }) { return frames }
            }
        }
        // Some macOS versions omit spacer elements from Accessibility. A measured gap
        // bounded by the next real Dock item is safe to divide; never cover a real icon.
        guard let next = sorted.dropFirst(anchorIndex + 1).first(where: { !$0.isSpace }) else { return nil }
        let start = vertical ? anchor.frame.minY : anchor.frame.minX
        let end = vertical ? next.frame.minY : next.frame.minX
        let length = vertical ? anchor.frame.height : anchor.frame.width
        let pitch = (end - start) / Double(count)
        guard pitch >= length * 0.80, pitch <= length * 1.7 else { return nil }
        return (0..<count).map { index in
            if vertical { return CGRect(x: anchor.frame.minX, y: start + Double(index) * pitch, width: anchor.frame.width, height: max(1, pitch - 4)) }
            return CGRect(x: start + Double(index) * pitch, y: anchor.frame.minY, width: max(1, pitch - 4), height: anchor.frame.height)
        }
    }
    static func cocoaRect(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }
    static func iconRowRect(_ rect: CGRect, slotLength: CGFloat, orientation: String) -> CGRect {
        // Accessibility includes the Dock's hover padding. Its icon row is the
        // square portion at the screen edge, with the icon artwork inset inside it.
        let edge = min(slotLength, orientation == "bottom" ? rect.height : rect.width)
        let inset = edge * 0.09
        let thickness = edge - inset * 2
        if orientation == "left" {
            return CGRect(x: rect.minX + inset, y: rect.minY + inset, width: thickness, height: max(1, rect.height - inset * 2))
        }
        if orientation == "right" {
            return CGRect(x: rect.maxX - edge + inset, y: rect.minY + inset, width: thickness, height: max(1, rect.height - inset * 2))
        }
        return CGRect(x: rect.minX + inset, y: rect.minY + inset, width: max(1, rect.width - inset * 2), height: thickness)
    }
    static func widgetFrames(slots: [CGRect], placements: [WidgetPlacement]) -> [String: CGRect]? {
        guard slots.count == placements.reduce(0, { $0 + $1.slots }), placements.allSatisfy({ (1...5).contains($0.slots) }) else { return nil }
        var result: [String: CGRect] = [:]
        var offset = 0
        for placement in placements {
            let frames = slots[offset..<(offset + placement.slots)]
            result[placement.id] = frames.reduce(CGRect.null) { $0.union($1) }
            offset += placement.slots
        }
        return result
    }
}
