import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var timerStore: TimerStore
    @ObservedObject var weatherStore: WeatherStore
    @ObservedObject var musicStore: MusicStore
    @ObservedObject var stockStore: StockStore
    @ObservedObject var integration: DockIntegrationController
    @StateObject private var apps = DockApplicationManager()
    @State private var page = Page.widgets
    @StateObject private var profiles = LayoutProfiles()
    @State private var layoutName = ""
    @State private var showGallery = false
    @State private var showLayouts = false
    @State private var query = ""
    @State private var started = false
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var settingsMessage: String?
    private enum Page: String, CaseIterable, Identifiable {
        case widgets = "Widgets", appearance = "Size & Appearance", apps = "Applications", settings = "Settings"
        var id: String { rawValue }
        var symbol: String {
            switch self { case .widgets: return "square.grid.2x2"; case .appearance: return "slider.horizontal.3"; case .apps: return "app.badge"; case .settings: return "gearshape" }
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Docklet", systemImage: "dock.rectangle").font(.title2.bold()).padding(.top, 18).padding(.bottom, 24)
                ForEach(Page.allCases) { item in
                    Button { page = item } label: {
                        Label(item.rawValue, systemImage: item.symbol).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(page == item ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("ONE APP · 0.5.1").font(.caption2.bold()).foregroundStyle(.secondary)
            }.padding(20).frame(width: 220).background(.white.opacity(0.025))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch page { case .widgets: widgetsPage; case .appearance: AppearanceView(); case .apps: appsPage; case .settings: settingsPage }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .background(Color(red: 0.065, green: 0.075, blue: 0.095))
        .preferredColorScheme(.dark)
        .onAppear {
            if !started {
                started = true; apps.scanApplications()
                if profiles.profiles.isEmpty && !integration.placements.isEmpty { profiles.save(name: "My Dock", widgets: integration.placements) }
            }
        }
    }
    private var widgetsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your Dock, with widgets").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Stocks, timers, notes and more. Add what you use and choose its size.").font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Label(integration.status, systemImage: integration.isVisible ? "checkmark.circle.fill" : "dock.rectangle").foregroundStyle(integration.isVisible ? .green : .cyan)
                HStack {
                    if !integration.accessibilityAllowed {
                        Button("Enable Accessibility", action: integration.enableAccessibility).buttonStyle(.borderedProminent)
                    } else {
                        Toggle("Show Dock widgets", isOn: Binding(get: { integration.enabled }, set: integration.setEnabled))
                        Spacer()
                        Button("Repair Placement", action: integration.repair)
                    }
                }
                if !integration.accessibilityAllowed { Text("In the macOS panel, turn on Docklet under Accessibility. Access is used to find the Dock's icon positions and keep the widgets aligned.").font(.caption).foregroundStyle(.secondary) }
            }.padding(16).background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            layoutControls
            HStack {
                Text("Your widgets").font(.title3.bold())
                Spacer()
                Button("Undo layout", action: integration.undoLayout).disabled(!integration.canUndoLayout)
                Menu("Add widget") {
                    ForEach(DockWidget.allCases.filter { !integration.has($0) }) { kind in
                        Button { integration.add(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                    }
                }.disabled(integration.placements.count == DockWidget.allCases.count)
            }
            DisclosureGroup("Browse all widgets", isExpanded: $showGallery) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], alignment: .leading, spacing: 12) {
                ForEach(DockWidget.allCases) { kind in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(kind.title, systemImage: kind.symbol).font(.headline)
                        Text(kind.summary).font(.caption).foregroundStyle(.secondary).frame(minHeight: 34, alignment: .topLeading)
                        Button(integration.addButtonTitle(kind)) { integration.add(kind) }
                            .buttonStyle(.borderedProminent).disabled(integration.has(kind))
                            .accessibilityIdentifier("add-\(kind.rawValue)")
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            }
            Text("\(integration.placements.count) widgets · right-click a Dock tile for quick actions").font(.caption).foregroundStyle(.secondary)
            if integration.placements.isEmpty {
                Text("Use Add widget above to place your first widget. Each widget has its own width control.")
                    .foregroundStyle(.secondary).padding(16)
            }
            ForEach(integration.placements) { item in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(item.kind.title, systemImage: item.kind.symbol).font(.headline)
                        Spacer()
                        Button { integration.move(item.kind, by: -1) } label: { Image(systemName: "arrow.up") }.help("Move earlier in the Dock").disabled(integration.placements.first?.id == item.id)
                        Button { integration.move(item.kind, by: 1) } label: { Image(systemName: "arrow.down") }.help("Move later in the Dock").disabled(integration.placements.last?.id == item.id)
                        Button { integration.remove(item.kind) } label: { Image(systemName: "minus.circle") }.help("Remove widget")
                    }
                    Text(item.kind.summary).font(.caption).foregroundStyle(.secondary)
                    HStack {
                    DockIntegratedTile(kind: item.kind, timer: timerStore, stocks: stockStore, weather: weatherStore, music: musicStore, agenda: integration.calendarStore, onOpen: { integration.open(item.kind) })
                        .frame(width: max(12, integration.liveIconSize * (CGFloat(item.slots) - 0.18)), height: max(12, integration.liveIconSize * 0.82))
                        .accessibilityLabel("\(item.kind.title) actual size preview")
                        Spacer()
                        Text("Actual Dock size").font(.caption2).foregroundStyle(.tertiary)
                    }.frame(minHeight: 42)
                    Picker("Widget width", selection: Binding(get: { integration.slots(item.kind) }, set: { integration.setSlots(item.kind, $0) })) {
                        Text("Compact").tag(1); Text("Medium").tag(2); Text("Wide").tag(3); Text("Extra wide").tag(5)
                    }.pickerStyle(.segmented)
                    HStack {
                        Text("\(item.slots) Dock icon \(item.slots == 1 ? "space" : "spaces")").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Controls") { integration.open(item.kind) }
                    }
                }.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Widths reserve space in Apple's Dock; changing the layout briefly reloads it. Existing apps remain in place. Closing these settings leaves the widgets running.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var layoutControls: some View {
        DisclosureGroup(isExpanded: $showLayouts) {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Saved layouts", systemImage: "square.stack").font(.headline)
                Spacer()
                Menu("Presets") {
                    Button("Focus · Timer, Notes, Weather") { integration.replaceLayout([.init(kind: .timer, slots: 2), .init(kind: .notes, slots: 2), .init(kind: .weather, slots: 2)]) }
                    Button("Markets · Stocks, Clock, Weather") { integration.replaceLayout([.init(kind: .stocks, slots: 3), .init(kind: .clock, slots: 2), .init(kind: .weather, slots: 2)]) }
                    Button("Minimal · Timer, Weather") { integration.replaceLayout([.init(kind: .timer, slots: 2), .init(kind: .weather, slots: 2)]) }
                }
            }
            HStack {
                TextField("Name this layout", text: $layoutName).textFieldStyle(.roundedBorder)
                Button("Save layout") {
                    if profiles.save(name: layoutName, widgets: integration.placements) { layoutName = "" }
                }.disabled(layoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !profiles.profiles.isEmpty {
                    Menu("Load layout") {
                        ForEach(profiles.profiles) { profile in Button(profile.name) { integration.replaceLayout(profile.widgets) } }
                    }
                    Menu { ForEach(profiles.profiles) { profile in Button("Delete \(profile.name)") { profiles.remove(profile) } } }
                    label: { Image(systemName: "ellipsis") }.help("Manage saved layouts")
                }
            }
            if profiles.removed != nil { Button("Undo deleted layout", action: profiles.undoRemove).font(.caption) }
            Text("Saves widget order and widths. Saving the same name updates that layout.").font(.caption2).foregroundStyle(.secondary)
        }
        } label: {
            Label("Saved layouts and presets", systemImage: "square.stack").font(.headline)
        }.padding(14).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Saved layouts and widget presets")
    }
    private var appsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Applications").font(.largeTitle.bold())
            Text("Choose apps to pin alongside your widgets.").foregroundStyle(.secondary)
            HStack {
                TextField("Search applications", text: $query).textFieldStyle(.roundedBorder)
                Button("Browse…", action: apps.chooseApplication)
                Button { apps.scanApplications() } label: { Image(systemName: "arrow.clockwise") }.disabled(apps.isScanning)
            }
            if apps.isScanning { ProgressView("Finding applications…") }
            ForEach(apps.applications.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { app in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 35, height: 35)
                    Text(app.name)
                    Spacer()
                    Button(apps.isPinned(app.url) ? "Added" : "Add to Dock") { apps.pinApplication(app) }.disabled(apps.isPinned(app.url))
                }.padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            if let message = apps.message { Text(message).foregroundStyle(.cyan) }
        }
    }
    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.largeTitle.bold())
            Toggle("Open Docklet at login", isOn: Binding(get: { loginEnabled }, set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginEnabled = SMAppService.mainApp.status == .enabled
                    settingsMessage = SMAppService.mainApp.status == .requiresApproval ? "Allow Docklet under System Settings → General → Login Items." : nil
                } catch { settingsMessage = error.localizedDescription }
            }))
            if let settingsMessage { Text(settingsMessage).foregroundStyle(.orange) }
            Text("Use Docklet's menu bar icon to open widget controls or settings. Quit Docklet to stop the widgets and clear their reserved spaces.").foregroundStyle(.secondary)
            Divider()
            Text("Sources & access").font(.headline)
            Text("Stocks use Yahoo Finance and may be delayed. Weather uses the city you select through Open-Meteo. Music supports Apple Music and Spotify. Calendar and Reminders request access when you connect them. Dock alignment uses Accessibility.").foregroundStyle(.secondary)
            Button("Show Dock Backups") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Docklet/Dock Backups").path)
            }
            Text("Docklet 0.5.1 · One app, shared widgets, local preferences.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
