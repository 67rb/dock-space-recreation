import AppKit
import SwiftUI

final class DockletDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct DockletApp: App {
    @NSApplicationDelegateAdaptor(DockletDelegate.self) private var delegate
    @StateObject private var timer = TimerStore()
    @StateObject private var weather = WeatherStore()
    @StateObject private var music = MusicStore()
    @StateObject private var stocks = StockStore()
    @StateObject private var integration = DockIntegrationController()
    @State private var startedSetup = false

    var body: some Scene {
        Window("Docklet", id: "settings") {
            SettingsView(timerStore: timer, weatherStore: weather, musicStore: music, stockStore: stocks, integration: integration)
                .defaultAppStorage(DockletPreferences.shared)
                .onOpenURL { integration.handleURL($0) }
                                .onAppear {
                    integration.configure(timer: timer, weather: weather, music: music, stocks: stocks)
                    if CommandLine.arguments.contains("--setup-dock") && !startedSetup {
                        startedSetup = true
                        integration.enableAccessibility()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 930, height: 690)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Widgets") {
                Button("Quick Note") { integration.open(.notes) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Start / Pause Timer") { timer.isRunning ? timer.pause() : timer.startOrResume() }.keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Open Stocks") { integration.open(.stocks) }.keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Undo Layout", action: integration.undoLayout).disabled(!integration.canUndoLayout)
            }
        }
        MenuBarExtra("Docklet", systemImage: "rectangle.bottomthird.inset.filled") {
            DockletMenu(integration: integration)
        }
    }
}

private struct DockletMenu: View {
    @ObservedObject var integration: DockIntegrationController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Docklet Settings") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        ForEach(integration.placements) { item in Button("Open \(item.kind.title)") { integration.open(item.kind) } }
        Divider()
        Toggle("Show Dock Widgets", isOn: Binding(get: { integration.enabled }, set: integration.setEnabled))
        Button("Quit Docklet") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
