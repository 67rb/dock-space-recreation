import AppKit
import Combine
import Foundation

enum MusicPlayer: String, CaseIterable, Identifiable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"

    var id: String { rawValue }

    var appleScriptName: String { self == .appleMusic ? "Music" : "Spotify" }
}

@MainActor
final class MusicStore: ObservableObject {
    @Published private(set) var player: MusicPlayer = .appleMusic
    @Published private(set) var title = "Choose a player"
    @Published private(set) var artist = "Apple Music or Spotify"
    @Published private(set) var isPlaying = false
    @Published private(set) var hasTrack = false
    @Published private(set) var isConnected = false
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?

    func selectPlayer(_ newPlayer: MusicPlayer) {
        guard player != newPlayer else { return }
        player = newPlayer
        isConnected = false
        hasTrack = false
        isPlaying = false
        title = "Connect \(newPlayer.rawValue)"
        artist = "Tap Connect to enable controls"
        errorMessage = nil
    }

    func connect() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        let script = Self.queryScript(for: player)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                AppleScriptRunner.execute(script)
            }.value
            isWorking = false
            apply(result)
        }
    }

    func refresh() {
        guard isConnected, !isWorking else { return }
        isWorking = true
        let script = Self.queryScript(for: player)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                AppleScriptRunner.execute(script)
            }.value
            isWorking = false
            apply(result)
        }
    }

    func togglePlayback() { perform("playpause") }
    func nextTrack() { perform("next track") }
    func previousTrack() { perform("previous track") }

    private func perform(_ command: String) {
        guard isConnected, !isWorking else { return }
        isWorking = true
        let playerName = player.appleScriptName
        let script = "tell application \"\(playerName)\" to \(command)"
        let query = Self.queryScript(for: player)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let commandResult = AppleScriptRunner.execute(script)
                guard commandResult.error == nil else { return commandResult }
                return AppleScriptRunner.execute(query)
            }.value
            isWorking = false
            apply(result)
        }
    }

    private func apply(_ result: AppleScriptResult) {
        if let error = result.error {
            isConnected = false
            errorMessage = "Could not control \(player.rawValue). Allow Docklet under System Settings → Privacy & Security → Automation, then try again. (\(error))"
            title = "Connection unavailable"
            artist = player.rawValue
            hasTrack = false
            return
        }

        isConnected = true
        errorMessage = nil
        guard let output = result.output, output != "__NO_TRACK__" else {
            hasTrack = false
            isPlaying = false
            title = "Nothing playing"
            artist = player.rawValue
            return
        }

        let fields = output.components(separatedBy: "¶")
        guard fields.count >= 3 else {
            hasTrack = false
            isPlaying = false
            title = "No track available"
            artist = player.rawValue
            return
        }
        title = fields[0].isEmpty ? "Unknown track" : fields[0]
        artist = fields[1].isEmpty ? "Unknown artist" : fields[1]
        isPlaying = fields[2].localizedCaseInsensitiveContains("playing")
        hasTrack = true
    }

    private static func queryScript(for player: MusicPlayer) -> String {
        let name = player.appleScriptName
        return """
        tell application "\(name)"
            if player state is stopped then return "__NO_TRACK__"
            set trackTitle to name of current track as text
            set trackArtist to artist of current track as text
            set playbackState to player state as text
            return trackTitle & "¶" & trackArtist & "¶" & playbackState
        end tell
        """
    }
}

private struct AppleScriptResult: Sendable {
    let output: String?
    let error: String?
}

private enum AppleScriptRunner {
    static func execute(_ source: String) -> AppleScriptResult {
        guard let script = NSAppleScript(source: source) else {
            return AppleScriptResult(output: nil, error: "The script could not be created.")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = errorInfo[NSAppleScript.errorNumber] ?? "unknown"
            let message = errorInfo[NSAppleScript.errorMessage] ?? "Apple Events request failed"
            return AppleScriptResult(output: nil, error: "\(number): \(message)")
        }
        return AppleScriptResult(output: result.stringValue, error: nil)
    }
}
