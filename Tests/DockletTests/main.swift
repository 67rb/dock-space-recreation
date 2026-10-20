import Foundation

final class DockIntegrationChecks {
    private let appURL = URL(fileURLWithPath: "/Applications/Docklet.app")
    private func app(_ name: String) -> [String: Any] {
        DockEntries.adding(URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleID: "test.\(name)", to: []).first!
    }
    func testReservingPreservesUnrelatedAppsAndSpacers() {
        let finder = app("Finder"), safari = app("Safari")
        let userSpacer: [String: Any] = ["tile-type": "spacer-tile", "GUID": 123, "tile-data": ["user-field": "keep"]]
        let old = [finder, userSpacer, safari]
        let result = DockSlotPlan.reserving(entries: old, appURL: appURL, slots: 4, ids: [900, 901, 902])
        require(NSArray(array: Array(result.prefix(3))).isEqual(to: old))
        requireEqual(result.count, 7)
        requireEqual(result.filter { DockSlotPlan.isOwnedSpace($0, ids: [900, 901, 902]) }.count, 3)
    }
    func testRepeatedReservationsDoNotDuplicateAnchorOrSpaces() {
        let once = DockSlotPlan.reserving(entries: [app("Finder")], appURL: appURL, slots: 3, ids: [900, 901])
        let twice = DockSlotPlan.reserving(entries: once, appURL: appURL, slots: 3, ids: [900, 901])
        require(NSArray(array: once).isEqual(to: twice))
    }
    func testRemovingOwnedSpacesPreservesOtherSpacers() {
        let userSpacer: [String: Any] = ["tile-type": "spacer-tile", "GUID": 44]
        let old = DockSlotPlan.reserving(entries: [app("Finder"), userSpacer], appURL: appURL, slots: 4, ids: [900, 901, 902])
        let removed = DockSlotPlan.removingSpaces(from: old, ids: [900, 901, 902])
        requireEqual(removed.count, 3)
        requireEqual(removed[1]["GUID"] as? Int, 44)
        requireEqual(DockEntries.url(of: removed[2])?.path, appURL.path)
    }
    func testResizingSlotsPreservesAppsAfterTheAnchor() {
        let anchor = DockEntries.adding(appURL, name: "Docklet", bundleID: "app.personal.docklet", to: []).first!
        let base = [app("Finder"), anchor, app("Safari")]
        let wide = DockSlotPlan.reserving(entries: base, appURL: appURL, slots: 4, ids: [900, 901, 902])
        let small = DockSlotPlan.reserving(entries: wide, appURL: appURL, slots: 2, ids: [900, 901, 902])
        requireEqual(small.count, 4)
        require(NSDictionary(dictionary: small.last!).isEqual(to: base.last!))
    }
    func testLegacyMigrationOnlyRemovesKnownHelperBundleIDs() {
        var legacy = app("Docklet Stocks")
        var tile = legacy["tile-data"] as! [String: Any]
        tile["bundle-identifier"] = "app.personal.docklet.widget.stocks"
        legacy["tile-data"] = tile
        let other = app("Another Stocks App")
        let result = DockSlotPlan.retiringHelpers(from: [app("Finder"), legacy, other])
        requireEqual(result.count, 2)
        require(NSDictionary(dictionary: result.last!).isEqual(to: other))
    }
    func testMeasuredSpacerFramesAllocateWideWidgetSafely() {
        let items = [
            DockItemGeometry(title: "Docklet", url: appURL.absoluteString, subrole: "AXApplicationDockItem", frame: CGRect(x: 100, y: 900, width: 60, height: 60)),
            DockItemGeometry(title: "", url: nil, subrole: "AXSpacerDockItem", frame: CGRect(x: 166, y: 900, width: 60, height: 60)),
            DockItemGeometry(title: "", url: nil, subrole: "AXSpacerDockItem", frame: CGRect(x: 232, y: 900, width: 60, height: 60)),
            DockItemGeometry(title: "Safari", url: "file:///Applications/Safari.app", subrole: "AXApplicationDockItem", frame: CGRect(x: 298, y: 900, width: 60, height: 60))
        ]
        let slots = DockGeometry.reservedFrames(items: items, appPath: appURL.path, count: 3, vertical: false)!
        let widget = DockGeometry.widgetFrames(slots: slots, placements: [.init(kind: .music, slots: 3)])!["music"]!
        requireEqual(widget.width, 192)
        requireLess(widget.maxX, items.last!.frame.minX)
    }
    func testOrdinaryAdjacentAppCannotBeCoveredByWideWidget() {
        let items = [
            DockItemGeometry(title: "Docklet", url: appURL.absoluteString, subrole: "AXApplicationDockItem", frame: CGRect(x: 100, y: 900, width: 60, height: 60)),
            DockItemGeometry(title: "Safari", url: "file:///Applications/Safari.app", subrole: "AXApplicationDockItem", frame: CGRect(x: 166, y: 900, width: 60, height: 60))
        ]
        requireNil(DockGeometry.reservedFrames(items: items, appPath: appURL.path, count: 3, vertical: false))
    }
    func testOmittedSpacersUseMeasuredGapAndStopBeforeNextApp() {
        let items = [
            DockItemGeometry(title: "Docklet", url: appURL.absoluteString, subrole: "AXApplicationDockItem", frame: CGRect(x: 100, y: 900, width: 60, height: 60)),
            DockItemGeometry(title: "Safari", url: "file:///Applications/Safari.app", subrole: "AXApplicationDockItem", frame: CGRect(x: 298, y: 900, width: 60, height: 60))
        ]
        let slots = DockGeometry.reservedFrames(items: items, appPath: appURL.path, count: 3, vertical: false)!
        requireEqual(slots.count, 3)
        requireLess(slots.last!.maxX, items.last!.frame.minX)
    }
    func testScreenCoordinateConversionSupportsSecondaryDisplay() {
        let ax = CGRect(x: -1200, y: 100, width: 200, height: 70)
        let converted = DockGeometry.cocoaRect(ax, primaryTop: 1000)
        requireEqual(converted, CGRect(x: -1200, y: 830, width: 200, height: 70))
    }
    func testMismatchedSlotCountFailsSafely() {
        requireNil(DockGeometry.widgetFrames(slots: [.zero], placements: [.init(kind: .stocks, slots: 3)]))
    }
}

func require(_ value: Bool, file: StaticString = #file, line: UInt = #line) { if !value { fatalError("Check failed at \(file):\(line)") } }
func requireEqual<T: Equatable>(_ left: T, _ right: T, file: StaticString = #file, line: UInt = #line) { if left != right { fatalError("Expected \(left) == \(right) at \(file):\(line)") } }
func requireLess<T: Comparable>(_ left: T, _ right: T, file: StaticString = #file, line: UInt = #line) { if !(left < right) { fatalError("Expected \(left) < \(right) at \(file):\(line)") } }
func requireNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { if value != nil { fatalError("Expected no result at \(file):\(line)") } }

let checks = DockIntegrationChecks()
checks.testReservingPreservesUnrelatedAppsAndSpacers()
print("PASS: testReservingPreservesUnrelatedAppsAndSpacers")
checks.testRepeatedReservationsDoNotDuplicateAnchorOrSpaces()
print("PASS: testRepeatedReservationsDoNotDuplicateAnchorOrSpaces")
checks.testRemovingOwnedSpacesPreservesOtherSpacers()
print("PASS: testRemovingOwnedSpacesPreservesOtherSpacers")
checks.testResizingSlotsPreservesAppsAfterTheAnchor()
print("PASS: testResizingSlotsPreservesAppsAfterTheAnchor")
checks.testLegacyMigrationOnlyRemovesKnownHelperBundleIDs()
print("PASS: testLegacyMigrationOnlyRemovesKnownHelperBundleIDs")
checks.testMeasuredSpacerFramesAllocateWideWidgetSafely()
print("PASS: testMeasuredSpacerFramesAllocateWideWidgetSafely")
checks.testOrdinaryAdjacentAppCannotBeCoveredByWideWidget()
print("PASS: testOrdinaryAdjacentAppCannotBeCoveredByWideWidget")
checks.testOmittedSpacersUseMeasuredGapAndStopBeforeNextApp()
print("PASS: testOmittedSpacersUseMeasuredGapAndStopBeforeNextApp")
checks.testScreenCoordinateConversionSupportsSecondaryDisplay()
print("PASS: testScreenCoordinateConversionSupportsSecondaryDisplay")
checks.testMismatchedSlotCountFailsSafely()
print("PASS: testMismatchedSlotCountFailsSafely")
print("10 Dock layout checks passed. No system preferences were changed.")
