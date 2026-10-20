import AppKit
import SwiftUI

@main
struct DockletEntry {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--generate-icons") {
            _ = NSApplication.shared
            let destination = URL(fileURLWithPath: CommandLine.arguments.last!)
            NativeArtworkView.writePNG(NativeTileState(title: "DOCKLET", value: "D", detail: "YOUR DOCK", accent: .blue), to: destination.appendingPathComponent("manager.png"))
            return
        }
        DockletApp.main()
    }
}

enum TileAccent: String { case green, red, orange, blue, purple
    var color: NSColor {
        switch self {
        case .green: return .systemGreen
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .blue: return .systemCyan
        case .purple: return .systemPurple
        }
    }
}
struct NativeTileState: Equatable {
    var title: String
    var value: String
    var detail: String
    var accent: TileAccent
    var chart: [Double] = []
    static func placeholder(_ kind: DockWidget) -> Self {
        .init(title: kind.title.uppercased(), value: kind == .clock ? "12:00" : (kind == .timer ? "05:00" : (kind == .stocks ? "—" : kind.title.prefix(1).uppercased())), detail: "Click to open", accent: kind == .timer ? .orange : .blue)
    }
}

final class NativeArtworkView: NSView {
    var largeText = false
    var state = NativeTileState(title: "DOCKLET", value: "D", detail: "Widgets", accent: .blue)
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.scaleBy(x: bounds.width / 128, y: bounds.height / 128)
        let card = NSBezierPath(roundedRect: NSRect(x: 5, y: 5, width: 118, height: 118), xRadius: 26, yRadius: 26)
        NSColor(calibratedWhite: 0.075, alpha: 1).setFill()
        card.fill()
        state.accent.color.withAlphaComponent(0.45).setStroke()
        card.lineWidth = 1.4
        card.stroke()
        drawText(state.title, rect: NSRect(x: 13, y: 18, width: 102, height: 18), size: 12, color: state.accent.color, weight: .bold)
        drawText(state.value, rect: NSRect(x: 11, y: largeText ? 36 : 42, width: 106, height: 44), size: largeText ? 40 : 32, color: .white, weight: .bold)
        drawText(state.detail, rect: NSRect(x: 13, y: state.chart.count > 1 ? 77 : 88, width: 102, height: 18), size: 11, color: .lightGray, weight: .medium)
        if state.chart.count > 1, let low = state.chart.min(), let high = state.chart.max() {
            let range = max(high - low, 0.01)
            let path = NSBezierPath()
            for (index, price) in state.chart.enumerated() {
                let point = NSPoint(x: 16 + 96 * Double(index) / Double(state.chart.count - 1), y: 114 - 16 * (price - low) / range)
                if index == 0 { path.move(to: point) } else { path.line(to: point) }
            }
            state.accent.color.setStroke()
            path.lineWidth = 2
            path.lineJoinStyle = .round
            path.stroke()
        }
        context.restoreGState()
    }
    private func drawText(_ value: String, rect: NSRect, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        var fontSize = size
        while fontSize > 10 && (value as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)]).width > rect.width { fontSize -= 1 }
        (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
    }
    static func writePNG(_ state: NativeTileState, to url: URL) {
        let view = NativeArtworkView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        view.state = state
        let image = NSImage(size: view.bounds.size, flipped: true) { rect in view.draw(rect); return true }
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
}

struct ClockControls: View {
    @AppStorage("docklet.clock.24hour") private var use24Hour = true
    var body: some View {
        VStack(spacing: 20) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date, style: .time).font(.system(size: 54, weight: .light, design: .rounded))
                Text(context.date.formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)
            }
            Toggle("24-hour time in the Dock", isOn: $use24Hour)
            Text(TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary)
        }.padding(28)
    }
}
