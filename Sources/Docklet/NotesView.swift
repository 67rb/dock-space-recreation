import SwiftUI
import AppKit

struct NotesPopover: View {
    @AppStorage("docklet.notes.text.v1") private var text = ""
    @State private var previousText: String?
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Quick Notes", systemImage: "note.text").font(.headline)
                Spacer()
                Text("Saved on this Mac").font(.caption2).foregroundStyle(.secondary)
            }
            TextEditor(text: $text)
                .font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(8).frame(height: 230)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty { Text("An idea, a link, a quick reminder…").foregroundStyle(.tertiary).padding(13).allowsHitTesting(false) }
                }
                .accessibilityLabel("Quick note")
            HStack {
                Text("\(text.split(whereSeparator: { $0.isWhitespace }).count) words").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let previousText {
                    Button("Undo Clear") { text = previousText; self.previousText = nil }
                }
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }.disabled(text.isEmpty)
                Button("Clear") { previousText = text; text = "" }.disabled(text.isEmpty)
            }
        }.padding(20).background(.regularMaterial)
            .onChange(of: text) { _, _ in copied = false }
    }
}
