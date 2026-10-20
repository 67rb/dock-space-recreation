import Foundation
import AppKit
import Combine

enum TimerMode: String, CaseIterable, Codable, Identifiable {
    case timer = "Timer"
    case stopwatch = "Stopwatch"

    var id: String { rawValue }
}

struct StopwatchLap: Codable, Identifiable {
    let id: Int
    let elapsed: TimeInterval
    let split: TimeInterval
}

@MainActor
final class TimerStore: ObservableObject {
    @Published private(set) var mode: TimerMode = .timer
    @Published private(set) var duration: TimeInterval = 5 * 60
    @Published private(set) var remaining: TimeInterval = 5 * 60
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isComplete = false

    @Published private(set) var laps: [StopwatchLap] = []
    @Published private(set) var sessionName = "Timer"
    @Published private(set) var completedFocusSessions = 0
    @Published var soundEnabled = true { didSet { preferences.set(soundEnabled, forKey: "docklet.timer.sound") } }
    private let preferences: UserDefaults
    private let now: () -> Date
    private let automaticTicker: Bool
    private var deadline: Date?
    private var stopwatchStartedAt: Date?
    private var elapsedBeforeStart: TimeInterval = 0
    private var tickerTask: Task<Void, Never>?
    private var lastSnapshot: Data?

    private let storageKey = "docklet.timer.snapshot.v1"

    init(preferences: UserDefaults = DockletPreferences.shared, now: @escaping () -> Date = Date.init, automaticTicker: Bool = true) {
        self.preferences = preferences; self.now = now; self.automaticTicker = automaticTicker
        soundEnabled = preferences.object(forKey: "docklet.timer.sound") as? Bool ?? true
        completedFocusSessions = preferences.integer(forKey: "docklet.timer.focusCompleted")
        restore()
    }
    deinit { tickerTask?.cancel() }

    func choosePreset(minutes: Int, name: String = "Timer") {
        selectMode(.timer); setDuration(minutes: minutes); sessionName = name; persist()
    }
    func addMinute() {
        guard mode == .timer else { return }
        let added = min(60, max(0, 180 * 60 - remaining))
        remaining += added; duration = max(duration, remaining); isComplete = false
        if let deadline { self.deadline = deadline.addingTimeInterval(added) }
        persist()
    }
    func recordLap() {
        guard mode == .stopwatch, isRunning, laps.count < 1000 else { return }
        refreshFromClock()
        let prior = laps.last?.elapsed ?? 0
        laps.append(.init(id: laps.count + 1, elapsed: elapsed, split: max(0, elapsed - prior))); persist()
    }
    var progress: Double { duration > 0 ? min(1, max(0, 1 - remaining / duration)) : 0 }

    func selectMode(_ newMode: TimerMode) {
        guard mode != newMode else { return }
        tickerTask?.cancel()
        tickerTask = nil
        mode = newMode
        laps = []; sessionName = newMode.rawValue
        isRunning = false
        isComplete = false
        deadline = nil
        stopwatchStartedAt = nil
        elapsedBeforeStart = 0
        elapsed = 0
        remaining = duration
        persist()
    }

    func setDuration(minutes: Int) {
        let safeMinutes = min(max(minutes, 1), 180)
        sessionName = "Timer"
        duration = TimeInterval(safeMinutes * 60)
        remaining = duration
        isComplete = false
        isRunning = false
        deadline = nil
        tickerTask?.cancel()
        tickerTask = nil
        persist()
    }

    func startOrResume() {
        guard !isRunning else { return }
        isComplete = false
        isRunning = true

        switch mode {
        case .timer:
            if remaining <= 0 { remaining = duration }
            deadline = now().addingTimeInterval(remaining)
        case .stopwatch:
            elapsedBeforeStart = elapsed
            stopwatchStartedAt = now()
        }

        persist()
        startTicker()
    }

    func pause() {
        guard isRunning else { return }
        refreshFromClock()
        isRunning = false
        deadline = nil
        stopwatchStartedAt = nil
        tickerTask?.cancel()
        tickerTask = nil
        persist()
    }

    func reset() {
        laps = []
        isRunning = false
        isComplete = false
        deadline = nil
        stopwatchStartedAt = nil
        elapsedBeforeStart = 0
        elapsed = 0
        remaining = duration
        tickerTask?.cancel()
        tickerTask = nil
        persist()
    }

    var displayValue: String {
        Self.format(mode == .timer ? remaining : elapsed)
    }

    var statusText: String {
        if isComplete { return "Complete" }
        if isRunning { return "Running" }
        if mode == .stopwatch, elapsed > 0 { return "Paused" }
        if mode == .timer, remaining < duration { return "Paused" }
        return "Ready"
    }

    static func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(ceil(interval)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func startTicker() {
        guard automaticTicker else { return }
        tickerTask?.cancel()
        tickerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRunning else { return }
                self.refreshFromClock()
                if !self.isRunning { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func refreshFromClock() {
        guard isRunning else { return }
        switch mode {
        case .timer:
            let newRemaining = max(0, (deadline ?? now()).timeIntervalSince(now()))
            remaining = newRemaining
            if newRemaining <= 0 {
                remaining = 0
                isRunning = false
                isComplete = true
                if sessionName == "Focus" {
                    completedFocusSessions += 1
                    preferences.set(completedFocusSessions, forKey: "docklet.timer.focusCompleted")
                }
                if soundEnabled && automaticTicker { NSSound(named: "Glass")?.play() }
                deadline = nil
                tickerTask?.cancel()
                tickerTask = nil
                persist()
            }
        case .stopwatch:
            if let stopwatchStartedAt {
                elapsed = elapsedBeforeStart + now().timeIntervalSince(stopwatchStartedAt)
            }
        }
    }

    private struct Snapshot: Codable {
        var mode: TimerMode
        var duration: TimeInterval
        var remaining: TimeInterval
        var elapsed: TimeInterval
        var isRunning: Bool
        var isComplete: Bool
        var deadline: Date?
        var stopwatchStartedAt: Date?
        var elapsedBeforeStart: TimeInterval
        var laps: [StopwatchLap]?
        var sessionName: String?
    }

    private func persist() {
        let snapshot = Snapshot(
            mode: mode,
            duration: duration,
            remaining: remaining,
            elapsed: elapsed,
            isRunning: isRunning,
            isComplete: isComplete,
            deadline: deadline,
            stopwatchStartedAt: stopwatchStartedAt,
            elapsedBeforeStart: elapsedBeforeStart,
            laps: laps,
            sessionName: sessionName
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            lastSnapshot = data
            preferences.set(data, forKey: storageKey)
        }
    }

    private func restore() {
        guard
            let data = preferences.data(forKey: storageKey),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }

        lastSnapshot = data
        laps = snapshot.laps ?? []
        sessionName = snapshot.sessionName ?? snapshot.mode.rawValue
        mode = snapshot.mode
        duration = min(max(snapshot.duration, 60), 180 * 60)
        remaining = min(max(snapshot.remaining, 0), duration)
        elapsed = max(0, snapshot.elapsed)
        isRunning = snapshot.isRunning
        isComplete = snapshot.isComplete
        deadline = snapshot.deadline
        stopwatchStartedAt = snapshot.stopwatchStartedAt
        elapsedBeforeStart = max(0, snapshot.elapsedBeforeStart)

        guard isRunning else { return }
        switch mode {
        case .timer:
            refreshFromClock()
            if !isRunning { return }
        case .stopwatch:
            if let stopwatchStartedAt {
                elapsed = elapsedBeforeStart + now().timeIntervalSince(stopwatchStartedAt)
            }
        }
        startTicker()
    }
}
