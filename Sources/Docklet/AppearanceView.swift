import SwiftUI

struct AppearanceView: View {
    @StateObject private var dock = DockAppearanceStore()
    @AppStorage("docklet.native.largeText", store: DockletPreferences.shared) private var largeText = false
    @AppStorage("docklet.widget.cornerRadius", store: DockletPreferences.shared) private var cornerRadius = 18.0
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Size & Appearance").font(.largeTitle.bold())
            Text("Choose each widget's width on the Widgets page. Use the Dock size here to change their height.").foregroundStyle(.secondary)
            GroupBox("macOS Dock size") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("This changes all icons in Apple's Dock, including widget height.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        ForEach([32, 48, 64, 96], id: \.self) { size in Button("\(size) pt") { dock.preset(Double(size)) }.tint(dock.iconSize == Double(size) ? .blue : .gray) }
                    }
                    HStack {
                        Slider(value: $dock.iconSize, in: 16...128, step: 1).accessibilityLabel("Dock icon size")
                        Text("\(Int(dock.iconSize)) pt").monospacedDigit().frame(width: 60)
                    }
                    Toggle("Magnify icons on hover", isOn: $dock.magnification)
                    if dock.magnification { Slider(value: $dock.hoverSize, in: 16...128, step: 1).accessibilityLabel("Hover size") }
                    HStack {
                        Button("Apply to macOS Dock", action: dock.apply).buttonStyle(.borderedProminent).disabled(!dock.hasChanges)
                        Button("Discard", action: dock.reload).disabled(!dock.hasChanges)
                        if dock.canUndo { Button("Undo", action: dock.undo) }
                    }
                    if let message = dock.message { Text(message).font(.caption).foregroundStyle(.cyan) }
                }.padding(12)
            }
            GroupBox("Widget appearance") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Larger text", isOn: $largeText)
                    HStack { Text("Rounded corners"); Slider(value: $cornerRadius, in: 4...30, step: 1) }
                    Text("Widget appearance updates live. Wide music cards include inline playback controls; wide timer cards include start, pause and reset.").font(.caption).foregroundStyle(.secondary)
                }.padding(12)
            }
        }
    }
}
