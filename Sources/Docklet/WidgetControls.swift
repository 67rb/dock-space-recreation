import SwiftUI

struct TimerPopover: View {
    @ObservedObject var store: TimerStore

    private let presets = [1, 5, 10, 25]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Timer & Stopwatch")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
            }

            Picker("Mode", selection: Binding(get: { store.mode }, set: store.selectMode)) {
                ForEach(TimerMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if store.mode == .timer {
                HStack(spacing: 7) {
                    Text("PRESETS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    ForEach(presets, id: \.self) { minutes in
                        Button("\(minutes)m") { store.setDuration(minutes: minutes) }.disabled(store.isRunning)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Spacer(minLength: 0)
                }
                Stepper(value: Binding(
                    get: { Int(store.duration / 60) },
                    set: { store.setDuration(minutes: $0) }
                ), in: 1...180) {
                    Text("Duration · \(Int(store.duration / 60)) min")
                        .font(.system(size: 12, weight: .medium))
                }
                .disabled(store.isRunning)
                HStack {
                    Button("Focus · 25m") { store.choosePreset(minutes: 25, name: "Focus") }
                    Button("Break · 5m") { store.choosePreset(minutes: 5, name: "Break") }
                    Button("Long break · 15m") { store.choosePreset(minutes: 15, name: "Break") }
                }.font(.caption).disabled(store.isRunning)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(store.mode == .timer ? store.sessionName.uppercased() : "ELAPSED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(store.displayValue)
                    .font(.system(size: 46, weight: .medium, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(store.isComplete ? "Time is up" : store.statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(store.isComplete ? .orange : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.mode == .timer {
                ProgressView(value: store.progress).tint(.orange)
                HStack {
                    Button("+1 minute", action: store.addMinute)
                    Spacer()
                    Toggle("Completion sound", isOn: $store.soundEnabled).toggleStyle(.checkbox)
                }.font(.caption)
                if store.completedFocusSessions > 0 {
                    Text("\(store.completedFocusSessions) focus sessions completed").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button("Record Lap", action: store.recordLap).disabled(!store.isRunning)
                if !store.laps.isEmpty {
                    ScrollView {
                        VStack(spacing: 7) {
                            ForEach(store.laps.reversed()) { lap in
                                HStack {
                                    Text("Lap \(lap.id)"); Spacer()
                                    Text("+" + TimerStore.format(lap.split)).foregroundStyle(.secondary)
                                    Text(TimerStore.format(lap.elapsed)).monospacedDigit()
                                }.font(.caption)
                            }
                        }
                    }.frame(maxHeight: 120)
                }
            }
            HStack(spacing: 10) {
                Button {
                    store.isRunning ? store.pause() : store.startOrResume()
                } label: {
                    Label(store.isRunning ? "Pause" : (store.statusText == "Paused" ? "Resume" : "Start"),
                          systemImage: store.isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button(role: .destructive, action: store.reset) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(.regularMaterial)
    }
}

struct MusicPopover: View {
    @ObservedObject var store: MusicStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Now Playing").font(.system(size: 17, weight: .bold))
                Spacer()
                if store.isConnected {
                    Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Refresh track information")
                }
            }

            Picker("Music app", selection: Binding(get: { store.player }, set: store.selectPlayer)) {
                ForEach(MusicPlayer.allCases) { player in
                    Text(player.rawValue).tag(player)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Image(systemName: store.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(LinearGradient(colors: [.pink, .purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Text(store.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if store.isWorking { ProgressView().controlSize(.small) }
            }

            if store.isConnected {
                HStack(spacing: 24) {
                    Button(action: store.previousTrack) { Image(systemName: "backward.end.fill") }
                    Button(action: store.togglePlayback) {
                        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 42, height: 42)
                            .background(.white, in: Circle())
                    }
                    Button(action: store.nextTrack) { Image(systemName: "forward.end.fill") }
                }
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
            } else {
                Text("Connect lets Docklet read the current track and send playback commands to this app. macOS may ask you to allow Automation access.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Connect to \(store.player.rawValue)", action: store.connect)
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(store.isWorking)
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(.regularMaterial)
    }
}

